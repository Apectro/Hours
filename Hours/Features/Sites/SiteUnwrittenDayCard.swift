import SwiftUI

/// A day with nothing written on the site yet (1.2 redesign, mockups 06
/// "A normal day: one tap" and 07 "A missed day").
///
/// Today, or a day still to come: "NOT WRITTEN YET", the site's usual day
/// and the people it would tick with their times, a big **Same as usual**
/// and **Something's different…**. "Same as last day" and "Start from empty"
/// stay underneath, smaller, for the day that copies another or starts bare.
///
/// A work day gone by with nothing written: a dashed red card, "NOT
/// WRITTEN", **Same as the day before** first with what it would copy, then
/// Same as usual and Start from empty.
///
/// Draws and reports; the site screen writes, through the month lock.
struct SiteUnwrittenDayCard: View {
    enum Kind {
        /// Today or later.
        case upcoming
        /// A work day of the site before today (`SiteDayStatus.missing`).
        case missed
        /// A day before today that was not expected to be worked.
        case pastDayOff
    }

    /// One person the usual day would tick, with their times.
    struct Line: Identifiable {
        let person: PersonReference
        let times: String
        var id: UUID { person.id }
    }

    let kind: Kind
    /// The site's usual day: who it ticks and their times.
    let usualPeople: [Line]
    let usualTimes: String
    let usualBreak: String
    /// What "Same as the day before" would copy, when there is an earlier day.
    let lastDaySummary: String?
    /// Today, copying yesterday: "Same as yesterday", as the site widget says.
    var copiesYesterday = false
    let canEdit: Bool
    let onSameAsUsual: () -> Void
    let onSomethingDifferent: () -> Void
    let onSameAsLastDay: () -> Void
    let onStartEmpty: () -> Void

    var body: some View {
        switch kind {
        case .missed: missedCard
        case .upcoming, .pastDayOff: usualCard
        }
    }

    // MARK: - Today

    private var usualCard: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            HStack(spacing: Metrics.small) {
                Text(kind == .upcoming ? "Not written yet" : "Not written")
                    .font(.footnote.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(.hoursSecondaryText)
                    .accessibilityIdentifier("site-day-not-written")
                Spacer(minLength: Metrics.small)
                // Orange: today is not over, so it is only a look-at-this.
                // A day off gone by is grey: nothing was expected.
                SiteStatusDot(color: kind == .upcoming ? Color.hoursAttentionFill : Color.hoursSubdued)
            }

            Text(usualSentence)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(usualPeople.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { SiteDivider() }
                    HStack(spacing: Metrics.small) {
                        SiteInitials(person: entry.person)
                        Text(verbatim: entry.person.name)
                            .font(.body)
                        Spacer(minLength: Metrics.small)
                        Text(verbatim: entry.times)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.hoursSecondaryText)
                    }
                    .frame(minHeight: 42)
                    .accessibilityElement(children: .combine)
                }
            }

            Button(action: onSameAsUsual) {
                Text("Same as usual")
            }
            .buttonStyle(.bigAction(.primary, isMain: true))
            .disabled(!canEdit)
            .accessibilityIdentifier("site-day-same-as-usual")

            Button(action: onSomethingDifferent) {
                Text("Something's different…")
            }
            .buttonStyle(.bigAction(.secondary))
            .disabled(!canEdit)
            .accessibilityIdentifier("site-day-something-different")

            // The ways in that were the card's own before 1.2, kept: the
            // widget's "Same as yesterday" lands here, and a bare day.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.small) { quietChoices }
                VStack(alignment: .leading, spacing: 0) { quietChoices }
            }
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: SiteDayStyle.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var quietChoices: some View {
        if let lastDaySummary {
            Button(action: onSameAsLastDay) {
                Text(copiesYesterday ? "Same as yesterday" : "Same as last day")
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!canEdit)
            // Read as one sentence, so VoiceOver says what would be copied
            // and a test can check it names the right day.
            .accessibilityLabel(Text(copiesYesterday ? "Same as yesterday" : "Same as last day") + Text(verbatim: ", \(lastDaySummary)"))
            .accessibilityIdentifier("site-day-same-as-last")
            Spacer(minLength: Metrics.small)
        }
        Button(action: onStartEmpty) {
            Text("Start from empty")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!canEdit)
        .accessibilityIdentifier("site-day-start-empty")
    }

    /// "The usual day: **5 people**, **07:00–16:00**, 30 min break".
    private var usualSentence: AttributedString {
        let people = String(inflected: "^[\(usualPeople.count) person](inflect: true)")
        return AttributedString(
            localized: "The usual day: **\(people)**, **\(usualTimes)**, \(usualBreak)",
            comment: "On an unwritten site day; the values are how many people, a time range and the break"
        )
    }

    // MARK: - A missed day

    private var missedCard: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            VStack(alignment: .leading, spacing: Metrics.medium) {
                Text("Not written")
                    .font(.footnote.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundStyle(Color.hoursMissing)
                    .accessibilityIdentifier("site-day-not-written")

                Text("Nobody is ticked for this day yet.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                if let lastDaySummary {
                    VStack(alignment: .leading, spacing: Metrics.tiny) {
                        Button(action: onSameAsLastDay) {
                            Text("Same as the day before")
                        }
                        .buttonStyle(.bigAction(.primary, isMain: true))
                        .disabled(!canEdit)
                        .accessibilityLabel(Text("Same as the day before") + Text(verbatim: ", \(lastDaySummary)"))
                        .accessibilityIdentifier("site-day-same-as-last")
                        Text(verbatim: lastDaySummary)
                            .font(.footnote)
                            .foregroundStyle(.hoursSecondaryText)
                            .accessibilityHidden(true)
                    }
                }

                Button(action: onSameAsUsual) {
                    Text("Same as usual")
                }
                .buttonStyle(.bigAction(lastDaySummary == nil ? .primary : .secondary, isMain: lastDaySummary == nil))
                .disabled(!canEdit)
                .accessibilityIdentifier("site-day-same-as-usual")

                Button(action: onStartEmpty) {
                    Text("Start from empty")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(.hoursHairlineStyle, lineWidth: 1.5)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canEdit)
                .accessibilityIdentifier("site-day-start-empty")

                // Kept as a way in from the card too: a day that differs
                // from both the usual day and the one before.
                Button(action: onSomethingDifferent) {
                    Text("Something's different…")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!canEdit)
                .accessibilityIdentifier("site-day-something-different")
            }
            .padding(Metrics.large + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: SiteDayStyle.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: SiteDayStyle.cardRadius, style: .continuous)
                    .strokeBorder(Color.hoursMissing, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }

            Text("Nobody worked that day? Choose “Start from empty” and leave everyone unticked, or mark it as bad weather.")
                .font(.footnote)
                .foregroundStyle(.hoursSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metrics.small)
        }
    }
}
