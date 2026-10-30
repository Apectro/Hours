import SwiftUI
import SwiftData

/// What the Today tab opens on (1.2, mockup Today, first two phones): the
/// date and a big "Today", then either today's usual day or the running
/// clock, two tiles (this week, the balance), a row for each site whose
/// crew day is due today, and the day's big buttons at the bottom — Clock in
/// and "I worked the usual day", or Break and Clock out.
///
/// The month follows under it, on the same scroll (`CalendarScreen`).
struct TodaySection: View {
    let today: CalendarDate
    let settings: AppSettings
    let calendar: Calendar
    let formatting: CalendarFormatting
    let running: RunningShift?
    /// The ⋯ menu, drawn beside the title.
    let menu: AnyView
    var onClockIn: () -> Void
    var onClockOut: () -> Void
    var onToggleBreak: () -> Void
    var onDiscard: () -> Void
    /// Writes today as the usual day.
    var onUsualDay: () -> Void
    /// Opens today in the editor.
    var onEdit: () -> Void
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
        menu: AnyView,
        onClockIn: @escaping () -> Void,
        onClockOut: @escaping () -> Void,
        onToggleBreak: @escaping () -> Void,
        onDiscard: @escaping () -> Void,
        onUsualDay: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onWorked: @escaping () -> Void,
        onOpenSite: @escaping (UUID) -> Void
    ) {
        self.today = today
        self.settings = settings
        self.calendar = calendar
        self.formatting = formatting
        self.running = running
        self.menu = menu
        self.onClockIn = onClockIn
        self.onClockOut = onClockOut
        self.onToggleBreak = onToggleBreak
        self.onDiscard = onDiscard
        self.onUsualDay = onUsualDay
        self.onEdit = onEdit
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
        VStack(alignment: .leading, spacing: Metrics.medium) {
            header

            if let running, settings.features.useTimeClock {
                ClockCard(
                    running: running,
                    settings: settings,
                    formatting: formatting,
                    siteName: clockSiteName(running),
                    onDiscard: onDiscard
                )
                .transition(.opacity)
            } else {
                TodayDayCard(
                    computation: figures.today,
                    settings: settings,
                    formatting: formatting,
                    onEdit: onEdit
                )
            }

            tiles(figures)

            ForEach(Array(crewRows.enumerated()), id: \.element.id) { index, row in
                CrewDayRow(row: row, duration: settings.displayFormatting) { onOpenSite(row.siteID) }
                    .accessibilityIdentifier("today-crew-day-\(index)")
            }

            Spacer(minLength: Metrics.medium)

            actions(figures.today)
        }
        .onChange(of: changeToken, initial: true) { _, _ in reloadCrewRows() }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: Metrics.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: formatting.dayTitle(today))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.hoursSecondaryText)
                Text("Today")
                    .font(.largeTitle.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            menu
        }
    }

    @ViewBuilder
    private func tiles(_ figures: Figures) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.small) { tileList(figures) }
            VStack(spacing: Metrics.small) { tileList(figures) }
        }
    }

    @ViewBuilder
    private func tileList(_ figures: Figures) -> some View {
        // Ticks once a minute while a clock runs, so the week moves with it.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let running = runningMinutes(at: context.date)
            TodayTile(
                label: String(localized: "This week"),
                value: settings.displayFormatting.string(figures.weekWorked + running),
                tint: .primary
            )
            .accessibilityIdentifier("today-week")
        }
        if settings.features.showsBalance {
            TodayTile(
                label: String(localized: "Balance"),
                value: settings.displayFormatting.signedString(figures.balance),
                tint: Color.hoursBalance(figures.balance)
            )
            .accessibilityIdentifier("today-balance")
        } else {
            TodayTile(
                label: String(localized: "This month"),
                value: settings.displayFormatting.string(figures.monthWorked),
                tint: .primary
            )
            .accessibilityIdentifier("today-month")
        }
    }

    /// The big buttons, at the bottom where the thumb is.
    @ViewBuilder
    private func actions(_ day: DayComputation) -> some View {
        if let running, settings.features.useTimeClock {
            HStack(spacing: Metrics.small) {
                if settings.features.trackBreaks {
                    Button(action: onToggleBreak) {
                        Text(running.isOnBreak ? "Back to work" : "Break")
                    }
                    .buttonStyle(.bigAction(.secondary, isMain: true))
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                    .accessibilityIdentifier("today-break")
                }
                Button(action: onClockOut) {
                    Text("Clock out")
                }
                .buttonStyle(.bigAction(.warning, isMain: true))
                .frame(maxWidth: .infinity)
                .layoutPriority(2)
                .accessibilityIdentifier("today-clock-out")
            }
        } else {
            VStack(spacing: Metrics.small) {
                if settings.features.useTimeClock {
                    Button(action: onClockIn) {
                        Text("Clock in")
                    }
                    .buttonStyle(.bigAction(.positive, isMain: true))
                    .accessibilityIdentifier("today-clock-in")
                }
                secondaryAction(day)
            }
        }
    }

    @ViewBuilder
    private func secondaryAction(_ day: DayComputation) -> some View {
        let isMain = !settings.features.useTimeClock
        if TodayDayCard.isPublicHolidayOff(day) {
            Button(action: onWorked) {
                Text("I worked")
            }
            .buttonStyle(.bigAction(isMain ? BigActionKind.primary : BigActionKind.secondary, isMain: isMain))
            .accessibilityHint(Text("Opens the day with your usual times filled in. The holiday stays paid."))
            .accessibilityIdentifier("day-card-holiday-worked")
        } else if day.hasEntry || day.workedMinutes > 0 {
            Button(action: onEdit) {
                Text("Edit today")
            }
            .buttonStyle(.bigAction(.secondary, isMain: isMain))
            .accessibilityIdentifier("today-edit")
        } else if DayKind.of(day.dayType) == .worked && day.dayType.expectation == .scheduled {
            Button(action: onUsualDay) {
                Text("I worked the usual day")
            }
            .buttonStyle(.bigAction(isMain ? BigActionKind.primary : BigActionKind.secondary, isMain: isMain))
            .accessibilityIdentifier("today-usual-day")
        } else {
            Button(action: onWorked) {
                Text("I worked")
            }
            .buttonStyle(.bigAction(isMain ? BigActionKind.primary : BigActionKind.secondary, isMain: isMain))
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

/// Today's day before any clock runs: the usual day (times, break,
/// expected), what is already written, or a holiday, a day off or leave in
/// the same card. Tapping it opens the day in the editor.
struct TodayDayCard: View {
    let computation: DayComputation
    let settings: AppSettings
    let formatting: CalendarFormatting
    let onEdit: () -> Void

    private var duration: DurationFormatting { settings.displayFormatting }

    /// A public holiday off with nothing worked: "Day off (paid)", and
    /// "I worked" for one worked anyway.
    static func isPublicHolidayOff(_ day: DayComputation) -> Bool {
        day.holidayName != nil && day.dayType.id == .holiday && day.workedMinutes == 0 && !day.hasEntry
    }

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.hoursSecondaryText)
                    Spacer(minLength: Metrics.small)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if Self.isPublicHolidayOff(computation) {
                    Label {
                        Text("Day off (paid)")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.hoursPositive)
                    }
                    .font(.title2.weight(.bold))
                    .accessibilityIdentifier("day-card-holiday-off")
                } else if let figure {
                    Text(verbatim: figure)
                        .font(.hoursFigure(.title, weight: .heavy))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                if !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Metrics.large)
            .padding(.vertical, Metrics.medium + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens today"))
        .accessibilityIdentifier("today-card")
    }

    private var isWritten: Bool { computation.hasEntry || computation.workedMinutes > 0 }

    private var title: String {
        if Self.isPublicHolidayOff(computation), let name = computation.holidayName {
            return String(
                localized: "\(name) · public holiday",
                comment: "Day editor: the holiday's name, e.g. Christmas Day · public holiday"
            )
        }
        if isWritten { return String(localized: "Written today") }
        switch DayKind.of(computation.dayType) {
        case .worked where computation.dayType.expectation == .scheduled:
            return String(localized: "Your usual day")
        default:
            return computation.dayType.displayName()
        }
    }

    /// The big line: the times worked or expected, else the day's type.
    private var figure: String? {
        if isWritten {
            if let start = computation.start, let end = computation.end {
                return "\(formatting.time(start, on: computation.date))–\(formatting.time(end, on: computation.date))"
            }
            return duration.string(computation.workedMinutes)
        }
        if DayKind.of(computation.dayType) == .worked && computation.dayType.expectation == .scheduled {
            let schedule = settings.primarySchedule(on: computation.date)
            return "\(formatting.time(schedule.defaultStart, on: computation.date))–\(formatting.time(schedule.defaultEnd, on: computation.date))"
        }
        if computation.creditedMinutes > 0 { return computation.dayType.displayName() }
        return String(localized: "Nothing expected")
    }

    /// "30 min break · 8h 30m expected", or what was written.
    private var detail: String {
        var parts: [String] = []
        if isWritten {
            parts.append(String(
                localized: "\(duration.string(computation.workedMinutes)) worked",
                comment: "VoiceOver, the hours worked on a calendar day"
            ))
            if settings.features.trackExpectedHours && computation.expectedMinutes > 0 {
                parts.append(String(
                    localized: "\(duration.string(computation.expectedMinutes)) expected",
                    comment: "Today: the hours expected of the day, e.g. 8h 30m expected"
                ))
            }
            return parts.joined(separator: " · ")
        }
        if computation.creditedMinutes > 0 {
            return String(
                localized: "\(duration.string(computation.creditedMinutes)) credited.",
                comment: "A paid day off: the hours credited for it, e.g. 8 h credited."
            )
        }
        guard DayKind.of(computation.dayType) == .worked && computation.dayType.expectation == .scheduled else { return "" }
        let schedule = settings.primarySchedule(on: computation.date)
        if settings.features.trackBreaks && schedule.defaultBreakMinutes > 0 {
            parts.append(String(
                localized: "\(duration.string(schedule.defaultBreakMinutes)) break",
                comment: "The running clock: the breaks already taken, e.g. 30m break"
            ))
        }
        if settings.features.trackExpectedHours {
            parts.append(String(
                localized: "\(duration.string(computation.expectedMinutes)) expected",
                comment: "Today: the hours expected of the day, e.g. 8h 30m expected"
            ))
        }
        return parts.joined(separator: " · ")
    }
}

/// One of Today's two figures.
struct TodayTile: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.hoursSecondaryText)
            Text(verbatim: value)
                .font(.hoursFigure(.title2, weight: .heavy))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(.horizontal, Metrics.medium + 2)
        .padding(.vertical, Metrics.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// "Crew day not written · Trg Pravde · 5 people · Write", or written with
/// a green dot, who was there and the crew's hours, and Open.
struct CrewDayRow: View {
    let row: CrewDayToday.Row
    let duration: DurationFormatting
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.medium) {
                Circle()
                    // Green: done. Orange: look at this (today is not over,
                    // so it is not missing yet).
                    .fill(row.isWritten ? Color.hoursPositive : Color.hoursAttentionFill)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.isWritten ? "Crew day written" : "Crew day not written")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Metrics.small)
                Text(row.isWritten ? "Open" : "Write")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, Metrics.large)
            .padding(.vertical, Metrics.medium)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let people = String(inflected: "^[\(row.people) person](inflect: true)")
        var parts = [row.siteName, people]
        if let minutes = row.crewMinutes { parts.append(duration.string(minutes)) }
        return parts.joined(separator: " · ")
    }
}
