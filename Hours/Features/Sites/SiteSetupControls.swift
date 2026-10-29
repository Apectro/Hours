import SwiftUI

/// The pieces a site's usual day and extras are set with (1.2): the
/// wizard's steps, the site's settings and Settings › New sites start with
/// all use these, so the three read and behave the same.

/// Start, end and break of a usual day, as rows of a `Form` section.
struct UsualDayRows: View {
    @Binding var start: TimeOfDay
    @Binding var end: TimeOfDay
    @Binding var breakMinutes: Int
    let calendar: Calendar
    var isDisabled = false

    /// The site times sheet's choices, and whatever is set already.
    private static let breakChoices = [0, 15, 20, 30, 45, 60, 90]

    // Not private: that would make the memberwise initializer private too.
    @Environment(SettingsStore.self) var settingsStore

    var body: some View {
        DatePicker("Start", selection: binding($start), displayedComponents: .hourAndMinute)
            .accessibilityIdentifier("usual-day-start")
            .disabled(isDisabled)
        DatePicker("End", selection: binding($end), displayedComponents: .hourAndMinute)
            .accessibilityIdentifier("usual-day-end")
            .disabled(isDisabled)
        Picker("Break", selection: $breakMinutes) {
            ForEach(choices, id: \.self) { minutes in
                Text(minutes == 0 ? String(localized: "None") : settingsStore.settings.displayFormatting.string(minutes))
                    .tag(minutes)
            }
        }
        .accessibilityIdentifier("usual-day-break")
        .disabled(isDisabled)
    }

    private var choices: [Int] {
        var all = Self.breakChoices
        if !all.contains(breakMinutes) { all.append(breakMinutes) }
        return all.sorted()
    }

    private func binding(_ time: Binding<TimeOfDay>) -> Binding<Date> {
        Binding(
            get: { OptionalTimeRow.date(from: time.wrappedValue, in: calendar) },
            set: { time.wrappedValue = OptionalTimeRow.time(from: $0, in: calendar) }
        )
    }
}

/// The seven days as round buttons in the week's order, a filled one being
/// a work day.
struct WorkDaysPicker: View {
    @Binding var days: Set<Int>
    let formatting: CalendarFormatting
    var isDisabled = false

    var body: some View {
        HStack(spacing: Metrics.tiny) {
            ForEach(formatting.orderedWeekdayNumbers, id: \.self) { weekday in
                let isOn = days.contains(weekday)
                Button {
                    if isOn { days.remove(weekday) } else { days.insert(weekday) }
                } label: {
                    Text(verbatim: formatting.veryShortWeekdaySymbol(for: weekday))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            Circle()
                                .fill(isOn ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                                .frame(width: 40, height: 40)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .accessibilityLabel(Text(verbatim: formatting.weekdayName(for: weekday)))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("work-day-\(weekday)")
            }
        }
        .padding(.vertical, Metrics.tiny)
    }
}

/// The site's extras as switches, each wired to the setting that does it.
/// The allowance and kilometres only while the allowance is tracked at all
/// (Settings › Pay › Allowance & travel); crew sign-off is not here, since
/// signing is switched on the sheet's export for every site at once.
struct SiteExtrasRows: View {
    @Binding var setup: SiteSetup
    @Binding var allowanceByDefault: Bool
    /// Settings › New sites start with has no diary switch: every new site
    /// starts with the diary.
    var showsDiary = true
    /// The site's settings keep their own allowance switch, above.
    var showsAllowance = true
    var isDisabled = false

    // Not private: that would make the memberwise initializer private too.
    @Environment(SettingsStore.self) var settingsStore

    var body: some View {
        if settingsStore.settings.allowance.isEnabled, showsAllowance {
            extra(
                "Field allowance by default",
                detail: String(localized: "Everyone ticked gets the allowance"),
                isOn: $allowanceByDefault,
                identifier: "site-extra-allowance"
            )
        }
        if settingsStore.settings.allowance.isEnabled {
            extra(
                "Kilometres each day",
                detail: String(localized: "Ask for the van's km on the day"),
                isOn: $setup.asksKilometres,
                identifier: "site-extra-kilometres"
            )
        }
        extra(
            "Evening reminder",
            detail: eveningDetail,
            isOn: $setup.eveningReminder,
            identifier: "site-extra-evening"
        )
        extra(
            "Sheet ready on the 1st",
            detail: String(localized: "A note to send last month's sheet"),
            isOn: $setup.monthlySheet,
            identifier: "site-extra-sheet"
        )
        if showsDiary {
            extra(
                "Site diary",
                detail: String(localized: "Weather, deliveries, photos per day"),
                isOn: $setup.keepsDiary,
                identifier: "site-extra-diary"
            )
        }
    }

    private var eveningDetail: String {
        let reminders = settingsStore.settings.reminders
        let time = settingsStore.dateFormatting.time(reminders.siteReminderTime, on: CalendarDate.today(in: settingsStore.workCalendar))
        return String(
            localized: "\(time) if today isn't written",
            comment: "Site extra: the evening reminder; the value is its time"
        )
    }

    private func extra(_ title: LocalizedStringKey, detail: String, isOn: Binding<Bool>, identifier: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(verbatim: detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isDisabled)
        .accessibilityIdentifier(identifier)
    }
}

/// A site's usual day and extras in words, for summaries: "07:00–15:30 ·
/// 30m break", "Mon–Fri", "Allowance, km, evening reminder".
@MainActor
struct SiteSetupText {
    let formatting: CalendarFormatting
    let durations: DurationFormatting
    let calendar: Calendar

    func usualDay(_ setup: SiteSetup) -> String {
        guard let start = setup.start, let end = setup.end else { return String(localized: "Not set") }
        let today = CalendarDate.today(in: calendar)
        let times = "\(formatting.time(start, on: today))–\(formatting.time(end, on: today))"
        guard setup.breakMinutes > 0 else { return times }
        return String(
            localized: "\(times) · \(durations.string(setup.breakMinutes)) break",
            comment: "A site's usual day; the values are its times and the length of its break"
        )
    }

    /// "Mon–Fri", "Mon–Wed, Sat"; every day is "Every day".
    func workDays(_ days: Set<Int>) -> String {
        guard !days.isEmpty else { return String(localized: "As worked lately") }
        if days.count == 7 { return String(localized: "Every day") }
        return SiteWorkDays.runs(days, firstWeekday: calendar.firstWeekday)
            .map { run in
                let first = formatting.shortWeekdaySymbol(for: run[0])
                guard run.count > 2, let last = run.last else {
                    return run.map { formatting.shortWeekdaySymbol(for: $0) }.joined(separator: ", ")
                }
                return "\(first)–\(formatting.shortWeekdaySymbol(for: last))"
            }
            .joined(separator: ", ")
    }

    /// The extras that are on, in a line, by their switches' names.
    func extras(_ setup: SiteSetup, allowanceByDefault: Bool, tracksAllowance: Bool) -> String {
        var on: [String] = []
        if tracksAllowance && allowanceByDefault { on.append(String(localized: "Field allowance")) }
        if tracksAllowance && setup.asksKilometres { on.append(String(localized: "Kilometres")) }
        if setup.eveningReminder { on.append(String(localized: "Evening reminder")) }
        if setup.monthlySheet { on.append(String(localized: "Sheet ready on the 1st")) }
        if setup.keepsDiary { on.append(String(localized: "Site diary")) }
        return on.isEmpty ? String(localized: "None") : on.joined(separator: ", ")
    }
}
