import SwiftUI

/// Changes a site day's own times: when the site started, when it finished
/// and the break, which everyone ticked shares unless their own times were
/// changed.
///
/// A form: Start and End as the day editor's time rows, the break as one
/// tap of a segmented picker. One save on Save rather than one per change,
/// as with a single person's times: the day screen writes through the month
/// lock and your calendar day, and doing that for every minute a picker
/// passes would be sixty writes for one change. Cancel leaves the day
/// exactly as it was.
struct SiteTimesSheet: View {
    let day: SiteDay
    let onSave: (SiteDay) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore

    @State private var start: TimeOfDay?
    @State private var end: TimeOfDay?
    @State private var breakMinutes: Int

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
            Form {
                Section {
                    OptionalTimeRow(
                        title: String(localized: "Start"),
                        time: $start,
                        calendar: calendar,
                        fallback: defaultStart
                    )
                    .accessibilityIdentifier("site-hours-start")
                    OptionalTimeRow(
                        title: String(localized: "End"),
                        time: $end,
                        calendar: calendar,
                        fallback: defaultEnd
                    )
                    .accessibilityIdentifier("site-hours-end")
                } footer: {
                    Text("Everyone ticked on this day gets these times, except people whose own times you changed.")
                }

                Section {
                    Picker(String(localized: "Break"), selection: $breakMinutes) {
                        ForEach(choices, id: \.self) { value in
                            Text(verbatim: chipTitle(value)).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("site-hours-break")
                } header: {
                    Text("Break")
                        .textCase(nil)
                }
            }
            .accessibilityIdentifier("site-hours")
            .navigationTitle(String(
                localized: "Site times · \(formatting.mediumDate(day.date))",
                comment: "Title of the sheet that changes a site day's times; the value is a date"
            ))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Cancel"))
                    .accessibilityIdentifier("site-hours-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(String(localized: "Save"))
                    .accessibilityIdentifier("site-hours-save")
                }
            }
        }
        .presentationDetents([.large])
        // A stray swipe must not throw away times that were changed.
        .interactiveDismissDisabled(hasChanges)
    }

    // MARK: - Break

    private var choices: [Int] {
        // The day's own break stays on offer after another is picked, so
        // changing your mind is one tap back.
        var all = Self.breakChoices
        for extra in [day.breakMinutes, breakMinutes] where !all.contains(extra) {
            all.append(extra)
        }
        return all.sorted()
    }

    private func chipTitle(_ minutes: Int) -> String {
        guard minutes > 0 else { return String(localized: "None") }
        // Hours and minutes whatever the display setting: "0:15" in a
        // segment reads as a time of day, "15m" cannot.
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

    /// Against what the sheet opened on, so a day with no times yet, which
    /// opens on the schedule's, is not "changed" just by being looked at.
    private var hasChanges: Bool {
        let isUntimed = day.start == nil && day.end == nil
        let openedStart = isUntimed ? defaultStart : day.start
        let openedEnd = isUntimed ? defaultEnd : day.end
        return start != openedStart || end != openedEnd || breakMinutes != day.breakMinutes
    }

    private var calendar: Calendar { settingsStore.workCalendar }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }
}
