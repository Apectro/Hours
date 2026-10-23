import SwiftUI
import SwiftData

/// One site's crew: add, rename, reorder, hide and bring back.
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

                if !isReadOnly {
                    TextField("Add a coworker", text: $newName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($isAddingFocused)
                        .onSubmit(add)
                        .accessibilityIdentifier("crew-new-name")

                    if !candidates.isEmpty {
                        Button {
                            isPicking = true
                        } label: {
                            Label("Add from other sites", systemImage: "person.badge.plus")
                        }
                        .accessibilityIdentifier("crew-add-from-sites")
                    }
                }
            } footer: {
                if isReadOnly {
                    Text("Read-only until Zeitkonto Pro is active again or your other sites are archived. Nothing on it is lost.")
                } else {
                    Text("Swipe a name to rename or hide it. Nobody is ever deleted, so hours already recorded never disappear: someone hidden simply stops being offered for new days.")
                }
            }

            if !hidden.isEmpty {
                Section {
                    ForEach(hidden) { member in
                        memberRow(member, hiding: false)
                    }
                } header: {
                    Text("Hidden")
                        .accessibilityIdentifier("crew-hidden-header")
                } footer: {
                    Text("Not offered for new days. Every day already recorded for them stays, on screen and on exports.")
                }
            }
        }
        .navigationTitle("Crew")
        .navigationBarTitleDisplayMode(.inline)
        // A screen the UI tests wait for. The title beside it is translated.
        .accessibilityIdentifier("screen-crew")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !isReadOnly && visible.count > 1 {
                    EditButton()
                }
            }
        }
        .alert("Rename", isPresented: isRenaming, presenting: renaming) { member in
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Save") { rename(member) }
            Button("Cancel", role: .cancel) { renaming = nil }
                .accessibilityIdentifier("crew-rename-cancel")
        }
        .sheet(isPresented: $isPicking) {
            CrewPickerSheet(candidates: candidates) { chosen in
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
            Text("You")
            Spacer(minLength: Metrics.medium)
            Text("Always on the crew")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Plain text rather than a button, with the actions on a swipe and a
    /// long press: a row that is a button reads as "open this", and there is
    /// nothing behind a name to open.
    private func memberRow(_ member: CrewMember, hiding: Bool) -> some View {
        Text(member.name)
            .foregroundStyle(hiding ? .primary : .secondary)
            .accessibilityIdentifier("crew-member")
            .swipeActions(edge: .trailing) {
                if !isReadOnly {
                    if hiding {
                        Button("Hide", systemImage: "eye.slash") { setHidden(member, true) }
                            .tint(.orange)
                    } else {
                        Button("Show", systemImage: "eye") { setHidden(member, false) }
                            .tint(.blue)
                    }
                }
            }
            .swipeActions(edge: .leading) {
                if !isReadOnly {
                    Button("Rename", systemImage: "pencil") { startRenaming(member) }
                        .tint(.gray)
                }
            }
            .contextMenu {
                if !isReadOnly {
                    Button("Rename", systemImage: "pencil") { startRenaming(member) }
                        .accessibilityIdentifier("crew-rename")
                    if hiding {
                        Button("Hide", systemImage: "eye.slash") { setHidden(member, true) }
                    } else {
                        Button("Show", systemImage: "eye") { setHidden(member, false) }
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
        candidates = store.crewCandidates(for: siteID, today: CalendarDate.today(in: calendar), calendar: calendar)
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { isPresented in if !isPresented { renaming = nil } }
        )
    }

    // MARK: - Editing

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
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
