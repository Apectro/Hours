import SwiftUI
import SwiftData

/// The main screen.
///
/// One anchor date drives everything: which month or week is on screen, what
/// the totals cover, and what the summary underneath describes. Selecting a day
/// never navigates away — the grid stays put and the detail appears beneath it.
struct CalendarScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(ActiveShiftStore.self) private var clockStore
    @Environment(\.modelContext) private var modelContext
    @Environment(TourCoordinator.self) private var tour: TourCoordinator?

    @State private var anchorDate = CalendarDate.today(in: .current)
    @State private var selectedDate = CalendarDate.today(in: .current)
    @State private var activeSheet: ActiveSheet?
    /// Reopening a closed month is deliberate, so it is asked once more.
    @State private var monthToReopen: YearMonth?
    /// Only whether there are any, for the one-time public holidays card.
    @Query private var holidayRecords: [HolidayRecord]
    /// Every site, archived too, for the names on a day worked on two sites.
    @Query(sort: \SiteEntry.sortOrder) private var siteEntries: [SiteEntry]
    /// A site's day opened from the day card, pushed by value; the site's
    /// crew from there, as on the Sites tab.
    @State private var path = NavigationPath()

    /// One sheet at a time, chosen by value. Stacking several `.sheet`
    /// modifiers on a single view has undefined behaviour.
    private enum ActiveSheet: Identifiable {
        case day(CalendarDate)
        case export(CalendarDateRange)
        case bulkEdit(CalendarDateRange)
        case publicHolidays
        /// "I worked" on a public holiday: the editor, times filled in.
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
                    if settings.features.useTimeClock, let running = clockStore.running {
                        ClockCard(
                            running: running,
                            settings: settings,
                            formatting: settingsStore.dateFormatting,
                            onClockOut: clockOut,
                            onDiscard: discard
                        )
                        .padding(.bottom, Metrics.large)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if showsPublicHolidayOffer {
                        PublicHolidayOfferCard(
                            onChoose: { activeSheet = .publicHolidays },
                            onDismiss: dismissPublicHolidayOffer
                        )
                        .padding(.horizontal, Metrics.large)
                        .padding(.top, Metrics.small)
                        .transition(.opacity)
                    }

                    PeriodDataProvider(range: fetchedRange) { data in
                        CalendarPeriodView(
                            layout: layout,
                            summaryRange: summaryRange,
                            data: data,
                            settings: settings,
                            calendar: calendar,
                            formatting: settingsStore.dateFormatting,
                            selectedDate: selectedDate,
                            today: today,
                            scope: scope,
                            closedMonth: closedMonthOnScreen,
                            onSelect: select,
                            onStep: step,
                            onEdit: { activeSheet = .day(selectedDate) },
                            onWorkedHoliday: { activeSheet = .workedHoliday(selectedDate) },
                            onClockIn: showsClockInOnSelectedDay ? clockIn : nil,
                            onExport: { activeSheet = .export(summaryRange) },
                            onReopen: { monthToReopen = $0 },
                            siteNames: siteNames,
                            onOpenSite: { path.append(CalendarSiteRoute(siteID: $0, date: selectedDate)) }
                        )
                    }
                    .padding(.horizontal, Metrics.large)
                    .padding(.top, Metrics.small)
                    .padding(.bottom, Metrics.extraLarge)
                }
                .background(Color.hoursCanvas)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar { toolbarContent }
                // The tour's stops on the calendar: what they point at has to be
                // on screen. The totals sit under the day card, below the fold on
                // a small phone.
                .onChange(of: tour?.tour?.stop) { _, stop in
                    if stop == .today {
                        goToToday()
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

    /// Every site's name by id. For display only: a duplicate left by sync
    /// just means the first of the two names is used.
    private var siteNames: [UUID: String] {
        Dictionary(siteEntries.map { ($0.site.id, $0.site.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// Where the tour's totals stop scrolls to.
    static let summaryAnchor = "calendar-summary"

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

    private var title: String {
        let formatting = settingsStore.dateFormatting
        switch scope {
        case .month:
            return formatting.monthTitle(anchorDate.yearMonth)
        case .week:
            let range = summaryRange
            return "\(formatting.shortDate(range.start)) – \(formatting.shortDate(range.end))"
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

    private func select(_ date: CalendarDate) {
        if selectedDate == date {
            activeSheet = .day(date)
            return
        }
        withAnimation(.snappy(duration: 0.2)) {
            selectedDate = date
            // Tapping a day borrowed from the next month moves the grid there,
            // rather than selecting something the user can no longer see.
            if scope == .month && !anchorDate.yearMonth.contains(date) {
                anchorDate = date
            }
        }
    }

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
            if !summaryRange.contains(selectedDate) {
                selectedDate = anchorDate
            }
        }
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

    /// Offered on today only, and only while nothing is already running.
    private var showsClockInOnSelectedDay: Bool {
        settings.features.useTimeClock
            && clockStore.running == nil
            && selectedDate == today
    }

    private func clockIn() {
        withAnimation(.snappy(duration: 0.25)) {
            // Discarded deliberately: a second tap while a clock is already
            // running returns nil, and there is nothing for the UI to do about
            // it beyond leaving the running clock alone.
            _ = timeClock.clockIn()
        }
        HoursStack.refreshWidget()
    }

    private func clockOut() {
        withAnimation(.snappy(duration: 0.25)) {
            let result = timeClock.clockOut()
            // Stopping a clock that was started on an earlier day should show
            // the day it belonged to, not the day you happened to stop it.
            if case let .recorded(date, _, _) = result {
                selectedDate = date
                if !summaryRange.contains(date) { anchorDate = date }
            }
        }
        HoursStack.refreshWidget()
    }

    /// Nothing is recorded, but the widget and the Live Activity were both
    /// showing a running clock, so they are told it stopped.
    private func discard() {
        timeClock.discard()
        HoursStack.refreshWidget()
    }

    private func goToToday() {
        withAnimation(.snappy(duration: 0.25)) {
            anchorDate = today
            selectedDate = today
        }
    }

    private func setScope(_ newScope: CalendarScope) {
        settingsStore.update { $0.calendar.preferredScope = newScope }
    }

    // MARK: - Closing a month

    private func closeMonth(_ month: YearMonth) {
        settingsStore.update { $0.monthLock.lock(month) }
    }

    private func reopen(_ month: YearMonth) {
        settingsStore.update { $0.monthLock.unlock(month) }
        monthToReopen = nil
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Today", action: goToToday)
                .disabled(selectedDate == today && summaryRange.contains(today))
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(scope == .month ? "Previous month" : "Previous week")
            .accessibilityIdentifier("calendar-previous")

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(scope == .month ? "Next month" : "Next week")
            .accessibilityIdentifier("calendar-next")

            // Out of the menu: sending a month's hours is a monthly job, and
            // it was the one thing people could not find.
            Button {
                activeSheet = .export(summaryRange)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Export")
            // On the control, not on its label: the accessibility element
            // a UI test can tap is the button.
            .accessibilityIdentifier("calendar-export")

            Menu {
                Picker("View", selection: Binding(get: { scope }, set: setScope)) {
                    ForEach(CalendarScope.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)

                Divider()

                Button {
                    // Seeded with the selected day rather than the whole month:
                    // a range edit almost always starts from a day you are
                    // looking at, and widening is easier than narrowing.
                    activeSheet = .bulkEdit(CalendarDateRange(single: selectedDate))
                } label: {
                    Label("Edit a range…", systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("calendar-edit-range")

                // Closing a month lives where months are. Settings › Balance & rounding ›
                // Closed months lists them all.
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
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("calendar-more")
        }
    }
}

/// Everything below the navigation bar for one visible period.
///
/// The engine runs once, in `init`, and the result is handed to the grid, the
/// totals and the day summary — so the three can never disagree, and nothing is
/// recomputed while SwiftUI diffs the body.
private struct CalendarPeriodView: View {
    let layout: MonthLayout
    let settings: AppSettings
    let formatting: CalendarFormatting
    let selectedDate: CalendarDate
    let today: CalendarDate
    let scope: CalendarScope
    let closedMonth: YearMonth?
    let onSelect: (CalendarDate) -> Void
    let onStep: (Int) -> Void
    let onEdit: () -> Void
    let onWorkedHoliday: () -> Void
    let onClockIn: (() -> Void)?
    let onExport: () -> Void
    let onReopen: (YearMonth) -> Void
    /// Site names, for a day worked on two sites, and the way to its sites.
    var siteNames: [UUID: String] = [:]
    var onOpenSite: ((UUID) -> Void)? = nil

    private let computationsByKey: [Int: DayComputation]
    private let summary: PeriodSummary
    /// What the period earned through today, while earnings are the main
    /// figure.
    private let earnings: EarningsSummary?
    /// Field allowance, kilometres and travel through today, while they are
    /// tracked.
    private let allowance: AllowanceSummary
    private let selectedComputation: DayComputation
    private let weekDays: [DayComputation]

    init(
        layout: MonthLayout,
        summaryRange: CalendarDateRange,
        data: PeriodData,
        settings: AppSettings,
        calendar: Calendar,
        formatting: CalendarFormatting,
        selectedDate: CalendarDate,
        today: CalendarDate,
        scope: CalendarScope,
        closedMonth: YearMonth?,
        onSelect: @escaping (CalendarDate) -> Void,
        onStep: @escaping (Int) -> Void,
        onEdit: @escaping () -> Void,
        onWorkedHoliday: @escaping () -> Void,
        onClockIn: (() -> Void)? = nil,
        onExport: @escaping () -> Void,
        onReopen: @escaping (YearMonth) -> Void,
        siteNames: [UUID: String] = [:],
        onOpenSite: ((UUID) -> Void)? = nil
    ) {
        self.siteNames = siteNames
        self.onOpenSite = onOpenSite
        self.layout = layout
        self.settings = settings
        self.formatting = formatting
        self.selectedDate = selectedDate
        self.today = today
        self.scope = scope
        self.closedMonth = closedMonth
        self.onSelect = onSelect
        self.onStep = onStep
        self.onEdit = onEdit
        self.onWorkedHoliday = onWorkedHoliday
        self.onClockIn = onClockIn
        self.onExport = onExport
        self.onReopen = onReopen

        let engine = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: data.firstRecorded)
        // The grid can show days from neighbouring months, and the selected day
        // can be one of them, so resolve the union of both spans in one pass.
        let span = CalendarDateRange(
            start: min(layout.coveredRange.start, min(summaryRange.start, selectedDate)),
            end: max(layout.coveredRange.end, max(summaryRange.end, selectedDate))
        )
        let resolved = engine.days(in: span, records: data.records, holidays: data.holidays)

        var byKey: [Int: DayComputation] = [:]
        byKey.reserveCapacity(resolved.count)
        for day in resolved { byKey[day.date.key] = day }
        self.computationsByKey = byKey

        self.summary = PeriodAggregator.summarize(
            resolved.filter { summaryRange.contains($0.date) },
            range: summaryRange,
            countingThrough: today
        )
        self.earnings = settings.showsEarnings
            ? engine.earnings(in: summaryRange, records: data.records, holidays: data.holidays, countingThrough: today)
            : nil
        self.allowance = AllowanceSummary(
            days: resolved.filter { summaryRange.contains($0.date) },
            settings: settings,
            countingThrough: today
        )
        self.selectedComputation = byKey[selectedDate.key] ?? DayComputation.empty(on: selectedDate)
        self.weekDays = scope == .week
            ? resolved.filter { summaryRange.contains($0.date) }
            : []
    }

    var body: some View {
        VStack(spacing: Metrics.large) {
            if let closedMonth {
                ClosedMonthNotice(month: closedMonth, formatting: formatting) { onReopen(closedMonth) }
            }

            CalendarMonthGrid(
                layout: layout,
                computations: computationsByKey,
                selectedDate: selectedDate,
                today: today,
                detail: settings.calendar.dayCellDetail,
                formatting: formatting,
                durationFormatting: settings.displayFormatting,
                onSelect: onSelect
            )
            // A sideways swipe pages the period, as the toolbar arrows do.
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

            // The selected day first, right under the grid: a tap on a day
            // has to show its card without scrolling, or it looks like the
            // tap did nothing.
            DaySummaryCard(
                computation: selectedComputation,
                settings: settings,
                formatting: formatting,
                onEdit: onEdit,
                onWorkedHoliday: onWorkedHoliday,
                onClockIn: onClockIn,
                siteNames: siteNames,
                onOpenSite: onOpenSite
            )

            if settings.calendar.showMonthSummary {
                PeriodSummaryBar(
                    summary: summary,
                    settings: settings,
                    catalog: settings.dayTypeCatalog,
                    earnings: earnings,
                    allowance: allowance,
                    onExport: onExport
                )
                .tourTarget(.calendarSummary)
                .id(CalendarScreen.summaryAnchor)
            }

            if scope == .week && !weekDays.isEmpty {
                WeekDayList(
                    days: weekDays,
                    settings: settings,
                    formatting: formatting,
                    selectedDate: selectedDate,
                    onSelect: onSelect
                )
            }
        }
    }
}

/// A compact list of the week's days, shown only in week scope where there is
/// room to say more than a grid cell can.
private struct WeekDayList: View {
    let days: [DayComputation]
    let settings: AppSettings
    let formatting: CalendarFormatting
    let selectedDate: CalendarDate
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
