import SwiftUI

/// A day with nothing written on the site yet (mockup board 5).
///
/// Offers the two ways in rather than an empty form: "Same as last day",
/// which is what most days on a site are, saying exactly what it would copy,
/// and "Start from empty" for the day that was different. Choosing either
/// writes nothing by itself beyond what the choice says — copying saves the
/// copied day; starting empty only shows the ordinary card, and the day is
/// stored on its first tick or time, as before.
struct SiteUnwrittenDayCard: View {
    let title: String
    /// What "Same as last day" copies: the date it comes from, the site's
    /// times there and how many people it brings.
    let lastDayDate: CalendarDate
    let lastDay: SiteDay
    let formatting: CalendarFormatting
    let onSameAsLastDay: () -> Void
    let onStartEmpty: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Metrics.small)
                Text("Not written")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.hoursNegative)
                    .accessibilityIdentifier("site-day-not-written")
            }

            Text("Nobody is ticked for this day yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onSameAsLastDay) {
                VStack(spacing: 2) {
                    Label("Same as last day", systemImage: "arrow.uturn.backward.circle")
                        .font(.body.weight(.semibold))
                    Text(copySummary)
                        .font(.footnote)
                        .opacity(0.85)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, Metrics.tiny)
            }
            .buttonStyle(.borderedProminent)
            // Read as one sentence, so VoiceOver says what would be copied
            // and a test can check it names the right day.
            .accessibilityLabel(Text("Same as last day") + Text(verbatim: ", \(copySummary)"))
            .accessibilityIdentifier("site-day-same-as-last")

            Button(action: onStartEmpty) {
                Text("Start from empty")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("site-day-start-empty")
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    /// "Tue 20 Oct · 07:00 – 16:00 · 4 people". The times are left out when
    /// the day it copies had none.
    private var copySummary: String {
        var parts = [formatting.mediumDate(lastDayDate)]
        if let start = lastDay.start, let end = lastDay.end {
            parts.append("\(formatting.time(start, on: lastDayDate)) – \(formatting.time(end, on: lastDayDate))")
        }
        if !lastDay.present.isEmpty {
            parts.append(String(inflected: "^[\(lastDay.present.count) person](inflect: true)"))
        }
        return parts.joined(separator: " · ")
    }
}
