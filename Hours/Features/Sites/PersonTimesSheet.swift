import SwiftUI

/// "Late/early" on the crew's day (1.2 redesign, mockup 06 "Late or early:
/// one person's times"): Start, End and Break, what that comes to, why it
/// shows in orange on the sheet ("left 3 hours before the site's usual
/// end"), and "Use the site's times again".
///
/// The fields show what the person actually worked — their own time where
/// they have one, the site's otherwise — and a value set back to the site's
/// is stored as "the site's", not as a copy of it. So a row is only ever
/// marked as different when it really is, and a later change to the site's
/// times still reaches everyone who had no exception.
///
/// One person's change is handed back on Save; the crew's day keeps it with
/// the rest until its own Save, which writes.
struct PersonTimesSheet: View {
    let name: String
    let day: SiteDay
    let onSave: (Attendance) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore

    @State private var attendance: Attendance
    /// What the sheet opened on, to tell a change from a look.
    private let original: Attendance

    init(name: String, attendance: Attendance, day: SiteDay, onSave: @escaping (Attendance) -> Void) {
        self.name = name
        self.day = day
        self.onSave = onSave
        _attendance = State(initialValue: attendance)
        original = attendance
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    OptionalTimeRow(
                        title: String(localized: "Start"),
                        time: startBinding,
                        calendar: calendar,
                        fallback: day.start ?? settings.primarySchedule(on: day.date).defaultStart
                    )
                    OptionalTimeRow(
                        title: String(localized: "End"),
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
                }

                Section {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Worked")
                            .foregroundStyle(.hoursSecondaryText)
                        Spacer(minLength: Metrics.small)
                        Text(verbatim: settings.displayFormatting.string(workedMinutes))
                            .font(.hoursFigure(.title, weight: .heavy))
                            .contentTransition(.numericText())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("person-times-worked")
                } footer: {
                    VStack(alignment: .leading, spacing: Metrics.tiny) {
                        if let explanation {
                            Text(verbatim: explanation)
                                .foregroundStyle(Color.hoursAttention)
                                .accessibilityIdentifier("person-times-explanation")
                        }
                        Text(String(
                            localized: "Everyone else keeps the site times: \(siteTimes).",
                            comment: "Under one person's changed times; the value is a time range"
                        ))
                    }
                }

                Section {
                    Button("Use the site's times again") {
                        attendance = Attendance(memberID: attendance.memberID)
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasOwnTimes)
                    .accessibilityIdentifier("person-times-reset")
                }
            }
            .navigationTitle(Text(verbatim: "\(name) · \(settingsStore.dateFormatting.dayTitle(day.date))"))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("person-times")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("person-times-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(attendance)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("person-times-save")
                }
            }
        }
        .presentationDetents([.large])
        // A stray swipe must not throw away times that were changed.
        .interactiveDismissDisabled(attendance != original)
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }

    private var hasOwnTimes: Bool {
        attendance.start != nil || attendance.end != nil || attendance.breakMinutes != nil
    }

    /// What these times come to, through the same calculator as the day.
    private var workedMinutes: Int {
        let withThese = day.settingAttendance(attendance, allowanceByDefault: false)
        return SiteDayCalculator(settings: settings, calendar: calendar)
            .compute(withThese)
            .people
            .first { $0.memberID == attendance.memberID }?
            .workedMinutes ?? 0
    }

    /// "Shown in orange on the sheet: left 3h before the site's end."
    private var explanation: String? {
        let difference = SiteTimeDifference.of(attendance, in: day)
        guard !difference.isNone else { return nil }
        let length = { (minutes: Int) in DurationFormatting(style: .hoursAndMinutes).string(abs(minutes)) }
        var parts: [String] = []
        if difference.startMinutes > 0 {
            parts.append(String(localized: "came \(length(difference.startMinutes)) after the site's start", comment: "Why a crew member's row is orange; the value is a duration"))
        } else if difference.startMinutes < 0 {
            parts.append(String(localized: "started \(length(difference.startMinutes)) before the site's start", comment: "Why a crew member's row is orange; the value is a duration"))
        }
        if difference.endMinutes < 0 {
            parts.append(String(localized: "left \(length(difference.endMinutes)) before the site's end", comment: "Why a crew member's row is orange; the value is a duration"))
        } else if difference.endMinutes > 0 {
            parts.append(String(localized: "stayed \(length(difference.endMinutes)) after the site's end", comment: "Why a crew member's row is orange; the value is a duration"))
        }
        if difference.breakMinutes != 0 {
            parts.append(String(localized: "a break of \(length(attendance.breakMinutes ?? day.breakMinutes))", comment: "Why a crew member's row is orange; the value is their own break"))
        }
        let reasons = parts.joined(separator: ", ")
        return String(localized: "Shown in orange on the sheet: \(reasons).", comment: "Under one person's times; the value says how they differ from the site's")
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
