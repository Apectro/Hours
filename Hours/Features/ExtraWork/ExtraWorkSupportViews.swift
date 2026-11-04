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
                    HStack(spacing: Metrics.small) {
                        TextField(String(localized: "Name, e.g. Junction box"), text: $name)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .accessibilityLabel(String(localized: "Name"))
                            .accessibilityIdentifier("extra-work-item-name")
                        ScanTextButton(identifier: "extra-work-item-scan-text") { text in
                            name = text
                        }
                    }
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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Cancel"))
                    .accessibilityIdentifier("extra-work-item-cancel")
                }
                // It commits: Save, as every sheet that writes something.
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let unit else { return }
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), unit)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .disabled(!canSave)
                    .accessibilityLabel(String(localized: "Save"))
                    .accessibilityIdentifier("extra-work-item-save")
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

/// The client signing on the supervisor's phone (Extra work board, phone
/// 4): who signs and what they sign for, in a form, and Sign at the bottom,
/// which opens the full-screen pad (`SignaturePad`, 1.3) the crew signs on.
struct ExtraWorkSignSheet: View {
    let prompt: String
    /// "3 jobs · 26–29 Oct · 4h 30m": what is being signed for.
    var summary: String = ""
    let onSign: (ExtraWorkSignature) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var signer = ""
    @State private var showsPad = false
    /// What the pad handed back, signed once the pad has closed.
    @State private var signed: [[SignaturePoint]]?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.medium) {
                Form {
                    Section {
                        TextField(String(localized: "Name and role, e.g. Ing. Horvat, site manager"), text: $signer)
                            .textContentType(.name)
                            .accessibilityLabel(String(localized: "Who signs"))
                            .accessibilityIdentifier("extra-work-signer")
                    } header: {
                        Text("Who signs")
                            .textCase(nil)
                    } footer: {
                        if !summary.isEmpty {
                            Text(verbatim: summary)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)

                // Signing itself is full screen, in landscape on a phone
                // (1.3): more room for a finger than a strip under the name.
                Button {
                    showsPad = true
                } label: {
                    Label("Sign", systemImage: "signature")
                }
                .buttonStyle(.bigAction(.primary))
                .accessibilityIdentifier("extra-work-signature-open")
                .padding(.horizontal, Metrics.large)
                .padding(.bottom, Metrics.small)
            }
            .background(Color.hoursCanvas)
            .navigationTitle("Client's signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Sign at the bottom is the one way to confirm.
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Cancel"))
                    .accessibilityIdentifier("extra-work-signature-cancel")
                }
            }
        }
        .fullScreenCover(isPresented: $showsPad, onDismiss: {
            guard let signed, CrewSignature.isSignature(signed) else { return }
            onSign(ExtraWorkSignature(
                signerName: signerName,
                signedAt: Date(),
                strokes: signed,
                aspectRatio: SignatureFit.boxAspectRatio
            ))
            dismiss()
        }) {
            SignaturePad(caption: padCaption, identifierPrefix: "extra-work-signature") { strokes in
                signed = strokes
            }
        }
        .interactiveDismissDisabled(showsPad)
    }

    private var signerName: String {
        signer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Ing. Horvat, site manager · Sign to confirm these jobs".
    private var padCaption: String {
        signerName.isEmpty ? prompt : "\(signerName) · \(prompt)"
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
                                .foregroundStyle(.hoursSecondaryText)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("extra-work-catalog-item")
                    // 1.3: the swipe the rows always had, drawn as Missing's are.
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            ExtraWorkRepository(context: modelContext).removeCatalogItem(id: item.id)
                            reload()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .accessibilityIdentifier("extra-work-catalog-item-swipe-delete")
                    }
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
