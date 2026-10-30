import SwiftUI

/// 1 · "Your hours, counted right." — and your name, for the sheets.
struct SetupNameStep: View {
    @Binding var name: String
    /// Return on the keyboard continues, as the button does.
    let onReturn: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        SetupPage(
            heading: "Your hours, counted right.",
            message: "Write a day in seconds. The app works out overtime, balance and the monthly sheet.",
            identifier: "screen-setup-name"
        ) {
            VStack(alignment: .leading, spacing: Metrics.small) {
                SetupCaption("Your name")
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
                Text("Printed on your sheets. You can change it later in Settings › Sheets.")
                    .font(.footnote)
                    .foregroundStyle(.hoursSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { isFocused = true }
    }
}

/// A small capital heading over a group, as the mockups draw it.
struct SetupCaption: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.hoursSecondaryText)
            .textCase(.uppercase)
            .tracking(0.5)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 2 · "A normal day for you" — start, end, break, whether breaks are
/// paid, and the work days.
struct SetupWeekStep: View {
    @Binding var answers: FirstRunAnswers

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        SetupPage(
            heading: "A normal day for you",
            message: "Every new day starts with these. Change any day as you go.",
            identifier: "screen-setup-week"
        ) {
            VStack(alignment: .leading, spacing: Metrics.large) {
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
                        Divider()
                        Toggle("Breaks are paid", isOn: $answers.breaksArePaid)
                            .accessibilityIdentifier("setup-breaks-paid")
                    }
                }

                VStack(alignment: .leading, spacing: Metrics.small) {
                    SetupCaption("Work days")
                    SetupWeekdayToggles(
                        selection: $answers.workingWeekdays,
                        formatting: settingsStore.dateFormatting,
                        firstWeekday: settingsStore.workCalendar.firstWeekday
                    )
                }

                Text(String(
                    localized: "That's \(settingsStore.durationFormatting.string(answers.dailyMinutes * answers.workingWeekdays.count)) a week. Overtime counts from here.",
                    comment: "First-run setup, under the usual day and work days; the value is the hours of a week"
                ))
                .font(.footnote)
                .foregroundStyle(.hoursSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
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

/// "Where do you work?": a country, and a state or canton where the
/// holidays depend on it. Nothing is preselected — the app never guesses a
/// country — and continuing with none adds nothing.
struct SetupHolidaysStep: View {
    @Binding var country: HolidayCountry?
    @Binding var region: String?
    /// "No public holidays": none, and on to the next step.
    var onNone: () -> Void = {}

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        SetupPage(
            heading: "Where do you work?",
            message: "Public holidays go in the calendar, paid, so your balance stays right.",
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
                        Picker("Region", selection: $region) {
                            Text("Choose").tag(String?.none)
                            ForEach(country.regions) { region in
                                Text(PublicHolidayActions.regionName(region)).tag(Optional(region.code))
                            }
                        }
                        .accessibilityIdentifier("setup-holidays-region")
                    }
                }

                if !upcoming.isEmpty {
                    SetupCaption("Next holidays")
                        .padding(.top, Metrics.medium)
                    SurfaceCard {
                        VStack(spacing: Metrics.medium) {
                            ForEach(upcoming, id: \.name) { holiday in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(verbatim: holiday.name)
                                    Spacer(minLength: Metrics.small)
                                    Text(settingsStore.dateFormatting.mediumDate(holiday.date))
                                        .foregroundStyle(.hoursSecondaryText)
                                        .monospacedDigit()
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }

                if country != nil {
                    Text("You can see, change or remove them later in Settings › Day types & holidays.")
                        .font(.footnote)
                        .foregroundStyle(.hoursSecondaryText)
                } else {
                    Button(action: onNone) {
                        Text("No public holidays")
                    }
                    .buttonStyle(.bigAction(.secondary))
                    .padding(.top, Metrics.medium)
                    .accessibilityIdentifier("setup-holidays-none")
                }
            }
            .onChange(of: country) { _, _ in region = nil }
        }
    }

    /// The next three of the chosen set, as the calendar will show them.
    private var upcoming: [(name: String, date: CalendarDate)] {
        guard let country, let set = PublicHolidayCatalog.set(country: country, region: region) else { return [] }
        let calendar = settingsStore.workCalendar
        let today = CalendarDate.today(in: calendar)
        let dated = set.holidays.compactMap { holiday -> (name: String, date: CalendarDate)? in
            for year in today.year...(today.year + 1) {
                if let date = holiday.recurrence.occurrence(inYear: year, calendar: calendar), date >= today {
                    return (holiday.name(in: .device, setLanguage: set.language), date)
                }
            }
            return nil
        }
        return Array(dated.sorted { $0.date < $1.date }.prefix(3))
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
                Text("You can change it later in Settings › Sheets.")
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
            heading: "See what your hours earn",
            message: "Optional. Only you see it, and it never goes on a sheet unless you ask.",
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

/// "All set, Marijo." — and three big rows to pick where to start: write
/// today, set up a site, or the tour.
struct SetupFinishStep: View {
    let name: String
    let onFinish: (FirstRunFinish?) -> Void

    var body: some View {
        SetupPage(
            heading: heading,
            message: "Pick where to start. Everything else is one tap away.",
            identifier: "screen-setup-finish"
        ) {
            VStack(spacing: Metrics.medium) {
                row(
                    title: "Write today", detail: "Your own hours",
                    systemImage: "sun.max.fill", identifier: "setup-write-today"
                ) { onFinish(.writeToday) }
                row(
                    title: "Set up a site", detail: "Your crew's hours and the monthly sheet",
                    systemImage: "building.2.fill", identifier: "setup-create-site"
                ) { onFinish(.createSite) }
                row(
                    title: "Show me around", detail: "Six stops, about a minute",
                    systemImage: "questionmark.circle.fill", identifier: "setup-show-tour"
                ) { onFinish(.tour) }
            }
        }
    }

    private var heading: LocalizedStringKey {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(separator: " ").first else { return "All set." }
        return "All set, \(String(first))."
    }

    private func row(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Metrics.medium) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Metrics.small)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(Metrics.large)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
