import SwiftUI
import SwiftData

/// A site's Missing list, pushed from the site's page by value.
struct SiteMissingRoute: Hashable {
    let siteID: UUID
}

/// Missing (Missing board, phone 6): what the site needs and has not got.
/// The large title, the site under it, Needed · Ordered · Arrived, and a row
/// per item — a dot, the name, "note · who · day" and the quantity. Swipe a
/// row to mark it ordered or arrived, or to delete it. The toolbar scans a
/// delivered box (it asks before ticking the item off as arrived) and adds;
/// Send the list is at the bottom.
///
/// Not hours, so not under the month lock; a read-only site (the Pro rule)
/// is shown, not changed.
struct SiteMissingScreen: View {
    let siteID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions

    @Query(sort: \SiteEntry.sortOrder) private var siteEntries: [SiteEntry]

    @State private var items: [MissingItem] = []
    @State private var catalog: [ExtraWorkCatalogItem] = []
    @State private var shownState: MissingState = .needed
    @State private var sheet: MissingSheet?
    /// What a scan asked for, opened once the scanner's sheet has gone.
    @State private var afterScan: AfterScan?
    /// A delivered box scanned: the item it would tick off, asked first.
    @State private var arriving: MissingItem?
    /// A code scanned that nothing on the list has.
    @State private var unmatchedCode: String?

    private enum MissingSheet: Identifiable {
        case add(code: String?)
        case scan
        case send

        var id: String {
            switch self {
            case let .add(code): return "add-\(code ?? "")"
            case .scan: return "scan"
            case .send: return "send"
            }
        }
    }

    private enum AfterScan {
        case arrive(MissingItem)
        case unmatched(String)
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
                    Text(String(localized: "Needed \(MissingList.count(.needed, in: items))", comment: "Missing list: the segment of items still needed; the value is how many"))
                        .tag(MissingState.needed)
                    Text(String(localized: "Ordered \(MissingList.count(.ordered, in: items))", comment: "Missing list: the segment of items ordered; the value is how many"))
                        .tag(MissingState.ordered)
                    Text("Arrived")
                        .tag(MissingState.arrived)
                } label: {
                    Text("Show")
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 0, leading: Metrics.large, bottom: 0, trailing: Metrics.large))
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("missing-state")
            }
            .listRowSeparator(.hidden)

            Section {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    MissingRow(item: item, state: shownState, today: today, formatting: settingsStore.dateFormatting)
                        .accessibilityIdentifier("missing-row-\(index)")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canEdit {
                                swipeButtons(for: item)
                            }
                        }
                }
            } footer: {
                if !shown.isEmpty, canEdit {
                    Text("Swipe an item to mark it ordered or arrived. Scanning a delivered box ticks it off as arrived.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: "shippingbox")
                } description: {
                    if shownState == .needed && canEdit {
                        Text("Note it the moment you notice: tap + or scan the box.")
                    }
                }
                .accessibilityIdentifier("missing-empty")
            }
        }
        .accessibilityIdentifier("screen-missing")
        .navigationTitle("Missing")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if canEdit {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        sheet = .scan
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel(String(localized: "Scan a delivery"))
                    .accessibilityIdentifier("missing-scan")
                    Button {
                        sheet = .add(code: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "Add something missing"))
                    .accessibilityIdentifier("missing-add")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if canEdit && !MissingList.toSend(items).isEmpty {
                Button {
                    sheet = .send
                } label: {
                    Text("Send the list")
                }
                .buttonStyle(.bigAction(.primary))
                .accessibilityIdentifier("missing-send")
                .padding(.horizontal, Metrics.large)
                .padding(.vertical, Metrics.small)
                .background(Color.hoursCanvas)
            }
        }
        .onAppear(perform: reload)
        .sheet(item: $sheet, onDismiss: sheetClosed) { sheet in
            switch sheet {
            case let .add(code):
                if let site {
                    MissingAddSheet(site: site, initialCode: code, onAdded: reload)
                }
            case .scan:
                BarcodeScanSheet(title: String(localized: "Scan a delivery"), onCode: scanned)
            case .send:
                if let site {
                    MissingSendSheet(site: site, items: items, catalog: catalog, onSent: reload)
                }
            }
        }
        .confirmationDialog(
            arrivingTitle,
            isPresented: Binding(get: { arriving != nil }, set: { if !$0 { arriving = nil } }),
            titleVisibility: .visible
        ) {
            Button("Arrived") {
                if let arriving { mark(arriving, .arrived) }
                arriving = nil
            }
            .accessibilityIdentifier("missing-arrived-confirm")
            Button("Not now", role: .cancel) { arriving = nil }
        }
        .alert(
            "Not on the list",
            isPresented: Binding(get: { unmatchedCode != nil }, set: { if !$0 { unmatchedCode = nil } })
        ) {
            Button("Add it") {
                let code = unmatchedCode
                unmatchedCode = nil
                sheet = .add(code: code)
            }
            Button("OK", role: .cancel) { unmatchedCode = nil }
        } message: {
            Text("Nothing needed or ordered here has this code.")
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func swipeButtons(for item: MissingItem) -> some View {
        Button(role: .destructive) {
            MissingRepository(context: modelContext).remove(id: item.id)
            reload()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .accessibilityIdentifier("missing-delete")
        if item.state != .arrived {
            Button {
                mark(item, .arrived)
            } label: {
                Label("Arrived", systemImage: "checkmark.circle")
            }
            .tint(.green)
            .accessibilityIdentifier("missing-mark-arrived")
        }
        switch item.state {
        case .needed:
            Button {
                mark(item, .ordered)
            } label: {
                Label("Ordered", systemImage: "shippingbox")
            }
            .tint(.blue)
            .accessibilityIdentifier("missing-mark-ordered")
        case .ordered, .arrived:
            Button {
                mark(item, .needed)
            } label: {
                Label("Needed", systemImage: "arrow.uturn.backward")
            }
            .tint(.orange)
            .accessibilityIdentifier("missing-mark-needed")
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

    private var today: CalendarDate {
        CalendarDate.today(in: settingsStore.workCalendar)
    }

    private var shown: [MissingItem] {
        MissingList.items(shownState, in: items)
    }

    private var emptyTitle: String {
        switch shownState {
        case .needed: return String(localized: "Nothing missing")
        case .ordered: return String(localized: "Nothing ordered")
        case .arrived: return String(localized: "Nothing arrived yet")
        }
    }

    private var arrivingTitle: String {
        guard let arriving else { return "" }
        let line = arriving.line(in: .device, decimalSeparator: ExtraWorkFormatting.decimalSeparator)
        return String(localized: "Mark \(line) as arrived?", comment: "Missing list, after scanning a delivered box; the value is e.g. 6 × Junction box IP65")
    }

    private func reload() {
        items = MissingRepository(context: modelContext).items(siteID: siteID)
        catalog = ExtraWorkRepository(context: modelContext).catalog()
    }

    private func mark(_ item: MissingItem, _ state: MissingState) {
        MissingRepository(context: modelContext).mark(item.id, state, siteID: siteID)
        reload()
    }

    // MARK: - Scanning a delivery

    private func scanned(_ code: String) {
        if let match = MissingList.arrivalMatch(forCode: code, catalog: catalog, in: items) {
            afterScan = .arrive(match)
        } else if let kept = ExtraWorkCatalog.code(code) {
            afterScan = .unmatched(kept)
        }
    }

    private func sheetClosed() {
        reload()
        guard let next = afterScan else { return }
        afterScan = nil
        switch next {
        case let .arrive(item): arriving = item
        case let .unmatched(code): unmatchedCode = code
        }
    }
}

/// One row: a dot in the state's colour, the name, "note · who · day" under
/// it, and the quantity on the right.
struct MissingRow: View {
    let item: MissingItem
    let state: MissingState
    let today: CalendarDate
    let formatting: CalendarFormatting

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        HStack(spacing: Metrics.medium) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                    .foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: item.amount(in: .device, decimalSeparator: ExtraWorkFormatting.decimalSeparator))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    private var dotColor: Color {
        switch state {
        case .needed: return Color.hoursAttentionFill
        case .ordered: return Color(uiColor: .systemGray)
        case .arrived: return Color.hoursDone
        }
    }

    /// "2nd floor corridor · Dusko · Thu 29": the note, who noticed when it
    /// was not you, and the day it got to this state.
    private var detail: String {
        let moment: Date
        switch state {
        case .needed: moment = item.notedAt
        case .ordered: moment = item.orderedAt ?? item.notedAt
        case .arrived: moment = item.arrivedAt ?? item.notedAt
        }
        let date = CalendarDate(moment, calendar: settingsStore.workCalendar)
        let day = date == today ? String(localized: "today") : formatting.shortWeekdayAndDay(date)
        return [item.note, item.notedBy, day].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
