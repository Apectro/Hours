import SwiftUI
import SwiftData

/// The Today tab (1.2, mockup Today).
///
/// Opens on today — the usual day or the running clock, the week and the
/// balance, today's crew days and the day's big buttons (`TodaySection`) —
/// and under it, on the same scroll, the month: ‹ › and worked / expected,
/// "N days not written · Fix", the grid by the colour rule, Edit a range and
/// Export, then the month's totals. A tap on a day pushes the day
/// (`CalendarDayScreen`); Edit there opens the editor as a sheet.
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
    /// The day, a site's day and the site's crew, pushed by value.
    @State private var path = NavigationPath()
    /// The scroll view's visible height: Today fills the first screen, with
    /// its buttons at the bottom, and the month starts under it.
    @State private var viewportHeight: CGFloat = 0

    /// One sheet at a time, chosen by value. Stacking several `.sheet`
    /// modifiers on a single view has undefined behaviour.
    private enum ActiveSheet: Identifiable {
        case day(CalendarDate)
        case export(CalendarDateRange)
        case bulkEdit(CalendarDateRange)
        case publicHolidays
        /// "I worked" on a public holiday or a day off: the editor, times
        /// filled in.
        case workedHoliday(CalendarDate)

        var id: String {
            switch self {
            case let .day(date): return "day-\(date.key)"
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
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.large) {
                        if showsPublicHolidayOffer {
                            PublicHolidayOfferCard(
                                onChoose: { activeSheet = .publicHolidays },
                                onDismiss: dismissPublicHolidayOffer
                            )
                            .transition(.opacity)
                        }

                        TodaySection(
                            today: today,
                            settings: settings,
                            calendar: calendar,
                            formatting: settingsStore.dateFormatting,
                            running: clockStore.running,
                            menu: AnyView(moreMenu),
                            onClockIn: clockIn,
                            onClockOut: clockOut,
                            onToggleBreak: toggleBreak,
                            onDiscard: discard,
                            onUsualDay: writeUsualDay,
                            onEdit: { activeSheet = .day(today) },
                            onWorked: { activeSheet = .workedHoliday(today) },
                            onOpenSite: { path.append(CalendarSiteRoute(siteID: $0, date: today)) }
                        )
                        .frame(minHeight: max(0, viewportHeight - Metrics.large * 2), alignment: .top)

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
                                title: periodTitle,
                                closedMonth: closedMonthOnScreen,
                                exportTitle: exportTitle,
                                onSelect: { path.append(CalendarDayRoute(date: $0)) },
                                onStep: step,
                                onGoToToday: summaryRange.contains(today) ? nil : goToToday,
                                onFix: { activeSheet = .day($0) },
                                onEditRange: {
                                    // Seeded with today when it is on screen,
                                    // else the period's first day: widening is
                                    // easier than narrowing.
                                    let start = summaryRange.contains(today) ? today : summaryRange.start
                                    activeSheet = .bulkEdit(CalendarDateRange(single: start))
                                },
                                onExport: { activeSheet = .export(summaryRange) },
                                onReopen: { monthToReopen = $0 }
                            )
                        }
                        .id(Self.monthAnchor)
                    }
                    .padding(.horizontal, Metrics.large)
                    .padding(.vertical, Metrics.large)
                    .animation(.snappy(duration: 0.25), value: clockStore.running)
                }
                .background(Color.hoursCanvas)
                .scrollDismissesKeyboard(.interactively)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    viewportHeight = height
                }
                // The title is drawn in the content, with the date above it.
                .toolbar(.hidden, for: .navigationBar)
                .navigationTitle("Today")
                // The tour's stops on the calendar: what they point at has to be
                // on screen. Today's cell and the totals are under Today.
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
                .navigationDestination(for: CalendarDayRoute.self) { route in
                    CalendarDayScreen(date: route.date)
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

    /// "October", or "3 Nov – 9 Nov" in week view.
    private var periodTitle: String {
        let formatting = settingsStore.dateFormatting
        switch scope {
        case .month:
            return anchorDate.yearMonth.year == today.year
                ? formatting.monthName(anchorDate.yearMonth)
                : formatting.monthTitle(anchorDate.yearMonth)
        case .week:
            let range = summaryRange
            return "\(formatting.shortDate(range.start)) – \(formatting.shortDate(range.end))"
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
            activeSheet = .day(today)
            return
        }
        do {
            try repository.save(record)
        } catch {
            activeSheet = .day(today)
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

    /// Beside the title: the view, closing or reopening the month on
    /// screen, and the list of closed months.
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
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.hoursSurface, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel("More")
        .accessibilityIdentifier("calendar-more")
    }
}

/// The closed months, pushed from the ⋯ menu.
struct CalendarClosedMonthsRoute: Hashable {}

/// The month under Today, for one visible period.
///
/// The engine runs once, in `init`, and the result is handed to the grid,
/// the banner and the totals — so they can never disagree, and nothing is
/// recomputed while SwiftUI diffs the body.
private struct CalendarPeriodView: View {
    let layout: MonthLayout
    let settings: AppSettings
    let formatting: CalendarFormatting
    let today: CalendarDate
    let scope: CalendarScope
    let title: String
    let closedMonth: YearMonth?
    let exportTitle: String
    let onSelect: (CalendarDate) -> Void
    let onStep: (Int) -> Void
    let onGoToToday: (() -> Void)?
    let onFix: (CalendarDate) -> Void
    let onEditRange: () -> Void
    let onExport: () -> Void
    let onReopen: (YearMonth) -> Void

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
        title: String,
        closedMonth: YearMonth?,
        exportTitle: String,
        onSelect: @escaping (CalendarDate) -> Void,
        onStep: @escaping (Int) -> Void,
        onGoToToday: (() -> Void)?,
        onFix: @escaping (CalendarDate) -> Void,
        onEditRange: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onReopen: @escaping (YearMonth) -> Void
    ) {
        self.layout = layout
        self.settings = settings
        self.formatting = formatting
        self.today = today
        self.scope = scope
        self.title = title
        self.closedMonth = closedMonth
        self.exportTitle = exportTitle
        self.onSelect = onSelect
        self.onStep = onStep
        self.onGoToToday = onGoToToday
        self.onFix = onFix
        self.onEditRange = onEditRange
        self.onExport = onExport
        self.onReopen = onReopen

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
        VStack(alignment: .leading, spacing: Metrics.medium) {
            header

            if let closedMonth {
                ClosedMonthNotice(month: closedMonth, formatting: formatting) { onReopen(closedMonth) }
            }

            if let first = missing.first {
                MissingDaysBanner(count: missing.count) { onFix(first) }
            }

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
            // Simultaneous, so the scroll view still scrolls and a cell
            // still takes its tap; only a clearly horizontal drag counts.
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        let width = value.translation.width
                        guard abs(width) > 50, abs(width) > abs(value.translation.height) * 1.5 else { return }
                        onStep(width < 0 ? 1 : -1)
                    }
            )

            Text("Dashed red: not written · orange: away · green: holiday · grey: day off")
                .font(.caption2)
                .foregroundStyle(.hoursSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metrics.tiny)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.small) { periodButtons }
                VStack(spacing: Metrics.small) { periodButtons }
            }

            if settings.calendar.showMonthSummary {
                PeriodSummaryBar(
                    summary: summary,
                    settings: settings,
                    catalog: settings.dayTypeCatalog,
                    earnings: earnings,
                    allowance: allowance
                )
                .padding(Metrics.large)
                .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .tourTarget(.calendarSummary)
                .id(CalendarScreen.summaryAnchor)
            }

            if scope == .week && !weekDays.isEmpty {
                WeekDayList(
                    days: weekDays,
                    settings: settings,
                    formatting: formatting,
                    onSelect: onSelect
                )
            }
        }
    }

    /// ‹ October › on the left; worked / expected on the right.
    private var header: some View {
        HStack(spacing: Metrics.small) {
            stepButton(-1)
            Text(verbatim: title)
                .font(.title2.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            stepButton(1)
            Spacer(minLength: Metrics.small)
            if let onGoToToday {
                Button("Today", action: onGoToToday)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("calendar-today")
            } else {
                Text(verbatim: workedLine)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.hoursSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityIdentifier("calendar-worked-expected")
            }
        }
    }

    /// "168h / 184h", or the hours alone where nothing is expected.
    private var workedLine: String {
        let worked = duration.string(summary.workedMinutes)
        guard settings.features.trackExpectedHours else { return worked }
        return "\(worked) / \(duration.string(summary.expectedMinutes))"
    }

    private func stepButton(_ direction: Int) -> some View {
        Button {
            onStep(direction)
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.hoursSurface, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel(direction < 0
            ? (scope == .month ? String(localized: "Previous month") : String(localized: "Previous week"))
            : (scope == .month ? String(localized: "Next month") : String(localized: "Next week")))
        .accessibilityIdentifier(direction < 0 ? "calendar-previous" : "calendar-next")
    }

    @ViewBuilder
    private var periodButtons: some View {
        Button(action: onEditRange) {
            Text("Edit a range")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .accessibilityIdentifier("calendar-edit-range")

        Button(action: onExport) {
            Text(verbatim: exportTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        // Sending a month's hours is a monthly job: on its own button,
        // found by this identifier.
        .accessibilityIdentifier("calendar-export")
    }
}

/// "2 days not written · Fix" (red: missing): Fix opens the first of them.
private struct MissingDaysBanner: View {
    let count: Int
    let onFix: () -> Void

    private var days: String { String(inflected: "^[\(count) day](inflect: true)") }

    var body: some View {
        Button(action: onFix) {
            HStack(spacing: Metrics.small) {
                Circle()
                    .fill(Color.hoursMissingFill)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(String(
                    localized: "\(days) not written",
                    comment: "Calendar banner; the value is a number of days, e.g. 2 days"
                ))
                .font(.body.weight(.bold))
                .foregroundStyle(.primary)
                Spacer(minLength: Metrics.small)
                Text("Fix")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, Metrics.medium)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.hoursMissing, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendar-missing-fix")
    }
}

/// A compact list of the week's days, shown only in week scope where there is
/// room to say more than a grid cell can.
private struct WeekDayList: View {
    let days: [DayComputation]
    let settings: AppSettings
    let formatting: CalendarFormatting
    let onSelect: (CalendarDate) -> Void

    private var duration: DurationFormatting { settings.displayFormatting }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(days) { day in
                Button {
                    onSelect(day.date)
                } label: {
                    HStack(spacing: Metrics.medium) {
                        DayTypeBadge(definition: day.dayType, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(formatting.mediumDate(day.date))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(subtitle(for: day))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Metrics.small)
                        if settings.features.showsBalance && day.hasEntry {
                            BalanceText(
                                minutes: day.balanceMinutes,
                                formatting: duration,
                                font: .hoursFigure(.subheadline)
                            )
                        }
                    }
                    .padding(.vertical, Metrics.small)
                }
                .buttonStyle(.plain)

                if day.date != days.last?.date {
                    Divider().padding(.leading, 38)
                }
            }
        }
        .padding(.horizontal, Metrics.large)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    private func subtitle(for day: DayComputation) -> String {
        if let start = day.start, let end = day.end {
            let times = "\(formatting.time(start, on: day.date)) – \(formatting.time(end, on: day.date))"
            return "\(times)  ·  \(duration.string(day.workedMinutes))"
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

/// Above the grid while the period on screen is in a closed month: the
/// grid looks the same either way, and an editor refusing to save is a poor
/// way to find out.
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
            .font(.footnote)
            .foregroundStyle(.secondary)
            Spacer(minLength: Metrics.small)
            Button("Reopen", action: onReopen)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .accessibilityIdentifier("calendar-closed-reopen")
        }
        .padding(.horizontal, Metrics.medium)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
    }
}

/// A site's day opened from a calendar day worked on more than one site
/// (1.2): pushed by value, as every destination on a stack is here.
struct CalendarSiteRoute: Hashable {
    let siteID: UUID
    let date: CalendarDate
}
