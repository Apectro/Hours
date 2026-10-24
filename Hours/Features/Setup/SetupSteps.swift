import SwiftUI

/// 1 · "What's your name?" — for the sheets you hand in.
struct SetupNameStep: View {
    @Binding var name: String
    /// Return on the keyboard continues, as the button does.
    let onReturn: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        SetupPage(
            heading: "What's your name?",
            message: "It goes on the sheets you hand in. Nothing else uses it.",
            identifier: "screen-setup-name"
        ) {
            TextField("Your name", text: $name)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .submitLabel(.continue)
                .focused($isFocused)
                .onSubmit(onReturn)
                .font(.title3)
                .padding(Metrics.large)
                .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                .accessibilityIdentifier("setup-name")
        }
        .onAppear { isFocused = true }
    }
}

/// 2 · "Your working week" — which days, and what a day looks like.
struct SetupWeekStep: View {
    @Binding var answers: FirstRunAnswers

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        SetupPage(
            heading: "Your working week",
            message: "The days you normally work and your usual hours. A day you leave empty is then a day short.",
            identifier: "screen-setup-week"
        ) {
            VStack(alignment: .leading, spacing: Metrics.large) {
                SetupWeekdayToggles(
                    selection: $answers.workingWeekdays,
                    formatting: settingsStore.dateFormatting,
                    firstWeekday: settingsStore.workCalendar.firstWeekday
                )

                SurfaceCard {
                    VStack(spacing: Metrics.medium) {
                        DatePicker("Start", selection: timeBinding(\.start), displayedComponents: .hourAndMinute)
                        Divider()
                        DatePicker("End", selection: timeBinding(\.end), displayedComponents: .hourAndMinute)
                        Divider()
                        DurationStepperRow(
                            title: String(localized: "Break"),
                            minutes: $answers.breakMinutes,
                            range: 0...(4 * 60),
                            step: 5,
                            formatting: settingsStore.durationFormatting
                        )
                    }
                }

                Text(String(
                    localized: "That comes to \(settingsStore.durationFormatting.string(answers.dailyMinutes)) a day.",
                    comment: "First-run setup, under the usual start, end and break"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<FirstRunAnswers, TimeOfDay>) -> Binding<Date> {
        let calendar = settingsStore.workCalendar
        return Binding(
            get: { OptionalTimeRow.date(from: answers[keyPath: keyPath], in: calendar) },
            set: { answers[keyPath: keyPath] = OptionalTimeRow.time(from: $0, in: calendar) }
        )
    }
}

/// The seven days as buttons that stay pressed, in the calendar's own order.
struct SetupWeekdayToggles: View {
    @Binding var selection: Set<Int>
    let formatting: CalendarFormatting
    let firstWeekday: Int

    var body: some View {
        HStack(spacing: Metrics.tiny) {
            ForEach(order, id: \.self) { weekday in
                let isOn = selection.contains(weekday)
                Button {
                    toggle(weekday)
                } label: {
                    Text(formatting.veryShortWeekdaySymbol(for: weekday))
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                        .background(
                            isOn ? Color.accentColor : Color.hoursSurface,
                            in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(formatting.weekdayName(for: weekday))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("setup-weekday-\(weekday)")
            }
        }
    }

    /// 1 = Sunday ... 7 = Saturday, starting from the calendar's first day.
    private var order: [Int] {
        (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }
    }

    private func toggle(_ weekday: Int) {
        if selection.contains(weekday) {
            selection.remove(weekday)
        } else {
            selection.insert(weekday)
        }
    }
}

/// 3 · "Are your breaks paid?"
struct SetupBreaksStep: View {
    @Binding var breaksArePaid: Bool

    var body: some View {
        SetupPage(
            heading: "Are your breaks paid?",
            message: "A paid break is still written down, but it counts as worked time instead of being taken off the day.",
            identifier: "screen-setup-breaks"
        ) {
            VStack(spacing: Metrics.small) {
                SetupChoice(title: "Yes, they're paid", isSelected: breaksArePaid) {
                    breaksArePaid = true
                }
                .accessibilityIdentifier("setup-breaks-paid")
                SetupChoice(title: "No, they're taken off", isSelected: !breaksArePaid) {
                    breaksArePaid = false
                }
                .accessibilityIdentifier("setup-breaks-unpaid")
            }
        }
    }
}

/// "Where do you work?": a country, and a state or canton where the
/// holidays depend on it. Nothing is preselected — the app never guesses a
/// country — and continuing with none adds nothing.
struct SetupHolidaysStep: View {
    @Binding var country: HolidayCountry?
    @Binding var region: String?

    var body: some View {
        SetupPage(
            heading: "Where do you work?",
            message: "For your country's public holidays, so they show in the calendar as paid days off. Skip it to add holidays yourself later.",
            identifier: "screen-setup-holidays"
        ) {
            VStack(alignment: .leading, spacing: Metrics.small) {
                pickerRow {
                    Picker("Country", selection: $country) {
                        Text("None").tag(HolidayCountry?.none)
                        ForEach(PublicHolidayActions.sortedCountries) { country in
                            Text(PublicHolidayActions.countryName(country)).tag(Optional(country))
                        }
                    }
                    .accessibilityIdentifier("setup-holidays-country")
                }
                if let country, !country.regions.isEmpty {
                    pickerRow {
                        Picker("State or canton", selection: $region) {
                            Text("Choose").tag(String?.none)
                            ForEach(country.regions) { region in
                                Text(PublicHolidayActions.regionName(region)).tag(Optional(region.code))
                            }
                        }
                        .accessibilityIdentifier("setup-holidays-region")
                    }
                }
                if country != nil {
                    Text("You can see, change or remove them later in Settings › Holidays.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: country) { _, _ in region = nil }
        }
    }

    private func pickerRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .pickerStyle(.menu)
            .padding(.horizontal, Metrics.large)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

/// 5 · "Reports for your boss" — the language the exported files are
/// written in, preselected from the country (`HolidayCountry.reportLanguage`).
/// The ten languages are named in their own words, as a language picker
/// should name them.
struct SetupLanguageStep: View {
    @Binding var language: ExportLanguage
    /// Called when a language is tapped, so a later change of country does
    /// not overrule it.
    let onChoose: () -> Void

    private static let choices = ExportLanguage.allCases.filter { $0 != .device }

    var body: some View {
        SetupPage(
            heading: "Reports for your boss",
            message: "The language your PDF, Excel and CSV files are written in. The app itself stays in your phone's language.",
            identifier: "screen-setup-language"
        ) {
            VStack(alignment: .leading, spacing: Metrics.small) {
                ForEach(Self.choices) { choice in
                    // "Same as the phone" is shown as the language it
                    // stands for, so one row is always ticked.
                    SetupChoice(verbatim: choice.title, isSelected: language.resolved == choice) {
                        language = choice
                        onChoose()
                    }
                    .accessibilityIdentifier("setup-language-\(choice.rawValue)")
                }
                Text("You can change it later in Settings › Export options.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 6 · "Do you lead a crew?" — only decides what the last screen and the
/// tour offer. The Sites tab is there either way.
struct SetupCrewStep: View {
    @Binding var leadsCrew: Bool

    var body: some View {
        SetupPage(
            heading: "Do you lead a crew?",
            message: "Sites keep your crew's hours, extra work and a site diary.",
            identifier: "screen-setup-crew"
        ) {
            VStack(alignment: .leading, spacing: Metrics.small) {
                SetupChoice(title: "Yes, I lead a crew", isSelected: leadsCrew) {
                    leadsCrew = true
                }
                .accessibilityIdentifier("setup-crew-yes")
                SetupChoice(title: "No, just my own hours", isSelected: !leadsCrew) {
                    leadsCrew = false
                }
                .accessibilityIdentifier("setup-crew-no")
                Text("The Sites tab stays either way.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 7 · The hourly rate and its currency, both optional. Saved as the main
/// job's first rate, the way Settings › Pay saves one; nothing typed sets
/// nothing up.
///
/// The rate is plain text read by `MoneyInput` on every keystroke: a
/// formatted number field only hands over its value when it loses focus,
/// and the decimal keypad has no Return to make it.
struct SetupPayStep: View {
    @Binding var hourlyRateCents: Int
    /// Nil follows the phone's region.
    @Binding var currencyCode: String?
    /// Called when a currency is picked, so a later change of country does
    /// not overrule it.
    let onChooseCurrency: () -> Void

    @State private var rateText = ""
    @State private var hasLoaded = false

    var body: some View {
        SetupPage(
            heading: "What do you earn an hour?",
            message: "Optional, to see what a month earned. Your timesheet shows it only if you add it in Settings › Export options; a site sheet never does.",
            identifier: "screen-setup-pay"
        ) {
            VStack(alignment: .leading, spacing: Metrics.small) {
                HStack(spacing: Metrics.medium) {
                    TextField("Hourly rate", text: $rateText)
                        .keyboardType(.decimalPad)
                        .font(.title3)
                        .accessibilityIdentifier("setup-pay-rate")
                    Text(verbatim: shownCurrency)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(Metrics.large)
                .frame(minHeight: 44)
                .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))

                // A menu with its own label rather than a menu-style picker,
                // whose one-line label was cut off at the large text sizes.
                Menu {
                    Picker("Currency", selection: currencyBinding) {
                        ForEach(AppSettings.currencyChoices(including: shownCurrency), id: \.self) { code in
                            Text(verbatim: AppSettings.currencyName(code)).tag(code)
                        }
                    }
                } label: {
                    HStack(spacing: Metrics.small) {
                        Text(verbatim: AppSettings.currencyName(shownCurrency))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, Metrics.medium)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Currency"))
                .accessibilityValue(AppSettings.currencyName(shownCurrency))
                .padding(.horizontal, Metrics.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                .accessibilityIdentifier("setup-pay-currency")

                Text("Overtime, surcharges and paid days off can be added later in Settings › Pay.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            // Once: coming back to this step must not rewrite what is typed.
            guard !hasLoaded else { return }
            hasLoaded = true
            if hourlyRateCents > 0 {
                rateText = PayRules.amount(fromCents: hourlyRateCents)
                    .formatted(.number.precision(.fractionLength(2)))
            }
        }
        .onChange(of: rateText) { _, text in
            hourlyRateCents = MoneyInput.cents(from: text)
        }
    }

    private var shownCurrency: String {
        currencyCode ?? AppSettings.deviceCurrencyCode
    }

    /// The phone's own currency is stored as none, as Settings › Pay does.
    private var currencyBinding: Binding<String> {
        Binding(
            get: { shownCurrency },
            set: { code in
                currencyCode = code == AppSettings.deviceCurrencyCode ? nil : code
                onChooseCurrency()
            }
        )
    }
}

/// One answer of a question, as a whole-row button.
struct SetupChoice: View {
    let title: Text
    let isSelected: Bool
    let action: () -> Void

    init(title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) {
        self.title = Text(title)
        self.isSelected = isSelected
        self.action = action
    }

    /// For a title that is already what should be shown, such as a
    /// language named in its own words.
    init(verbatim title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.medium) {
                title
                    .foregroundStyle(.primary)
                Spacer(minLength: Metrics.small)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .padding(Metrics.large)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "You're set", the tour, and the things most people do next. Create a
/// site is offered to someone who leads a crew.
struct SetupFinishStep: View {
    let leadsCrew: Bool
    let onFinish: (FirstRunFinish?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SetupPage(
                heading: "You're set",
                message: "All of this can be changed in Settings whenever you like. A short tour shows where everything is.",
                identifier: "screen-setup-finish"
            ) {
                EmptyView()
            }

            VStack(spacing: Metrics.small) {
                Button {
                    onFinish(.tour)
                } label: {
                    Text("Show me around")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("setup-show-tour")

                Button {
                    onFinish(.writeToday)
                } label: {
                    Text("Write today")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("setup-write-today")

                if leadsCrew {
                    Button {
                        onFinish(.createSite)
                    } label: {
                        Text("Create a site")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("setup-create-site")
                }
            }
            .controlSize(.large)
            .padding(.vertical, Metrics.large)
        }
    }
}
