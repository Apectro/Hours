import SwiftUI
import SwiftData

/// The Today tab (design v2, mockup Main, "the month first").
///
/// One inset-grouped list under a large title, the month and year: the
/// month grid on the background (‹ › in the toolbar, or a sideways swipe,
/// change the month; Today goes back), then Today (`TodaySection`): today's
/// row, the week and the balance, the site days to write and the day's big
/// buttons; then the notices, the month's totals, Edit a range and Export.
/// A tap on a date opens that day as a sheet (`CalendarDaySheet`); Edit
/// there opens the editor.
struct CalendarScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ActiveShiftStore.self) private var clockStore
    @Environment(\.modelContext) private var modelContext
    @Environment(TourCoordinator.self) private var tour: TourCoordinator?

    @State private var anchorDate = CalendarDate.today(in: .current)
    @State private var activeSheet: ActiveSheet?
    /// Reopening a closed month is deliberate, so it is asked once more.
    @State private var monthToReopen: YearMonth?
    /// Only whether there are any, for the one-time public holidays card.
    @Query private var holidayRecords: [HolidayRecord]
    /// A site's day and the site's crew, pushed by value.
    @State private var path = NavigationPath()

    /// One sheet at a time, chosen by value. Stacking several `.sheet`
    /// modifiers on a single view has undefined behaviour.
    private enum ActiveSheet: Identifiable {
        /// A day tapped in the month, or today's written row: the day's
        /// sheet.
        case day(CalendarDate)
        /// The editor, straight away: today not written yet, or a missing
        /// day's Fix.
        case editor(CalendarDate)
        case export(CalendarDateRange)
        case bulkEdit(CalendarDateRange)
        case publicHolidays
        /// "I worked" on a public holiday or a day off: the editor, times
        /// filled in.
        case workedHoliday(CalendarDate)

        var id: String {
            switch self {
            case let .day(date): return "day-\(date.key)"
            case let .editor(date): return "editor-\(date.key)"
            case let .export(range): return "export-\(range.start.key)-\(range.end.key)"
            case let .bulkEdit(range): return "bulk-\(range.start.key)-\(range.end.key)"
            case .publicHolidays: return "public-holidays"
            case let .workedHoliday(date): return "worked-holiday-\(date.key)"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroller in
                List {
                    PeriodDataProvider(range: fetchedRange) { data in
                        CalendarPeriodView(
                            layout: layout,
                            summaryRange: summaryRange,
                            data: data,
                            settings: settings,
                            calendar: calendar,
                            formatting: settingsStore.dateFormatting,
                            today: today,
                            scope: scope,
                            summaryTitle: summaryTitle,
                            closedMonth: closedMonthOnScreen,
                            exportTitle: exportTitle,
                            onSelect: { activeSheet = .day($0) },
                            onStep: step,
                            onFix: { activeSheet = .editor($0) },
                            onEditRange: {
                                // Seeded with today when it is on screen,
                                // else the period's first day: widening is
                                // easier than narrowing.
                                let start = summaryRange.contains(today) ? today : summaryRange.start
                                activeSheet = .bulkEdit(CalendarDateRange(single: start))
                            },
                            onExport: { activeSheet = .export(summaryRange) },
                            onReopen: { monthToReopen = $0 }
                        ) {
                            TodaySection(
                                today: today,
                                settings: settings,
                                calendar: calendar,
                                formatting: settingsStore.dateFormatting,
                                running: clockStore.running,
                                onClockIn: clockIn,
                                onClockOut: clockOut,
                                onToggleBreak: toggleBreak,
                                onDiscard: discard,
                                onUsualDay: writeUsualDay,
                                onEdit: { activeSheet = .editor(today) },
                                onOpenDay: { activeSheet = .day(today) },
                                onWorked: { activeSheet = .workedHoliday(today) },
                                onOpenSite: { path.append(CalendarSiteRoute(siteID: $0, date: today)) }
                            )

                            if showsPublicHolidayOffer {
                                PublicHolidayOfferCard(
                                    onChoose: { activeSheet = .publicHolidays },
                                    onDismiss: dismissPublicHolidayOffer
                                )
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(.compact)
                .animation(.snappy(duration: 0.25), value: clockStore.running)
                .navigationTitle(periodTitle)
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbar }
                // The tour's stops on the calendar: what they point at has to be
                // on screen.
                .onChange(of: tour?.tour?.stop) { _, stop in
                    if stop == .today {
                        goToToday()
                        withAnimation { scroller.scrollTo(Self.monthAnchor, anchor: .top) }
                    } else if stop == .summary {
                        withAnimation { scroller.scrollTo(Self.summaryAnchor, anchor: .center) }
                    }
                }
                .confirmationDialog(
                    reopenTitle,
                    isPresented: Binding(get: { monthToReopen != nil }, set: { if !$0 { monthToReopen = nil } }),
                    titleVisibility: .visible
                ) {
                    Button("Reopen") {
                        if let month = monthToReopen { reopen(month) }
                    }
                    .accessibilityIdentifier("calendar-reopen-confirm")
                    Button("Cancel", role: .cancel) { monthToReopen = nil }
                } message: {
                    Text("Its days can be changed again. Close it again from the calendar's ⋯ menu when you are done.")
                }
                .navigationDestination(for: CalendarSiteRoute.self) { route in
                    SiteDetailScreen(siteID: route.siteID, initialDate: route.date)
                }
                .navigationDestination(for: SiteCrewRoute.self) { route in
                    CrewScreen(siteID: route.siteID)
                }
                .navigationDestination(for: CalendarClosedMonthsRoute.self) { _ in
                    ClosedMonthsScreen()
                }
                .sheet(item: $activeSheet) { sheet in
                    switch sheet {
                    case let .day(date):
                        CalendarDaySheet(date: date) { route in
                            // The site's day is pushed onto this tab's
                            // stack, under the sheet as it goes.
                            activeSheet = nil
                            path.append(route)
                        }
                    case let .editor(date):
                        DayEditorSheet(date: date)
                    case let .export(range):
                        ExportScreen(initialRange: range)
                    case let .bulkEdit(range):
                        BulkEditSheet(initialRange: range)
                    case .publicHolidays:
                        PublicHolidayPicker {}
                    case let .workedHoliday(date):
                        DayEditorSheet(date: date, startsWorking: true)
                    }
                }
            }
        }
        // The site screen's crew, pushed onto this stack by value.
        .environment(\.openSiteCrew, OpenSiteCrewAction { path.append($0) })
    }

    /// ‹ › on the left; Today and the ⋯ menu on the right.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            stepButton(-1)
            stepButton(1)
        }
        ToolbarItem(placement: .topBarTrailing) {
            // Back to this month and today; nothing to do when already there.
            Button("Today", action: goToToday)
                .disabled(summaryRange.contains(today))
                .accessibilityIdentifier("calendar-today")
        }
        ToolbarItem(placement: .topBarTrailing) {
            moreMenu
        }
    }

    private func stepButton(_ direction: Int) -> some View {
        Button {
            step(direction)
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
        }
        .accessibilityLabel(direction < 0
            ? (scope == .month ? String(localized: "Previous month") : String(localized: "Previous week"))
            : (scope == .month ? String(localized: "Next month") : String(localized: "Next week")))
        .accessibilityIdentifier(direction < 0 ? "calendar-previous" : "calendar-next")
    }

    /// Where the tour's totals stop scrolls to.
    static let summaryAnchor = "calendar-summary"
    /// The month under Today, where the tour's today stop scrolls to.
    static let monthAnchor = "calendar-month"

    // MARK: - Derived state

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var scope: CalendarScope { settings.calendar.preferredScope }
    private var today: CalendarDate { CalendarDate.today(in: calendar) }

    private var layout: MonthLayout {
        switch scope {
        case .month:
            return MonthLayout.make(
                month: anchorDate.yearMonth,
                calendar: calendar,
                includesWeekends: settings.calendar.showWeekends
            )
        case .week:
            return MonthLayout.week(
                containing: anchorDate,
                calendar: calendar,
                includesWeekends: settings.calendar.showWeekends
            )
        }
    }

    private var summaryRange: CalendarDateRange {
        switch scope {
        case .month: return anchorDate.yearMonth.range(in: calendar)
        case .week: return CalendarDateRange.week(containing: anchorDate, in: calendar)
        }
    }

    /// The grid's days, and the whole weeks around the summary's: earnings
    /// count overtime from the first day of a week, which a month that starts
    /// on a Thursday does not show.
    private var fetchedRange: CalendarDateRange {
        let covered = layout.coveredRange
        let weeks = CalendarDateRange(
            start: CalendarDateRange.week(containing: summaryRange.start, in: calendar).start,
            end: CalendarDateRange.week(containing: summaryRange.end, in: calendar).end
        )
        return CalendarDateRange(start: min(covered.start, weeks.start), end: max(covered.end, weeks.end))
    }

    /// The large title: "October 2026", or "3 Nov – 9 Nov" in week view.
    private var periodTitle: String {
        let formatting = settingsStore.dateFormatting
        switch scope {
        case .month:
            return formatting.monthTitle(anchorDate.yearMonth)
        case .week:
            let range = summaryRange
            return "\(formatting.shortDate(range.start)) – \(formatting.shortDate(range.end))"
        }
    }

    /// The totals' header: "October", or "This week".
    private var summaryTitle: String {
        switch scope {
        case .month: return settingsStore.dateFormatting.monthName(anchorDate.yearMonth)
        case .week: return String(localized: "This week")
        }
    }

    /// "Export October", or "Export this week".
    private var exportTitle: String {
        switch scope {
        case .month:
            return String(
                localized: "Export \(settingsStore.dateFormatting.monthName(anchorDate.yearMonth))",
                comment: "Button under the month; the value is a month's name"
            )
        case .week:
            return String(localized: "Export this week")
        }
    }

    /// The month the ⋯ menu's Close / Reopen is about: the one on screen,
    /// or in week view the month the week is anchored in.
    private var monthOnScreen: YearMonth { anchorDate.yearMonth }

    private var lockOffer: MonthLockOffer? {
        settings.monthLock.offer(for: monthOnScreen, today: today)
    }

    /// A closed month the grid shows, for the notice above it. In week
    /// view a week can straddle two months; the first closed one is named.
    private var closedMonthOnScreen: YearMonth? {
        settings.monthLock.lockedMonths(in: summaryRange, calendar: calendar).first
    }

    private var reopenTitle: String {
        guard let month = monthToReopen else { return "" }
        return String(
            localized: "Reopen \(settingsStore.dateFormatting.monthTitle(month))?",
            comment: "Confirmation title; the value is a month and year"
        )
    }

    /// Once, to someone with no holidays at all, until added or put away.
    private var showsPublicHolidayOffer: Bool {
        settings.features.trackHolidays
            && settings.publicHolidays.shouldOffer(hasHolidayRules: !holidayRecords.isEmpty)
    }

    private func dismissPublicHolidayOffer() {
        withAnimation(.snappy(duration: 0.2)) {
            settingsStore.update { $0.publicHolidays.offerDismissed = true }
        }
    }

    // MARK: - Actions

    private func step(_ direction: Int) {
        withAnimation(.snappy(duration: 0.25)) {
            switch scope {
            case .month:
                let month = anchorDate.yearMonth.adding(months: direction)
                let day = min(anchorDate.day, month.dayCount(in: calendar))
                anchorDate = CalendarDate(year: month.year, month: month.month, day: day)
            case .week:
                anchorDate = anchorDate.adding(days: direction * 7, in: calendar)
            }
        }
    }

    private func goToToday() {
        withAnimation(.snappy(duration: 0.25)) {
            anchorDate = today
        }
    }

    private func setScope(_ newScope: CalendarScope) {
        settingsStore.update { $0.calendar.preferredScope = newScope }
    }

    /// "I worked the usual day": today with the week's times, saved in one
    /// tap. A closed month opens the editor instead, which says so and
    /// offers to reopen it.
    private func writeUsualDay() {
        let repository = WorkdayRepository(context: modelContext, lock: settings.monthLock)
        guard let record = UsualDay.record(
            for: today,
            existing: repository.record(on: today),
            engine: settingsStore.engine,
            holidays: holidayRecords.map(\.rule)
        ) else {
            activeSheet = .editor(today)
            return
        }
        do {
            try repository.save(record)
        } catch {
            activeSheet = .editor(today)
            return
        }
        HoursStack.refreshWidget()
    }

    // MARK: - The clock

    private var timeClock: TimeClock {
        TimeClock(
            repository: WorkdayRepository(context: modelContext),
            clock: clockStore,
            settings: settings,
            calendar: calendar
        )
    }

    private func clockIn() {
        withAnimation(.snappy(duration: 0.25)) {
            // Discarded deliberately: a second tap while a clock is already
            // running returns nil, and there is nothing for the UI to do.
            _ = timeClock.clockIn()
        }
        HoursStack.refreshWidget()
    }

    private func clockOut() {
        withAnimation(.snappy(duration: 0.25)) {
            let result = timeClock.clockOut()
            // Stopping a clock started on an earlier day shows the month it
            // belonged to.
            if case let .recorded(date, _, _) = result, !summaryRange.contains(date) {
                anchorDate = date
            }
        }
        HoursStack.refreshWidget()
    }

    private func toggleBreak() {
        guard let running = clockStore.running else { return }
        withAnimation(.snappy(duration: 0.2)) {
            if running.isOnBreak {
                timeClock.endBreak()
            } else {
                timeClock.startBreak()
            }
        }
    }

    /// Nothing is recorded, but the widget and the Live Activity were both
    /// showing a running clock, so they are told it stopped.
    private func discard() {
        timeClock.discard()
        HoursStack.refreshWidget()
    }

    // MARK: - Closing a month

    private func closeMonth(_ month: YearMonth) {
        settingsStore.update { $0.monthLock.lock(month) }
    }

    private func reopen(_ month: YearMonth) {
        settingsStore.update { $0.monthLock.unlock(month) }
        monthToReopen = nil
    }

    // MARK: - The ⋯ menu

    /// In the toolbar: the view, closing or reopening the month on screen,
    /// and the list of closed months.
    private var moreMenu: some View {
        Menu {
            Picker("View", selection: Binding(get: { scope }, set: setScope)) {
                ForEach(CalendarScope.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)

            Divider()

            switch lockOffer {
            case .close?:
                Button {
                    closeMonth(monthOnScreen)
                } label: {
                    Label(
                        String(
                            localized: "Close \(settingsStore.dateFormatting.monthTitle(monthOnScreen))",
                            comment: "Button; the value is a month and year"
                        ),
                        systemImage: "lock"
                    )
                }
                .accessibilityIdentifier("calendar-close-month")
            case .reopen?:
                Button {
                    monthToReopen = monthOnScreen
                } label: {
                    Label(
                        String(
                            localized: "Reopen \(settingsStore.dateFormatting.monthTitle(monthOnScreen))",
                            comment: "Button; the value is a month and year"
                        ),
                        systemImage: "lock.open"
                    )
                }
                .accessibilityIdentifier("calendar-reopen-month")
            case nil:
                EmptyView()
            }

            Button {
                path.append(CalendarClosedMonthsRoute())
            } label: {
                Label("Closed months", systemImage: "lock.rectangle.stack")
            }
            .accessibilityIdentifier("calendar-closed-months")
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("calendar-more")
    }
}

/// The closed months, pushed from the ⋯ menu.
struct CalendarClosedMonthsRoute: Hashable {}

/// The Today tab's list for one visible period: the grid, then `middle`
/// (Today), then the notices, the totals, and Edit a range and Export.
///
/// The engine runs once, in `init`, and the result is handed to the grid,
/// the notices and the totals — so they can never disagree, and nothing is
/// recomputed while SwiftUI diffs the body. Its body is sections, for the
/// list it sits in.
private struct CalendarPeriodView<Middle: View>: View {
    let layout: MonthLayout
    let settings: AppSettings
    let formatting: CalendarFormatting
    let today: CalendarDate
    let scope: CalendarScope
    let summaryTitle: String
    let closedMonth: YearMonth?
    let exportTitle: String
    let onSelect: (CalendarDate) -> Void
    let onStep: (Int) -> Void
    let onFix: (CalendarDate) -> Void
    let onEditRange: () -> Void
    let onExport: () -> Void
    let onReopen: (YearMonth) -> Void
    let middle: Middle

    private let computationsByKey: [Int: DayComputation]
    private let summary: PeriodSummary
    /// What the period earned through today, while earnings are the main
    /// figure.
    private let earnings: EarningsSummary?
    /// Field allowance, kilometres and travel through today, while they are
    /// tracked.
    private let allowance: AllowanceSummary
    private let weekDays: [DayComputation]
    /// Your days not written in the period, in order (`MissingDays`).
    private let missing: [CalendarDate]

    init(
        layout: MonthLayout,
        summaryRange: CalendarDateRange,
        data: PeriodData,
        settings: AppSettings,
        calendar: Calendar,
        formatting: CalendarFormatting,
        today: CalendarDate,
        scope: CalendarScope,
        summaryTitle: String,
        closedMonth: YearMonth?,
        exportTitle: String,
        onSelect: @escaping (CalendarDate) -> Void,
        onStep: @escaping (Int) -> Void,
        onFix: @escaping (CalendarDate) -> Void,
        onEditRange: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onReopen: @escaping (YearMonth) -> Void,
        @ViewBuilder middle: () -> Middle
    ) {
        self.layout = layout
        self.settings = settings
        self.formatting = formatting
        self.today = today
        self.scope = scope
        self.summaryTitle = summaryTitle
        self.closedMonth = closedMonth
        self.exportTitle = exportTitle
        self.onSelect = onSelect
        self.onStep = onStep
        self.onFix = onFix
        self.onEditRange = onEditRange
        self.onExport = onExport
        self.onReopen = onReopen
        self.middle = middle()

        let engine = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: data.firstRecorded)
        let span = CalendarDateRange(
            start: min(layout.coveredRange.start, summaryRange.start),
            end: max(layout.coveredRange.end, summaryRange.end)
        )
        let resolved = engine.days(in: span, records: data.records, holidays: data.holidays)

        var byKey: [Int: DayComputation] = [:]
        byKey.reserveCapacity(resolved.count)
        for day in resolved { byKey[day.date.key] = day }
        self.computationsByKey = byKey

        let inPeriod = resolved.filter { summaryRange.contains($0.date) }
        self.summary = PeriodAggregator.summarize(inPeriod, range: summaryRange, countingThrough: today)
        self.earnings = settings.showsEarnings
            ? engine.earnings(in: summaryRange, records: data.records, holidays: data.holidays, countingThrough: today)
            : nil
        self.allowance = AllowanceSummary(days: inPeriod, settings: settings, countingThrough: today)
        self.weekDays = scope == .week ? inPeriod : []
        self.missing = MissingDays.personal(days: inPeriod, today: today)
    }

    private var duration: DurationFormatting { settings.displayFormatting }

    var body: some View {
        // The grid sits on the background, not in a card.
        Section {
            CalendarMonthGrid(
                layout: layout,
                computations: computationsByKey,
                today: today,
                detail: settings.calendar.dayCellDetail,
                formatting: formatting,
                durationFormatting: duration,
                onSelect: onSelect
            )
            // A sideways swipe pages the period, as the arrows do.
            // Simultaneous, so the list still scrolls and a date still
            // takes its tap; only a clearly horizontal drag counts.
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        let width = value.translation.width
                        guard abs(width) > 50, abs(width) > abs(value.translation.height) * 1.5 else { return }
                        onStep(width < 0 ? 1 : -1)
                    }
            )
            .listRowInsets(EdgeInsets(top: Metrics.small, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .id(CalendarScreen.monthAnchor)
        }

        middle

        if closedMonth != nil || !missing.isEmpty {
            Section {
                if let closedMonth {
                    ClosedMonthNotice(month: closedMonth, formatting: formatting) { onReopen(closedMonth) }
                }
                if let first = missing.first {
                    MissingDaysBanner(count: missing.count) { onFix(first) }
                }
            }
        }

        if scope == .week && !weekDays.isEmpty {
            WeekDayList(
                days: weekDays,
                settings: settings,
                formatting: formatting,
                onSelect: onSelect
            )
        }

        if settings.calendar.showMonthSummary {
            PeriodSummaryBar(
                summary: summary,
                settings: settings,
                catalog: settings.dayTypeCatalog,
                title: summaryTitle,
                earnings: earnings,
                allowance: allowance
            )
        }

        Section {
            Button(action: onEditRange) {
                Text("Edit a range")
            }
            .accessibilityIdentifier("calendar-edit-range")

            Button(action: onExport) {
                Text(verbatim: exportTitle)
            }
            // Sending a month's hours is a monthly job: on its own row,
            // found by this identifier.
            .accessibilityIdentifier("calendar-export")
        }
    }
}

/// "2 days not written" with a red dot, and Fix, which opens the first of
/// them in the editor.
private struct MissingDaysBanner: View {
    let count: Int
    let onFix: () -> Void

    private var days: String { String(inflected: "^[\(count) day](inflect: true)") }

    var body: some View {
        Button(action: onFix) {
            HStack(spacing: Metrics.medium) {
                Circle()
                    .fill(Color.hoursMissingFill)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(String(
                    localized: "\(days) not written",
                    comment: "Calendar banner; the value is a number of days, e.g. 2 days"
                ))
                .foregroundStyle(.primary)
                Spacer(minLength: Metrics.small)
                Text("Fix")
                    .foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("calendar-missing-fix")
    }
}

/// The week's days as rows, shown only in week scope where there is room
/// to say more than a date in the grid can.
private struct WeekDayList: View {
    let days: [DayComputation]
    let settings: AppSettings
    let formatting: CalendarFormatting
    let onSelect: (CalendarDate) -> Void

    private var duration: DurationFormatting { settings.displayFormatting }

    var body: some View {
        Section {
            ForEach(days) { day in
                Button {
                    onSelect(day.date)
                } label: {
                    HStack(spacing: Metrics.medium) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(formatting.mediumDate(day.date))
                                .foregroundStyle(.primary)
                            Text(subtitle(for: day))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.hoursSecondaryText)
                        }
                        Spacer(minLength: Metrics.small)
                        if settings.features.showsBalance && day.hasEntry {
                            Text(verbatim: duration.signedString(day.balanceMinutes))
                                .monospacedDigit()
                                .foregroundStyle(Color.hoursBalance(day.balanceMinutes))
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
    }

    private func subtitle(for day: DayComputation) -> String {
        if let start = day.start, let end = day.end {
            let times = "\(formatting.time(start, on: day.date)) – \(formatting.time(end, on: day.date))"
            return "\(times) · \(duration.string(day.workedMinutes))"
        }
        if day.creditedMinutes > 0 {
            return String(
                localized: "\(day.dayType.displayName())  ·  \(duration.string(day.creditedMinutes)) credited",
                comment: "A day with no worked hours but paid time, e.g. Vacation · 8h 00m credited"
            )
        }
        return day.dayType.displayName()
    }
}

/// While the period on screen is in a closed month: the grid looks the
/// same either way, and an editor refusing to save is a poor way to find
/// out. One row, with Reopen.
private struct ClosedMonthNotice: View {
    let month: YearMonth
    let formatting: CalendarFormatting
    let onReopen: () -> Void

    var body: some View {
        HStack(spacing: Metrics.small) {
            Label {
                Text(String(
                    localized: "\(formatting.monthTitle(month)) is closed",
                    comment: "Calendar notice; the value is a month and year"
                ))
            } icon: {
                Image(systemName: "lock.fill")
            }
            .foregroundStyle(.hoursSecondaryText)
            Spacer(minLength: Metrics.small)
            Button("Reopen", action: onReopen)
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .accessibilityIdentifier("calendar-closed-reopen")
        }
    }
}

/// A site's day opened from a calendar day worked on more than one site
/// (1.2): pushed by value, as every destination on a stack is here.
struct CalendarSiteRoute: Hashable {
    let siteID: UUID
    let date: CalendarDate
}
