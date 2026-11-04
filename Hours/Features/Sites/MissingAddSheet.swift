import SwiftUI
import SwiftData

/// "Something's missing" (Missing board, phone 7): a search field over the
/// remembered items (this site's first), each match with its own − / + in
/// the item's unit, "Add "junc" as a new item" the same way, where or why,
/// who noticed, and "Add 3 items to missing". Several items go on the list
/// in one go (`MissingSelection`); the rows chosen stay at the top while the
/// sheet is open. The toolbar's scan counts the box's item up by one and
/// keeps the sheet open for the next box; a code not named yet is named once
/// (`NewScannedItemSheet`) and comes back chosen.
///
/// Adding a needed item that is already on the list counts it up rather than
/// listing it twice (`MissingList.adding`).
struct MissingAddSheet: View {
    let site: Site
    /// A code scanned on the list that nothing there has: picked (or named)
    /// as the sheet opens.
    var initialCode: String? = nil
    let onAdded: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var catalog: [ExtraWorkCatalogItem] = []
    @State private var crewNames: [String] = []
    @State private var query = ""
    @State private var selection = MissingSelection()
    @State private var note = ""
    /// Who noticed; empty is you.
    @State private var notedBy = ""
    @State private var inner: InnerSheet?
    /// A code scanned, waiting for the scanner's sheet to go.
    @State private var pendingCode: String?
    @State private var handledInitialCode = false
    /// The text the camera saw around the code scanned: a new code's name
    /// is offered from it.
    @State private var boxText: [RecognisedLine] = []
    /// The row whose amount is being typed.
    @State private var typing: MissingSelection.Candidate?
    @State private var typedQuantity = ""
    @FocusState private var searchFocused: Bool

    private typealias Candidate = MissingSelection.Candidate

    private enum InnerSheet: Identifiable {
        case scan
        case name(String)

        var id: String {
            switch self {
            case .scan: return "scan"
            case let .name(code): return "name-\(code)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Metrics.small) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.hoursSecondaryText)
                            .accessibilityHidden(true)
                        TextField(String(localized: "Search or type a name"), text: $query)
                            .focused($searchFocused)
                            .submitLabel(.done)
                            .autocorrectionDisabled()
                            .accessibilityLabel(String(localized: "Search or type a name"))
                            .accessibilityIdentifier("missing-add-search")
                        ScanTextButton(identifier: "missing-add-scan-text") { text in
                            query = text
                        }
                    }
                }

                let rows = self.rows
                if !rows.isEmpty {
                    Section {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, candidate in
                            row(candidate, index: index)
                        }
                    } header: {
                        if rows.contains(where: { !$0.isNew }) {
                            Text("From your list")
                        }
                    }
                }

                if selection.count > 0 {
                    Section {
                        ForEach(Array(selection.newPicks.enumerated()), id: \.element.key) { index, pick in
                            Picker(selection: unitBinding(pick.key)) {
                                ForEach(ExtraWorkScan.units, id: \.code) { unit in
                                    Text(verbatim: unit.name(in: .device)).tag(unit.code)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Counted in")
                                    Text(verbatim: pick.name)
                                        .font(.subheadline)
                                        .foregroundStyle(.hoursSecondaryText)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier(index == 0 ? "missing-add-unit" : "missing-add-unit-\(index)")
                        }
                        TextField(String(localized: "Where or why (optional)"), text: $note)
                            .accessibilityIdentifier("missing-add-note")
                        if !crewNames.isEmpty {
                            Picker(selection: $notedBy) {
                                Text("You").tag("")
                                ForEach(crewNames, id: \.self) { name in
                                    Text(verbatim: name).tag(name)
                                }
                            } label: {
                                Text("Noticed by")
                            }
                            .accessibilityIdentifier("missing-add-who")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("screen-missing-add")
            .navigationTitle("Something's missing")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: query) { _, _ in
                selection.searchChanged()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Cancel"))
                    .accessibilityIdentifier("missing-add-cancel")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        inner = .scan
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                    }
                    .accessibilityLabel(String(localized: "Scan the box"))
                    .accessibilityIdentifier("missing-add-scan")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: add) {
                    Text(saveTitle)
                }
                .buttonStyle(.bigAction(.primary))
                .accessibilityIdentifier("missing-add-save")
                .disabled(selection.count == 0)
                .padding(.horizontal, Metrics.large)
                .padding(.vertical, Metrics.small)
                .background(Color.hoursCanvas)
            }
            .alert("How many", isPresented: typingBinding) {
                TextField(String(localized: "Quantity"), text: $typedQuantity)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("missing-add-quantity-field")
                Button("Cancel", role: .cancel) {}
                Button("OK") {
                    if let typing, let value = ExtraWorkQuantity.parse(typedQuantity) {
                        selection.set(typing, to: value)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: load)
        .sheet(item: $inner, onDismiss: innerClosed) { sheet in
            switch sheet {
            case .scan:
                BarcodeScanSheet(title: String(localized: "Scan the box"), onCode: { code in
                    pendingCode = ExtraWorkCatalog.code(code)
                }, onBoxText: { lines in
                    boxText = lines
                })
            case let .name(code):
                NewScannedItemSheet(
                    code: code,
                    saveTitle: String(localized: "Save"),
                    initialName: trimmedQuery,
                    suggestions: BoxTextSuggestions.names(from: boxText, code: code)
                ) { name, unit in
                    let item = ExtraWorkRepository(context: modelContext).nameCode(code, name: name, unit: unit)
                    catalog = ExtraWorkRepository(context: modelContext).catalog()
                    selection.scanned(catalog.first { $0.id == item.id } ?? item)
                }
            }
        }
    }

    // MARK: - Rows

    /// The name on the leading side (wrapping, never squeezing), the amount
    /// control on the trailing side; at the accessibility sizes the control
    /// goes under the name.
    private func row(_ candidate: Candidate, index: Int) -> some View {
        let amount = selection.quantity(of: candidate.key)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: Metrics.small))
            : AnyLayout(HStackLayout(spacing: Metrics.medium))
        return layout {
            Button {
                selection.choose(candidate)
                searchFocused = false
            } label: {
                rowLabel(candidate)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(amount > 0 ? .isSelected : [])
            .accessibilityValue(amount > 0 ? Text(verbatim: amountText(candidate)) : Text(verbatim: ""))
            .accessibilityIdentifier(rowIdentifier(candidate, index: index))
            quantityControl(candidate, amount: amount, index: index)
                .fixedSize()
        }
    }

    /// The typed text's own row reads "Add "Wago 221" as a new item"; a new
    /// item chosen under an earlier search reads its name over "New item".
    @ViewBuilder
    private func rowLabel(_ candidate: Candidate) -> some View {
        if isTypedRow(candidate) {
            Text(String(localized: "Add “\(candidate.name)” as a new item", comment: "Missing list: adds what was typed as a new item; the value is what was typed"))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: candidate.name)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = candidate.isNew ? Optional(String(localized: "New item")) : matchDetail(candidate) {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
        }
    }

    /// Just "+" at nothing; "−  2 pcs  +" once chosen, the amount in the
    /// accent and tappable to type one.
    private func quantityControl(_ candidate: Candidate, amount: Decimal, index: Int) -> some View {
        HStack(spacing: Metrics.tiny) {
            if amount > 0 {
                QuantityCircleButton(
                    systemImage: "minus",
                    isTinted: false,
                    label: String(localized: "One fewer: \(candidate.name)", comment: "Extra work stepper; the value is the item's name")
                ) {
                    selection.step(candidate, by: -1)
                }
                .accessibilityIdentifier("\(rowIdentifier(candidate, index: index))-minus")
                Button {
                    typedQuantity = ExtraWorkFormatting.quantity(amount)
                    typing = candidate
                } label: {
                    Text(verbatim: amountText(candidate))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "How many"))
                .accessibilityValue(Text(verbatim: amountText(candidate)))
                .accessibilityHint(String(localized: "Type an amount, such as 12.5."))
                .accessibilityIdentifier("\(rowIdentifier(candidate, index: index))-quantity")
            }
            QuantityCircleButton(
                systemImage: "plus",
                isTinted: true,
                label: String(localized: "One more: \(candidate.name)", comment: "Extra work stepper; the value is the item's name")
            ) {
                selection.step(candidate, by: 1)
            }
            .accessibilityIdentifier("\(rowIdentifier(candidate, index: index))-plus")
        }
    }

    /// The typed text's row keeps "missing-add-new"; every other row is a
    /// match by its place in the list. Its −, amount and + add "-minus",
    /// "-quantity" and "-plus": "missing-add-match-0-plus".
    private func rowIdentifier(_ candidate: Candidate, index: Int) -> String {
        isTypedRow(candidate) ? "missing-add-new" : "missing-add-match-\(index)"
    }

    private func isTypedRow(_ candidate: Candidate) -> Bool {
        candidate.isNew && candidate.key == Candidate(newName: trimmedQuery, unit: .pieces).key
    }

    /// "2 pcs", "2.5 m": in the unit chosen for a new item, else the item's.
    private func amountText(_ candidate: Candidate) -> String {
        let unit = selection.unit(of: candidate.key) ?? candidate.unit
        return "\(ExtraWorkFormatting.quantity(selection.quantity(of: candidate.key))) \(unit.name(in: .device))"
    }

    /// "scanned · used 3 times".
    private func matchDetail(_ candidate: Candidate) -> String? {
        guard let id = candidate.catalogItemID, let item = catalog.first(where: { $0.id == id }) else { return nil }
        let parts = [item.hasBarcode ? String(localized: "scanned") : nil, MaterialText.uses(item.useCount)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - State

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The rows chosen first, then the remembered items the search finds
    /// (this site's first; nothing typed shows the site's own), then the
    /// typed text as a new item.
    private var rows: [Candidate] {
        let found = ExtraWorkCatalog.search(query, in: catalog, siteID: site.id)
        let matches = trimmedQuery.isEmpty
            ? Array(found.filter { $0.siteIDs.contains(site.id) }.prefix(6))
            : Array(found.prefix(6))
        var candidates = matches.map { Candidate($0) }
        if canAddNew {
            candidates.append(Candidate(newName: trimmedQuery, unit: .pieces))
        }
        return selection.rows(matches: candidates)
    }

    /// Typed text that is not exactly an item already there.
    private var canAddNew: Bool {
        let key = ExtraWorkCatalog.key(trimmedQuery)
        return !key.isEmpty && !catalog.contains { ExtraWorkCatalog.key($0.name) == key }
    }

    /// "Add 3 items to missing"; just "Add to missing" with nothing chosen.
    private var saveTitle: String {
        let count = selection.count
        return count == 0
            ? String(localized: "Add to missing")
            : String(inflected: "Add ^[\(count) item](inflect: true) to missing")
    }

    private var typingBinding: Binding<Bool> {
        Binding(get: { typing != nil }, set: { if !$0 { typing = nil } })
    }

    private func unitBinding(_ key: MissingSelection.Key) -> Binding<String> {
        Binding(
            get: { selection.unit(of: key)?.code ?? ExtraWorkUnit.pieces.code },
            set: { selection.setUnit(ExtraWorkUnit(code: $0), for: key) }
        )
    }

    private func load() {
        catalog = ExtraWorkRepository(context: modelContext).catalog()
        crewNames = SiteRepository(context: modelContext)
            .crew(for: site.id, includeHidden: false)
            .map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if let initialCode, !handledInitialCode {
            handledInitialCode = true
            handle(initialCode)
        }
    }

    // MARK: - Scanning

    private func innerClosed() {
        guard let code = pendingCode else { return }
        pendingCode = nil
        handle(code)
    }

    /// A known code counts its item up by one and the sheet stays for the
    /// next box; one not named yet is named first.
    private func handle(_ code: String) {
        if let item = ExtraWorkCatalog.item(forCode: code, in: catalog) {
            selection.scanned(item)
        } else if let kept = ExtraWorkCatalog.code(code) {
            inner = .name(kept)
        }
    }

    // MARK: - Adding

    /// Every item chosen, with the one note: a new name is remembered first,
    /// so it is offered next time and in Settings › Materials (not counted
    /// as used, since no job used it).
    private func add() {
        let drafts = selection.drafts(note: note, notedBy: notedBy).map { draft -> MissingDraft in
            guard draft.catalogItemID == nil else { return draft }
            let remembered = ExtraWorkCatalogItem(name: draft.name, unit: draft.unit, useCount: 0, lastUsed: Date(), siteIDs: [site.id])
            ExtraWorkRepository(context: modelContext).storeCatalogItem(remembered)
            var stored = draft
            stored.catalogItemID = remembered.id
            return stored
        }
        guard !drafts.isEmpty else { return }
        MissingRepository(context: modelContext).add(drafts, siteID: site.id)
        onAdded()
        dismiss()
    }
}

/// A row's − or +: a 44 pt circle, the + tinted with the accent.
private struct QuantityCircleButton: View {
    let systemImage: String
    let isTinted: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(isTinted ? Color.accentColor : Color.primary)
                .frame(width: 44, height: 44)
                .background(isTinted ? Color.accentColor.opacity(0.15) : Color(uiColor: .tertiarySystemFill), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
