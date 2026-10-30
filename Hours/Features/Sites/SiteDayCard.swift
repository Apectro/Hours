import SwiftUI

/// A written site day (design v2, mockup Sites phone 4): differences stand
/// out, the rest is quiet. A green tick and "Written" with the crew's hours
/// on the right, then one row per person: their times in grey on the right
/// and, under the name, only what was different — blue "Moved to Jarunski at
/// 12:40", orange "Left early", orange "Not here · no reason given" with Add
/// reason. Whoever was at another site or away for a reason is greyed.
///
/// These draw and report, nothing more. Every change goes back to the site
/// screen through a callback, because that is where the month lock, the
/// refusal and your calendar day are handled.

/// "✓ Written" on the left, the crew's hours on the right.
struct SiteWrittenHeader: View {
    let figures: SiteCrewFigures
    let durations: DurationFormatting
    /// "Saved" for a moment after each write: the day saves itself.
    var showsSaved = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.hoursDone)
                .accessibilityHidden(true)
            Text("Written")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if showsSaved {
                Text("Saved")
                    .font(.footnote)
                    .foregroundStyle(.hoursSecondaryText)
                    .transition(.opacity)
                    .accessibilityIdentifier("site-day-saved")
            }
            Spacer(minLength: Metrics.small)
            Text(verbatim: durations.string(figures.totalMinutes))
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.hoursSecondaryText)
                .contentTransition(.numericText())
                .accessibilityLabel(headerText)
                .accessibilityIdentifier("site-crew-total")
        }
    }

    /// "Written · 4 people · 32h", said by VoiceOver.
    private var headerText: String {
        [
            String(localized: "Written"),
            String(inflected: "^[\(figures.people) person](inflect: true)"),
            durations.string(figures.totalMinutes),
        ].joined(separator: " · ")
    }
}

/// One person on a written day.
struct SiteDayLine: Identifiable {
    enum NoteStyle {
        /// Moved to another site: the accent.
        case moved
        /// Late, early, not here with no reason: orange.
        case attention
    }

    let person: PersonReference
    /// On the right, in grey: their times, or where they were instead.
    var value: String
    /// Under the name: only what was different.
    var note: String? = nil
    var noteStyle = NoteStyle.attention
    /// At another site or away for a reason: the name in grey.
    var isQuiet = false
    /// Not here, no reason given, and expected that day: Add reason.
    var offersReason = false

    var id: UUID { person.id }
}

/// A row of the written day's crew.
struct SiteDayLineRow: View {
    let line: SiteDayLine
    let canEdit: Bool
    let onAddReason: () -> Void

    var body: some View {
        HStack(spacing: Metrics.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: line.person.name)
                    .foregroundStyle(line.isQuiet ? AnyShapeStyle(.hoursSecondaryText) : AnyShapeStyle(.primary))
                if let note = line.note {
                    Text(verbatim: note)
                        .font(.subheadline)
                        .foregroundStyle(line.noteStyle == .moved ? Color.accentColor : Color.hoursAttention)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One element for VoiceOver and the UI tests: the name, then the
            // times and what was different.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: line.person.name))
            .accessibilityValue(Text(verbatim: [line.value, line.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")))
            .accessibilityIdentifier("site-line-\(SiteDayStyle.key(line.person))")

            if line.offersReason {
                Button("Add reason", action: onAddReason)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .disabled(!canEdit)
                    .accessibilityIdentifier("site-add-reason-\(SiteDayStyle.key(line.person))")
            } else if !line.value.isEmpty {
                Text(verbatim: line.value)
                    .monospacedDigit()
                    .foregroundStyle(.hoursSecondaryText)
                    .multilineTextAlignment(.trailing)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
    }
}

/// "**4 went to Trg Pravde** at 11:30", with Undo.
struct SiteMoveRow: View {
    let text: AttributedString
    let canEdit: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Metrics.small) {
            Image(systemName: "arrow.left.arrow.right")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("site-move-banner")
            if canEdit {
                Button("Undo", action: onUndo)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("site-move-undo")
            }
        }
    }
}

extension SiteMoveRow {
    /// One sentence, the who and where in bold: "**4 went to Trg Pravde** at
    /// 11:30".
    static func text(
        _ move: SiteMove,
        on date: CalendarDate,
        names: [UUID: String],
        siteNames: [UUID: String],
        formatting: CalendarFormatting
    ) -> AttributedString {
        let site = siteNames[move.toSiteID] ?? String(localized: "Another site")
        let time = formatting.time(move.left, on: date)
        let ids = move.memberIDs
        if ids == [CrewMember.youID] {
            return AttributedString(localized: "**You went to \(site)** at \(time)", comment: "Site day banner, you alone moved; the values are the other site and a time")
        }
        if ids.count == 1, let name = names[ids[0]] {
            return AttributedString(localized: "**\(name) went to \(site)** at \(time)", comment: "Site day banner; the values are a person, the other site and a time")
        }
        return AttributedString(localized: "**\(ids.count) went to \(site)** at \(time)", comment: "Site day banner; the values are how many moved, the other site and a time")
    }
}
