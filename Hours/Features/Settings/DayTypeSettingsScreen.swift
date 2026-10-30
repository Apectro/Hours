import SwiftUI
import SwiftData

/// Manages day types (1.2 redesign, board 17).
///
/// Built-in types can be adjusted as well as added to: editing one stores an
/// override rather than mutating a constant, so "reset" is always available and
/// existing days keep working.
///
/// With `showsHolidays` it is Settings › Day types & holidays: the types,
/// then the public holidays and your own days off under them.
struct DayTypeSettingsScreen: View {
    var showsHolidays = false

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext

    @State private var draft: Draft?
    @State private var pendingDeletion: PendingDeletion?

    /// A single sheet, carrying whether it is a new type or an existing one.
    private struct Draft: Identifiable {
        let definition: DayTypeDefinition
        let isNew: Bool
        var id: String { definition.id.rawValue }
    }

    /// A deletion held back because recorded days already point at the type.
    private struct PendingDeletion: Identifiable {
        let types: [DayTypeID]
        let name: String
        let dayCount: Int
        var id: String { types.map(\.rawValue).joined(separator: ",") }
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
                    .accessibilityIdentifier("day-types-row")
                }
                .onDelete(perform: deleteCustom)

                Button {
                    draft = Draft(definition: DayTypeEditor.blankDefinition(), isNew: true)
                } label: {
                    Label("Add a day type", systemImage: "plus")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("day-types-add")
            } header: {
                Text("Day types")
            } footer: {
                Text("How a type counts is what makes the balance right: paid absence credits your contracted hours, so a day of leave leaves the balance unchanged.")
            }

            if showsHolidays && settingsStore.settings.features.trackHolidays {
                HolidayRowsSection()
            }
        }
        .navigationTitle(showsHolidays ? "Day types & holidays" : "Day types")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $draft) { draft in
            DayTypeEditor(definition: draft.definition, isNew: draft.isNew)
        }
        .alert(
            "This day type is still in use",
            isPresented: deletionConfirmationBinding,
            presenting: pendingDeletion
        ) { pending in
            Button("Delete anyway", role: .destructive) {
                remove(pending.types)
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { pending in
            Text(String(
                inflected: "^[\(pending.dayCount) day](inflect: true) still use “\(pending.name)”. Those days will show as Unknown and stop counting towards your balance. The hours recorded on them are kept."
            ))
        }
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in if !isPresented { pendingDeletion = nil } }
        )
    }

    /// "Sick leave · paid", as the mockup lists them: the badge, the name,
    /// and in grey how the day counts.
    private func row(for definition: DayTypeDefinition) -> some View {
        HStack(spacing: Metrics.medium) {
            DayTypeBadge(definition: definition, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(definition.displayName())
                    .foregroundStyle(.primary)
                if isOverridden(definition) {
                    Text("Edited")
                        .font(.caption)
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
            Spacer(minLength: Metrics.small)
            Text(expectationDescription(definition))
                .font(.subheadline)
                .foregroundStyle(.hoursSecondaryText)
                .multilineTextAlignment(.trailing)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private func isOverridden(_ definition: DayTypeDefinition) -> Bool {
        DayTypeCatalog.isBuiltIn(definition.id)
            && settingsStore.settings.customDayTypes.contains { $0.id == definition.id }
    }

    private func deleteCustom(at offsets: IndexSet) {
        let all = settingsStore.settings.dayTypeCatalog.all
        let removable = offsets.compactMap { index -> DayTypeDefinition? in
            guard index < all.count else { return nil }
            let definition = all[index]
            return DayTypeCatalog.isBuiltIn(definition.id) ? nil : definition
        }
        guard !removable.isEmpty else { return }

        // A day whose type no longer exists resolves to "Unknown", which
        // expects nothing and credits nothing. So deleting a type that ten days
        // of paid leave point at moves the balance by eighty hours — from a
        // settings screen, with a swipe, and nothing to undo it. Days already
        // recorded are not this screen's to change without asking.
        let repository = WorkdayRepository(context: modelContext)
        let affected = removable.reduce(0) { $0 + repository.dayCount(using: $1.id) }
        guard affected > 0 else {
            remove(removable.map(\.id))
            return
        }
        pendingDeletion = PendingDeletion(
            types: removable.map(\.id),
            name: removable.count == 1 ? removable[0].name : String(localized: "those types"),
            dayCount: affected
        )
    }

    private func remove(_ types: [DayTypeID]) {
        settingsStore.update { settings in
            settings.customDayTypes.removeAll { types.contains($0.id) }
        }
    }

    /// "working day", "paid", "paid at 70%", "not working".
    private func expectationDescription(_ definition: DayTypeDefinition) -> String {
        switch definition.expectation {
        case .scheduled:
            return String(localized: "working day", comment: "Settings › Day types: how a type counts")
        case .zero:
            return String(localized: "not working", comment: "Settings › Day types: how a type counts")
        case .creditedAbsence:
            guard definition.paidPercent < 100 else {
                return String(localized: "paid", comment: "Settings › Day types: a paid absence")
            }
            // Formatted first: a bare % beside a placeholder makes the key
            // ambiguous.
            let share = definition.paidPercent.formatted(.percent.scale(1))
            return String(localized: "paid at \(share)", comment: "Settings › Day types: a paid absence paid in part; the value is like 70%")
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

                Section {
                    Picker("Counts as", selection: $draft.expectation) {
                        Text("Working day").tag(ExpectationPolicy.scheduled)
                        Text("Paid absence").tag(ExpectationPolicy.creditedAbsence)
                        Text("Not working").tag(ExpectationPolicy.zero)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("day-type-counts-as")
                } header: {
                    Text("Counts as")
                } footer: {
                    Text(countsAsFooter)
                }

                if draft.expectation == .creditedAbsence {
                    paySection
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
                        .accessibilityIdentifier("day-type-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("day-type-editor-save")
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Pay

    /// What a day of paid absence earns: its credited hours at the rate,
    /// times this. Money only — the hours and the balance stay as they are.
    private var paySection: some View {
        Section {
            HStack(spacing: Metrics.small) {
                Text("Share of a normal day")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Metrics.small)
                Button {
                    draft.paidPercent = max(0, draft.paidPercent - 5)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(draft.paidPercent <= 0)
                // "Less, paid at, 70%": what it changes and where it stands.
                .accessibilityLabel(Text("Less") + Text(verbatim: ", ") + Text("Paid at"))
                .accessibilityValue(Text(verbatim: "\(draft.paidPercent)%"))
                .accessibilityIdentifier("day-type-paid-at-down")
                Text(verbatim: "\(draft.paidPercent)%")
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 52)
                Button {
                    draft.paidPercent = min(100, draft.paidPercent + 5)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(draft.paidPercent >= 100)
                .accessibilityLabel(Text("More") + Text(verbatim: ", ") + Text("Paid at"))
                .accessibilityValue(Text(verbatim: "\(draft.paidPercent)%"))
                .accessibilityIdentifier("day-type-paid-at-up")
            }

            if draft.id == .sick {
                Toggle("Employer pays the first 42 days", isOn: $draft.employerPaysFirst42Days)
                    .accessibilityIdentifier("day-type-employer-42-days")
            }
        } header: {
            Text("Paid at")
        } footer: {
            if draft.id == .sick {
                // The percentage goes in as a value: a bare "%" in a key is
                // read as the start of a format.
                let seventy = "70%"
                Text(String(
                    localized: "In Croatia sick leave is paid at least \(seventy) for the first 42 days, then by HZZO; a work injury is paid in full. Check your contract: the app uses your hourly rate, not your average pay.",
                    comment: "Footer under Sick's pay in Settings › Day types; the value is 70%"
                ))
            } else {
                Text("Only what the day earns changes: the hours it credits and your balance stay the same.")
            }
        }
    }

    /// What the chosen way of counting does to the balance.
    private var countsAsFooter: String {
        switch draft.expectation {
        case .scheduled: return String(localized: "A day of this type expects your normal hours.")
        case .creditedAbsence: return String(localized: "Your normal hours are credited, so the balance stays the same.")
        case .zero: return String(localized: "Nothing is expected and nothing is credited.")
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

    private static let columns = [GridItem(.adaptive(minimum: 44), spacing: Metrics.medium)]

    var body: some View {
        LazyVGrid(columns: TintPicker.columns, spacing: Metrics.medium) {
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
                        // The swatch stays 30pt; what you can hit is 44,
                        // which is the smallest target the HIG allows. They
                        // were the same size, so a third of the intended
                        // target was not there.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
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

    private static let columns = [GridItem(.adaptive(minimum: 44), spacing: Metrics.medium)]

    var body: some View {
        LazyVGrid(columns: SymbolPicker.columns, spacing: Metrics.medium) {
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(selection == symbol ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, Metrics.tiny)
    }
}
