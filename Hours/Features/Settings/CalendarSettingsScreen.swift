import SwiftUI

/// How the calendar looks (1.2 redesign, board 18).
struct CalendarSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Form {
            Section {
                Picker("Week starts on", selection: firstWeekdayBinding) {
                    Text("Automatic").tag(0)
                    ForEach(1...7, id: \.self) { weekday in
                        Text(formatting.weekdayName(for: weekday)).tag(weekday)
                    }
                }
                Toggle("Show weekends", isOn: settingsStore.binding(\.calendar.showWeekends))
                if settingsStore.settings.features.trackHolidays {
                    Toggle("Mark holidays", isOn: settingsStore.binding(\.calendar.showHolidayMarkers))
                }
                Toggle("Show totals", isOn: settingsStore.binding(\.calendar.showMonthSummary))
            } footer: {
                Text("Automatic follows your region. Hiding weekends removes the Saturday and Sunday columns from the grid. The days themselves are still recorded and still counted.")
            }

            Section {
                Picker("Inside each day", selection: settingsStore.binding(\.calendar.dayCellDetail)) {
                    ForEach(DayCellDetail.allCases) { detail in
                        Text(detail.title).tag(detail)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Inside each day")
            } footer: {
                Text("One figure at most. A calendar that shows everything shows nothing.")
            }

            Section {
                Picker("Open on", selection: settingsStore.binding(\.calendar.preferredScope)) {
                    ForEach(CalendarScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                Text("Open on")
            }

            // Closed months have their own screen; the month on screen also
            // closes and reopens from the calendar's ⋯ menu.
            Section {
                ClosedMonthsRow()
            } footer: {
                Text("Close a month once its hours are handed over, so it can't change by mistake.")
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var formatting: CalendarFormatting { settingsStore.dateFormatting }

    /// `0` stands for "follow the region", which keeps the picker a single
    /// control rather than a toggle plus a picker.
    private var firstWeekdayBinding: Binding<Int> {
        Binding(
            get: { settingsStore.settings.calendar.firstWeekdayOverride ?? 0 },
            set: { value in
                settingsStore.update {
                    $0.calendar.firstWeekdayOverride = (1...7).contains(value) ? value : nil
                }
            }
        )
    }
}
