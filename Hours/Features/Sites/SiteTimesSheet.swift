import SwiftUI

/// Changes a site day's own times: when the site started, when it finished
/// and the break, which everyone ticked shares unless their own times were
/// changed.
///
/// One save on Done rather than one per turn of the wheel, as with a single
/// person's times: the day screen writes through the month lock and your
/// calendar day, and doing that for every minute the wheel passes would be
/// sixty writes for one change. Cancel leaves the day exactly as it was.
struct SiteTimesSheet: View {
    let day: SiteDay
    let onSave: (SiteDay) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore

    @State private var start: TimeOfDay?
    @State private var end: TimeOfDay?
    @State private var breakMinutes: Int
    @State private var editing: TimeField = .start

    /// Which of the two times the wheel is turning.
    private enum TimeField: Hashable {
        case start, end
    }

    /// The breaks a site actually takes, one tap each. Anything else already
    /// on the day is shown beside them rather than silently rounded away.
    private static let breakChoices = [0, 15, 30, 45, 60]

    init(day: SiteDay, defaultStart: TimeOfDay, defaultEnd: TimeOfDay, onSave: @escaping (SiteDay) -> Void) {
        self.day = day
        self.onSave = onSave
        // A day with no times yet opens on the schedule's, as a new day in
        // the calendar does. A day with one of the two keeps the gap: a start
        // with no finish is a real state, and filling it in would change it.
        let isUntimed = day.start == nil && day.end == nil
        _start = State(initialValue: isUntimed ? defaultStart : day.start)
        _end = State(initialValue: isUntimed ? defaultEnd : day.end)
        _breakMinutes = State(initialValue: day.breakMinutes)
        self.defaultStart = defaultStart
        self.defaultEnd = defaultEnd
    }

    private let defaultStart: TimeOfDay
    private let defaultEnd: TimeOfDay

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.large) {
                    HStack(spacing: Metrics.medium) {
                        timeTile(.start)
                        timeTile(.end)
                    }

                    DatePicker(
                        editing == .start ? String(localized: "On site") : String(localized: "Off site"),
                        selection: wheelBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("site-hours-wheel")

                    breakChips

                    Text("Everyone ticked on this day gets these times, except people whose own times you changed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Metrics.large)
            }
            .background(Color.hoursCanvas)
            .navigationTitle(String(
                localized: "Site times · \(formatting.mediumDate(day.date))",
                comment: "Title of the sheet that changes a site day's times; the value is a date"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("site-hours")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("site-hours-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("site-hours-done")
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Times

    private func timeTile(_ edge: TimeField) -> some View {
        let isSelected = editing == edge
        let title = edge == .start ? String(localized: "On site") : String(localized: "Off site")
        let value = edge == .start ? start : end

        return Button {
            editing = edge
            // Choosing an empty time is choosing to set it: it starts where
            // the wheel shows it, so what is on screen is what Done saves.
            if value == nil {
                setTime(fallback(for: edge), for: edge)
            }
        } label: {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .lineLimit(2)
                Text(value.map { formatting.time($0, on: day.date) } ?? "—")
                    .font(.hoursFigure(.largeTitle))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(Metrics.medium)
            .background(
                Color.hoursSurface,
                in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            }
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { formatting.time($0, on: day.date) } ?? "—")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(edge == .start ? "site-hours-start" : "site-hours-end")
    }

    private var wheelBinding: Binding<Date> {
        Binding(
            get: {
                let time = (editing == .start ? start : end) ?? fallback(for: editing)
                return OptionalTimeRow.date(from: time, in: calendar)
            },
            set: { setTime(OptionalTimeRow.time(from: $0, in: calendar), for: editing) }
        )
    }

    private func setTime(_ time: TimeOfDay, for edge: TimeField) {
        switch edge {
        case .start: start = time
        case .end: end = time
        }
    }

    private func fallback(for edge: TimeField) -> TimeOfDay {
        edge == .start ? defaultStart : defaultEnd
    }

    // MARK: - Break

    private var breakChips: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Text("Break")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)

            // Wraps onto a second line at large text sizes rather than
            // squeezing the chips below a usable size.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.small) { chipRow(choices[...]) }
                VStack(alignment: .leading, spacing: Metrics.small) {
                    HStack(spacing: Metrics.small) { chipRow(choices.prefix(3)) }
                    HStack(spacing: Metrics.small) { chipRow(choices.dropFirst(3)) }
                }
            }
        }
    }

    private var choices: [Int] {
        // The day's own break stays on offer after another chip is tapped,
        // so changing your mind is one tap back.
        var all = Self.breakChoices
        for extra in [day.breakMinutes, breakMinutes] where !all.contains(extra) {
            all.append(extra)
        }
        return all.sorted()
    }

    private func chipRow(_ minutes: ArraySlice<Int>) -> some View {
        ForEach(Array(minutes), id: \.self) { value in
            let isSelected = value == breakMinutes
            Button {
                breakMinutes = value
            } label: {
                Text(chipTitle(value))
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                    .padding(.horizontal, Metrics.medium)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(
                        isSelected ? Color.accentColor : Color.hoursSurface,
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("site-break-\(value)")
        }
    }

    private func chipTitle(_ minutes: Int) -> String {
        guard minutes > 0 else { return String(localized: "None") }
        // Hours and minutes whatever the display setting: "0:15" on a chip
        // reads as a time of day, "15m" cannot.
        return DurationFormatting(style: .hoursAndMinutes).string(minutes)
    }

    // MARK: - Saving

    private func save() {
        var next = day
        next.start = start
        next.end = end
        next.breakMinutes = breakMinutes
        onSave(next)
        dismiss()
    }

    // MARK: - Derived

    private var calendar: Calendar { settingsStore.workCalendar }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }
}
