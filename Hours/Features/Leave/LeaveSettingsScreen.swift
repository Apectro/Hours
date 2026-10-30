import SwiftUI

/// Settings › Leave (1.2 redesign, board 16): the year as it stands, then
/// the vacation allowance and the leave year it belongs to.
///
/// For the primary job only. The figures it feeds — the Insights card and the
/// line in the day editor — come from `LeaveCalculator`.
struct LeaveSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Form {
            // The year as it stands: what is left, taken and booked.
            Section {
                LeaveBalanceCard(
                    date: CalendarDate.today(in: calendar),
                    settings: settingsStore.settings,
                    calendar: calendar,
                    alwaysShows: true,
                    identifier: nil
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                DaysStepperRow(
                    title: String(localized: "Days a year"),
                    days: settingsStore.binding(\.leave.allowanceDays),
                    range: 0...60
                )
                .accessibilityIdentifier("leave-allowance")
                MonthDayPicker(
                    title: String(localized: "Leave year starts"),
                    value: settingsStore.binding(\.leave.yearStart),
                    formatting: settingsStore.dateFormatting
                )
                DaysStepperRow(
                    title: String(
                        localized: "Carried over from \(String(currentLeaveYear - 1))",
                        comment: "Settings › Leave; the value is last leave year, such as 2025"
                    ),
                    days: carriedOverBinding,
                    range: 0...60
                )
                .accessibilityIdentifier("leave-carried-over")
                Toggle("Carry-over expires", isOn: expiryToggle)
                    .accessibilityIdentifier("leave-expiry-toggle")
                if let expiry = settingsStore.settings.leave.carryOverExpires {
                    MonthDayPicker(
                        title: String(localized: "Expires on"),
                        value: Binding(
                            get: { expiry },
                            set: { value in settingsStore.update { $0.leave.carryOverExpires = value } }
                        ),
                        formatting: settingsStore.dateFormatting
                    )
                }
            } header: {
                Text("Your contract")
            } footer: {
                Text("Half days are fine. Leave days come from the calendar. Days carried over are used first, and any not taken by the expiry date are lost.")
            }
        }
        .navigationTitle("Leave")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen-leave")
    }

    private var calendar: Calendar { settingsStore.workCalendar }

    /// The leave year today falls in, which is the one a carry-over typed
    /// now is for.
    private var currentLeaveYear: Int {
        settingsStore.settings.leave.leaveYear(containing: CalendarDate.today(in: calendar), calendar: calendar)
    }

    private var carriedOverBinding: Binding<Double> {
        Binding(
            get: { settingsStore.settings.leave.carriedOver(into: currentLeaveYear) },
            set: { days in
                let year = currentLeaveYear
                settingsStore.update {
                    $0.leave.carriedOverDays = max(0, days)
                    $0.leave.carriedOverYear = days > 0 ? year : nil
                }
            }
        )
    }

    private var expiryToggle: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.leave.carryOverExpires != nil },
            set: { isOn in
                settingsStore.update {
                    $0.leave.carryOverExpires = isOn ? MonthDay(month: 3, day: 31) : nil
                }
            }
        )
    }
}

/// A count of days in half-day steps.
struct DaysStepperRow: View {
    let title: String
    @Binding var days: Double
    var range: ClosedRange<Double> = 0...60

    var body: some View {
        Stepper(value: $days, in: range, step: 0.5) {
            HStack {
                Text(title)
                Spacer(minLength: Metrics.small)
                Text(text)
                    .font(.hoursFigure(.body, weight: .medium))
            }
        }
        .accessibilityValue(text)
    }

    private var text: String { HalfDays(days: days).localized }
}

/// A day of the year: a month, and a day of that month.
struct MonthDayPicker: View {
    let title: String
    @Binding var value: MonthDay
    let formatting: CalendarFormatting

    private var calendar: Calendar { formatting.calendar }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: Metrics.small) {
                Picker(title, selection: dayBinding) {
                    ForEach(1...daysInMonth, id: \.self) { day in
                        Text(String(day)).tag(day)
                    }
                }
                Picker(title, selection: monthBinding) {
                    ForEach(1...12, id: \.self) { month in
                        Text(monthName(month)).tag(month)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    /// The most days the month ever has — 29 for February — so a leave year
    /// can start on the 29th and fall back to the 28th in a common year.
    private var daysInMonth: Int {
        YearMonth(year: 2028, month: value.month).dayCount(in: calendar)
    }

    private var dayBinding: Binding<Int> {
        Binding(get: { min(value.day, daysInMonth) }, set: { value = MonthDay(month: value.month, day: $0) })
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { value.month },
            set: { month in
                let limit = YearMonth(year: 2028, month: month).dayCount(in: calendar)
                value = MonthDay(month: month, day: min(value.day, limit))
            }
        )
    }

    private func monthName(_ month: Int) -> String {
        formatting.monthName(YearMonth(year: 2028, month: month))
    }
}

extension HalfDays {
    /// With the decimal separator of the language the app is shown in.
    var localized: String {
        formatted(decimalSeparator: Locale.current.decimalSeparator ?? ".")
    }
}
