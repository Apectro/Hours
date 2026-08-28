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

    @State private var anchorDate = CalendarDate.today(in: .current)
    @State private var selectedDate = CalendarDate.today(in: .current)
    @State private var activeSheet: ActiveSheet?

    /// One sheet at a time, chosen by value. Stacking several `.sheet`
    /// modifiers on a single view has undefined behaviour.
    private enum ActiveSheet: Identifiable {
        case day(CalendarDate)
        case export(CalendarDateRange)
        case bulkEdit(CalendarDateRange)

        var id: String {
            switch self {
            case let .day(date): return "day-\(date.key)"
            case let .export(range): return "export-\(range.start.key)-\(range.end.key)"
            case let .bulkEdit(range): return "bulk-\(range.start.key)-\(range.end.key)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if settings.features.useTimeClock, let running = clockStore.running {
                    ClockCard(
                        running: running,
                        settings: settings,
                        formatting: settingsStore.dateFormatting,
                        onClockOut: clockOut,
                        onDiscard: { timeClock.discard() }
                    )
                    .padding(.bottom, Metrics.large)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                PeriodDataProvider(range: layout.coveredRange) { data in
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
                        onSelect: select,
                        onEdit: { activeSheet = .day(selectedDate) },
                        onClockIn: showsClockInOnSelectedDay ? clockIn : nil
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
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case let .day(date):
                    DayEditorSheet(date: date)
                case let .export(range):
                    ExportScreen(initialRange: range)
                case let .bulkEdit(range):
                    BulkEditSheet(initialRange: range)
                }
            }
        }
    }

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

    private func goToToday() {
        withAnimation(.snappy(duration: 0.25)) {
            anchorDate = today
            selectedDate = today
        }
    }

    private func setScope(_ newScope: CalendarScope) {
        settingsStore.update { $0.calendar.preferredScope = newScope }
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

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(scope == .month ? "Next month" : "Next week")

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

                Button {
                    activeSheet = .export(summaryRange)
                } label: {
                    Label("Export…", systemImage: "square.and.arrow.up")
                }
                // On the control, not on its label: the accessibility element
                // a UI test can tap is the button.
                .accessibilityIdentifier("calendar-export")
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
    let onSelect: (CalendarDate) -> Void
    let onEdit: () -> Void
    let onClockIn: (() -> Void)?

    private let computationsByKey: [Int: DayComputation]
    private let summary: PeriodSummary
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
        onSelect: @escaping (CalendarDate) -> Void,
        onEdit: @escaping () -> Void,
        onClockIn: (() -> Void)? = nil
    ) {
        self.layout = layout
        self.settings = settings
        self.formatting = formatting
        self.selectedDate = selectedDate
        self.today = today
        self.scope = scope
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onClockIn = onClockIn

        let engine = PeriodEngine(settings: settings, calendar: calendar)
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
        self.selectedComputation = byKey[selectedDate.key] ?? DayComputation.empty(on: selectedDate)
        self.weekDays = scope == .week
            ? resolved.filter { summaryRange.contains($0.date) }
            : []
    }

    var body: some View {
        VStack(spacing: Metrics.large) {
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

            if settings.calendar.showMonthSummary {
                PeriodSummaryBar(
                    summary: summary,
                    settings: settings,
                    catalog: settings.dayTypeCatalog
                )
            }

            DaySummaryCard(
                computation: selectedComputation,
                settings: settings,
                formatting: formatting,
                onEdit: onEdit,
                onClockIn: onClockIn
            )

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
            return "\(day.dayType.name)  ·  \(duration.string(day.creditedMinutes)) credited"
        }
        return day.dayType.name
    }
}
