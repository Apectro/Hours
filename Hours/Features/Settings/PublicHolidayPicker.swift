import SwiftUI
import SwiftData

/// Adding and removing a country's public holidays, for every screen that
/// offers it: Settings › Holidays, the first-run setup and the calendar's
/// one-time card. The rules are worked out by `PublicHolidayImport`; this
/// only writes them.
@MainActor
enum PublicHolidayActions {
    /// Adds the ticked holidays as ordinary rules, skipping any a rule
    /// already covers, and remembers the set.
    @discardableResult
    static func add(
        _ set: PublicHolidaySet,
        selection: Set<String>,
        context: ModelContext,
        settingsStore: SettingsStore
    ) -> PublicHolidayImport.Plan {
        let repository = WorkdayRepository(context: context)
        let calendar = settingsStore.workCalendar
        let plan = PublicHolidayImport.plan(
            set: set,
            selection: selection,
            existing: repository.holidayRules(),
            language: .device,
            calendar: calendar,
            fromYear: CalendarDate.today(in: calendar).year
        )
        for rule in plan.rules { repository.upsert(rule) }
        settingsStore.update { settings in
            settings.publicHolidays.recordAdded(set: set, rules: plan.rules)
            // Where the country is chosen, its sick-pay rule comes with it
            // (Croatia: 70%, the employer's first 42 days) — unless Sick
            // was already edited, which is the person's own answer.
            SickPay.applyCountryDefault(set.country, to: &settings)
        }
        HoursStack.refreshWidget()
        return plan
    }

    /// Deletes the rules the set added that are still there, and forgets
    /// the set. The person's own rules are never touched.
    static func removeAdded(context: ModelContext, settingsStore: SettingsStore) {
        let repository = WorkdayRepository(context: context)
        for id in settingsStore.settings.publicHolidays.rulesToRemove(from: repository.holidayRules()) {
            repository.deleteHoliday(id: id)
        }
        settingsStore.update { $0.publicHolidays.forgetAdded() }
        HoursStack.refreshWidget()
    }

    /// "Austria", "Germany · Bayern", "Switzerland · Zürich", in the
    /// phone's language where the system names the country.
    static func title(of set: PublicHolidaySet) -> String {
        let country = countryName(set.country)
        guard let region = set.region else { return country }
        return "\(country) · \(regionName(region))"
    }

    static func countryName(_ country: HolidayCountry) -> String {
        Locale.current.localizedString(forRegionCode: country.regionCode) ?? country.regionCode
    }

    static func regionName(_ region: HolidayRegion) -> String {
        region.code == HolidayCountry.otherSwissCanton
            ? String(localized: "Another canton", comment: "Public holidays: a Swiss canton not in the list")
            : region.name
    }

    /// Countries sorted by their name on this phone.
    static var sortedCountries: [HolidayCountry] {
        HolidayCountry.allCases.sorted {
            countryName($0).localizedStandardCompare(countryName($1)) == .orderedAscending
        }
    }
}

/// The steps of picking a country's holidays, as values.
enum PublicHolidayRoute: Hashable {
    case regions(HolidayCountry)
    case preview(setID: String)
}

/// Country, then state or canton where it matters, then the list to add.
/// Presented as a sheet; its own steps are value routes.
struct PublicHolidayPicker: View {
    /// Called once the holidays are added, or with nothing on Cancel.
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [PublicHolidayRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(PublicHolidayActions.sortedCountries) { country in
                        NavigationLink(value: route(for: country)) {
                            Text(PublicHolidayActions.countryName(country))
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .accessibilityIdentifier("public-holidays-country-\(country.rawValue)")
                    }
                } footer: {
                    Text("Nothing is added until you have seen the list. The holidays come from tables inside the app; nothing is looked up online.")
                }
            }
            .navigationTitle("Public holidays")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PublicHolidayRoute.self) { route in
                switch route {
                case let .regions(country):
                    PublicHolidayRegionList(country: country)
                case let .preview(setID):
                    if let set = PublicHolidayCatalog.set(id: setID) {
                        PublicHolidayPreview(set: set) {
                            dismiss()
                            onFinish()
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("public-holidays-cancel")
                }
            }
        }
    }

    private func route(for country: HolidayCountry) -> PublicHolidayRoute {
        if country.regions.isEmpty, let set = PublicHolidayCatalog.set(country: country, region: nil) {
            return .preview(setID: set.id)
        }
        return .regions(country)
    }
}

private struct PublicHolidayRegionList: View {
    let country: HolidayCountry

    var body: some View {
        List {
            ForEach(country.regions) { region in
                if let set = PublicHolidayCatalog.set(country: country, region: region.code) {
                    NavigationLink(value: PublicHolidayRoute.preview(setID: set.id)) {
                        Text(PublicHolidayActions.regionName(region))
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("public-holidays-region-\(region.code)")
                }
            }
        }
        .navigationTitle(PublicHolidayActions.countryName(country))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The holidays a set would add, each with its next date, ticked unless it
/// applies only in part of the region or by custom.
struct PublicHolidayPreview: View {
    let set: PublicHolidaySet
    let onAdded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    @State private var selection: Set<String>

    init(set: PublicHolidaySet, onAdded: @escaping () -> Void) {
        self.set = set
        self.onAdded = onAdded
        _selection = State(initialValue: set.defaultSelection)
    }

    var body: some View {
        List {
            Section {
                ForEach(set.holidays) { holiday in
                    PublicHolidayPreviewRow(
                        holiday: holiday,
                        setLanguage: set.language,
                        nextDate: nextDate(of: holiday),
                        formatting: settingsStore.dateFormatting,
                        isSelected: selection.contains(holiday.id)
                    ) {
                        if selection.contains(holiday.id) {
                            selection.remove(holiday.id)
                        } else {
                            selection.insert(holiday.id)
                        }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: Metrics.small) {
                    ForEach(set.tips, id: \.self) { tip in
                        Text(tipText(tip))
                    }
                    Text(String(
                        localized: "Checked for \(String(set.checkedFor)). Paid days off: your contracted hours are credited. Each one can be edited, switched off or deleted later.",
                        comment: "Public holidays preview footer; the value is a year such as 2026"
                    ))
                }
            }
        }
        // Always on screen, however long the list: the one thing to do here.
        .safeAreaInset(edge: .bottom) {
            Button {
                PublicHolidayActions.add(
                    set, selection: selection, context: modelContext, settingsStore: settingsStore
                )
                onAdded()
            } label: {
                Text("Add these holidays")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selection.isEmpty)
            .accessibilityIdentifier("public-holidays-add")
            .padding(.horizontal, Metrics.large)
            .padding(.vertical, Metrics.small)
            .background(.bar)
        }
        .navigationTitle(PublicHolidayActions.title(of: set))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func nextDate(of holiday: PublicHoliday) -> CalendarDate? {
        let calendar = settingsStore.workCalendar
        let today = CalendarDate.today(in: calendar)
        for year in today.year...(today.year + 2) {
            if let date = holiday.recurrence.occurrence(inYear: year, calendar: calendar), date >= today {
                return date
            }
        }
        return nil
    }

    private func tipText(_ tip: PublicHolidayTip) -> String {
        switch tip {
        case .christmasEveAndNewYearsEve:
            return String(localized: "24 and 31 December are often days off by collective agreement. Add them by hand if yours are.")
        case .cantonalHolidaysMissing:
            return String(localized: "Only the days every canton shares. Add your canton's other holidays by hand.")
        case .regionalHolidaysNotIncluded:
            return String(localized: "National holidays only. Add regional and local ones by hand.")
        case .sundayMovedToMonday:
            return String(localized: "When a holiday falls on a Sunday, your region may move it to the Monday. Check the regional list.")
        }
    }
}

private struct PublicHolidayPreviewRow: View {
    let holiday: PublicHoliday
    let setLanguage: ExportLanguage
    let nextDate: CalendarDate?
    let formatting: CalendarFormatting
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.medium) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .foregroundStyle(.primary)
                    if let other {
                        Text(other)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let note = holiday.note {
                        Text(noteText(note))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Metrics.small)
                if let nextDate {
                    Text(formatting.mediumDate(nextDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("public-holidays-item-\(holiday.id)")
    }

    private var name: String { holiday.name(in: .device, setLanguage: setLanguage) }

    /// The other name, when the two differ: the local one under an English
    /// name, the English one under a local name.
    private var other: String? {
        let alternative = name == holiday.localName ? holiday.englishName : holiday.localName
        return alternative == name ? nil : alternative
    }

    private func noteText(_ note: PublicHolidayNote) -> String {
        switch note {
        case .partOfRegion:
            return String(localized: "Only in part of the region")
        case .customary:
            return String(localized: "Usually a day off, but not a public holiday by law")
        case .collectiveAgreement:
            return String(localized: "A day off depending on your collective agreement")
        }
    }
}
