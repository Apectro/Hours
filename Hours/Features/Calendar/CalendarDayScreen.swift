import SwiftUI

/// The selected day, shown inline under the calendar.
///
/// Reading a day should not cost a sheet. Editing does.
struct DaySummaryCard: View {
    let computation: DayComputation
    let settings: AppSettings
    let formatting: CalendarFormatting
    let onEdit: () -> Void
    /// "I worked" on a public holiday off: opens the editor with the day's
    /// times filled in, and the holiday still paid.
    var onWorkedHoliday: (() -> Void)? = nil
    /// Present only on today, and only when no clock is already running.
    var onClockIn: (() -> Void)? = nil
    /// Site names by id, for a day worked on more than one site (1.2).
    var siteNames: [UUID: String] = [:]
    /// Opens a site on this day, from the buttons under a split day.
    var onOpenSite: ((UUID) -> Void)? = nil

    private var duration: DurationFormatting { settings.displayFormatting }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Metrics.medium) {
                header

                if isPublicHolidayOff {
                    publicHolidayChoice
                } else if computation.hasEntry || computation.workedMinutes > 0 {
                    Divider()
                    figures
                } else {
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !computation.note.isEmpty {
                    Text(computation.note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                warnings

                if let split, let onOpenSite {
                    siteButtons(split, open: onOpenSite)
                }

                if let onClockIn {
                    Button(action: onClockIn) {
                        Label("Clock in", systemImage: "play.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Button(action: onEdit) {
                        Label(
                            computation.hasEntry ? "Edit day" : "Write by hand",
                            systemImage: "square.and.pencil"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .accessibilityIdentifier("day-card-edit")
                } else {
                    Button(action: onEdit) {
                        Label(
                            computation.hasEntry ? "Edit day" : "Write hours",
                            systemImage: "square.and.pencil"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .accessibilityIdentifier("day-card-edit")
                }
            }
        }
    }

    // MARK: - Public holidays

    /// A holiday rule's paid day off, whether worked or not.
    private var isPublicHoliday: Bool {
        computation.holidayName != nil && computation.dayType.id == .holiday
    }

    /// Nothing worked on it: the choice between leaving it and "I worked".
    private var isPublicHolidayOff: Bool {
        isPublicHoliday && computation.workedMinutes == 0 && !computation.hasEntry && onWorkedHoliday != nil
    }

    private var publicHolidayChoice: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Label {
                Text("Day off (paid)")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            .font(.subheadline)
            .accessibilityIdentifier("day-card-holiday-off")
            if computation.creditedMinutes > 0 {
                Text(String(
                    localized: "\(duration.string(computation.creditedMinutes)) credited.",
                    comment: "A paid day off: the hours credited for it, e.g. 8 h credited."
                ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                onWorkedHoliday?()
            } label: {
                Label("I worked", systemImage: "hammer")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityHint(Text("Opens the day with your usual times filled in. The holiday stays paid."))
            .accessibilityIdentifier("day-card-holiday-worked")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: Metrics.medium) {
            DayTypeBadge(definition: computation.dayType, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(formatting.fullDate(computation.date))
                    .font(.headline)
                // One text rather than three side by side, so a long line
                // wraps as a sentence instead of each piece on its own.
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    // Two lines: "Tijelovo · public holiday" at a large text
                    // size is longer than one.
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }
            Spacer(minLength: 0)
            if settings.features.showsBalance && computation.hasEntry {
                BalanceText(
                    minutes: computation.balanceMinutes,
                    formatting: duration,
                    font: .hoursFigure(.title3)
                )
            }
        }
    }

    /// "Christmas Day · public holiday", or the day type and any holiday.
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

    private var figures: some View {
        VStack(spacing: Metrics.small) {
            if let split {
                SiteSplitView(
                    split: split,
                    date: computation.date,
                    siteNames: siteNames,
                    formatting: formatting,
                    duration: duration
                )
            } else if computation.isSplitShift {
                // Each block gets its own line: the time between them is
                // neither worked nor a break, and one merged range would say
                // the opposite.
                ForEach(computation.shifts.indices, id: \.self) { position in
                    MetricRow(
                        label: String(localized: "Block \(position + 1)"),
                        value: shiftRange(computation.shifts[position]),
                        systemImage: position == 0 ? "clock" : "clock.arrow.circlepath"
                    )
                }
            } else if let start = computation.start, let end = computation.end {
                MetricRow(
                    label: String(localized: "Hours"),
                    value: "\(formatting.time(start, on: computation.date)) – \(formatting.time(end, on: computation.date))"
                        + (computation.crossesMidnight ? " (+1)" : ""),
                    systemImage: "clock"
                )
            }
            if settings.features.trackBreaks && computation.breakMinutes > 0 {
                MetricRow(label: String(localized: "Break"), value: breakText, systemImage: "cup.and.saucer")
            }
            MetricRow(
                label: String(localized: "Worked"),
                value: duration.string(computation.workedMinutes),
                systemImage: "timer"
            )
            if computation.creditedMinutes > 0 {
                MetricRow(
                    label: String(localized: "Paid absence"),
                    value: duration.string(computation.creditedMinutes),
                    systemImage: "checkmark.seal"
                )
            }
            if settings.features.trackExpectedHours {
                MetricRow(label: String(localized: "Expected"), value: duration.string(computation.expectedMinutes), systemImage: "target")
            }
            if computation.adjustmentMinutes != 0 {
                MetricRow(
                    label: computation.adjustmentReason.title,
                    value: duration.signedString(computation.adjustmentMinutes),
                    tint: Color.hoursBalance(computation.adjustmentMinutes),
                    systemImage: computation.adjustmentReason.symbolName
                )
            }
            if settings.features.trackLocation && !computation.location.isEmpty {
                MetricRow(label: String(localized: "Location"), value: computation.location, systemImage: "mappin.and.ellipse")
            }
            if settings.features.trackTags && !computation.tags.isEmpty {
                MetricRow(label: String(localized: "Tags"), value: computation.tags.joined(separator: ", "), systemImage: "tag")
            }
        }
    }

    // MARK: - Two sites (1.2)

    /// The day's blocks by site, when it was worked on more than one.
    private var split: DaySiteSplit? { DaySiteSplit.make(computation) }

    /// "30m at Trg Pravde" when the break was taken on one of the sites.
    private var breakText: String {
        let length = duration.string(computation.breakMinutes)
        guard let siteID = split?.breakSiteID ?? nil, let name = siteNames[siteID] else { return length }
        return String(localized: "\(length) at \(name)", comment: "Calendar day card: a break and the site it was taken on")
    }

    /// A button for each site's day, as the mockup's pair under the card.
    private func siteButtons(_ split: DaySiteSplit, open: @escaping (UUID) -> Void) -> some View {
        var seen = Set<UUID>()
        let sites = split.parts.compactMap(\.siteID).filter { seen.insert($0).inserted }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.small) { siteButtonList(sites, open: open) }
            VStack(spacing: Metrics.small) { siteButtonList(sites, open: open) }
        }
    }

    private func siteButtonList(_ sites: [UUID], open: @escaping (UUID) -> Void) -> some View {
        ForEach(Array(sites.enumerated()), id: \.element) { offset, siteID in
            Button {
                open(siteID)
            } label: {
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

    @ViewBuilder
    private var warnings: some View {
        let visible = computation.warnings.filter { $0.isProblem || $0 == .excludedFromTotals }
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                ForEach(visible) { warning in
                    Label(warning.message, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func shiftRange(_ shift: ShiftPeriod) -> String {
        guard let start = shift.start, let end = shift.end else { return "—" }
        let range = "\(formatting.time(start, on: computation.date)) – \(formatting.time(end, on: computation.date))"
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

/// A day worked on more than one site (mockup Calendar): a thin bar with a
/// colour per site and a gap where neither was worked, the times under it,
/// then a row per site — "Trg Pravde · 12:00 – 16:00 · 3h 30m".
struct SiteSplitView: View {
    let split: DaySiteSplit
    let date: CalendarDate
    let siteNames: [UUID: String]
    let formatting: CalendarFormatting
    let duration: DurationFormatting

    /// One colour per site, in the order worked; hours of your own in grey.
    static let palette: [Color] = [.accentColor, .orange, .green, .purple, .pink]

    private func color(of index: Int) -> Color {
        guard let siteID = split.parts[index].siteID else { return Color.secondary }
        var seen: [UUID] = []
        for part in split.parts { if let id = part.siteID, !seen.contains(id) { seen.append(id) } }
        let position = seen.firstIndex(of: siteID) ?? 0
        return Self.palette[position % Self.palette.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            if !split.segments.isEmpty {
                bar
                    .accessibilityHidden(true)
            }
            ForEach(split.parts.indices, id: \.self) { index in
                row(index)
            }
        }
    }

    private var bar: some View {
        VStack(spacing: Metrics.tiny) {
            GeometryReader { proxy in
                let total = max(1, split.segments.reduce(0) { $0 + minutes(of: $1) })
                let gaps = CGFloat(max(0, split.segments.count - 1)) * 3
                HStack(spacing: 3) {
                    ForEach(Array(split.segments.enumerated()), id: \.offset) { _, segment in
                        Capsule()
                            .fill(fill(of: segment))
                            .frame(width: max(2, (proxy.size.width - gaps) * CGFloat(minutes(of: segment)) / CGFloat(total)))
                    }
                }
            }
            .frame(height: 10)
            HStack {
                Text(split.start.map { formatting.time($0, on: date) } ?? "")
                Spacer()
                Text(verbatim: middleTimes)
                Spacer()
                Text(split.end.map { formatting.time($0, on: date) } ?? "")
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }

    /// Where the first site ended and the next began: "11:30 · 12:00".
    private var middleTimes: String {
        guard split.parts.count >= 2, let end = split.parts[0].end, let start = split.parts[1].start else { return "" }
        let first = formatting.time(end, on: date)
        let second = formatting.time(start, on: date)
        return first == second ? first : "\(first) · \(second)"
    }

    private func minutes(of segment: DaySiteSplit.Segment) -> Int {
        switch segment {
        case let .site(_, minutes): return minutes
        case let .gap(minutes): return minutes
        }
    }

    private func fill(of segment: DaySiteSplit.Segment) -> Color {
        switch segment {
        case let .site(index, _): return color(of: index)
        case .gap: return Color.hoursSubdued.opacity(0.3)
        }
    }

    private func row(_ index: Int) -> some View {
        let part = split.parts[index]
        let name = part.siteID.flatMap { siteNames[$0] } ?? (part.siteID == nil ? String(localized: "Your own hours") : String(localized: "Site"))
        let times: String = {
            guard let start = part.start, let end = part.end else { return "—" }
            return "\(formatting.time(start, on: date)) – \(formatting.time(end, on: date))" + (part.crossesMidnight ? " (+1)" : "")
        }()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.small) {
                label(name, index: index)
                Spacer(minLength: Metrics.small)
                figures(times: times, worked: part.workedMinutes)
            }
            VStack(alignment: .leading, spacing: 2) {
                label(name, index: index)
                figures(times: times, worked: part.workedMinutes)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("day-card-site-\(index)")
    }

    private func label(_ name: String, index: Int) -> some View {
        HStack(spacing: Metrics.small) {
            Circle()
                .fill(color(of: index))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(verbatim: name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func figures(times: String, worked: Int) -> some View {
        (Text(verbatim: "\(times) · ") + Text(verbatim: duration.string(worked)).fontWeight(.semibold))
            .font(.subheadline)
            .monospacedDigit()
    }
}
