import SwiftUI
import SwiftData

/// Edits one day.
///
/// Opens on a draft: an existing day is loaded as it stands, a new one is
/// pre-filled from the schedule so the ordinary case is open-glance-save.
/// Nothing is written until Save, and saving a day with nothing in it deletes
/// it rather than storing an empty row.
struct DayEditorSheet: View {
    let date: CalendarDate

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    @Query private var holidayRecords: [HolidayRecord]

    @State private var draft: DayRecord
    @State private var storedRecord: DayRecord?
    @State private var hasLoaded = false
    @State private var isConfirmingDelete = false
    /// Set when a write is refused. Non-nil is the alert's own trigger, so a
    /// refusal cannot be recorded without being shown.
    @State private var refusal: Error?

    init(date: CalendarDate) {
        self.date = date
        _draft = State(initialValue: DayRecord(date: date))
    }

    var body: some View {
        NavigationStack {
            DayEditorForm(
                draft: $draft,
                computation: computation,
                settings: settingsStore.settings,
                calendar: settingsStore.workCalendar,
                formatting: settingsStore.dateFormatting
            )
            .navigationTitle(settingsStore.dateFormatting.mediumDate(date))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("day-editor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("day-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("day-editor-save")
                }
                if storedRecord != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete day", role: .destructive) { isConfirmingDelete = true }
                            .accessibilityIdentifier("day-editor-delete")
                    }
                }
            }
            .confirmationDialog(
                "Delete everything recorded for this day?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete day", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            }
            .alert(
                "This month is closed",
                isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })
            ) {
                Button("OK", role: .cancel) { refusal = nil }
            } message: {
                Text("Reopen it in Settings › Calculation if you need to change these hours.")
            }
            .task { load() }
        }
    }

    // MARK: - Derived

    private var holidays: [HolidayRule] { holidayRecords.map(\.rule) }

    private var computation: DayComputation {
        settingsStore.engine.day(date, record: draft, holidays: holidays)
    }

    private var repository: WorkdayRepository {
        WorkdayRepository(context: modelContext, lock: settingsStore.settings.monthLock)
    }

    // MARK: - Actions

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let stored = repository.record(on: date)
        storedRecord = stored
        draft = stored ?? settingsStore.engine.draftRecord(for: date, holidays: holidays)
    }

    private func save() {
        do {
            try repository.save(draft)
        } catch {
            // Stay on the sheet. Dismissing would look exactly like a
            // successful save, which is the failure this refusal exists to
            // prevent in the first place.
            refusal = error
            return
        }
        HoursStack.refreshWidget()
        dismiss()
    }

    private func delete() {
        do {
            try repository.delete(on: date)
        } catch {
            refusal = error
            return
        }
        HoursStack.refreshWidget()
        dismiss()
    }
}
