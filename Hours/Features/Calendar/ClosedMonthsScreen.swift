import SwiftUI

/// Months whose timesheet has already been handed over.
///
/// Closing and reopening the month on screen is in the calendar's ⋯ menu,
/// where months are; this is the whole list, reached from Settings. The list
/// is the control: closing is adding a month, reopening is swiping it away.
/// A toggle per month would need somewhere to show every month that ever
/// existed.
struct ClosedMonthsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Form {
            Section {
                if let month = lockableMonth {
                    Button {
                        settingsStore.update { $0.monthLock.lock(month) }
                    } label: {
                        Label(
                            String(
                                localized: "Close \(formatting.monthTitle(month))",
                                comment: "Button; the value is a month and year"
                            ),
                            systemImage: "lock"
                        )
                    }
                    .accessibilityIdentifier("closed-months-close")
                }

                ForEach(closedMonths, id: \.self) { month in
                    Label(formatting.monthTitle(month), systemImage: "lock.fill")
                        .swipeActions {
                            Button("Reopen") { reopen(month) }
                                .tint(.accentColor)
                        }
                }
            } footer: {
                Text("A closed month can't be changed by mistake. Swipe one to reopen it. The calendar's ⋯ menu closes or reopens the month on screen.")
            }
        }
        .navigationTitle("Closed months")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var formatting: CalendarFormatting { settingsStore.dateFormatting }

    private var closedMonths: [YearMonth] {
        settingsStore.settings.monthLock.months.sorted(by: >)
    }

    /// The most recent month that is over and not already closed. Only a
    /// finished month: closing the one you are in would refuse today's hours.
    private var lockableMonth: YearMonth? {
        let thisMonth = YearMonth(CalendarDate.today(in: settingsStore.workCalendar))
        let closed = settingsStore.settings.monthLock.months
        return (1...12)
            .map { thisMonth.adding(months: -$0) }
            .first { !closed.contains($0) }
    }

    private func reopen(_ month: YearMonth) {
        settingsStore.update { $0.monthLock.unlock(month) }
    }
}

/// The row that leads to the list, with the latest closed month as its
/// value: "Through September 2026" when the months run up to it unbroken
/// is more than the store can promise, so it names the latest one only.
struct ClosedMonthsRow: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        NavigationLink {
            ClosedMonthsScreen()
        } label: {
            LabeledContent {
                Text(value)
            } label: {
                Label("Closed months", systemImage: "lock")
            }
        }
        .accessibilityIdentifier("settings-closed-months")
    }

    private var value: String {
        guard let latest = settingsStore.settings.monthLock.months.max() else {
            return String(localized: "None")
        }
        return settingsStore.dateFormatting.monthTitle(latest)
    }
}
