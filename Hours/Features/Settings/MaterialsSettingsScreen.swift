import SwiftUI
import SwiftData

/// Settings › More › Materials (Scanning board, phone 4): every item written
/// or scanned, with its unit, how often it was used and a barcode symbol when
/// it has a code. Search filters by name or code; the toolbar's scan finds
/// the item a box is (or names a new one). A tap opens the item to rename
/// it, change its unit, add or remove a barcode, or delete it.
struct MaterialsSettingsScreen: View {
    @Environment(\.modelContext) private var modelContext

    @State private var items: [ExtraWorkCatalogItem] = []
    @State private var query = ""
    /// One sheet at a time, chosen by value.
    @State private var sheet: MaterialsSheet?
    /// What a scan found, opened once the scanner's sheet has gone.
    @State private var afterScan: MaterialsSheet?
    /// The text the camera saw around the code scanned: a new code's name
    /// is offered from it.
    @State private var boxText: [RecognisedLine] = []

    private enum MaterialsSheet: Identifiable {
        case scan
        case name(String)
        case edit(ExtraWorkCatalogItem)

        var id: String {
            switch self {
            case .scan: return "scan"
            case let .name(code): return "name-\(code)"
            case let .edit(item): return "edit-\(item.id.uuidString)"
            }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    Button {
                        sheet = .edit(item)
                    } label: {
                        MaterialRow(item: item)
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("materials-item-\(index)")
                }
                .onDelete { offsets in
                    let repository = ExtraWorkRepository(context: modelContext)
                    for index in offsets { repository.removeCatalogItem(id: shown[index].id) }
                    reload()
                }
            } footer: {
                if !items.isEmpty {
                    Text("Tap one to rename it, change its unit, or add a second barcode.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label("No materials yet", systemImage: "shippingbox")
                } description: {
                    Text("Items you add to extra work, or scan, appear here.")
                }
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: Text("Search"))
        .navigationTitle("Materials")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("screen-materials")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    sheet = .scan
                } label: {
                    Image(systemName: "barcode.viewfinder")
                }
                .accessibilityLabel(String(localized: "Scan to find"))
                .accessibilityIdentifier("materials-scan")
            }
        }
        .onAppear(perform: reload)
        .sheet(item: $sheet, onDismiss: sheetClosed) { sheet in
            switch sheet {
            case .scan:
                BarcodeScanSheet(title: String(localized: "Scan to find"), onCode: found, onBoxText: { lines in boxText = lines })
            case let .name(code):
                NewScannedItemSheet(
                    code: code,
                    saveTitle: String(localized: "Save"),
                    suggestions: BoxTextSuggestions.names(from: boxText, code: code)
                ) { name, unit in
                    ExtraWorkRepository(context: modelContext).nameCode(code, name: name, unit: unit)
                    reload()
                }
            case let .edit(item):
                MaterialEditorSheet(item: item)
            }
        }
    }

    private func sheetClosed() {
        reload()
        if let next = afterScan {
            afterScan = nil
            sheet = next
        }
    }

    /// Search by name or code, as the catalogue searches; the most used first.
    private var shown: [ExtraWorkCatalogItem] {
        ExtraWorkCatalog.search(query, in: items, siteID: nil)
    }

    private func reload() {
        items = ExtraWorkRepository(context: modelContext).catalog()
    }

    /// A scanned box: its item opens; a code not named yet is named here —
    /// once the scanner's sheet has gone (`sheetClosed`).
    private func found(_ code: String) {
        if let item = ExtraWorkCatalog.item(forCode: code, in: items) {
            afterScan = .edit(item)
        } else if let kept = ExtraWorkCatalog.code(code) {
            afterScan = .name(kept)
        }
    }
}

/// "LED panel 60×60" over "pcs · used 14 times", and a barcode symbol when
/// it has a code.
struct MaterialRow: View {
    let item: ExtraWorkCatalogItem

    var body: some View {
        HStack(spacing: Metrics.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.name)
                    .foregroundStyle(.primary)
                Text(verbatim: MaterialText.detail(item))
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if item.hasBarcode {
                Image(systemName: "barcode")
                    .foregroundStyle(.hoursSecondaryText)
                    .accessibilityLabel(String(localized: "Has a barcode"))
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The words under a remembered item's name.
enum MaterialText {
    /// "used once", "used 3 times"; nothing before it was used.
    static func uses(_ count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1: return String(localized: "used once", comment: "A remembered item: how often it was used")
        default: return String(localized: "used \(count) times", comment: "A remembered item: how often it was used; the value is 2 or more")
        }
    }

    /// "pcs · used 14 times".
    static func detail(_ item: ExtraWorkCatalogItem) -> String {
        [item.unit.name(in: .device), uses(item.useCount)].compactMap { $0 }.joined(separator: " · ")
    }
}

/// One remembered item: its name, its unit, its barcodes (scanned or typed;
/// swipe one away to remove it), and Delete.
struct MaterialEditorSheet: View {
    let item: ExtraWorkCatalogItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var unitCode: String
    @State private var customUnit: String
    @State private var barcodes: [String]
    @State private var isScanning = false
    @State private var isTypingCode = false
    @State private var typedCode = ""
    @State private var confirmsDelete = false

    private static let other = "other"

    init(item: ExtraWorkCatalogItem) {
        self.item = item
        _name = State(initialValue: item.name)
        _barcodes = State(initialValue: item.barcodes)
        if case let .custom(text) = item.unit {
            _unitCode = State(initialValue: MaterialEditorSheet.other)
            _customUnit = State(initialValue: text)
        } else {
            _unitCode = State(initialValue: item.unit.code)
            _customUnit = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    HStack(spacing: Metrics.small) {
                        TextField(String(localized: "Name, e.g. Junction box"), text: $name)
                            .accessibilityLabel(String(localized: "Name"))
                            .accessibilityIdentifier("materials-name")
                        ScanTextButton(identifier: "materials-scan-text") { text in
                            name = text
                        }
                    }
                }
                Section {
                    Picker(selection: $unitCode) {
                        ForEach(ExtraWorkUnit.builtIn, id: \.code) { unit in
                            Text(verbatim: unit.name(in: .device)).tag(unit.code)
                        }
                        Text("Other unit").tag(MaterialEditorSheet.other)
                    } label: {
                        Text("Unit")
                    }
                    .accessibilityIdentifier("materials-unit")
                    if unitCode == MaterialEditorSheet.other {
                        TextField(String(localized: "Unit, e.g. roll"), text: $customUnit)
                            .accessibilityLabel(String(localized: "Unit"))
                    }
                }
                Section {
                    ForEach(barcodes, id: \.self) { code in
                        Label {
                            Text(verbatim: code)
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "barcode")
                                .foregroundStyle(.hoursSecondaryText)
                        }
                    }
                    .onDelete { offsets in barcodes.remove(atOffsets: offsets) }
                    Button {
                        isScanning = true
                    } label: {
                        Label("Scan a barcode", systemImage: "barcode.viewfinder")
                    }
                    .accessibilityIdentifier("materials-add-scan")
                    Button {
                        typedCode = ""
                        isTypingCode = true
                    } label: {
                        Label("Type a barcode", systemImage: "keyboard")
                    }
                    .accessibilityIdentifier("materials-add-typed")
                } header: {
                    Text("Barcodes")
                } footer: {
                    Text("A code belongs to one item: given to this one, it leaves any other.")
                }
                Section {
                    Button("Delete this item", role: .destructive) { confirmsDelete = true }
                        .accessibilityIdentifier("materials-delete")
                } footer: {
                    Text("Jobs that used it keep it as they were written.")
                }
            }
            .navigationTitle(Text(verbatim: item.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Cancel"))
                    .accessibilityIdentifier("materials-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(String(localized: "Save"))
                    .disabled(!canSave)
                    .accessibilityIdentifier("materials-save")
                }
            }
            .sheet(isPresented: $isScanning) {
                BarcodeScanSheet(title: String(localized: "Scan a barcode")) { code in
                    add(code)
                }
            }
            .alert("Type a barcode", isPresented: $isTypingCode) {
                TextField(String(localized: "Code under the barcode"), text: $typedCode)
                    .keyboardType(.asciiCapable)
                    .accessibilityIdentifier("materials-code-field")
                Button("Cancel", role: .cancel) {}
                Button("Add") { add(typedCode) }
            }
            .confirmationDialog("Delete this item?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    ExtraWorkRepository(context: modelContext).removeCatalogItem(id: item.id)
                    dismiss()
                }
            } message: {
                Text("It is no longer offered under Material, and its barcodes are forgotten.")
            }
        }
    }

    private var unit: ExtraWorkUnit? {
        unitCode == MaterialEditorSheet.other ? ExtraWorkUnit.typed(customUnit) : ExtraWorkUnit(code: unitCode)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && unit != nil
    }

    private func add(_ raw: String) {
        guard let code = ExtraWorkCatalog.code(raw), !barcodes.contains(code) else { return }
        barcodes.append(code)
    }

    /// The name and unit as edited, and the codes: those added taken off any
    /// other item, those removed forgotten.
    private func save() {
        guard canSave, let unit else { return }
        let repository = ExtraWorkRepository(context: modelContext)
        var changed = item
        changed.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        changed.unit = unit
        changed.barcodes = item.barcodes.filter(barcodes.contains)
        repository.storeCatalogItem(changed)
        for code in barcodes where !item.barcodes.contains(code) {
            repository.addCode(code, to: item.id)
        }
        dismiss()
    }
}
