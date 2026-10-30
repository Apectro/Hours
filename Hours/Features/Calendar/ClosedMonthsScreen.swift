import SwiftUI
import SwiftData

/// Months whose timesheet has already been handed over (1.2, mockup
/// CalendarTools, "Closed months"): each with its hours and balance and a
/// Reopen button that asks once more, and at the bottom "Close September?"
/// while the latest finished month is still open.
///
/// Reached from Settings › Overtime & balance and from the Today tab's ⋯
/// menu; closing and reopening the month on screen is also in that menu.
struct ClosedMonthsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext

    /// Watched so the figures follow an edit made anywhere.
    @Query private var entries: [DayEntry]
    @Query private var holidayRecords: [HolidayRecord]

    @State private var figures: [YearMonth: PeriodSummary] = [:]
    @State private var monthToReopen: YearMonth?

    var body: some View {
        Form {
            Section {
                if closedMonths.isEmpty {
                    Text("No month is closed yet.")
                        .foregroundStyle(.hoursSecondaryText)
                }
                ForEach(Array(closedMonths.enumerated()), id: \.element) { index, month in
                    HStack(spacing: Metrics.medium) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: formatting.monthTitle(month))
                            if let line = figuresLine(month) {
                                Text(verbatim: line)
                                    .font(.footnote)
                                    .monospacedDigit()
                                    .foregroundStyle(.hoursSecondaryText)
                            }
                        }
                        Spacer(minLength: Metrics.small)
                        Button("Reopen") { monthToReopen = month }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("closed-months-reopen-\(index)")
                    }
                    .padding(.vertical, Metrics.tiny)
                }
            } footer: {
                Text("A closed month can't be changed by accident.")
            }

            if let month = lockableMonth {
                Section {
                    VStack(alignment: .leading, spacing: Metrics.small) {
                        Text(String(
                            localized: "Close \(formatting.monthName(month))?",
                            comment: "Closed months, the card at the bottom; the value is a month's name"
                        ))
                        .font(.headline)
                        Text("Do this after you send the sheet.")
                            .font(.subheadline)
                            .foregroundStyle(.hoursSecondaryText)
                        Button {
                            settingsStore.update { $0.monthLock.lock(month) }
                        } label: {
                            Text(String(
                                localized: "Close \(formatting.monthTitle(month))",
                                comment: "Button; the value is a month and year"
                            ))
                        }
                        .buttonStyle(.bigAction(.primary))
                        .accessibilityIdentifier("closed-months-close")
                    }
                    .padding(.vertical, Metrics.small)
                }
            }
        }
        .navigationTitle("Closed months")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: changeToken, initial: true) { _, _ in reloadFigures() }
        .confirmationDialog(
            reopenTitle,
            isPresented: Binding(get: { monthToReopen != nil }, set: { if !$0 { monthToReopen = nil } }),
            titleVisibility: .visible
        ) {
            Button("Reopen") {
                if let month = monthToReopen { reopen(month) }
            }
            .accessibilityIdentifier("closed-months-reopen-confirm")
            Button("Cancel", role: .cancel) { monthToReopen = nil }
        } message: {
            Text("Its days can be changed again. Close it again from the calendar's ⋯ menu when you are done.")
        }
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

    private var reopenTitle: String {
        guard let month = monthToReopen else { return "" }
        return String(
            localized: "Reopen \(formatting.monthTitle(month))?",
            comment: "Confirmation title; the value is a month and year"
        )
    }

    /// "176h · balance +3h 40m".
    private func figuresLine(_ month: YearMonth) -> String? {
        guard let summary = figures[month] else { return nil }
        let duration = settingsStore.settings.displayFormatting
        let worked = duration.string(summary.workedMinutes)
        guard settingsStore.settings.features.showsBalance else { return worked }
        return String(
            localized: "\(worked) · balance \(duration.signedString(summary.balanceMinutes))",
            comment: "Closed months: a month's hours and its balance, e.g. 176h · balance +3h 40m"
        )
    }

    private var changeToken: [Int] {
        closedMonths.map { $0.year * 100 + $0.month } + [entries.count]
    }

    private func reloadFigures() {
        let settings = settingsStore.settings
        let calendar = settingsStore.workCalendar
        let repository = WorkdayRepository(context: modelContext)
        let engine = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: repository.firstRecordedDate())
        let holidays = holidayRecords.map(\.rule)
        let today = CalendarDate.today(in: calendar)
        var result: [YearMonth: PeriodSummary] = [:]
        for month in closedMonths {
            let range = month.range(in: calendar)
            let days = engine.days(in: range, records: repository.records(in: range), holidays: holidays)
            result[month] = PeriodAggregator.summarize(days, range: range, countingThrough: today)
        }
        figures = result
    }

    private func reopen(_ month: YearMonth) {
        settingsStore.update { $0.monthLock.unlock(month) }
        monthToReopen = nil
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
