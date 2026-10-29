import SwiftUI
import SwiftData

/// Setting up a new site, step by step (1.2, mockups W1–W6): how to start,
/// where it is, who works there, a usual day, the extras, and a check
/// before anything is written. For someone with a lot of sites, "Copy from a
/// site" and "Several sites at once" are the fast ways; "Create and set up
/// another like it" keeps the crew, the day and the extras for the next one.
///
/// Nothing is stored until Create. The engine decides what is made
/// (`SiteBlueprint`, `NameList`, `CrewPicking`); this gathers the answers
/// and writes the result through `SiteRepository` and the settings.
struct NewSiteWizard: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// How the new site starts (W1).
    enum Start: Hashable {
        case copy
        case fresh
        case several
    }

    @State private var step = 1
    @State private var start: Start = .fresh
    /// The site "Copy from a site" copies.
    @State private var sourceID: UUID?
    /// The job, allowance, usual day, extras and crew, as the steps set them.
    @State private var blueprint = SiteBlueprint(jobID: nil, allowanceByDefault: false, setup: SiteSetup(), crewNames: [])
    /// The new site's name, address and arrival reminder (W2). A `Site`, so
    /// the site's own arrival section can be used as it is.
    @State private var place = Site(name: "")
    /// "Several sites at once": the names, one per line.
    @State private var severalText = ""
    /// Who is ticked from the other sites, by folded name.
    @State private var ticked: Set<String> = []
    /// "New people", one per line.
    @State private var newPeopleText = ""

    @State private var sites: [Site] = []
    @State private var choices: [CrewChoice] = []
    @State private var crew: [CrewMember] = []
    /// Sites made in this sitting, for "another like it".
    @State private var madeCount = 0
    @State private var paywallReason: ProFeature?

    private static let stepCount = 6

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom) { bottomBar }
                .background(Color.hoursCanvas)
        }
        .paywall(for: $paywallReason)
        .task { load() }
    }

    // MARK: - Frame

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if step == 1 {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("wizard-cancel")
            } else {
                Button {
                    withAnimation { step = previousStep }
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityIdentifier("wizard-back")
            }
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: Metrics.tiny) {
                Text(String(
                    localized: "Step \(step) of \(Self.stepCount)",
                    comment: "New-site wizard; the values are the step and how many there are"
                ))
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("wizard-step")
                ProgressView(value: Double(step), total: Double(Self.stepCount))
                    .frame(width: 120)
                    .accessibilityHidden(true)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if step > 1 {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("wizard-cancel")
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(spacing: Metrics.small) {
            if step < Self.stepCount {
                Button {
                    next()
                } label: {
                    Text("Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
                .accessibilityIdentifier("wizard-next")
            } else {
                Button {
                    create(another: false)
                } label: {
                    Text(createTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
                .accessibilityIdentifier("wizard-create")
                if start != .several {
                    Button {
                        create(another: true)
                    } label: {
                        Text("Create and set up another like it")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canCreate)
                    .accessibilityIdentifier("wizard-create-another")
                }
            }
        }
        .padding(Metrics.large)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 1: startStep
        case 2: start == .several ? AnyView(severalStep) : AnyView(placeStep)
        case 3: crewStep
        case 4: usualDayStep
        case 5: extrasStep
        default: checkStep
        }
    }

    /// The step's big title and the line under it, as the first rows.
    private func heading(_ title: String, _ detail: String? = nil) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                Text(verbatim: title)
                    .font(.largeTitle.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let detail {
                    Text(verbatim: detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: Metrics.tiny, bottom: 0, trailing: Metrics.tiny))
        }
    }

    // MARK: - 1 · Start

    private var startStep: some View {
        Form {
            heading(String(localized: "New site"), String(localized: "How do you want to start?"))
            Section {
                if !activeSites.isEmpty {
                    option(
                        .copy,
                        title: String(localized: "Copy from a site"),
                        detail: String(localized: "Same crew, times, allowance and reminders as one of your sites. You only change the name and place."),
                        systemImage: "doc.on.doc",
                        identifier: "wizard-start-copy"
                    )
                    if start == .copy {
                        Picker("Copy from", selection: sourceBinding) {
                            ForEach(activeSites) { site in
                                Text(verbatim: site.name).tag(site.id)
                            }
                        }
                        .accessibilityIdentifier("wizard-copy-source")
                    }
                }
                option(
                    .fresh,
                    title: String(localized: "Start fresh"),
                    detail: String(localized: "Set everything step by step: place, crew, usual day, extras."),
                    systemImage: "sparkles",
                    identifier: "wizard-start-fresh"
                )
                option(
                    .several,
                    title: String(localized: "Several sites at once"),
                    detail: String(localized: "Type or paste the names, one per line. They all get the same setup; add the places later."),
                    systemImage: "square.stack.3d.up",
                    identifier: "wizard-start-several"
                )
            }
        }
    }

    private func option(_ value: Start, title: String, detail: String, systemImage: String, identifier: String) -> some View {
        Button {
            start = value
            if value == .copy, sourceID == nil { sourceID = activeSites.first?.id }
        } label: {
            HStack(alignment: .top, spacing: Metrics.medium) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Metrics.tiny) {
                    Text(verbatim: title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: start == value ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(start == value ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Metrics.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(start == value ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private var sourceBinding: Binding<UUID> {
        Binding(
            get: { sourceID ?? activeSites.first?.id ?? UUID() },
            set: { sourceID = $0 }
        )
    }

    // MARK: - 2 · Where

    private var placeStep: some View {
        Form {
            heading(String(localized: "Where is it?"))
            Section {
                TextField("Name", text: $place.name)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("site-name")
                TextField("Address", text: $place.address, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.words)
                    .textContentType(.fullStreetAddress)
                    .accessibilityIdentifier("site-address")
                if settingsStore.settings.tracksMultipleJobs {
                    Picker("Job", selection: jobBinding) {
                        ForEach(settingsStore.settings.activeJobs) { job in
                            Text(job.displayName()).tag(job.id)
                        }
                    }
                }
            } footer: {
                if nameIsTaken {
                    Text("You already have a site with this name.")
                        .foregroundStyle(Color.hoursNegative)
                        .accessibilityIdentifier("wizard-name-taken")
                } else {
                    Text("The address is printed under the name on every sheet.")
                }
            }

            // The site's own arrival section, as in its settings: the same
            // explanation first, the same one fix of where you are.
            SiteArrivalSection(site: $place, isReadOnly: false, otherSites: activeSites)
        }
    }

    private var severalStep: some View {
        Form {
            heading(
                String(localized: "Which sites?"),
                String(localized: "One name per line, or paste a list. Each gets the crew, usual day and extras you choose next.")
            )
            Section {
                TextField("Site names", text: $severalText, axis: .vertical)
                    .lineLimit(4...12)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("wizard-several-names")
            } footer: {
                VStack(alignment: .leading, spacing: Metrics.tiny) {
                    let split = severalSplit
                    if !split.new.isEmpty {
                        Text(String(inflected: "^[\(split.new.count) site](inflect: true) to create"))
                            .accessibilityIdentifier("wizard-several-count")
                    }
                    if !split.taken.isEmpty {
                        Text(String(
                            localized: "Already a site, left out: \(split.taken.joined(separator: ", "))",
                            comment: "New-site wizard; the value is the names of sites that exist already"
                        ))
                        .foregroundStyle(Color.hoursNegative)
                    }
                    Text("Add each site's address and place later, in its settings.")
                }
            }
        }
    }

    // MARK: - 3 · Crew

    private var crewStep: some View {
        Form {
            heading(String(localized: "Who works here?"))
            if !choices.isEmpty {
                Section {
                    ForEach(choices) { choice in
                        let isOn = ticked.contains(choice.id)
                        Button {
                            if isOn { ticked.remove(choice.id) } else { ticked.insert(choice.id) }
                        } label: {
                            HStack(spacing: Metrics.medium) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: choice.name)
                                        .foregroundStyle(.primary)
                                    Text(verbatim: choice.siteNames.joined(separator: " · "))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                        .accessibilityIdentifier("wizard-crew-choice")
                    }
                } header: {
                    HStack {
                        Text("From your other sites")
                        Spacer()
                        Button(allTicked ? String(localized: "Untick all") : String(localized: "Tick all")) {
                            ticked = allTicked ? [] : Set(choices.map(\.id))
                        }
                        .font(.footnote.weight(.semibold))
                        .textCase(nil)
                        .accessibilityIdentifier("wizard-tick-all")
                    }
                }
            }
            Section {
                TextField("One name per line, or paste a list", text: $newPeopleText, axis: .vertical)
                    .lineLimit(3...10)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("wizard-new-people")
            } header: {
                Text("New people")
            } footer: {
                Text(String(
                    localized: "\(crewNames.count + 1) on the crew, you included.",
                    comment: "New-site wizard, under the crew; the value is how many people"
                ))
                .accessibilityIdentifier("wizard-crew-count")
            }
        }
    }

    private var allTicked: Bool { !choices.isEmpty && ticked.isSuperset(of: choices.map(\.id)) }

    /// Ticked people in the list's order, then the typed ones, each once.
    private var crewNames: [String] {
        CrewPicking.merge(
            ticked: choices.filter { ticked.contains($0.id) }.map(\.name),
            typed: NameList.parse(newPeopleText)
        )
    }

    // MARK: - 4 · Usual day

    private var usualDayStep: some View {
        Form {
            heading(String(localized: "A usual day here"))
            Section {
                UsualDayRows(
                    start: timeBinding(\.start, fallback: TimeOfDay(hour: 7, minute: 0)),
                    end: timeBinding(\.end, fallback: TimeOfDay(hour: 15, minute: 30)),
                    breakMinutes: $blueprint.setup.breakMinutes,
                    calendar: settingsStore.workCalendar
                )
            } footer: {
                Text("A new day on this site starts with these times for everyone ticked. Change any day or person as usual.")
            }
            Section {
                WorkDaysPicker(days: $blueprint.setup.workDays, formatting: settingsStore.dateFormatting)
            } header: {
                Text("Work days here")
            } footer: {
                Text("Reminders only nag on these days.")
            }
        }
    }

    private func timeBinding(_ keyPath: WritableKeyPath<SiteSetup, TimeOfDay?>, fallback: TimeOfDay) -> Binding<TimeOfDay> {
        Binding(
            get: { blueprint.setup[keyPath: keyPath] ?? fallback },
            set: { blueprint.setup[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - 5 · Extras

    private var extrasStep: some View {
        Form {
            heading(String(localized: "Extras"), String(localized: "All optional. Change them later in the site's settings."))
            Section {
                SiteExtrasRows(setup: $blueprint.setup, allowanceByDefault: $blueprint.allowanceByDefault)
            }
        }
    }

    // MARK: - 6 · Check

    private var checkStep: some View {
        Form {
            heading(checkTitle, String(localized: "Check it once, then it's ready."))
            Section {
                summaryRow(
                    String(localized: "Place"),
                    value: placeSummary,
                    step: 2,
                    identifier: "wizard-check-place"
                )
                summaryRow(
                    String(localized: "Crew"),
                    value: ([String(localized: "You")] + crewNames).joined(separator: ", "),
                    step: 3,
                    identifier: "wizard-check-crew"
                )
                summaryRow(
                    String(localized: "Usual day"),
                    value: text.usualDay(blueprint.setup) + "\n" + text.workDays(blueprint.setup.workDays),
                    step: 4,
                    identifier: "wizard-check-day"
                )
                summaryRow(
                    String(localized: "Extras"),
                    value: text.extras(
                        blueprint.setup,
                        allowanceByDefault: blueprint.allowanceByDefault,
                        tracksAllowance: settingsStore.settings.allowance.isEnabled
                    ),
                    step: 5,
                    identifier: "wizard-check-extras"
                )
            } footer: {
                if madeCount > 0 {
                    Text(String(
                        localized: "Created so far: \(madeCount)",
                        comment: "New-site wizard, after Create and set up another like it; the value is how many sites"
                    ))
                    .accessibilityIdentifier("wizard-made-count")
                }
            }
        }
    }

    /// One line of the check: tapping it goes back to its step.
    private func summaryRow(_ title: String, value: String, step target: Int, identifier: String) -> some View {
        Button {
            withAnimation { step = target }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.medium) {
                Text(verbatim: title)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Metrics.small)
                Text(verbatim: value)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Change"))
        .accessibilityIdentifier(identifier)
    }

    private var checkTitle: String {
        switch start {
        case .several:
            return String(inflected: "^[\(severalSplit.new.count) site](inflect: true)")
        case .copy, .fresh:
            let name = place.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? String(localized: "New site") : name
        }
    }

    private var placeSummary: String {
        if start == .several {
            return severalSplit.new.joined(separator: ", ")
        }
        var lines: [String] = []
        let address = SiteAddress.singleLine(place.address)
        lines.append(address.isEmpty ? String(localized: "No address yet") : address)
        if place.remindsOnArrival, place.place != nil {
            lines.append(String(
                localized: "Arrival reminder within \(SiteArrivalSection.metres(place.monitoredRadius))",
                comment: "New-site wizard summary; the value is a distance"
            ))
        }
        return lines.joined(separator: "\n")
    }

    private var createTitle: String {
        switch start {
        case .several:
            return String(inflected: "Create ^[\(severalSplit.new.count) site](inflect: true)")
        case .copy, .fresh:
            return String(localized: "Create site")
        }
    }

    // MARK: - Moving between steps

    private var trimmedName: String { place.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var nameIsTaken: Bool { NameList.isTaken(trimmedName, among: sites) }

    private var severalSplit: (new: [String], taken: [String]) {
        NameList.newSites(from: severalText, among: sites)
    }

    private var canContinue: Bool {
        switch step {
        case 1: return start != .copy || sourceID != nil
        case 2: return start == .several ? !severalSplit.new.isEmpty : !trimmedName.isEmpty && !nameIsTaken
        default: return true
        }
    }

    private var canCreate: Bool {
        start == .several ? !severalSplit.new.isEmpty : !trimmedName.isEmpty && !nameIsTaken
    }

    private var previousStep: Int { max(1, step - 1) }

    private func next() {
        guard canContinue else { return }
        if step == 1 { prepare() }
        withAnimation { step = min(Self.stepCount, step + 1) }
    }

    /// Leaving the first step fills everything after it from the choice:
    /// the site copied, or what new sites start with.
    private func prepare() {
        let settings = settingsStore.settings
        let calendar = settingsStore.workCalendar
        let today = CalendarDate.today(in: calendar)
        let defaults = settings.newSites.setup(schedule: settings.primarySchedule(on: today))
        if start == .copy, let source = activeSites.first(where: { $0.id == sourceID }) {
            let recent = repository.siteDays(
                siteID: source.id,
                in: CalendarDateRange(start: today.adding(days: -60, in: calendar), end: today)
            )
            blueprint = SiteBlueprint.copying(
                site: source,
                setup: settings.siteSetup(for: source.id),
                crew: crew,
                recentDays: recent,
                calendar: calendar,
                fallback: defaults
            )
            ticked = Set(blueprint.crewNames.map(CrewCandidates.key(for:)))
        } else {
            blueprint = SiteBlueprint.fresh(
                defaults: settings.newSites,
                schedule: settings.primarySchedule(on: today),
                jobID: nil
            )
            ticked = []
        }
        newPeopleText = ""
    }

    private var jobBinding: Binding<UUID> {
        Binding(
            get: { settingsStore.settings.job(blueprint.jobID).id },
            set: { blueprint.jobID = $0 }
        )
    }

    // MARK: - Data

    private var text: SiteSetupText {
        SiteSetupText(
            formatting: settingsStore.dateFormatting,
            durations: settingsStore.settings.displayFormatting,
            calendar: settingsStore.workCalendar
        )
    }

    private var activeSites: [Site] { sites.filter { !$0.isArchived } }

    private var repository: SiteRepository {
        SiteRepository(context: modelContext, lock: settingsStore.settings.monthLock)
    }

    /// In a task rather than in `body`: the repository's reads collapse
    /// duplicates, which writes.
    private func load() {
        let store = repository
        sites = store.sites(includeArchived: true)
        crew = sites.flatMap { store.crew(for: $0.id, includeHidden: true) }
        choices = CrewPicking.choices(sites: sites, crew: crew)
        if sourceID == nil { sourceID = activeSites.first?.id }
    }

    // MARK: - Creating

    private func create(another: Bool) {
        guard canCreate else { return }
        blueprint.crewNames = crewNames
        let store = repository
        let existing = store.sites(includeArchived: true)
        var order = (existing.map(\.sortOrder).max() ?? -1) + 1
        var active = existing.filter { !$0.isArchived }.count
        let names = start == .several ? NameList.newSites(from: severalText, among: existing).new : [trimmedName]

        for name in names {
            // The first site is free; more than one active site is Pro
            // (nothing is sold while the first release is free).
            guard subscriptions.canAddSite(activeSites: active) else {
                paywallReason = .multipleSites
                break
            }
            let made = blueprint.make(
                name: name,
                address: start == .several ? "" : place.address,
                arrival: start == .several ? nil : place,
                sortOrder: order
            )
            store.upsert(made.site)
            for member in made.crew {
                store.upsert(member)
            }
            settingsStore.update { $0.setSiteSetup(made.setup, for: made.site.id) }
            order += 1
            active += 1
            madeCount += 1
        }

        afterCreating()
        if another && paywallReason == nil {
            // The next site like this one: a new name and place, the same
            // crew, day and extras.
            place = Site(name: "")
            withAnimation { step = 2 }
            load()
        } else if paywallReason == nil {
            dismiss()
        }
    }

    /// What a new site changes: the widget's card, the watched places, the
    /// evening reminder and the note on the 1st.
    private func afterCreating() {
        HoursStack.refreshWidget()
        HoursStack.arrivals.refresh()
        let context = modelContext
        let store = settingsStore
        Task {
            await SiteReminderRefresher.refresh(
                context: context,
                preferences: store.settings.reminders,
                calendar: store.workCalendar
            )
            await MonthlySheetRefresher.refresh(context: context, settingsStore: store)
        }
    }
}
