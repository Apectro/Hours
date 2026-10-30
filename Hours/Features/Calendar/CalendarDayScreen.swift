import SwiftUI
import SwiftData

/// A day opened from the month, pushed by value (1.2).
struct CalendarDayRoute: Hashable {
    let date: CalendarDate
}

/// A day tapped in the month (1.2, mockup Today, phone 4): the weekday and
/// the date large with Edit beside them; the hours — a row per site when the
/// day was split — and the Worked total; Expected, Overtime and the balance
/// after this day; and the allowance, kilometres and note. Reading a day
/// costs no sheet; Edit opens the editor.
struct CalendarDayScreen: View {
    let date: CalendarDate

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext

    /// Every day up to this one, for the balance after it.
    @Query private var entries: [DayEntry]
    @Query private var holidayRecords: [HolidayRecord]
    /// Every site, archived too, for the names on a split day.
    @Query(sort: \SiteEntry.sortOrder) private var siteEntries: [SiteEntry]

    @State private var sheet: DaySheet?

    private enum DaySheet: Identifiable {
        case edit
        case worked
        var id: Int { self == .edit ? 0 : 1 }
    }

    init(date: CalendarDate) {
        self.date = date
        let upper = date.key
        _entries = Query(filter: #Predicate<DayEntry> { $0.dateKey <= upper }, sort: \DayEntry.dateKey)
        _holidayRecords = Query(sort: \HolidayRecord.name)
    }

    var body: some View {
        let figures = self.figures
        ScrollView {
            DayDetailContent(
                computation: figures.day,
                balanceAfter: figures.balance,
                settings: settings,
                formatting: settingsStore.dateFormatting,
                siteNames: siteNames,
                onEdit: { sheet = .edit },
                onWorkedHoliday: { sheet = .worked }
            )
            .padding(.horizontal, Metrics.large)
            .padding(.bottom, Metrics.extraLarge)
        }
        .background(Color.hoursCanvas)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen-calendar-day")
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit: DayEditorSheet(date: date)
            case .worked: DayEditorSheet(date: date, startsWorking: true)
            }
        }
    }

    private var settings: AppSettings { settingsStore.settings }

    private var siteNames: [UUID: String] {
        Dictionary(siteEntries.map { ($0.site.id, $0.site.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// The day as the engine resolves it, and the running balance at its
    /// end — the rule Insights and the export use.
    private var figures: (day: DayComputation, balance: Int) {
        var records: [Int: DayRecord] = [:]
        for entry in entries { records[entry.dateKey] = entry.record }
        let calendar = settingsStore.workCalendar
        let holidays = holidayRecords.map(\.rule)
        let engine = PeriodEngine(
            settings: settings,
            calendar: calendar,
            firstRecorded: WorkdayRepository(context: modelContext).firstRecordedDate()
        )
        let day = engine.day(date, record: records[date.key], holidays: holidays)
        let balance = settings.features.showsBalance
            ? engine.runningBalance(
                through: date,
                holidays: holidays,
                countingThrough: CalendarDate.today(in: calendar),
                records: { _ in records }
            )
            : 0
        return (day, balance)
    }
}

/// The day screen's cards, apart from the data that feeds them.
struct DayDetailContent: View {
    let computation: DayComputation
    let balanceAfter: Int
    let settings: AppSettings
    let formatting: CalendarFormatting
    var siteNames: [UUID: String] = [:]
    let onEdit: () -> Void
    /// "I worked" on a public holiday off: the editor with the day's times
    /// filled in, the holiday still paid.
    var onWorkedHoliday: (() -> Void)? = nil

    private var duration: DurationFormatting { settings.displayFormatting }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            header

            if isPublicHolidayOff {
                publicHolidayChoice
            } else if computation.hasEntry || computation.workedMinutes > 0 {
                hoursCard
            } else {
                card {
                    Text(verbatim: emptyMessage)
                        .font(.body)
                        .foregroundStyle(.hoursSecondaryText)
                        .padding(.vertical, Metrics.small)
                }
            }

            if showsFigures {
                figuresCard
            }

            if !extras.isEmpty {
                card {
                    ForEach(Array(extras.enumerated()), id: \.offset) { index, extra in
                        if index > 0 { Divider() }
                        row(extra.label, value: extra.value, secondary: true)
                    }
                }
            }

            warnings

            if split != nil {
                Text("Written on the sites' days. Open a site to change the crew.")
                    .font(.footnote)
                    .foregroundStyle(.hoursSecondaryText)
                    .padding(.horizontal, Metrics.small)
                if let split { siteButtons(split) }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Metrics.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: formatting.weekdayName(for: computation.date.weekday(in: formatting.calendar)))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.hoursSecondaryText)
                Text(verbatim: formatting.shortDate(computation.date))
                    .font(.largeTitle.weight(.heavy))
                    .accessibilityAddTraits(.isHeader)
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: Metrics.small)
            Button(action: onEdit) {
                Text(computation.hasEntry ? "Edit" : "Write hours")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, Metrics.large)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .accessibilityIdentifier("day-card-edit")
        }
    }

    /// "Vacation", "Christmas Day · public holiday", "Work · two sites".
    private var subtitle: String {
        if isPublicHoliday, let holidayName = computation.holidayName {
            return String(
                localized: "\(holidayName) · public holiday",
                comment: "Day editor: the holiday's name, e.g. Christmas Day · public holiday"
            )
        }
        var parts = [computation.dayType.displayName()] + [computation.holidayName].compactMap { $0 }
        if let split {
            let sites = Set(split.parts.compactMap(\.siteID)).count
            parts.append(sites == 2 ? String(localized: "two sites") : String(localized: "several sites"))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Public holidays

    private var isPublicHoliday: Bool {
        computation.holidayName != nil && computation.dayType.id == .holiday
    }

    private var isPublicHolidayOff: Bool {
        isPublicHoliday && computation.workedMinutes == 0 && !computation.hasEntry && onWorkedHoliday != nil
    }

    private var publicHolidayChoice: some View {
        card {
            VStack(alignment: .leading, spacing: Metrics.small) {
                Label {
                    Text("Day off (paid)")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.hoursPositive)
                }
                .font(.headline)
                .accessibilityIdentifier("day-card-holiday-off")
                if computation.creditedMinutes > 0 {
                    Text(String(
                        localized: "\(duration.string(computation.creditedMinutes)) credited.",
                        comment: "A paid day off: the hours credited for it, e.g. 8 h credited."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.hoursSecondaryText)
                }
                Button {
                    onWorkedHoliday?()
                } label: {
                    Text("I worked")
                }
                .buttonStyle(.bigAction(.secondary))
                .accessibilityHint(Text("Opens the day with your usual times filled in. The holiday stays paid."))
                .accessibilityIdentifier("day-card-holiday-worked")
            }
            .padding(.vertical, Metrics.small)
        }
    }

    // MARK: - The hours

    private var hoursCard: some View {
        card {
            if let split {
                ForEach(split.parts.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    splitRow(split, index: index)
                }
            } else if computation.isSplitShift {
                // Each block on its own line: the time between them is
                // neither worked nor a break.
                ForEach(computation.shifts.indices, id: \.self) { position in
                    if position > 0 { Divider() }
                    row(String(localized: "Block \(position + 1)"), value: shiftRange(computation.shifts[position]))
                }
            } else if let start = computation.start, let end = computation.end {
                row(
                    String(localized: "Hours"),
                    value: "\(formatting.time(start, on: computation.date))–\(formatting.time(end, on: computation.date))"
                        + (computation.crossesMidnight ? " (+1)" : "")
                )
            }
            if settings.features.trackBreaks && computation.breakMinutes > 0 {
                Divider()
                row(String(localized: "Break"), value: breakText)
            }
            if computation.creditedMinutes > 0 {
                Divider()
                row(String(localized: "Paid absence"), value: duration.string(computation.creditedMinutes))
            }
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text("Worked")
                    .font(.headline)
                Spacer(minLength: Metrics.small)
                Text(verbatim: duration.string(computation.workedMinutes))
                    .font(.hoursFigure(.headline, weight: .bold))
            }
            .frame(minHeight: 36)
            .accessibilityElement(children: .combine)
        }
    }

    private func splitRow(_ split: DaySiteSplit, index: Int) -> some View {
        let part = split.parts[index]
        let name = part.siteID.flatMap { siteNames[$0] }
            ?? (part.siteID == nil ? String(localized: "Your own hours") : String(localized: "Site"))
        let times: String = {
            guard let start = part.start, let end = part.end else { return "—" }
            return "\(formatting.time(start, on: computation.date))–\(formatting.time(end, on: computation.date))"
                + (part.crossesMidnight ? " (+1)" : "")
        }()
        return row(name, value: "\(times) · \(duration.string(part.workedMinutes))", bold: true)
            .accessibilityIdentifier("day-card-site-\(index)")
    }

    // MARK: - Figures

    private var showsFigures: Bool {
        settings.features.trackExpectedHours && (computation.hasEntry || computation.expectedMinutes > 0)
    }

    private var figuresCard: some View {
        card {
            row(String(localized: "Expected"), value: duration.string(computation.expectedMinutes))
            if settings.features.showsBalance {
                Divider()
                row(
                    String(localized: "Overtime"),
                    value: overtimeText,
                    tint: Color.hoursBalance(computation.balanceMinutes),
                    bold: true
                )
                Divider()
                row(
                    String(localized: "Balance after this day"),
                    value: duration.signedString(balanceAfter),
                    tint: Color.hoursBalance(balanceAfter),
                    bold: true
                )
                .accessibilityIdentifier("day-card-balance-after")
            }
            if computation.adjustmentMinutes != 0 {
                Divider()
                row(
                    computation.adjustmentReason.title,
                    value: duration.signedString(computation.adjustmentMinutes),
                    tint: Color.hoursBalance(computation.adjustmentMinutes)
                )
            }
        }
    }

    /// The day's overtime, signed; a plain 0 when there is none.
    private var overtimeText: String {
        computation.balanceMinutes == 0 ? duration.string(0) : duration.signedString(computation.balanceMinutes)
    }

    /// Allowance, kilometres, travel, note, location and tags: what is on
    /// the day, each only when there is some.
    private var extras: [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        if settings.allowance.isEnabled {
            if computation.hasFieldAllowance { list.append((String(localized: "Field allowance"), String(localized: "Yes"))) }
            if computation.kilometres > 0 {
                list.append((String(localized: "Kilometres"), String(
                    localized: "\(computation.kilometres) km",
                    comment: "A distance driven; the value is a number of kilometres"
                )))
            }
            if computation.travelMinutes > 0 {
                list.append((String(localized: "Travel time"), DurationFormatting(style: .clock).string(computation.travelMinutes)))
            }
        }
        if !computation.note.isEmpty { list.append((String(localized: "Note"), computation.note)) }
        if settings.features.trackLocation && !computation.location.isEmpty {
            list.append((String(localized: "Location"), computation.location))
        }
        if settings.features.trackTags && !computation.tags.isEmpty {
            list.append((String(localized: "Tags"), computation.tags.joined(separator: ", ")))
        }
        return list
    }

    @ViewBuilder
    private var warnings: some View {
        let visible = computation.warnings.filter { $0.isProblem || $0 == .excludedFromTotals }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                ForEach(visible) { warning in
                    Label(warning.message, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Color.hoursAttention)
                }
            }
            .padding(.horizontal, Metrics.small)
        }
    }

    // MARK: - Two sites (1.2)

    private var split: DaySiteSplit? { DaySiteSplit.make(computation) }

    /// "30m at Trg Pravde" when the break was taken on one of the sites.
    private var breakText: String {
        let length = duration.string(computation.breakMinutes)
        guard let siteID = split?.breakSiteID ?? nil, let name = siteNames[siteID] else { return length }
        return String(localized: "\(length) at \(name)", comment: "Calendar day card: a break and the site it was taken on")
    }

    /// A link to each site's day, by value onto the Today stack.
    private func siteButtons(_ split: DaySiteSplit) -> some View {
        var seen = Set<UUID>()
        let sites = split.parts.compactMap(\.siteID).filter { seen.insert($0).inserted }
        return VStack(spacing: Metrics.small) {
            ForEach(Array(sites.enumerated()), id: \.element) { offset, siteID in
                NavigationLink(value: CalendarSiteRoute(siteID: siteID, date: computation.date)) {
                    Text(verbatim: siteNames[siteID] ?? String(localized: "Site"))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text(String(
                    localized: "Open \(siteNames[siteID] ?? String(localized: "Site"))",
                    comment: "VoiceOver: opens a site's day from the calendar; the value is the site"
                )))
                .accessibilityIdentifier("day-card-open-site-\(offset)")
            }
        }
    }

    // MARK: - Pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            content()
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(
        _ label: String,
        value: String,
        tint: Color = .primary,
        bold: Bool = false,
        secondary: Bool = false
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                Text(verbatim: label)
                Spacer(minLength: Metrics.small)
                valueText(value, tint: tint, bold: bold, secondary: secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: label)
                valueText(value, tint: tint, bold: bold, secondary: secondary)
            }
        }
        .font(.body)
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func valueText(_ value: String, tint: Color, bold: Bool, secondary: Bool) -> some View {
        if secondary {
            Text(verbatim: value)
                .foregroundStyle(.hoursSecondaryText)
                .multilineTextAlignment(.trailing)
        } else {
            Text(verbatim: value)
                .fontWeight(bold ? .semibold : .regular)
                .monospacedDigit()
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
    }

    private func shiftRange(_ shift: ShiftPeriod) -> String {
        guard let start = shift.start, let end = shift.end else { return "—" }
        let range = "\(formatting.time(start, on: computation.date))–\(formatting.time(end, on: computation.date))"
        return range + (shift.crossesMidnight ? " (+1)" : "")
    }

    private var emptyMessage: String {
        switch computation.dayType.expectation {
        case .scheduled:
            return computation.expectedMinutes > 0
                ? String(
                    localized: "Nothing recorded yet. \(duration.string(computation.expectedMinutes)) expected.",
                    comment: "An empty working day, with the hours its schedule expects"
                  )
                : String(localized: "Nothing recorded yet.")
        case .zero:
            return String(localized: "Not a working day.")
        case .creditedAbsence:
            return String(
                localized: "\(duration.string(computation.creditedMinutes)) credited.",
                comment: "A paid day off: the hours credited for it, e.g. 8 h credited."
            )
        }
    }
}
