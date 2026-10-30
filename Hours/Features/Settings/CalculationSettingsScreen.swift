import SwiftUI

/// How the numbers are worked out: Settings › Balance & rounding.
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
                Text("Overtime counts")
            } footer: {
                Text("Overtime is what you work beyond your week in Working hours. Switch these off to enter worked hours, or the balance, by hand on each day.")
            }

            Section {
                Picker("Round each day to", selection: settingsStore.binding(\.rounding)) {
                    ForEach(RoundingRule.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
            } header: {
                Text("Rounding")
            } footer: {
                Text("Applied to each day's total, not to the times you write.")
            }

            Section {
                if let start = settingsStore.settings.balanceStartDate {
                    DatePicker(
                        "Counts from",
                        selection: balanceStartBinding(start),
                        displayedComponents: .date
                    )
                } else {
                    LabeledContent("Counts from", value: firstEntryDescription)
                }
                Toggle("Choose the start date", isOn: balanceStartToggle)
                DurationStepperRow(
                    title: String(localized: "Starting balance"),
                    minutes: settingsStore.binding(\.openingBalanceMinutes),
                    range: (-500 * 60)...(500 * 60),
                    step: 30,
                    signed: true,
                    formatting: settingsStore.settings.displayFormatting
                )
            } header: {
                Text("Balance")
            } footer: {
                Text("Overtime you had before using the app. The balance counts from the start date, or else from your first recorded day.")
            }

            carryOverSection

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
        }
        .navigationTitle("Overtime & balance")
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
            // A shortfall carries in full because forgiving it would invent
            // hours nobody worked; later edits to a closed year no longer
            // move what it handed over.
            Text("Closing a year fixes what it carries into the next. A cap limits overtime carried; a shortfall always carries in full.")
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
    ///
    /// Through the engine's `runningBalance`, which starts at the first
    /// recorded day. This used to start on 1 January four years back, and
    /// count every working day before the app was in use as a day short.
    private func balance(of year: Int) -> Int {
        let repository = self.repository
        return PeriodEngine(
            settings: settingsStore.settings,
            calendar: settingsStore.workCalendar,
            firstRecorded: repository.firstRecordedDate()
        ).runningBalance(
            through: CalendarDate(year: year, month: 12, day: 31),
            holidays: repository.holidayRules(),
            countingThrough: nil,
            records: { repository.records(in: $0) }
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

    /// "19 Oct 2026 (your first entry)": where the balance starts while no
    /// start date is set, so a month that began halfway through is explained
    /// rather than discovered.
    private var firstEntryDescription: String {
        guard let first = repository.firstRecordedDate() else {
            return String(localized: "Your first entry", comment: "Settings, where the balance starts before anything is recorded")
        }
        let date = settingsStore.dateFormatting.dateWithYear(first)
        return String(localized: "\(date) (your first entry)", comment: "Settings, where the balance starts; the value is a date")
    }

    private var balanceStartToggle: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.balanceStartDate != nil },
            set: { isOn in
                // Switched on, it starts where the balance already starts, so
                // turning it on changes nothing until a date is picked.
                let start = repository.firstRecordedDate() ?? CalendarDate.today(in: settingsStore.workCalendar)
                settingsStore.update {
                    $0.balanceStartDate = isOn ? start : nil
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
