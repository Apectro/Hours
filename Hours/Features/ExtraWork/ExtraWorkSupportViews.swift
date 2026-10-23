import SwiftUI
import SwiftData

/// A new item for a job, or a remembered one renamed: its name and the unit
/// it is counted in — a built-in one, or one typed in, kept as typed.
struct ExtraWorkItemSheet: View {
    let title: String
    let onSave: (String, ExtraWorkUnit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var unitCode: String
    @State private var customUnit: String
    @FocusState private var nameFocused: Bool

    private static let other = "other"

    init(title: String, name: String, unit: ExtraWorkUnit, onSave: @escaping (String, ExtraWorkUnit) -> Void) {
        self.title = title
        self.onSave = onSave
        _name = State(initialValue: name)
        if case let .custom(text) = unit {
            _unitCode = State(initialValue: ExtraWorkItemSheet.other)
            _customUnit = State(initialValue: text)
        } else {
            _unitCode = State(initialValue: unit.code)
            _customUnit = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name, e.g. Junction box"), text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .accessibilityLabel(String(localized: "Name"))
                        .accessibilityIdentifier("extra-work-item-name")
                }
                Section {
                    Picker(selection: $unitCode) {
                        ForEach(ExtraWorkUnit.builtIn, id: \.code) { unit in
                            Text(verbatim: unit.name(in: .device)).tag(unit.code)
                        }
                        Text("Other unit").tag(ExtraWorkItemSheet.other)
                    } label: {
                        Text("Unit")
                    }
                    .accessibilityIdentifier("extra-work-item-unit")
                    if unitCode == ExtraWorkItemSheet.other {
                        TextField(String(localized: "Unit, e.g. roll"), text: $customUnit)
                            .accessibilityLabel(String(localized: "Unit"))
                            .accessibilityIdentifier("extra-work-item-custom-unit")
                    }
                } footer: {
                    Text("Remembered for next time, on every site.")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("extra-work-item-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        guard let unit else { return }
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), unit)
                        dismiss()
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("extra-work-item-done")
                }
            }
            .onAppear { nameFocused = name.isEmpty }
        }
        .presentationDetents([.medium, .large])
    }

    private var unit: ExtraWorkUnit? {
        unitCode == ExtraWorkItemSheet.other ? ExtraWorkUnit.typed(customUnit) : ExtraWorkUnit(code: unitCode)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && unit != nil
    }
}

/// The client signing on the supervisor's phone: who they are, and their
/// signature with a finger — the crew sign-off's canvas.
struct ExtraWorkSignSheet: View {
    let prompt: String
    let onSign: (ExtraWorkSignature) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var signer = ""
    @State private var strokes: [[SignaturePoint]] = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.medium) {
                TextField(String(localized: "Name and role, e.g. Ing. Horvat, site manager"), text: $signer)
                    .textContentType(.name)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(String(localized: "Who signs"))
                    .accessibilityIdentifier("extra-work-signer")

                HStack {
                    Text(verbatim: prompt)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: Metrics.small)
                    Button("Clear") { strokes = [] }
                        .disabled(strokes.isEmpty)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("extra-work-signature-clear")
                }
                SignatureCanvas(strokes: $strokes)
                    .accessibilityIdentifier("extra-work-signature-canvas")
                Spacer(minLength: 0)
            }
            .padding(Metrics.large)
            .background(Color.hoursCanvas)
            .navigationTitle("Client's signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("extra-work-signature-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign") {
                        onSign(ExtraWorkSignature(
                            signerName: signer.trimmingCharacters(in: .whitespacesAndNewlines),
                            signedAt: Date(),
                            strokes: strokes,
                            aspectRatio: SignatureCanvas.aspectRatio
                        ))
                        dismiss()
                    }
                    .disabled(!CrewSignature.isSignature(strokes))
                    .accessibilityIdentifier("extra-work-signature-sign")
                }
            }
        }
        // A downward stroke must not close the sheet halfway through a name.
        .interactiveDismissDisabled()
    }
}

/// The remembered items: renamed, given another unit, or forgotten.
struct ExtraWorkCatalogScreen: View {
    let onChange: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var items: [ExtraWorkCatalogItem] = []
    @State private var editing: ExtraWorkCatalogItem?

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    Button {
                        editing = item
                    } label: {
                        HStack {
                            Text(verbatim: item.name)
                                .foregroundStyle(.primary)
                            Spacer(minLength: Metrics.small)
                            Text(verbatim: item.unit.name(in: .device))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("extra-work-catalog-item")
                }
                .onDelete { offsets in
                    let repository = ExtraWorkRepository(context: modelContext)
                    for index in offsets { repository.removeCatalogItem(id: items[index].id) }
                    reload()
                }
            } footer: {
                Text("Offered under Material, the most recently used first. Removing one here does not change any job.")
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nothing remembered yet", systemImage: "shippingbox")
            }
        }
        .navigationTitle("Used before")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen-extra-work-items")
        .onAppear(perform: reload)
        .sheet(item: $editing) { item in
            ExtraWorkItemSheet(title: String(localized: "Edit item"), name: item.name, unit: item.unit) { name, unit in
                var changed = item
                changed.name = name
                changed.unit = unit
                ExtraWorkRepository(context: modelContext).storeCatalogItem(changed)
                reload()
            }
        }
    }

    private func reload() {
        items = ExtraWorkRepository(context: modelContext).catalog()
        onChange()
    }
}
