import SwiftUI

/// One site day on one rounded surface (mockup board 4): the day and the
/// crew's total, the site's times once for everyone, then each person with a
/// tick, and the note at the bottom.
///
/// Draws and reports, nothing more. Every change goes back to the site screen
/// through a callback, because that is where the month lock, the refusal and
/// your calendar day are handled — a card that wrote on its own would be a
/// second way in that could forget one of them.
struct SiteDayCard: View {
    let title: String
    let day: SiteDay
    let result: SiteDayResult
    let rows: [PersonReference]
    /// Whether anything is stored for the day. An unstored day says so where
    /// a written one shows its total.
    let isWritten: Bool
    let canEdit: Bool
    let warnings: [DayWarning]
    let formatting: CalendarFormatting
    let durations: DurationFormatting
    @Binding var noteText: String
    var isNoteFocused: FocusState<Bool>.Binding
    let onToggle: (UUID) -> Void
    let onEditPerson: (PersonReference) -> Void
    let onEditTimes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            header
            timesRow
            warningsView

            Text(String(
                localized: "Crew · \(result.people.count) of \(rows.count) here",
                comment: "Above the crew on a site day; the values are how many were there and how many could have been"
            ))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
            .padding(.top, Metrics.tiny)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: Metrics.tiny) {
                ForEach(rows) { row in
                    SitePersonRow(
                        row: row,
                        person: result.people.first(where: { $0.memberID == row.id }),
                        exception: SiteException.of(row.id, in: day),
                        date: day.date,
                        canEdit: canEdit,
                        formatting: formatting,
                        durations: durations,
                        onToggle: { onToggle(row.id) },
                        onEdit: { onEditPerson(row) }
                    )
                }
            }

            Text("Tap a name to tick or untick them. Tap their times to change just that person.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: Metrics.tiny) {
                TextField("Notes", text: $noteText, axis: .vertical)
                    .lineLimit(1...5)
                    .focused(isNoteFocused)
                    .disabled(!canEdit)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("site-day-note")
                Text("Printed with this day when the site is exported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Metrics.small)
            if isWritten {
                Text(durations.string(result.crewTotalMinutes))
                    .font(.hoursFigure(.headline))
                    .contentTransition(.numericText())
                    .accessibilityLabel(String(
                        localized: "Crew total: \(durations.string(result.crewTotalMinutes))",
                        comment: "VoiceOver, the crew's hours on a site day; the value is a duration"
                    ))
                    .accessibilityIdentifier("site-crew-total")
            } else {
                Text("Not written")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.hoursNegative)
                    .accessibilityIdentifier("site-day-not-written")
            }
        }
    }

    // MARK: - Site times

    private var timesRow: some View {
        Button(action: onEditTimes) {
            HStack(spacing: Metrics.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timesText)
                        .font(.hoursFigure(.title2))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(breakText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Metrics.small)
                Text("Change")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(canEdit ? Color.accentColor : Color.secondary)
            }
            .padding(Metrics.medium)
            .frame(minHeight: 44)
            .background(
                Color.hoursCanvas,
                in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("site-day-times")
    }

    private var timesText: String {
        let start = day.start.map { formatting.time($0, on: day.date) } ?? "—"
        let end = day.end.map { formatting.time($0, on: day.date) } ?? "—"
        return "\(start) – \(end)"
    }

    private var breakText: String {
        guard day.breakMinutes > 0 else {
            return String(localized: "No break · everyone")
        }
        // Hours and minutes whatever the display setting, as on the sheet's
        // chips: "0:30 break" reads like a time of day.
        let length = DurationFormatting(style: .hoursAndMinutes).string(day.breakMinutes)
        return String(
            localized: "\(length) break · everyone",
            comment: "Under a site day's times; the value is a duration such as 30m"
        )
    }

    /// Quiet, as in the day editor: a half-entered day is a normal state while
    /// typing. Each warning once, however many people it applies to — with no
    /// end time it applies to all of them, and saying so per person is noise.
    @ViewBuilder
    private var warningsView: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                ForEach(warnings) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(warning.isProblem ? Color.hoursNegative : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One person on a site day: who, their times, their hours and the tick.
///
/// Two controls in one row, as before the redesign: the name, the initials
/// and the tick all tick or untick, and the line of times under the name
/// opens that person's own times. Only the name is exposed to VoiceOver as
/// the tick, carrying the hours in its value, so the row is not read out
/// three times over.
struct SitePersonRow: View {
    let row: PersonReference
    let person: PersonDay?
    let exception: SiteException?
    let date: CalendarDate
    let canEdit: Bool
    let formatting: CalendarFormatting
    let durations: DurationFormatting
    let onToggle: () -> Void
    let onEdit: () -> Void

    // Not `private`: that would make the memberwise initializer private too.
    @ScaledMetric(relativeTo: .subheadline) var initialsDiameter: CGFloat = 36

    private var isHere: Bool { person != nil }
    private var isYou: Bool { row.id == CrewMember.youID }

    var body: some View {
        HStack(spacing: Metrics.medium) {
            Button(action: onToggle) {
                initials
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Button(action: onToggle) {
                    Text(row.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canEdit)
                .accessibilityLabel(row.name)
                .accessibilityValue(toggleValue)
                .accessibilityAddTraits(isHere ? .isSelected : [])
                .accessibilityIdentifier(isYou ? "site-person-you" : "site-person-\(row.name)")

                Button(action: onEdit) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(exception != nil ? Color.hoursNegative : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canEdit || !isHere)
                .accessibilityIdentifier(isYou ? "site-times-you" : "site-times-\(row.name)")
            }
            .opacity(isHere ? 1 : 0.55)

            Button(action: onToggle) {
                HStack(spacing: Metrics.small) {
                    Text(person.map { durations.string($0.workedMinutes) } ?? "—")
                        .font(.hoursFigure(.subheadline, weight: .medium))
                        .foregroundStyle(isHere ? Color.primary : Color.secondary)
                        .opacity(isHere ? 1 : 0.55)
                    Image(systemName: isHere ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isHere ? Color.accentColor : Color.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, Metrics.small)
        .padding(.vertical, Metrics.tiny)
        .background(
            exception != nil ? Color.hoursNegative.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
        )
    }

    // MARK: - Pieces

    private var initials: some View {
        ZStack {
            Circle()
                .fill(isHere ? Color.accentColor.opacity(0.15) : Color.hoursSubdued.opacity(0.2))
            if isYou {
                Image(systemName: "person.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isHere ? Color.accentColor : Color.secondary)
            } else {
                Text(verbatim: Self.initials(of: row.name))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(isHere ? Color.accentColor : Color.secondary)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: initialsDiameter, height: initialsDiameter)
        .opacity(isHere ? 1 : 0.55)
    }

    /// Up to two letters, from the first two words of the name.
    static func initials(of name: String) -> String {
        name.split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { word in word.first.map { String($0) } }
            .joined()
            .uppercased()
    }

    private var subtitle: String {
        guard let person else { return String(localized: "Not here") }
        let times = timeRange(person)
        guard let exception else { return times }
        return "\(exceptionTitle(exception)) · \(times)"
    }

    private var toggleValue: String {
        guard let person else { return String(localized: "Not here") }
        return [String(localized: "Here"), durations.string(person.workedMinutes)].joined(separator: ", ")
    }

    private func exceptionTitle(_ exception: SiteException) -> String {
        switch exception {
        case .cameLate: return String(localized: "Came late")
        case .leftEarly: return String(localized: "Left early")
        case .changedTimes: return String(localized: "Own times")
        }
    }

    private func timeRange(_ person: PersonDay) -> String {
        let start = person.start.map { formatting.time($0, on: date) } ?? "—"
        let end = person.end.map { formatting.time($0, on: date) } ?? "—"
        return "\(start) – \(end)"
    }
}

/// A row of the crew list: who, and the name to show.
struct PersonReference: Identifiable, Hashable {
    let id: UUID
    let name: String
}
