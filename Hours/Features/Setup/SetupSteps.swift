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

/// One answer of a yes/no question, as a whole-row button.
struct SetupChoice: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.medium) {
                Text(title)
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

/// "You're set", and the two things most people do next.
struct SetupFinishStep: View {
    let onFinish: (FirstRunFinish?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SetupPage(
                heading: "You're set",
                message: "All of this can be changed in Settings whenever you like.",
                identifier: "screen-setup-finish"
            ) {
                EmptyView()
            }

            VStack(spacing: Metrics.small) {
                Button {
                    onFinish(.writeToday)
                } label: {
                    Text("Write today")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("setup-write-today")

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
            .controlSize(.large)
            .padding(.vertical, Metrics.large)
        }
    }
}
