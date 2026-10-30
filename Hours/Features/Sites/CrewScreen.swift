import SwiftUI
import SwiftData

/// One site's crew (1.2, mockup Crew): you first, then each person with
/// their hours on the site this month; tap a person for their month and
/// their own sheet (`CrewMemberSheetScreen`); add, rename, reorder, hide and
/// bring back.
///
/// There is no delete, on purpose. A crew member is named on every day they
/// were ticked present, and on the director's sheet those days produce; taking
/// the name away would take their hours with it. Someone who has left is
/// hidden instead, which only stops them being offered for new days.
///
/// "You" heads the list and cannot be edited: you are on every site, and you
/// are not a stored member at all (see `CrewMember.youID`).
struct CrewScreen: View {
    let siteID: UUID

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.modelContext) private var modelContext

    // Watched rather than read, for the reason given in `SitesScreen`.
    @Query private var crewEntries: [CrewMemberEntry]
    @Query private var siteEntries: [SiteEntry]

    @State private var members: [CrewMember] = []
    @State private var sites: [Site] = []
    @State private var newName = ""
    @State private var renaming: CrewMember?
    @State private var renameText = ""
    /// People on your other crews who are not on this one.
    @State private var candidates: [CrewCandidate] = []
    @State private var isPicking = false
    /// Each member's hours on this site this month.
    @State private var monthMinutes: [UUID: Int] = [:]
    /// Each candidate's sites, for "Add from other sites".
    @State private var candidateSites: [String: [String]] = [:]
    /// Crew sign-off, from the toolbar (1.2): with the site's "…" menu gone,
    /// this and the site's Sheet are where people sign their month.
    @State private var signingOff: Site?
    @FocusState private var isAddingFocused: Bool

    init(siteID: UUID) {
        self.siteID = siteID
        let key = siteID.uuidString
        _crewEntries = Query(
            filter: #Predicate<CrewMemberEntry> { $0.siteID == key },
            sort: \CrewMemberEntry.sortOrder
        )
        _siteEntries = Query(sort: \SiteEntry.sortOrder)
    }

    var body: some View {
        List {
            Section {
                youRow

                ForEach(visible) { member in
                    memberRow(member, hiding: true)
                }
                .onMove(perform: moveAction)
            } footer: {
                if isReadOnly {
                    Text("Read-only until Zeitkonto Pro is active again or your other sites are archived. Nothing on it is lost.")
                } else {
                    Text("Tap a person for their month and their own sheet. Swipe to rename or hide.")
                }
            }

            if !isReadOnly {
                Section {
                    // The return key adds too; the button says that it can.
                    HStack(spacing: Metrics.small) {
                        Image(systemName: "plus")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        TextField("Add a coworker", text: $newName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .focused($isAddingFocused)
                            .onSubmit(add)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("crew-new-name")
                        if !trimmedNewName.isEmpty {
                            Button("Add", action: add)
                                .buttonStyle(.borderless)
                                .fontWeight(.semibold)
                                .frame(minWidth: 44, minHeight: 44)
                                .accessibilityIdentifier("crew-add")
                        }
                    }

                    if !candidates.isEmpty {
                        Button {
                            isPicking = true
                        } label: {
                            Label("Add from other sites", systemImage: "plus")
                                .fontWeight(.semibold)
                        }
                        .accessibilityIdentifier("crew-add-from-sites")
                    }
                }
            }

            if !hidden.isEmpty {
                Section {
                    ForEach(hidden) { member in
                        memberRow(member, hiding: false)
                    }
                } header: {
                    Text("Hidden · keep their hours")
                        .accessibilityIdentifier("crew-hidden-header")
                } footer: {
                    Text("Not offered for new days. Every day already recorded for them stays, on screen and on exports.")
                }
            }
        }
        .navigationTitle("Crew")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    signingOff = sites.first { $0.id == siteID }
                } label: {
                    Label("Crew sign-off", systemImage: "signature")
                }
                .disabled(!sites.contains { $0.id == siteID })
                .accessibilityIdentifier("site-sign-off")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !isReadOnly && visible.count > 1 {
                    EditButton()
                }
            }
        }
        .sheet(item: $signingOff) { site in
            SiteSignOffSheet(site: site)
        }
        .alert("Rename", isPresented: isRenaming, presenting: renaming) { member in
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Save") { rename(member) }
            Button("Cancel", role: .cancel) { renaming = nil }
                .accessibilityIdentifier("crew-rename-cancel")
        }
        .sheet(isPresented: $isPicking) {
            CrewPickerSheet(candidates: candidates, siteNames: candidateSites) { chosen in
                repository.addCrew(chosen, to: siteID)
                // The site widget draws the crew by their initials.
                HoursStack.refreshWidget()
            }
        }
        .onChange(of: changeToken, initial: true) { _, _ in
            reload()
        }
    }

    // MARK: - Rows

    private var youRow: some View {
        HStack(spacing: Metrics.medium) {
            CrewInitial(name: yourName, isHidden: false)
            HStack(spacing: 0) {
                Text(verbatim: yourName)
                Text(verbatim: " · ")
                    .foregroundStyle(.hoursSecondaryText)
                Text("you")
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("always")
                .font(.subheadline)
                .foregroundStyle(.hoursSecondaryText)
                // What the UI tests wait for: this text is on screen whenever
                // the crew is. Not on the List, which would hand the
                // identifier down to every row and button inside it.
                .accessibilityIdentifier("screen-crew")
        }
        .frame(minHeight: 44)
    }

    /// The name in Export options, or "You".
    private var yourName: String {
        let owner = settingsStore.settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return owner.isEmpty ? String(localized: "You") : owner
    }

    /// The row opens the person's month; rename and hide are on a swipe and
    /// a long press. A hidden person has a Show button instead.
    private func memberRow(_ member: CrewMember, hiding: Bool) -> some View {
        HStack(spacing: Metrics.small) {
            // A destination link rather than a value: a destination declared
            // on a screen that was itself pushed by value is not found.
            NavigationLink {
                CrewMemberSheetScreen(member: member)
            } label: {
                HStack(spacing: Metrics.medium) {
                    CrewInitial(name: member.name, isHidden: !hiding)
                    Text(member.name)
                        .foregroundStyle(hiding ? AnyShapeStyle(.primary) : AnyShapeStyle(.hoursSecondaryText))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if hiding {
                        Text(verbatim: settingsStore.settings.displayFormatting.string(monthMinutes[member.id] ?? 0))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.hoursSecondaryText)
                    }
                }
                .frame(minHeight: 44)
            }
            .accessibilityIdentifier("crew-member")
            if !hiding && !isReadOnly {
                Button("Show") { setHidden(member, false) }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("crew-show")
            }
        }
        .swipeActions(edge: .trailing) {
            if !isReadOnly {
                if hiding {
                    Button("Hide", systemImage: "eye.slash") { setHidden(member, true) }
                        .tint(.orange)
                        .accessibilityIdentifier("crew-hide")
                } else {
                    Button("Show", systemImage: "eye") { setHidden(member, false) }
                        .tint(.blue)
                        .accessibilityIdentifier("crew-show")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if !isReadOnly {
                Button("Rename", systemImage: "pencil") { startRenaming(member) }
                    .tint(.gray)
                    .accessibilityIdentifier("crew-rename-swipe")
            }
        }
        .contextMenu {
            if !isReadOnly {
                Button("Rename", systemImage: "pencil") { startRenaming(member) }
                    .accessibilityIdentifier("crew-rename")
                if hiding {
                    Button("Hide", systemImage: "eye.slash") { setHidden(member, true) }
                        .accessibilityIdentifier("crew-hide")
                } else {
                    Button("Show", systemImage: "eye") { setHidden(member, false) }
                        .accessibilityIdentifier("crew-show")
                }
            }
        }
    }

    // MARK: - Data

    private var visible: [CrewMember] { members.filter { !$0.isHidden } }
    private var hidden: [CrewMember] { members.filter(\.isHidden) }

    /// The crew of one of the extra sites after Pro lapsed can be read but
    /// not changed, as the rest of that site.
    private var isReadOnly: Bool {
        guard let site = sites.first(where: { $0.id == siteID }) else { return false }
        return subscriptions.isReadOnly(site, among: sites)
    }

    /// `nil` turns reordering off, for a crew that cannot be changed.
    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard !isReadOnly else { return nil }
        return { source, destination in move(from: source, to: destination) }
    }

    private var repository: SiteRepository {
        SiteRepository(context: modelContext, lock: settingsStore.settings.monthLock)
    }

    private var changeToken: [Date] {
        crewEntries.map(\.updatedAt) + siteEntries.map(\.updatedAt)
    }

    private func reload() {
        let store = repository
        members = store.crew(for: siteID, includeHidden: true)
        sites = store.sites(includeArchived: true)
        let calendar = settingsStore.workCalendar
        let today = CalendarDate.today(in: calendar)
        candidates = store.crewCandidates(for: siteID, today: today, calendar: calendar)

        // Who is on which other crew, by the name that makes them one person.
        var onSites: [String: [String]] = [:]
        for site in sites where site.id != siteID {
            for member in store.crew(for: site.id, includeHidden: true) {
                let key = CrewCandidates.key(for: member.name)
                if !(onSites[key]?.contains(site.name) ?? false) { onSites[key, default: []].append(site.name) }
            }
        }
        candidateSites = onSites

        let calculator = SiteDayCalculator(settings: settingsStore.settings, calendar: calendar)
        var minutes: [UUID: Int] = [:]
        for day in store.siteDays(siteID: siteID, in: today.yearMonth.range(in: calendar)) {
            for person in calculator.compute(day).people { minutes[person.memberID, default: 0] += person.workedMinutes }
        }
        monthMinutes = minutes
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { isPresented in if !isPresented { renaming = nil } }
        )
    }

    // MARK: - Editing

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let name = trimmedNewName
        guard !name.isEmpty, !isReadOnly else { return }
        let next = (members.map(\.sortOrder).max() ?? -1) + 1
        repository.upsert(CrewMember(siteID: siteID, name: name, sortOrder: next))
        newName = ""
        // Crews are usually entered several names at a time.
        isAddingFocused = true
    }

    private func startRenaming(_ member: CrewMember) {
        renameText = member.name
        renaming = member
    }

    private func rename(_ member: CrewMember) {
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !name.isEmpty, name != member.name else { return }
        var renamed = member
        renamed.name = name
        repository.upsert(renamed)
        // The site widget draws the crew by their initials.
        HoursStack.refreshWidget()
    }

    private func setHidden(_ member: CrewMember, _ isHidden: Bool) {
        var changed = member
        changed.isHidden = isHidden
        // Someone brought back goes to the end of the list rather than to
        // wherever they stood before they left.
        if !isHidden {
            changed.sortOrder = (members.map(\.sortOrder).max() ?? -1) + 1
        }
        repository.upsert(changed)
    }

    /// Renumbers everyone so the order survives sync and restore exactly as
    /// shown. The list is updated at once, before the store answers, so the
    /// row does not jump back while the save goes through.
    private func move(from source: IndexSet, to destination: Int) {
        var reordered = visible
        reordered.move(fromOffsets: source, toOffset: destination)
        let ordered = reordered + hidden
        var renumbered: [CrewMember] = []
        for (index, member) in ordered.enumerated() {
            var member = member
            member.sortOrder = index
            renumbered.append(member)
        }
        let previous = Dictionary(members.map { ($0.id, $0.sortOrder) }, uniquingKeysWith: { first, _ in first })
        members = renumbered
        let store = repository
        for member in renumbered where previous[member.id] != member.sortOrder {
            store.upsert(member)
        }
    }
}

/// A person's initial in a circle, as the mockup's crew list has them.
private struct CrewInitial: View {
    let name: String
    let isHidden: Bool

    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 32

    var body: some View {
        Text(verbatim: String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isHidden ? Color.secondary : Color.accentColor)
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(isHidden ? Color(uiColor: .systemGray5) : Color.accentColor.opacity(0.13))
            )
            .accessibilityHidden(true)
    }
}
