import SwiftUI

/// Pay › Allowance & travel (1.2 redesign, board 16): field allowance, kilometres and travel time: one switch, off by
/// default, and while it is on the rates and whether travel counts as work.
///
/// Switched off, the day editor, the sites and the exports show none of it,
/// and nothing counts; what was recorded on the days stays for when it is
/// switched on again. Free, like pay: it is a way of reading days you wrote.
struct AllowanceSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Track field allowance and travel", isOn: changing(\.allowance.isEnabled))
                    .accessibilityIdentifier("allowance-enabled")
            } footer: {
                Text("A field allowance on the days you get one, kilometres in your own car, and travel time — on your own days and on sites.")
            }

            if settings.allowance.isEnabled {
                Section {
                    AmountRow(
                        title: String(localized: "Field allowance a day"),
                        cents: changing(\.allowance.dailyAllowanceCents),
                        currencyCode: settings.money.currencyCode,
                        identifier: "allowance-per-day"
                    )
                    AmountRow(
                        title: String(localized: "Per kilometre"),
                        cents: changing(\.allowance.centsPerKilometre),
                        currencyCode: settings.money.currencyCode,
                        identifier: "allowance-per-km"
                    )
                } header: {
                    Text("Rates")
                } footer: {
                    Text("Ticked people on a site day get the allowance. The van's kilometres are written once per site day. Amounts and tax-free limits depend on your contract and your country.")
                }

                Section {
                    Toggle("Travel time counts as work", isOn: changing(\.allowance.travelCountsAsWork))
                        .accessibilityIdentifier("allowance-travel-counts")
                } header: {
                    Text("Travel time")
                } footer: {
                    Text(settings.allowance.travelCountsAsWork
                         ? "Travel time is added to the day's hours and balance."
                         : "Travel time is recorded and shown, not added to your hours.")
                }
            }
        }
        .navigationTitle("Allowance & travel")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var settings: AppSettings { settingsStore.settings }

    /// A settings binding that also brings the widget up to date: the
    /// allowance and travel can change the month's earnings and hours.
    private func changing<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settingsStore.settings[keyPath: keyPath] },
            set: { newValue in
                settingsStore.update { $0[keyPath: keyPath] = newValue }
                HoursStack.refreshWidget()
            }
        )
    }
}

/// An amount of money typed as a decimal, stored as whole cents.
///
/// Plain text read by `MoneyInput` on every keystroke, as the welcome's rate
/// is: a formatted number field hands its value over only when it loses
/// focus, a decimal keypad has no Return, and leaving the screen with Back
/// would keep the amount from before it was typed.
private struct AmountRow: View {
    let title: String
    @Binding var cents: Int
    let currencyCode: String
    let identifier: String

    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: Metrics.small)
            TextField(title, text: $text, prompt: Text(verbatim: "0.00"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.hoursFigure(.body, weight: .medium))
                .accessibilityIdentifier(identifier)
                .onChange(of: text) { _, typed in
                    let typedCents = MoneyInput.cents(from: typed)
                    if typedCents != cents { cents = typedCents }
                }
            Text(verbatim: currencyCode)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            text = cents > 0 ? PayRules.amount(fromCents: cents).formatted(.number.precision(.fractionLength(2))) : ""
        }
    }
}
