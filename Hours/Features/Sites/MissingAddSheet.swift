import SwiftUI
import SwiftData

/// "Something's missing" (Missing board, phone 7): a search field over the
/// remembered items (this site's first), the matches with a checkmark on the
/// one chosen, "Add "junc" as a new item", how many in the item's unit, where
/// or why, who noticed, and Add to missing. The toolbar's scan picks the
/// item a box is; a code not named yet is named once (`NewScannedItemSheet`).
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

    @State private var catalog: [ExtraWorkCatalogItem] = []
    @State private var crewNames: [String] = []
    @State private var query = ""
    @State private var choice: Choice?
    @State private var quantity: Decimal = 1
    @State private var newUnitCode = ExtraWorkUnit.pieces.code
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
    @State private var showsQuantityAlert = false
    @State private var typedQuantity = ""
    @FocusState private var searchFocused: Bool

    private enum Choice: Hashable {
        case item(ExtraWorkCatalogItem)
        case new(String)

        var name: String {
            switch self {
            case let .item(item): return item.name
            case let .new(name): return name
            }
        }
    }

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

                if !matches.isEmpty || canAddNew {
                    Section {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, item in
                            Button {
                                choose(item)
                            } label: {
                                matchRow(item)
                            }
                            .tint(.primary)
                            .accessibilityAddTraits(isChosen(item) ? .isSelected : [])
                            .accessibilityIdentifier("missing-add-match-\(index)")
                        }
                        if canAddNew {
                            Button {
                                choice = .new(trimmedQuery)
                            } label: {
                                HStack {
                                    Text(String(localized: "Add “\(trimmedQuery)” as a new item", comment: "Missing list: adds what was typed as a new item; the value is what was typed"))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if case .new = choice {
                                        chosenMark
                                    }
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("missing-add-new")
                        }
                    } header: {
                        if !matches.isEmpty {
                            Text("From your list")
                        }
                    }
                }

                if let choice {
                    Section("How many") {
                        quantityRow(choice)
                        if case .new = choice {
                            Picker(selection: $newUnitCode) {
                                ForEach(ExtraWorkScan.units, id: \.code) { unit in
                                    Text(verbatim: unit.name(in: .device)).tag(unit.code)
                                }
                            } label: {
                                Text("Counted in")
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("missing-add-unit")
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
                    Text("Add to missing")
                }
                .buttonStyle(.bigAction(.primary))
                .accessibilityIdentifier("missing-add-save")
                .disabled(choice == nil || quantity <= 0)
                .padding(.horizontal, Metrics.large)
                .padding(.vertical, Metrics.small)
                .background(Color.hoursCanvas)
            }
            .alert("How many", isPresented: $showsQuantityAlert) {
                TextField(String(localized: "Quantity"), text: $typedQuantity)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("missing-add-quantity-field")
                Button("Cancel", role: .cancel) {}
                Button("OK") {
                    if let value = ExtraWorkQuantity.parse(typedQuantity), value > 0 { quantity = value }
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
                    choose(catalog.first { $0.id == item.id } ?? item)
                }
            }
        }
    }

    // MARK: - Rows

    private func matchRow(_ item: ExtraWorkCatalogItem) -> some View {
        HStack(spacing: Metrics.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                    .foregroundStyle(.primary)
                if let detail = matchDetail(item) {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isChosen(item) {
                chosenMark
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var chosenMark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title3)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel(String(localized: "Chosen"))
    }

    /// "scanned · used 3 times".
    private func matchDetail(_ item: ExtraWorkCatalogItem) -> String? {
        let parts = [item.hasBarcode ? String(localized: "scanned") : nil, MaterialText.uses(item.useCount)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The chosen item's name with −, the amount in its unit, and +.
    private func quantityRow(_ choice: Choice) -> some View {
        HStack(spacing: Metrics.small) {
            Text(verbatim: choice.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            RoundStepButton(
                systemImage: "minus",
                isProminent: false,
                label: String(localized: "One fewer: \(choice.name)", comment: "Extra work stepper; the value is the item's name")
            ) {
                quantity = max(1, ExtraWorkQuantity.stepped(quantity, by: -1))
            }
            .disabled(quantity <= 1)
            .accessibilityIdentifier("missing-add-minus")
            Button {
                typedQuantity = ExtraWorkFormatting.quantity(quantity)
                showsQuantityAlert = true
            } label: {
                Text(verbatim: "\(ExtraWorkFormatting.quantity(quantity)) \(unit.name(in: .device))")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: 60, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "How many"))
            .accessibilityValue(Text(verbatim: "\(ExtraWorkFormatting.quantity(quantity)) \(unit.name(in: .device))"))
            .accessibilityHint(String(localized: "Type an amount, such as 12.5."))
            .accessibilityIdentifier("missing-add-quantity")
            RoundStepButton(
                systemImage: "plus",
                isProminent: true,
                label: String(localized: "One more: \(choice.name)", comment: "Extra work stepper; the value is the item's name")
            ) {
                quantity = ExtraWorkQuantity.stepped(quantity, by: 1)
            }
            .accessibilityIdentifier("missing-add-plus")
        }
    }

    // MARK: - State

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The remembered items the search finds, this site's first. Nothing
    /// typed shows the site's own.
    private var matches: [ExtraWorkCatalogItem] {
        let found = ExtraWorkCatalog.search(query, in: catalog, siteID: site.id)
        if trimmedQuery.isEmpty {
            return Array(found.filter { $0.siteIDs.contains(site.id) }.prefix(6))
        }
        return Array(found.prefix(6))
    }

    /// Typed text that is not exactly an item already there.
    private var canAddNew: Bool {
        let key = ExtraWorkCatalog.key(trimmedQuery)
        return !key.isEmpty && !catalog.contains { ExtraWorkCatalog.key($0.name) == key }
    }

    private var unit: ExtraWorkUnit {
        switch choice {
        case let .item(item): return item.unit
        case .new, nil: return ExtraWorkUnit(code: newUnitCode)
        }
    }

    private func isChosen(_ item: ExtraWorkCatalogItem) -> Bool {
        if case let .item(chosen) = choice { return chosen.id == item.id }
        return false
    }

    private func choose(_ item: ExtraWorkCatalogItem) {
        choice = .item(item)
        searchFocused = false
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

    /// A known code picks its item; one not named yet is named first.
    private func handle(_ code: String) {
        if let item = ExtraWorkCatalog.item(forCode: code, in: catalog) {
            choose(item)
        } else if let kept = ExtraWorkCatalog.code(code) {
            inner = .name(kept)
        }
    }

    // MARK: - Adding

    private func add() {
        guard let choice, quantity > 0 else { return }
        let draft: MissingDraft
        switch choice {
        case let .item(item):
            draft = MissingDraft(name: item.name, quantity: quantity, unit: item.unit, note: note, notedBy: notedBy, catalogItemID: item.id)
        case let .new(name):
            // Remembered, so it is offered next time and in Settings ›
            // Materials; not counted as used, since no job used it.
            let remembered = ExtraWorkCatalogItem(name: name, unit: unit, useCount: 0, lastUsed: Date(), siteIDs: [site.id])
            ExtraWorkRepository(context: modelContext).storeCatalogItem(remembered)
            draft = MissingDraft(name: name, quantity: quantity, unit: unit, note: note, notedBy: notedBy, catalogItemID: remembered.id)
        }
        MissingRepository(context: modelContext).add(draft, siteID: site.id)
        onAdded()
        dismiss()
    }
}
