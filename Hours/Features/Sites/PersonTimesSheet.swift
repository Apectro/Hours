import SwiftUI

/// Changes one person's hours on a site day: the late arrival, the early
/// finish, the longer break. Everyone else keeps the site's times.
///
/// The fields show what the person actually worked — their own time where
/// they have one, the site's otherwise — and a value set back to the site's
/// is stored as "the site's", not as a copy of it. So a row is only ever
/// marked as different when it really is, and a later change to the site's
/// times still reaches everyone who had no exception.
///
/// One person's change is a single save on Done, rather than a save per turn
/// of the time wheel; the day screen does the writing.
struct PersonTimesSheet: View {
    let name: String
    let day: SiteDay
    let onSave: (Attendance) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore

    @State private var attendance: Attendance

    init(name: String, attendance: Attendance, day: SiteDay, onSave: @escaping (Attendance) -> Void) {
        self.name = name
        self.day = day
        self.onSave = onSave
        _attendance = State(initialValue: attendance)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    OptionalTimeRow(
                        title: String(localized: "On site"),
                        time: startBinding,
                        calendar: calendar,
                        fallback: day.start ?? settings.primarySchedule(on: day.date).defaultStart
                    )
                    OptionalTimeRow(
                        title: String(localized: "Off site"),
                        time: endBinding,
                        calendar: calendar,
                        fallback: day.end ?? settings.primarySchedule(on: day.date).defaultEnd
                    )
                    DurationStepperRow(
                        title: String(localized: "Break"),
                        minutes: breakBinding,
                        range: 0...(12 * 60),
                        step: 5,
                        formatting: settings.displayFormatting
                    )
                } footer: {
                    Text(String(
                        localized: "Everyone else keeps the site times: \(siteTimes).",
                        comment: "Under one person's changed times; the value is a time range"
                    ))
                }

                Section {
                    Button("Use site times") {
                        attendance = Attendance(memberID: attendance.memberID)
                    }
                    .disabled(!hasOwnTimes)
                    .accessibilityIdentifier("person-times-reset")
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("person-times")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("person-times-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(attendance)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("person-times-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }

    private var hasOwnTimes: Bool {
        attendance.start != nil || attendance.end != nil || attendance.breakMinutes != nil
    }

    private var siteTimes: String {
        let formatting = settingsStore.dateFormatting
        guard let start = day.start, let end = day.end else { return "—" }
        return "\(formatting.time(start, on: day.date)) – \(formatting.time(end, on: day.date))"
    }

    // Clearing a time sets it back to the site's, which is the only "empty"
    // a person's time can have: they were ticked, so they were there.

    private var startBinding: Binding<TimeOfDay?> {
        Binding(
            get: { attendance.start ?? day.start },
            set: { attendance.start = $0 == day.start ? nil : $0 }
        )
    }

    private var endBinding: Binding<TimeOfDay?> {
        Binding(
            get: { attendance.end ?? day.end },
            set: { attendance.end = $0 == day.end ? nil : $0 }
        )
    }

    private var breakBinding: Binding<Int> {
        Binding(
            get: { attendance.breakMinutes ?? day.breakMinutes },
            set: { attendance.breakMinutes = $0 == day.breakMinutes ? nil : $0 }
        )
    }
}
