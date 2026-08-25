import SwiftUI

/// Manages day types.
///
/// Built-in types can be adjusted as well as added to: editing one stores an
/// override rather than mutating a constant, so "reset" is always available and
/// existing days keep working.
struct DayTypeSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    @State private var draft: Draft?

    /// A single sheet, carrying whether it is a new type or an existing one.
    private struct Draft: Identifiable {
        let definition: DayTypeDefinition
        let isNew: Bool
        var id: String { definition.id.rawValue }
    }

    var body: some View {
        List {
            Section {
                ForEach(settingsStore.settings.dayTypeCatalog.all) { definition in
                    Button {
                        draft = Draft(definition: definition, isNew: false)
                    } label: {
                        row(for: definition)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteCustom)
            } footer: {
                Text("How a type counts is what makes the balance right: paid absence credits your contracted hours, so a day of leave leaves the balance unchanged.")
            }

            Section {
                Button {
                    draft = Draft(definition: DayTypeEditor.blankDefinition(), isNew: true)
                } label: {
                    Label("Add a day type", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Day types")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $draft) { draft in
            DayTypeEditor(definition: draft.definition, isNew: draft.isNew)
        }
    }

    private func row(for definition: DayTypeDefinition) -> some View {
        HStack(spacing: Metrics.medium) {
            DayTypeBadge(definition: definition, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(definition.name)
                    .foregroundStyle(.primary)
                Text(expectationDescription(definition.expectation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isOverridden(definition) {
                Text("Edited")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func isOverridden(_ definition: DayTypeDefinition) -> Bool {
        DayTypeCatalog.isBuiltIn(definition.id)
            && settingsStore.settings.customDayTypes.contains { $0.id == definition.id }
    }

    private func deleteCustom(at offsets: IndexSet) {
        let all = settingsStore.settings.dayTypeCatalog.all
        let removable = offsets.compactMap { index -> DayTypeID? in
            guard index < all.count else { return nil }
            let definition = all[index]
            return DayTypeCatalog.isBuiltIn(definition.id) ? nil : definition.id
        }
        guard !removable.isEmpty else { return }
        settingsStore.update { settings in
            settings.customDayTypes.removeAll { removable.contains($0.id) }
        }
    }

    private func expectationDescription(_ policy: ExpectationPolicy) -> String {
        switch policy {
        case .scheduled: return "Counts as a working day"
        case .zero: return "Not a working day"
        case .creditedAbsence: return "Paid absence — credits your contracted hours"
        }
    }
}

/// Creates or edits one day type.
struct DayTypeEditor: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: DayTypeDefinition
    private let isNew: Bool

    init(definition: DayTypeDefinition, isNew: Bool) {
        _draft = State(initialValue: definition)
        self.isNew = isNew
    }

    static func blankDefinition() -> DayTypeDefinition {
        DayTypeDefinition(
            id: DayTypeID(UUID().uuidString),
            name: "",
            symbolName: "circle.fill",
            tint: .blue,
            expectation: .zero,
            showsTimesByDefault: true,
            sortOrder: 500
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                }

                Section("Counts as") {
                    Picker("Counts as", selection: $draft.expectation) {
                        Text("A working day").tag(ExpectationPolicy.scheduled)
                        Text("Paid absence").tag(ExpectationPolicy.creditedAbsence)
                        Text("Not a working day").tag(ExpectationPolicy.zero)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Colour") {
                    TintPicker(selection: $draft.tint)
                }

                Section("Symbol") {
                    SymbolPicker(selection: $draft.symbolName, tint: draft.tint.color)
                }

                Section {
                    Toggle("Show times by default", isOn: $draft.showsTimesByDefault)
                } footer: {
                    Text("Times can always be added to any day — working a public holiday should never be impossible to record.")
                }

                if !isNew && DayTypeCatalog.isBuiltIn(draft.id) {
                    Section {
                        Button("Reset to default", role: .destructive, action: resetBuiltIn)
                    }
                }
            }
            .navigationTitle(isNew ? "New day type" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        var definition = draft
        definition.name = definition.name.trimmingCharacters(in: .whitespacesAndNewlines)
        definition.isBuiltIn = DayTypeCatalog.isBuiltIn(definition.id)
        settingsStore.update { settings in
            settings.customDayTypes.removeAll { $0.id == definition.id }
            settings.customDayTypes.append(definition)
        }
        dismiss()
    }

    private func resetBuiltIn() {
        let id = draft.id
        settingsStore.update { settings in
            settings.customDayTypes.removeAll { $0.id == id }
        }
        dismiss()
    }
}

/// The colour choices, as a row of swatches.
struct TintPicker: View {
    @Binding var selection: TypeTint

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: Metrics.medium)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Metrics.medium) {
            ForEach(TypeTint.allCases, id: \.self) { tint in
                Button {
                    selection = tint
                } label: {
                    Circle()
                        .fill(tint.color)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if selection == tint {
                                Circle().strokeBorder(Color.primary, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tint.title)
                .accessibilityAddTraits(selection == tint ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, Metrics.tiny)
    }
}

/// A curated set of symbols. A full SF Symbols browser would be a worse
/// experience than a short list of ones that suit a working calendar.
struct SymbolPicker: View {
    @Binding var selection: String
    var tint: Color

    static let symbols: [String] = [
        "briefcase.fill", "building.2.fill", "house.fill", "laptopcomputer",
        "airplane", "beach.umbrella.fill", "sun.max.fill", "moon.stars.fill",
        "cross.case.fill", "heart.fill", "figure.walk", "figure.run",
        "person.fill", "person.2.fill", "graduationcap.fill", "book.fill",
        "flag.fill", "star.fill", "gift.fill", "party.popper.fill",
        "car.fill", "tram.fill", "hammer.fill", "wrench.and.screwdriver.fill",
        "phone.fill", "envelope.fill", "clock.fill", "square.dashed"
    ]

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: Metrics.medium)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Metrics.medium) {
            ForEach(SymbolPicker.symbols, id: \.self) { symbol in
                Button {
                    selection = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 17))
                        .foregroundStyle(selection == symbol ? Color.white : tint)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle().fill(selection == symbol ? tint : tint.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(selection == symbol ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, Metrics.tiny)
    }
}
