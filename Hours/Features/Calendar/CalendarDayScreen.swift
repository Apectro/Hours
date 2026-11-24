import SwiftUI
import SwiftData

/// A day tapped in the month, or today's written row (design v2, mockup
/// Main, "tap a day"): a sheet at half height, with a drag indicator, that
/// pulls up to full. ‹ › in its top bar step a day either way inside it,
/// as on a site's day (Polish phone 3).
struct CalendarDaySheet: View {
    let date: CalendarDate
    /// A site's day, pushed onto the Today tab's stack as the sheet goes.
    let onOpenSite: (CalendarSiteRoute) -> Void

    @Environment(SettingsStore.self) private var settingsStore
    /// The day on screen, once ‹ or › has been tapped.
    @State private var shown: CalendarDate?

    var body: some View {
        let day = shown ?? date
        NavigationStack {
            CalendarDayScreen(
                date: day,
                onOpenSite: onOpenSite,
                onStep: { direction in shown = day.adding(days: direction, in: settingsStore.workCalendar) }
            )
            // A new day is a new screen: its queries are built for its date.
            .id(day.key)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// One day, in its sheet: the weekday and the date as the title, one grey
/// line (the sites or the day's type, and the break), then the hours — a
/// row per site with its times, or the one time range — and the Total; one
/// sentence against a normal day. Then Expected, the overtime and the
/// balance after the day, and the allowance, kilometres and note. Edit (or
/// Write this day) at the bottom opens the editor; ✕ closes; ‹ › go to the
/// day before or after.
struct CalendarDayScreen: View {
    let date: CalendarDate
    var onOpenSite: ((CalendarSiteRoute) -> Void)? = nil
    /// The day before (-1) or after (+1); nil hides ‹ ›.
    var onStep: ((Int) -> Void)? = nil

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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

    init(
        date: CalendarDate,
        onOpenSite: ((CalendarSiteRoute) -> Void)? = nil,
        onStep: ((Int) -> Void)? = nil
    ) {
        self.date = date
        self.onOpenSite = onOpenSite
        self.onStep = onStep
        let upper = date.key
        _entries = Query(filter: #Predicate<DayEntry> { $0.dateKey <= upper }, sort: \DayEntry.dateKey)
        _holidayRecords = Query(sort: \HolidayRecord.name)
    }

    var body: some View {
        let figures = self.figures
        let content = DayDetailContent(
            computation: figures.day,
            balanceAfter: figures.balance,
            settings: settings,
            formatting: settingsStore.dateFormatting,
            siteNames: siteNames,
            onOpenSite: openSite,
            siteColors: SiteColors(sites: siteEntries.map(\.site)),
            earnings: figures.earnings,
            onToggleHideAmounts: { settingsStore.update { $0.hideAmounts.toggle() } }
        )
        List {
            content
        }
        .listStyle(.insetGrouped)
        .navigationTitle(settingsStore.dateFormatting.weekdayAndDay(date))
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("screen-calendar-day")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
                .accessibilityIdentifier("day-sheet-close")
            }
            if let onStep {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        onStep(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(String(localized: "Previous day"))
                    .accessibilityIdentifier("day-sheet-previous")
                    Button {
                        onStep(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .accessibilityLabel(String(localized: "Next day"))
                    .accessibilityIdentifier("day-sheet-next")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            buttons(content)
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit: DayEditorSheet(date: date)
            case .worked: DayEditorSheet(date: date, startsWorking: true)
            }
        }
    }

    /// The one primary, Edit or Write this day; on a public holiday off, I
    /// worked beside it.
    private func buttons(_ content: DayDetailContent) -> some View {
        HStack(spacing: Metrics.small) {
            if content.isPublicHolidayOff {
                Button {
                    sheet = .worked
                } label: {
                    Text("I worked")
                }
                .buttonStyle(.bigAction(.secondary))
                .accessibilityHint(Text("Opens the day with your usual times filled in. The holiday stays paid."))
                .accessibilityIdentifier("day-card-holiday-worked")
            }
            Button {
                sheet = .edit
            } label: {
                Text(content.isWritten ? "Edit" : "Write this day")
            }
            .buttonStyle(.bigAction(.primary))
            .accessibilityIdentifier("day-card-edit")
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var settings: AppSettings { settingsStore.settings }

    /// A site's day on this date, by the site.
    private var openSite: ((UUID) -> Void)? {
        guard let onOpenSite else { return nil }
        let date = self.date
        return { siteID in onOpenSite(CalendarSiteRoute(siteID: siteID, date: date)) }
    }

    private var siteNames: [UUID: String] {
        Dictionary(siteEntries.map { ($0.site.id, $0.site.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// The day as the engine resolves it, the running balance at its end —
    /// the rule Insights and the export use — and what the day earned, once
    /// pay is set up: the day's own entry of the earnings Insights adds up.
    private var figures: (day: DayComputation, balance: Int, earnings: DayEarnings?) {
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
        let earnings = settings.earningsAreSetUp
            ? engine.earnings(
                in: CalendarDateRange(single: date),
                records: records,
                holidays: holidays,
                countingThrough: CalendarDate.today(in: calendar)
            )?.days.first
            : nil
        return (day, balance, earnings)
    }
}

/// The day sheet's sections, apart from the data that feeds them.
struct DayDetailContent: View {
    let computation: DayComputation
    let balanceAfter: Int
    let settings: AppSettings
    let formatting: CalendarFormatting
    var siteNames: [UUID: String] = [:]
    /// Opens a site's day; nil where there is no stack to push it onto.
    var onOpenSite: ((UUID) -> Void)? = nil
    /// Each site's colour, for the dot beside its name.
    var siteColors = SiteColors()
    /// What the day earned (2026-11-24); nil while pay is not set up, and
    /// for a day that has not happened yet.
    var earnings: DayEarnings? = nil
    /// The eye on "Earned this day": hides or shows every amount
    /// (`AppSettings.hideAmounts`). Nil leaves the eye out.
    var onToggleHideAmounts: (() -> Void)? = nil

    private var duration: DurationFormatting { settings.displayFormatting }

    var isWritten: Bool { computation.hasEntry || computation.workedMinutes > 0 }

    /// A public holiday off with nothing worked: "Day off (paid)", and I
    /// worked for one worked anyway.
    var isPublicHolidayOff: Bool {
        isPublicHoliday && computation.workedMinutes == 0 && !computation.hasEntry
    }

    private var isPublicHoliday: Bool {
        computation.holidayName != nil && computation.dayType.id == .holiday
    }

    var body: some View {
        Section {
            hoursRows
        } header: {
            Text(verbatim: subtitle)
                .font(.subheadline)
                .foregroundStyle(.hoursSecondaryText)
                .textCase(nil)
        } footer: {
            hoursFooter
        }

        if let earnings, !earnings.lines.isEmpty {
            Section {
                earnedRows(earnings)
            }
        }

        if showsFigures {
            Section {
                figureRows
            }
        }

        if !extras.isEmpty {
            Section {
                ForEach(Array(extras.enumerated()), id: \.offset) { _, extra in
                    LabeledContent {
                        Text(verbatim: extra.value)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text(verbatim: extra.label)
                    }
                }
            }
        }
    }

    // MARK: - The grey line

    /// "Two sites · 30m break", "Vacation", "Christmas Day · public holiday":
    /// at most two parts.
    private var subtitle: String {
        if isPublicHoliday, let holidayName = computation.holidayName {
            return String(
                localized: "\(holidayName) · public holiday",
                comment: "Day editor: the holiday's name, e.g. Christmas Day · public holiday"
            )
        }
        var parts: [String] = []
        if let split {
            let sites = Set(split.parts.compactMap(\.siteID)).count
            parts.append(Self.sentenceCased(sites == 2 ? String(localized: "two sites") : String(localized: "several sites")))
        } else {
            parts.append(computation.dayType.displayName())
        }
        if settings.features.trackBreaks && computation.breakMinutes > 0 {
            parts.append(String(
                localized: "\(duration.string(computation.breakMinutes)) break",
                comment: "The running clock: the breaks already taken, e.g. 30m break"
            ))
        }
        return parts.joined(separator: " · ")
    }

    /// The first letter in capitals, for a fragment that starts the line.
    static func sentenceCased(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }

    // MARK: - The hours

    @ViewBuilder
    private var hoursRows: some View {
        if isPublicHolidayOff {
            Label {
                Text("Day off (paid)")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.hoursDone)
            }
            .accessibilityIdentifier("day-card-holiday-off")
            if computation.creditedMinutes > 0 {
                valueRow(String(localized: "Paid absence"), duration.string(computation.creditedMinutes))
            }
        } else if isWritten {
            if hasSiteHours {
                // Two parts, told apart: what a site's day wrote, and what
                // was written here.
                groupedRows
            } else if computation.isSplitShift {
                // Each block on its own line: the time between them is
                // neither worked nor a break.
                ForEach(computation.shifts.indices, id: \.self) { position in
                    valueRow(String(localized: "Block \(position + 1)"), shiftRange(computation.shifts[position]))
                }
            } else if let start = computation.start, let end = computation.end {
                singleRow(start: start, end: end)
            }
            // Where the break was taken, on a day on two sites; the grey
            // line under the title says how long it was.
            if settings.features.trackBreaks && computation.breakMinutes > 0 && split?.breakSiteID != nil {
                valueRow(String(localized: "Break"), breakText)
            }
            if computation.creditedMinutes > 0 {
                valueRow(String(localized: "Paid absence"), duration.string(computation.creditedMinutes))
            }
            if computation.workedMinutes > 0 || computation.creditedMinutes == 0 {
                HStack(alignment: .firstTextBaseline) {
                    Text("Total")
                        .fontWeight(.semibold)
                    Spacer(minLength: Metrics.small)
                    Text(verbatim: duration.string(computation.workedMinutes))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        } else {
            notWrittenRow
        }
    }

    /// A day with hours from a site (2026-11-24): "On sites", a row per
    /// site, then "Own hours", a row per block written here, when there are
    /// any. Each row keeps its place in the day as its identifier
    /// ("day-card-site-1" is the day's second block), as the two-site day
    /// always numbered them.
    @ViewBuilder
    private var groupedRows: some View {
        let parts = DaySiteSplit.parts(of: computation)
        let onSites = parts.indices.filter { parts[$0].siteID != nil }
        let own = parts.indices.filter { parts[$0].siteID == nil }
        groupHeading(String(localized: "On sites"), identifier: "day-card-on-sites")
        ForEach(onSites, id: \.self) { index in
            partRow(parts[index], index: index)
        }
        if !own.isEmpty {
            groupHeading(
                String(localized: "Own hours", comment: "Heading: hours that are on no site"),
                identifier: "day-card-own-hours"
            )
            ForEach(own, id: \.self) { index in
                partRow(parts[index], index: index)
            }
        }
    }

    /// A small heading inside the hours card.
    private func groupHeading(_ title: String, identifier: String) -> some View {
        Text(verbatim: title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.hoursSecondaryText)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(identifier)
    }

    /// One block of the day: the site, or "Your own hours", and its times,
    /// the hours on the right, a dot in the site's colour. A site's row
    /// opens the site's day.
    @ViewBuilder
    private func partRow(_ part: DaySiteSplit.Part, index: Int) -> some View {
        let name = part.siteID.flatMap { siteNames[$0] }
            ?? (part.siteID == nil ? String(localized: "Your own hours") : String(localized: "Site"))
        let times: String = {
            guard let start = part.start, let end = part.end else { return "—" }
            return "\(formatting.time(start, on: computation.date)) – \(formatting.time(end, on: computation.date))"
                + (part.crossesMidnight ? " (+1)" : "")
        }()
        if let siteID = part.siteID, let onOpenSite {
            Button {
                onOpenSite(siteID)
            } label: {
                siteLabel(
                    name: name, times: times, hours: duration.string(part.workedMinutes),
                    dot: siteColors.color(for: siteID), showsDot: true, opens: true
                )
            }
            .accessibilityHint(Text(String(
                localized: "Open \(name)",
                comment: "VoiceOver: opens a site's day from the calendar; the value is the site"
            )))
            .accessibilityIdentifier("day-card-site-\(index)")
        } else {
            siteLabel(
                name: name, times: times, hours: duration.string(part.workedMinutes),
                dot: part.siteID.map { siteColors.color(for: $0) }, showsDot: true, opens: false
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("day-card-site-\(index)")
        }
    }

    /// The one time range: the site above it when there is one, the hours on
    /// the right.
    @ViewBuilder
    private func singleRow(start: TimeOfDay, end: TimeOfDay) -> some View {
        let times = "\(formatting.time(start, on: computation.date)) – \(formatting.time(end, on: computation.date))"
            + (computation.crossesMidnight ? " (+1)" : "")
        let sites = Set(computation.shifts.compactMap(\.siteID))
        if sites.count == 1, let siteID = sites.first, let name = siteNames[siteID] {
            let label = siteLabel(name: name, times: times, hours: duration.string(computation.workedMinutes))
            if let onOpenSite {
                Button {
                    onOpenSite(siteID)
                } label: {
                    label
                }
                .accessibilityIdentifier("day-card-site-0")
            } else {
                label
            }
        } else {
            valueRow(times, duration.string(computation.workedMinutes))
        }
    }

    /// - Parameters:
    ///   - dot: the source's colour; nil is your own hours.
    ///   - showsDot: the grouped day's rows have one; the old single row
    ///     does not.
    ///   - opens: a small chevron, on a row that opens the site's day.
    private func siteLabel(
        name: String,
        times: String,
        hours: String,
        dot: Color? = nil,
        showsDot: Bool = false,
        opens: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: Metrics.small) {
            if showsDot {
                SourceDot(color: dot)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: name)
                    .foregroundStyle(.primary)
                Text(verbatim: times)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.hoursSecondaryText)
            }
            Spacer(minLength: Metrics.small)
            Text(verbatim: hours)
                .monospacedDigit()
                .foregroundStyle(.hoursSecondaryText)
            if opens {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var notWrittenRow: some View {
        switch computation.dayType.expectation {
        case .scheduled:
            valueRow(
                String(localized: "Not written"),
                settings.features.trackExpectedHours && computation.expectedMinutes > 0
                    ? String(
                        localized: "\(duration.string(computation.expectedMinutes)) expected",
                        comment: "Today: the hours expected of the day, e.g. 8h 30m expected"
                    )
                    : ""
            )
        case .zero:
            Text("Not a working day.")
                .foregroundStyle(.hoursSecondaryText)
        case .creditedAbsence:
            valueRow(computation.dayType.displayName(), String(
                localized: "\(duration.string(computation.creditedMinutes)) credited.",
                comment: "A paid day off: the hours credited for it, e.g. 8 h credited."
            ))
        }
    }

    /// One sentence against a normal day, the split day's note, and any
    /// warning.
    @ViewBuilder
    private var hoursFooter: some View {
        let lines = footerLines
        let visible = computation.warnings.filter { $0.isProblem || $0 == .excludedFromTotals }
        if !lines.isEmpty || !visible.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                ForEach(lines, id: \.self) { line in
                    Text(verbatim: line)
                }
                ForEach(visible) { warning in
                    Label(warning.message, systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color.hoursAttention)
                }
            }
        }
    }

    private var footerLines: [String] {
        var lines: [String] = []
        if settings.features.trackExpectedHours, isWritten,
           let difference = computation.differenceFromNormalDay, difference != 0 {
            let amount = duration.string(abs(difference))
            lines.append(difference > 0
                ? String(localized: "\(amount) more than a normal day.",
                         comment: "Under a day's hours; the value is a length of time, e.g. 30m")
                : String(localized: "\(amount) less than a normal day.",
                         comment: "Under a day's hours; the value is a length of time, e.g. 30m"))
        }
        if split != nil {
            lines.append(String(localized: "Written on the sites' days. Open a site to change the crew."))
        } else if hasSiteHours {
            lines.append(String(localized: "Written on the site's day, so it is changed there."))
        }
        return lines
    }

    // MARK: - Figures

    private var showsFigures: Bool {
        settings.features.trackExpectedHours && (computation.hasEntry || computation.expectedMinutes > 0)
    }

    @ViewBuilder
    private var figureRows: some View {
        valueRow(String(localized: "Expected"), duration.string(computation.expectedMinutes))
        if settings.features.showsBalance {
            coloredRow(String(localized: "Overtime"), overtimeText, minutes: computation.balanceMinutes)
            coloredRow(String(localized: "Balance after this day"), duration.signedString(balanceAfter), minutes: balanceAfter)
                .accessibilityIdentifier("day-card-balance-after")
        }
        if computation.adjustmentMinutes != 0 {
            coloredRow(
                computation.adjustmentReason.title,
                duration.signedString(computation.adjustmentMinutes),
                minutes: computation.adjustmentMinutes
            )
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

    // MARK: - Earned this day (2026-11-24)

    /// The day's pay in plain lines and a total; the eye hides every
    /// amount, here and in the calendar.
    @ViewBuilder
    private func earnedRows(_ earnings: DayEarnings) -> some View {
        HStack(alignment: .center, spacing: Metrics.small) {
            Text("Earned this day")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.hoursSecondaryText)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("day-card-earned")
            Spacer(minLength: Metrics.small)
            if let onToggleHideAmounts {
                Button(action: onToggleHideAmounts) {
                    Image(systemName: settings.hideAmounts ? "eye.slash" : "eye")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                // Borderless, so the row's one button takes only its own tap.
                .buttonStyle(.borderless)
                .accessibilityLabel(settings.hideAmounts ? Text("Show amounts") : Text("Hide amounts"))
                .accessibilityIdentifier("day-card-hide-amounts")
            }
        }
        ForEach(earnings.lines) { line in
            valueRow(earnedTitle(line), amount(line.cents))
        }
        HStack(alignment: .firstTextBaseline) {
            Text("Total")
                .fontWeight(.semibold)
            Spacer(minLength: Metrics.small)
            Text(verbatim: amount(earnings.totalCents))
                .fontWeight(.semibold)
                .monospacedDigit()
                .accessibilityIdentifier("day-card-earned-total")
        }
    }

    /// An amount, or the dots while amounts are hidden.
    private func amount(_ cents: Int) -> String {
        settings.money.string(cents, hidden: settings.hideAmounts)
    }

    /// "8h × €12.50", "1h 30m overtime × €15.63", "Saturday · 4h", "Field
    /// allowance": what the line is for, in the words Insights uses.
    private func earnedTitle(_ line: DayEarningsLine) -> String {
        let hours = line.minutes.map { duration.string($0) }
        func named(_ name: String) -> String {
            guard let hours else { return name }
            return "\(name) · \(hours)"
        }
        switch line.kind {
        case .regular:
            if let rate = line.rateCents, let hours { return "\(hours) × \(amount(rate))" }
            return named(String(localized: "Hours worked"))
        case .overtime:
            if let rate = line.rateCents, let hours {
                return String(
                    localized: "\(hours) overtime × \(amount(rate))",
                    comment: "A day's pay: overtime hours and the hourly rate they were paid, e.g. 1h 30m overtime × €15.63"
                )
            }
            return named(String(localized: "Overtime surcharge"))
        case .saturday:
            return named(String(localized: "Saturday"))
        case .sundayAndHoliday:
            return named(String(localized: "Sunday and public holidays"))
        case .night:
            return named(String(localized: "Night"))
        case .paidAbsence:
            let title = named(String(localized: "Paid days off"))
            guard let percent = line.percent else { return title }
            return "\(title) · \(percent)%"
        case .allowance:
            return String(localized: "Field allowance")
        case .mileage:
            let kilometres = line.kilometres ?? 0
            return String(
                localized: "Kilometres · \(kilometres) km",
                comment: "Insights, the month's kilometres; the value is a number"
            )
        }
    }

    // MARK: - Two sites (1.2)

    private var split: DaySiteSplit? { DaySiteSplit.make(computation) }

    /// Any of the day's hours came from a site's day.
    private var hasSiteHours: Bool { computation.shifts.contains { $0.siteID != nil } }

    /// "30m at Trg Pravde" when the break was taken on one of the sites.
    private var breakText: String {
        let length = duration.string(computation.breakMinutes)
        guard let siteID = split?.breakSiteID ?? nil, let name = siteNames[siteID] else {
            return String(
                localized: "\(length) break",
                comment: "The running clock: the breaks already taken, e.g. 30m break"
            )
        }
        return String(localized: "\(length) at \(name)", comment: "Calendar day card: a break and the site it was taken on")
    }

    // MARK: - Pieces

    /// A noun on the left and the value in grey on the right.
    private func valueRow(_ label: String, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } label: {
            Text(verbatim: label)
                .monospacedDigit()
        }
    }

    /// A signed figure by the colour rule: green over, red short, grey at
    /// nothing.
    private func coloredRow(_ label: String, _ value: String, minutes: Int) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .monospacedDigit()
                .foregroundStyle(Color.hoursBalance(minutes))
        } label: {
            Text(verbatim: label)
        }
    }

    private func shiftRange(_ shift: ShiftPeriod) -> String {
        guard let start = shift.start, let end = shift.end else { return "—" }
        let range = "\(formatting.time(start, on: computation.date)) – \(formatting.time(end, on: computation.date))"
        return range + (shift.crossesMidnight ? " (+1)" : "")
    }
}
