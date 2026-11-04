import SwiftUI
import SwiftData

/// A site's defects, pushed from the site's page by value.
struct SiteDefectsRoute: Hashable {
    let siteID: UUID
}

/// Defects (Defects board, phone 14): the large title, the site under it,
/// Open · Fixed, and the defects grouped by floor in the site's floor order,
/// those with no floor last. A row is the marked photo, what's wrong,
/// "room · who noted it · day", and who fixes it when the site assigns
/// defects. Swipe to mark fixed (or reopen) or delete; a tap opens the
/// photos. + adds one, camera first; Send the list is at the bottom.
///
/// Not hours, so not under the month lock; a read-only site (the Pro rule)
/// is shown, not changed.
struct SiteDefectsScreen: View {
    let siteID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions

    @Query(sort: \SiteEntry.sortOrder) private var siteEntries: [SiteEntry]

    @State private var defects: [Defect] = []
    @State private var thumbnails: [UUID: DefectPhoto] = [:]
    @State private var shownState: DefectState = .open
    @State private var cover: Cover?
    @State private var sending = false

    private enum Cover: Identifiable {
        case capture
        case viewer(UUID)

        var id: String {
            switch self {
            case .capture: return "capture"
            case let .viewer(id): return "viewer-\(id.uuidString)"
            }
        }
    }

    var body: some View {
        List {
            Section {
                if let site {
                    Text(verbatim: site.name)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                        .listRowInsets(EdgeInsets(top: 0, leading: Metrics.large + 4, bottom: Metrics.small, trailing: Metrics.large))
                        .listRowBackground(Color.clear)
                }
                Picker(selection: $shownState) {
                    Text(String(localized: "Open \(DefectList.count(.open, in: defects))", comment: "Defects: the segment of open defects; the value is how many"))
                        .tag(DefectState.open)
                    Text(String(localized: "Fixed \(DefectList.count(.fixed, in: defects))", comment: "Defects: the segment of fixed defects; the value is how many"))
                        .tag(DefectState.fixed)
                } label: {
                    Text("Show")
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 0, leading: Metrics.large, bottom: 0, trailing: Metrics.large))
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("defects-state")
            }
            .listRowSeparator(.hidden)

            ForEach(groups, id: \.floor) { group in
                Section {
                    ForEach(group.defects) { defect in
                        Button {
                            cover = .viewer(defect.id)
                        } label: {
                            DefectRow(
                                defect: defect,
                                photo: thumbnails[defect.id],
                                showsAssignee: setup.assignsDefects,
                                today: today,
                                calendar: settingsStore.workCalendar,
                                formatting: settingsStore.dateFormatting
                            )
                        }
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("defects-row-\(index(of: defect))")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canEdit {
                                swipeButtons(for: defect)
                            }
                        }
                    }
                } header: {
                    Text(verbatim: group.floor.isEmpty ? String(localized: "No floor") : group.floor)
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView {
                    Label(shownState == .open ? String(localized: "No open defects") : String(localized: "Nothing fixed yet"),
                          systemImage: "checkmark.seal")
                } description: {
                    if shownState == .open && canEdit {
                        Text("Found something wrong? Tap + and take a photo of it.")
                    }
                }
                .accessibilityIdentifier("defects-empty")
            }
        }
        .accessibilityIdentifier("screen-defects")
        .navigationTitle("Defects")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        cover = .capture
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "Add a defect"))
                    .accessibilityIdentifier("defects-add")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !defects.isEmpty {
                Button {
                    sending = true
                } label: {
                    Text("Send the list")
                }
                .buttonStyle(.bigAction(.primary))
                .accessibilityIdentifier("defects-send")
                .padding(.horizontal, Metrics.large)
                .padding(.vertical, Metrics.small)
                .background(Color.hoursCanvas)
            }
        }
        .onAppear(perform: reload)
        .fullScreenCover(item: $cover, onDismiss: reload) { cover in
            if let site {
                switch cover {
                case .capture:
                    DefectCaptureFlow(site: site, onAdded: reload)
                case let .viewer(id):
                    DefectViewerSheet(site: site, defectID: id, canEdit: canEdit, onChange: reload)
                }
            }
        }
        .sheet(isPresented: $sending) {
            if let site {
                DefectsSendSheet(site: site, defects: defects, thumbnails: thumbnails)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func swipeButtons(for defect: Defect) -> some View {
        Button(role: .destructive) {
            DefectRepository(context: modelContext).remove(id: defect.id)
            reload()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityIdentifier("defects-delete")
        switch defect.state {
        case .open:
            Button {
                DefectRepository(context: modelContext).markFixed(defect.id)
                reload()
            } label: {
                Label("Fixed", systemImage: "checkmark.circle")
            }
            .tint(.green)
            .accessibilityIdentifier("defects-fix")
        case .fixed:
            Button {
                DefectRepository(context: modelContext).reopen(defect.id)
                reload()
            } label: {
                Label("Reopen", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)
            .accessibilityIdentifier("defects-reopen")
        }
    }

    // MARK: - State

    private var sites: [Site] {
        var seen = Set<UUID>()
        return siteEntries.map(\.site).filter { seen.insert($0.id).inserted }
    }

    private var site: Site? {
        sites.first { $0.id == siteID }
    }

    private var canEdit: Bool {
        guard let site else { return false }
        return !subscriptions.isReadOnly(site, among: sites)
    }

    private var setup: SiteSetup {
        settingsStore.settings.siteSetup(for: siteID)
    }

    private var today: CalendarDate {
        CalendarDate.today(in: settingsStore.workCalendar)
    }

    private var shown: [Defect] {
        DefectList.items(shownState, in: defects)
    }

    private var groups: [DefectList.FloorGroup] {
        DefectList.groupedByFloor(shown, floors: setup.floorList(defaults: SiteFloorNames.defaults))
    }

    /// A row's place in the list as shown, for its identifier.
    private func index(of defect: Defect) -> Int {
        groups.flatMap(\.defects).firstIndex { $0.id == defect.id } ?? 0
    }

    private func reload() {
        let repository = DefectRepository(context: modelContext)
        defects = repository.defects(siteID: siteID)
        thumbnails = repository.firstPhotos(siteID: siteID)
    }
}

/// One defect: the photo, what's wrong, "room · who noted it · day" (or the
/// day it was fixed), and who fixes it in grey when the site assigns them.
struct DefectRow: View {
    let defect: Defect
    let photo: DefectPhoto?
    let showsAssignee: Bool
    let today: CalendarDate
    let calendar: Calendar
    let formatting: CalendarFormatting

    var body: some View {
        HStack(spacing: Metrics.medium) {
            DefectThumbnail(photo: photo, side: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: defect.what)
                    .foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsAssignee && defect.state == .open {
                Text(verbatim: DefectWords.assignee(defect.assignee))
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: 60)
        .accessibilityElement(children: .combine)
    }

    /// "Room 4 · Ivan · 3 Nov", "Corridor · you · today", "Room 4 · fixed 4 Nov".
    private var detail: String {
        if defect.state == .fixed {
            let day = CalendarDate(defect.fixedAt ?? defect.updatedAt, calendar: calendar)
            return [defect.room, String(localized: "fixed \(DefectWords.day(day, today: today, formatting: formatting))", comment: "A fixed defect's row; the value is a day such as today or 4 Nov")]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
        let who = defect.notedBy.isEmpty ? String(localized: "you", comment: "Who noted a defect, when it was you") : defect.notedBy
        let day = DefectWords.day(CalendarDate(defect.notedAt, calendar: calendar), today: today, formatting: formatting)
        return [defect.room, who, day].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// The words the defect screens share.
enum DefectWords {
    /// "today", or "3 Nov".
    static func day(_ date: CalendarDate, today: CalendarDate, formatting: CalendarFormatting) -> String {
        date == today ? String(localized: "today") : formatting.shortDate(date)
    }

    /// "Me", "Ivan", "Nobody yet".
    static func assignee(_ assignee: DefectAssignee) -> String {
        switch assignee {
        case .nobody: return String(localized: "Nobody yet", comment: "Who fixes a defect: not decided")
        case .you: return String(localized: "Me")
        case let .person(name): return name
        }
    }
}
