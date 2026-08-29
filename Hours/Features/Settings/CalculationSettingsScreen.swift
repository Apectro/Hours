import SwiftUI

/// How the numbers are worked out.
struct CalculationSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Form {
            Section {
                Toggle("Calculate worked hours", isOn: settingsStore.binding(\.features.autoCalculateWorkedHours))
                if settingsStore.settings.features.showsBalance {
                    Toggle("Calculate overtime", isOn: settingsStore.binding(\.features.autoCalculateOvertime))
                }
            } header: {
                Text("Automatic")
            } footer: {
                Text("Switch these off to enter worked hours, or the balance, by hand on each day.")
            }

            Section {
                Picker("Rounding", selection: settingsStore.binding(\.rounding)) {
                    ForEach(RoundingRule.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
            } header: {
                Text("Rounding")
            } footer: {
                Text("Applied to the worked total of each day, not to the times you enter.")
            }

            Section {
                Picker("Clock changes", selection: settingsStore.binding(\.durationPolicy)) {
                    ForEach(DurationPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
            } header: {
                Text("Daylight saving")
            } footer: {
                Text(settingsStore.settings.durationPolicy.explanation)
            }

            Section {
                DurationStepperRow(
                    title: String(localized: "Opening balance"),
                    minutes: settingsStore.binding(\.openingBalanceMinutes),
                    range: (-500 * 60)...(500 * 60),
                    step: 30,
                    signed: true,
                    formatting: settingsStore.settings.displayFormatting
                )
                Toggle("Count from a start date", isOn: balanceStartToggle)
                if let start = settingsStore.settings.balanceStartDate {
                    DatePicker(
                        "Start date",
                        selection: balanceStartBinding(start),
                        displayedComponents: .date
                    )
                }
            } header: {
                Text("Balance")
            } footer: {
                Text("The opening balance is the overtime you were already carrying before you started using the app. Days before the start date are left out of the running balance.")
            }

            carryOverSection
        }
        .navigationTitle("Calculation")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Carrying a year into the next

    /// A Zeitkonto has a year boundary: the balance closes in December and
    /// carries into January, and many contracts cap what may carry. Closing a
    /// year writes down what it handed over, rather than leaving the figure to
    /// be recomputed — editing a Tuesday in March two years later must not
    /// quietly change what was carried.
    @ViewBuilder
    private var carryOverSection: some View {
        Section {
            Toggle("Close the year", isOn: settingsStore.binding(\.carryOver.isEnabled))

            if settingsStore.settings.carryOver.isEnabled {
                Toggle("Cap what carries over", isOn: capToggle)

                if let cap = settingsStore.settings.carryOver.capMinutes {
                    DurationStepperRow(
                        title: String(localized: "Most that may carry"),
                        minutes: capBinding(cap),
                        range: 0...(500 * 60),
                        step: 30,
                        signed: false,
                        formatting: settingsStore.settings.displayFormatting
                    )
                    Picker("Above the cap", selection: settingsStore.binding(\.carryOver.surplusAbove)) {
                        ForEach([YearEndSurplus.paidOut, .forfeited]) { surplus in
                            Text(surplus.title).tag(surplus)
                        }
                    }
                }

                if let year = closableYear {
                    Button {
                        closeYear(year)
                    } label: {
                        LabeledContent(
                            String(
                                localized: "Close \(String(year))",
                                comment: "Button; the value is a year, e.g. Close 2026"
                            ),
                            value: settingsStore.settings.displayFormatting.signedString(balance(of: year))
                        )
                    }
                }

                ForEach(settingsStore.settings.yearCloses.sorted { $0.year > $1.year }) { close in
                    closeRow(close)
                }
                .onDelete(perform: reopen)
            }
        } header: {
            Text("Year end")
        } footer: {
            Text("Closing a year fixes what it carried into the next one, so later edits to that year no longer move the figure. A cap applies to overtime you are owed; a shortfall always carries in full, because forgiving it would invent hours nobody worked.")
        }
    }

    private var repository: WorkdayRepository { WorkdayRepository(context: modelContext) }

    /// The most recent year that is over and not yet closed.
    ///
    /// Only a finished year: closing the year you are still in would fix a
    /// figure that has months left to move, and the button would be an
    /// invitation to do it by accident every January.
    private var closableYear: Int? {
        let thisYear = CalendarDate.today(in: settingsStore.workCalendar).year
        let closed = Set(settingsStore.settings.yearCloses.map(\.year))
        return (1...4)
            .map { thisYear - $0 }
            .first { !closed.contains($0) }
    }

    /// The balance as it stood at the end of `year`, computed the same way the
    /// running total on the statistics screen is — through the same origin, so
    /// a year closed after another picks up the earlier carry-over rather than
    /// counting from the beginning again.
    private func balance(of year: Int) -> Int {
        let calendar = settingsStore.workCalendar
        let settings = settingsStore.settings
        let december = CalendarDate(year: year, month: 12, day: 31)
        let origin = settings.balanceOrigin(for: CalendarDate(year: year, month: 1, day: 1))
        let range = CalendarDateRange(
            start: origin.startDate ?? CalendarDate(year: year - 4, month: 1, day: 1),
            end: december
        )
        let days = PeriodEngine(settings: settings, calendar: calendar).days(
            in: range,
            records: repository.records(in: range),
            holidays: repository.holidayRules()
        )
        return BalanceLedger.cumulative(
            over: days,
            openingMinutes: origin.openingMinutes,
            startDate: origin.startDate
        )
    }

    private func closeYear(_ year: Int) {
        let close = CarryOver.close(
            year: year,
            balance: balance(of: year),
            policy: settingsStore.settings.carryOver
        )
        settingsStore.update {
            $0.yearCloses.removeAll { $0.year == year }
            $0.yearCloses.append(close)
        }
    }

    private func closeRow(_ close: YearClose) -> some View {
        let formatting = settingsStore.settings.displayFormatting
        return VStack(alignment: .leading, spacing: 2) {
            LabeledContent(
                String(close.year),
                value: formatting.signedString(close.carriedMinutes)
            )
            if close.surplusMinutes != 0 {
                // Two labelled halves rather than one glued string. "%@ %@" is
                // not a key a translator can do anything with, and it would
                // collide with every other pair of values in the catalogue.
                LabeledContent(
                    close.surplus.title,
                    value: formatting.signedString(close.surplusMinutes)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Reopening a year is deleting its close: the balance goes back to
    /// running through it. Deliberately not a separate concept — there is one
    /// record, and removing it is the whole of undoing.
    private func reopen(at offsets: IndexSet) {
        let sorted = settingsStore.settings.yearCloses.sorted { $0.year > $1.year }
        let years = Set(offsets.map { sorted[$0].year })
        settingsStore.update { $0.yearCloses.removeAll { years.contains($0.year) } }
    }

    private var capToggle: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.carryOver.capMinutes != nil },
            // Ten hours rather than zero as the first offer: a cap of zero is a
            // real setting but a surprising default, and somebody switching
            // this on to look at it should not find their balance zeroed.
            set: { isOn in
                settingsStore.update { $0.carryOver.capMinutes = isOn ? 600 : nil }
            }
        )
    }

    private func capBinding(_ current: Int) -> Binding<Int> {
        Binding(
            get: { current },
            set: { minutes in settingsStore.update { $0.carryOver.capMinutes = max(0, minutes) } }
        )
    }

    private var balanceStartToggle: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.balanceStartDate != nil },
            set: { isOn in
                settingsStore.update {
                    $0.balanceStartDate = isOn ? CalendarDate.today(in: settingsStore.workCalendar) : nil
                }
            }
        )
    }

    private func balanceStartBinding(_ current: CalendarDate) -> Binding<Date> {
        let calendar = settingsStore.workCalendar
        return Binding(
            get: { current.date(in: calendar) },
            set: { date in
                settingsStore.update { $0.balanceStartDate = CalendarDate(date, calendar: calendar) }
            }
        )
    }
}
