import SwiftUI
import SwiftData

/// Today, under the month (design v2, mockup Main, "the month first"), as
/// inset-grouped sections of the Today tab's list:
///
/// 1. Today: "Today" in grey and the times large ("7:00 – 15:00"), the
///    hours and the site on the right; "Not written" when nothing is. Or
///    the running clock (`ClockCard`). Then This week and the balance.
/// 2. A row for each site whose crew day is due today and not written yet.
/// 3. The day's big buttons: Clock in, or Break and Clock out; "I worked the
///    usual day" while today is not written.
///
/// The month grid is above it and the month's totals under it
/// (`CalendarScreen`). Its body is sections, for the list it sits in.
struct TodaySection: View {
    let today: CalendarDate
    let settings: AppSettings
    let calendar: Calendar
    let formatting: CalendarFormatting
    let running: RunningShift?
    var onClockIn: () -> Void
    var onClockOut: () -> Void
    var onToggleBreak: () -> Void
    var onDiscard: () -> Void
    /// Writes today as the usual day.
    var onUsualDay: () -> Void
    /// Opens today in the editor.
    var onEdit: () -> Void
    /// Opens today's sheet, once something is written.
    var onOpenDay: () -> Void
    /// Opens today in the editor with your usual times in (a holiday or a
    /// day off you worked anyway).
    var onWorked: () -> Void
    /// Opens a site's day for today.
    var onOpenSite: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext

    /// Every day up to today, for the running balance: the balance has no
    /// beginning but the one the engine decides.
    @Query private var entries: [DayEntry]
    @Query private var holidayRecords: [HolidayRecord]
    /// Watched rather than read, as on the Sites list: the rows come from
    /// `SiteRepository`, which owns the duplicate rules.
    @Query private var siteEntries: [SiteEntry]
    @Query private var crewEntries: [CrewMemberEntry]
    @Query private var siteDayEntries: [SiteDayEntry]

    @State private var crewRows: [CrewDayToday.Row] = []

    init(
        today: CalendarDate,
        settings: AppSettings,
        calendar: Calendar,
        formatting: CalendarFormatting,
        running: RunningShift?,
        onClockIn: @escaping () -> Void,
        onClockOut: @escaping () -> Void,
        onToggleBreak: @escaping () -> Void,
        onDiscard: @escaping () -> Void,
        onUsualDay: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onOpenDay: @escaping () -> Void,
        onWorked: @escaping () -> Void,
        onOpenSite: @escaping (UUID) -> Void
    ) {
        self.today = today
        self.settings = settings
        self.calendar = calendar
        self.formatting = formatting
        self.running = running
        self.onClockIn = onClockIn
        self.onClockOut = onClockOut
        self.onToggleBreak = onToggleBreak
        self.onDiscard = onDiscard
        self.onUsualDay = onUsualDay
        self.onEdit = onEdit
        self.onOpenDay = onOpenDay
        self.onWorked = onWorked
        self.onOpenSite = onOpenSite
        let upper = today.key
        _entries = Query(filter: #Predicate<DayEntry> { $0.dateKey <= upper }, sort: \DayEntry.dateKey)
        _holidayRecords = Query(sort: \HolidayRecord.name)
        _siteEntries = Query(sort: \SiteEntry.sortOrder)
        _crewEntries = Query(sort: \CrewMemberEntry.sortOrder)
        let lower = today.adding(days: -SiteWorkDays.lookBackDays, in: calendar).key
        _siteDayEntries = Query(
            filter: #Predicate<SiteDayEntry> { $0.dateKey >= lower && $0.dateKey <= upper },
            sort: \SiteDayEntry.dateKey
        )
    }

    var body: some View {
        let figures = self.figures

        Section {
            Group {
                if let running, settings.features.useTimeClock {
                    ClockCard(
                        running: running,
                        settings: settings,
                        formatting: formatting,
                        siteName: clockSiteName(running),
                        onDiscard: onDiscard
                    )
                } else {
                    TodayDayCard(
                        computation: figures.today,
                        settings: settings,
                        formatting: formatting,
                        siteNames: siteNames,
                        onEdit: onEdit,
                        onOpenDay: onOpenDay
                    )
                }
            }
            // On the first row, which is always there: the crew rows are
            // read outside of `body` (see `reloadCrewRows`).
            .onChange(of: changeToken, initial: true) { _, _ in reloadCrewRows() }

            // Ticks once a minute while a clock runs, so the week moves with it.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                LabeledContent("This week") {
                    Text(verbatim: settings.displayFormatting.string(figures.weekWorked + runningMinutes(at: context.date)))
                        .monospacedDigit()
                }
            }
            .accessibilityIdentifier("today-week")

            if settings.features.showsBalance {
                LabeledContent("Balance") {
                    Text(verbatim: settings.displayFormatting.signedString(figures.balance))
                        .monospacedDigit()
                        // Coloured only when it is not nothing.
                        .foregroundStyle(Color.hoursBalance(figures.balance))
                }
                .accessibilityIdentifier("today-balance")
            } else {
                LabeledContent("This month") {
                    Text(verbatim: settings.displayFormatting.string(figures.monthWorked))
                        .monospacedDigit()
                }
                .accessibilityIdentifier("today-month")
            }
        }

        let prompts = crewRows.filter { !$0.isWritten }
        if !prompts.isEmpty {
            Section {
                ForEach(Array(prompts.enumerated()), id: \.element.id) { index, row in
                    CrewDayRow(row: row) { onOpenSite(row.siteID) }
                        .accessibilityIdentifier("today-crew-day-\(index)")
                }
            }
        }

        if hasActions(figures.today) {
            Section {
                actions(figures.today)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - The big buttons

    private func hasActions(_ day: DayComputation) -> Bool {
        settings.features.useTimeClock || !isWritten(day)
    }

    private func isWritten(_ day: DayComputation) -> Bool {
        day.hasEntry || day.workedMinutes > 0
    }

    /// The big buttons, one primary: Clock in, or Break and Clock out; and
    /// while today is not written, "I worked the usual day" (or "I worked"
    /// on a holiday or a day off).
    @ViewBuilder
    private func actions(_ day: DayComputation) -> some View {
        if let running, settings.features.useTimeClock {
            HStack(spacing: Metrics.small) {
                if settings.features.trackBreaks {
                    Button(action: onToggleBreak) {
                        Text(running.isOnBreak ? "Back to work" : "Break")
                    }
                    .buttonStyle(.bigAction(.secondary))
                    .accessibilityIdentifier("today-break")
                }
                Button(action: onClockOut) {
                    Text("Clock out")
                }
                .buttonStyle(.bigAction(.primary))
                .accessibilityIdentifier("today-clock-out")
            }
        } else {
            VStack(spacing: Metrics.small) {
                if settings.features.useTimeClock {
                    Button(action: onClockIn) {
                        Text("Clock in")
                    }
                    .buttonStyle(.bigAction(.positive))
                    .accessibilityIdentifier("today-clock-in")
                }
                if !isWritten(day) {
                    writeAction(day, kind: settings.features.useTimeClock ? .secondary : .primary)
                }
            }
        }
    }

    @ViewBuilder
    private func writeAction(_ day: DayComputation, kind: BigActionKind) -> some View {
        if TodayDayCard.isPublicHolidayOff(day) {
            Button(action: onWorked) {
                Text("I worked")
            }
            .buttonStyle(.bigAction(kind))
            .accessibilityHint(Text("Opens the day with your usual times filled in. The holiday stays paid."))
            .accessibilityIdentifier("day-card-holiday-worked")
        } else if DayKind.of(day.dayType) == .worked && day.dayType.expectation == .scheduled {
            Button(action: onUsualDay) {
                Text("I worked the usual day")
            }
            .buttonStyle(.bigAction(kind))
            .accessibilityIdentifier("today-usual-day")
        } else {
            Button(action: onWorked) {
                Text("I worked")
            }
            .buttonStyle(.bigAction(kind))
            .accessibilityIdentifier("today-worked")
        }
    }

    // MARK: - Figures

    private struct Figures {
        var today: DayComputation
        var weekWorked: Int
        var monthWorked: Int
        var balance: Int
    }

    private var holidays: [HolidayRule] { holidayRecords.map(\.rule) }

    /// Today, the week and the month through today, and the balance at the
    /// end of today: the engine's rules, as everywhere else.
    private var figures: Figures {
        var records: [Int: DayRecord] = [:]
        for entry in entries { records[entry.dateKey] = entry.record }
        let engine = PeriodEngine(
            settings: settings,
            calendar: calendar,
            firstRecorded: WorkdayRepository(context: modelContext).firstRecordedDate()
        )
        let week = CalendarDateRange.week(containing: today, in: calendar)
        let month = today.yearMonth.range(in: calendar)
        let span = CalendarDateRange(start: min(week.start, month.start), end: today)
        let days = engine.days(in: span, records: records, holidays: holidays)
        let todayDay = days.first { $0.date == today } ?? engine.day(today, record: records[today.key], holidays: holidays)
        let worked: (CalendarDateRange) -> Int = { range in
            days.filter { range.contains($0.date) && $0.isIncluded }.reduce(0) { $0 + $1.workedMinutes }
        }
        let balance = settings.features.showsBalance
            ? engine.runningBalance(through: today, holidays: holidays, countingThrough: today, records: { _ in records })
            : 0
        return Figures(today: todayDay, weekWorked: worked(week), monthWorked: worked(month), balance: balance)
    }

    /// The running clock's worked minutes, while it belongs to this week.
    private func runningMinutes(at instant: Date) -> Int {
        guard settings.features.useTimeClock, let running,
              CalendarDateRange.week(containing: today, in: calendar).contains(running.date)
        else { return 0 }
        return running.workedSeconds(at: instant) / 60
    }

    private func clockSiteName(_ running: RunningShift) -> String? {
        WidgetSnapshotBuilder.clockSiteName(for: running, among: siteEntries.map(\.site))
    }

    private var siteNames: [UUID: String] {
        Dictionary(siteEntries.map { ($0.site.id, $0.site.name) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Crew days

    private var changeToken: [Date] {
        siteEntries.map(\.updatedAt) + crewEntries.map(\.updatedAt) + siteDayEntries.map(\.updatedAt)
    }

    /// Read through the repository outside of `body`: its reads collapse
    /// duplicates, which writes, and a view must not write while drawn.
    private func reloadCrewRows() {
        let repository = SiteRepository(context: modelContext, lock: settings.monthLock)
        let sites = repository.sites(includeArchived: false)
        guard !sites.isEmpty else {
            crewRows = []
            return
        }
        let recent = repository.siteDays(
            siteID: nil,
            in: CalendarDateRange(start: today.adding(days: -SiteWorkDays.lookBackDays, in: calendar), end: today)
        )
        var holidayKeys = Set<Int>()
        if settings.features.trackHolidays {
            let range = CalendarDateRange(single: today)
            holidayKeys = HolidayResolver(rules: holidays, calendar: calendar, covering: range)
                .daysOffKeys(in: range, calendar: calendar)
        }
        var written: [UUID: SiteDay] = [:]
        for day in recent where day.date == today { written[day.siteID] = day }
        var expected = Set<UUID>()
        var coworkers: [UUID: Int] = [:]
        for site in sites {
            coworkers[site.id] = repository.crew(for: site.id, includeHidden: false).count
            if SiteWorkDays.expects(
                site.id, on: today, setup: settings.siteSetup(for: site.id),
                siteDays: recent, calendar: calendar, holidays: holidayKeys
            ) {
                expected.insert(site.id)
            }
        }
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        crewRows = CrewDayToday.rows(
            sites: sites,
            written: written,
            expected: expected,
            coworkers: coworkers,
            crewMinutes: { calculator.compute($0).crewTotalMinutes }
        )
    }
}

/// Today's row: "Today" in grey over the times, large, and the hours and
/// the site on the right; "Not written" while nothing is, a holiday or a
/// day off by its name. A written day opens its sheet; one not written
/// opens the editor.
struct TodayDayCard: View {
    let computation: DayComputation
    let settings: AppSettings
    let formatting: CalendarFormatting
    var siteNames: [UUID: String] = [:]
    let onEdit: () -> Void
    let onOpenDay: () -> Void

    private var duration: DurationFormatting { settings.displayFormatting }

    /// A public holiday off with nothing worked: "Day off (paid)", and
    /// "I worked" for one worked anyway.
    static func isPublicHolidayOff(_ day: DayComputation) -> Bool {
        day.holidayName != nil && day.dayType.id == .holiday && day.workedMinutes == 0 && !day.hasEntry
    }

    private var isWritten: Bool { computation.hasEntry || computation.workedMinutes > 0 }

    var body: some View {
        Button(action: isWritten ? onOpenDay : onEdit) {
            HStack(alignment: .center, spacing: Metrics.medium) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                    figure
                }
                Spacer(minLength: Metrics.small)
                VStack(alignment: .trailing, spacing: 1) {
                    if let trailing {
                        Text(verbatim: trailing)
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    if let detail {
                        Text(verbatim: detail)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.hoursSecondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, Metrics.tiny)
            .contentShape(Rectangle())
        }
        .accessibilityHint(Text("Opens today"))
        .accessibilityIdentifier("today-card")
    }

    @ViewBuilder
    private var figure: some View {
        if Self.isPublicHolidayOff(computation) {
            Label {
                Text("Day off (paid)")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.hoursDone)
            }
            .font(.title2.weight(.semibold))
            .foregroundStyle(.primary)
            .accessibilityIdentifier("day-card-holiday-off")
        } else {
            Text(verbatim: figureText)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var title: String {
        if Self.isPublicHolidayOff(computation), let name = computation.holidayName {
            return String(
                localized: "\(name) · public holiday",
                comment: "Day editor: the holiday's name, e.g. Christmas Day · public holiday"
            )
        }
        return String(localized: "Today")
    }

    private var expectsWork: Bool {
        DayKind.of(computation.dayType) == .worked && computation.dayType.expectation == .scheduled
    }

    /// The big line: the times worked, else "Not written" or the day's type.
    private var figureText: String {
        if isWritten {
            if let start = computation.start, let end = computation.end {
                return "\(formatting.time(start, on: computation.date)) – \(formatting.time(end, on: computation.date))"
            }
            return duration.string(computation.workedMinutes)
        }
        if expectsWork { return String(localized: "Not written") }
        return computation.dayType.displayName()
    }

    /// On the right, large: the hours worked, or credited for a paid day off.
    private var trailing: String? {
        if isWritten, computation.start != nil, computation.workedMinutes > 0 {
            return duration.string(computation.workedMinutes)
        }
        if !isWritten, computation.creditedMinutes > 0 {
            return duration.string(computation.creditedMinutes)
        }
        return nil
    }

    /// On the right, in grey: the site, or the usual times not written yet.
    private var detail: String? {
        if isWritten {
            let sites = Set(computation.shifts.compactMap(\.siteID))
            guard sites.count == 1, let site = sites.first else { return nil }
            return siteNames[site]
        }
        guard expectsWork else { return nil }
        let schedule = settings.primarySchedule(on: computation.date)
        return "\(formatting.time(schedule.defaultStart, on: computation.date)) – \(formatting.time(schedule.defaultEnd, on: computation.date))"
    }
}

/// A site whose crew day is due today and not written: an orange dot, the
/// site, "Crew not written today" and Write. The whole row opens the site's
/// day.
struct CrewDayRow: View {
    let row: CrewDayToday.Row
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.medium) {
                Circle()
                    // Orange: look at this. Today is not over, so it is not
                    // missing yet.
                    .fill(Color.hoursAttentionFill)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.siteName)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("Crew not written today")
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                }
                Spacer(minLength: Metrics.small)
                // Drawn as a small bordered capsule; the row is the button.
                Text("Write")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            }
            .padding(.vertical, Metrics.tiny)
            .contentShape(Rectangle())
        }
    }
}
