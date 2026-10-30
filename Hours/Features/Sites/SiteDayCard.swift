import SwiftUI

/// A written site day (1.2 redesign, mockups 06 and 07 "A written day"): a
/// green "WRITTEN · 4 PEOPLE · 32H", one line per person — orange for
/// whoever came late, left early or was away, the accent for whoever moved
/// to another site — who moved where with Undo, anything that needs a look,
/// and **Change**, which opens the crew's day.
///
/// Draws and reports, nothing more. Every change goes back to the site screen
/// through a callback, because that is where the month lock, the refusal and
/// your calendar day are handled — a card that wrote on its own would be a
/// second way in that could forget one of them.
struct SiteDayCard: View {
    /// One person's line.
    struct Line: Identifiable {
        enum Style {
            /// The site's times: plain.
            case plain
            /// Late, early, away: orange.
            case attention
            /// Moved to another site: the accent.
            case moved
            /// Not ticked and no reason: grey.
            case quiet
        }

        let person: PersonReference
        let detail: String
        let style: Style
        /// Said by VoiceOver after the name, when the detail alone is not
        /// enough ("left early").
        var spoken: String? = nil
        var id: UUID { person.id }
    }

    let day: SiteDay
    let figures: SiteCrewFigures
    let lines: [Line]
    /// Someone on the crew is neither ticked nor given a reason: the dot is
    /// orange, "partly" under the colour rule.
    let isPartly: Bool
    let canEdit: Bool
    let warnings: [DayWarning]
    let formatting: CalendarFormatting
    let durations: DurationFormatting
    /// Every site's name by id, for who moved where.
    let siteNames: [UUID: String]
    /// "Saved" beside the status, for a moment after each write.
    var showsSaved = false
    let onChange: () -> Void
    var onUndoMove: (SiteMove) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            header

            VStack(alignment: .leading, spacing: Metrics.tiny) {
                ForEach(lines) { line in
                    lineView(line)
                }
            }

            warningsView

            ForEach(day.moves) { move in
                moveBanner(move)
            }

            Button(action: onChange) {
                Text("Change")
            }
            .buttonStyle(.bigAction(.secondary))
            .disabled(!canEdit)
            .accessibilityIdentifier("site-day-change")
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: SiteDayStyle.cardRadius, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Metrics.small) {
            Text(verbatim: headerText)
                .font(.footnote.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Color.hoursDone)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
                .accessibilityLabel(headerText)
                .accessibilityIdentifier("site-crew-total")
            if showsSaved {
                Label("Saved", systemImage: "checkmark")
                    .font(.footnote)
                    .foregroundStyle(.hoursSecondaryText)
                    .transition(.opacity)
                    .accessibilityIdentifier("site-day-saved")
            }
            Spacer(minLength: Metrics.small)
            SiteStatusDot(color: isPartly ? Color.hoursAttentionFill : Color.hoursDone)
        }
    }

    /// "Written · 4 people · 32h".
    private var headerText: String {
        [
            String(localized: "Written"),
            String(inflected: "^[\(figures.people) person](inflect: true)"),
            durations.string(figures.totalMinutes),
        ].joined(separator: " · ")
    }

    // MARK: - Lines

    private func lineView(_ line: Line) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
            Text(verbatim: line.person.name)
                .font(.subheadline.weight(line.style == .attention ? .semibold : .regular))
                .foregroundStyle(nameColor(line.style))
            Spacer(minLength: Metrics.small)
            Text(verbatim: line.detail)
                .font(.subheadline.monospacedDigit().weight(line.style == .plain || line.style == .quiet ? .regular : .semibold))
                .foregroundStyle(detailColor(line.style))
                .multilineTextAlignment(.trailing)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: line.person.name))
        .accessibilityValue(Text(verbatim: [line.detail, line.spoken].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityIdentifier("site-line-\(SiteDayStyle.key(line.person))")
    }

    private func nameColor(_ style: Line.Style) -> Color {
        switch style {
        case .plain, .moved: return .primary
        case .attention: return .hoursAttention
        case .quiet: return .secondary
        }
    }

    private func detailColor(_ style: Line.Style) -> Color {
        switch style {
        case .plain, .quiet: return .secondary
        case .attention: return .hoursAttention
        case .moved: return .accentColor
        }
    }

    // MARK: - Moves

    /// "4 went to Trg Pravde at 11:30", with Undo (mockup After).
    private func moveBanner(_ move: SiteMove) -> some View {
        HStack(spacing: Metrics.small) {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(moveText(move))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("site-move-banner")
            if canEdit {
                Button("Undo") { onUndoMove(move) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("site-move-undo")
            }
        }
        .padding(.horizontal, Metrics.medium)
        .padding(.vertical, Metrics.tiny)
        .background(
            Color.accentColor.opacity(0.10),
            in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    /// One sentence, the who and where in bold: "**4 went to Trg Pravde** at
    /// 11:30".
    private func moveText(_ move: SiteMove) -> AttributedString {
        let site = siteNames[move.toSiteID] ?? String(localized: "Another site")
        let time = formatting.time(move.left, on: day.date)
        let ids = move.memberIDs
        if ids == [CrewMember.youID] {
            return AttributedString(localized: "**You went to \(site)** at \(time)", comment: "Site day banner, you alone moved; the values are the other site and a time")
        }
        if ids.count == 1, let name = lines.first(where: { $0.id == ids[0] })?.person.name {
            return AttributedString(localized: "**\(name) went to \(site)** at \(time)", comment: "Site day banner; the values are a person, the other site and a time")
        }
        return AttributedString(localized: "**\(ids.count) went to \(site)** at \(time)", comment: "Site day banner; the values are how many moved, the other site and a time")
    }

    // MARK: - Warnings

    /// Each warning once, however many people it applies to — with no end
    /// time it applies to all of them, and saying so per person is noise.
    @ViewBuilder
    private var warningsView: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                ForEach(warnings) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(warning.isProblem ? Color.hoursAttention : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
