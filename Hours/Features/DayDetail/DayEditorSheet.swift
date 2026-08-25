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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
                if storedRecord != nil {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete day", role: .destructive) { isConfirmingDelete = true }
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
            .task { load() }
        }
    }

    // MARK: - Derived

    private var holidays: [HolidayRule] { holidayRecords.map(\.rule) }

    private var computation: DayComputation {
        settingsStore.engine.day(date, record: draft, holidays: holidays)
    }

    private var repository: WorkdayRepository { WorkdayRepository(context: modelContext) }

    // MARK: - Actions

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let stored = repository.record(on: date)
        storedRecord = stored
        draft = stored ?? settingsStore.engine.draftRecord(for: date, holidays: holidays)
    }

    private func save() {
        repository.save(draft)
        dismiss()
    }

    private func delete() {
        repository.delete(on: date)
        dismiss()
    }
}
