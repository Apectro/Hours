import SwiftUI

/// A day with nothing written on the site yet (design v2, mockup Sites
/// phone 3, "one tap when it's a normal day"): "Not written yet" and the
/// usual day in a sentence, then the crew the usual day would tick, each
/// with a filled tick and their times. Tapping a name changes their times
/// or says why they were not there; the bottom's Save writes the day.
///
/// A work day gone by with nothing written says "Not written" and offers
/// Same as the day before first. Draws only; the site screen writes,
/// through the month lock.

/// Which kind of unwritten day.
enum SiteUnwrittenKind {
    /// Today or later.
    case upcoming
    /// A work day of the site before today (`SiteDayStatus.missing`).
    case missed
    /// A day before today that was not expected to be worked.
    case pastDayOff
}

/// "Not written yet" over "The usual day is 7:00 – 15:00, 30m break."
struct SiteUnwrittenHeader: View {
    let kind: SiteUnwrittenKind
    let usualTimes: String
    let usualBreak: String

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.tiny) {
            Text(kind == .upcoming ? "Not written yet" : "Not written")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("site-day-not-written")
            Text(verbatim: sentence)
                .foregroundStyle(.hoursSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sentence: String {
        if kind == .missed {
            return String(localized: "Nobody is ticked for this day yet.")
        }
        return String(
            localized: "The usual day is \(usualTimes), \(usualBreak).",
            comment: "On an unwritten site day; the values are a time range such as 7:00 – 15:00 and the break such as 30m break"
        )
    }
}

/// One person on a day not written yet: a filled tick and their times when
/// the day would have them, an empty circle and why not when it would not.
struct SiteDraftPersonRow: View {
    let person: PersonReference
    let isHere: Bool
    /// Their times, or why they would not be there.
    let value: String
    /// Orange: their own times, or away.
    let needsAttention: Bool

    var body: some View {
        HStack(spacing: Metrics.medium) {
            if isHere {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .font(.title2)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.tertiary)
                    .font(.title2)
                    .accessibilityHidden(true)
            }
            Text(verbatim: person.name)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: value)
                .monospacedDigit()
                .foregroundStyle(needsAttention ? AnyShapeStyle(Color.hoursAttention) : AnyShapeStyle(.hoursSecondaryText))
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
