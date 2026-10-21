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
    @Query private var siteEntries: [SiteEntry]

    @State private var draft: DayRecord
    @State private var storedRecord: DayRecord?
    @State private var hasLoaded = false
    @State private var isConfirmingDelete = false
    /// Set when a write is refused. Non-nil is the alert's own trigger, so a
    /// refusal cannot be recorded without being shown.
    @State private var refusal: Error?
    /// The site screens pushed from here: a site shift's day, and from it
    /// the site's crew. A path of values, like the Sites tab, rather than a
    /// presented binding: mixing the two kinds of destination in one stack
    /// is what hung the site screen when it was opened from the Sites tab.
    @State private var path = NavigationPath()

    init(date: CalendarDate) {
        self.date = date
        _draft = State(initialValue: DayRecord(date: date))
    }

    var body: some View {
        NavigationStack(path: $path) {
            DayEditorForm(
                draft: $draft,
                computation: computation,
                settings: settingsStore.settings,
                calendar: settingsStore.workCalendar,
                formatting: settingsStore.dateFormatting,
                siteNames: siteNames,
                onOpenSite: { path.append(SiteRoute(siteID: $0)) }
            )
            .navigationDestination(for: SiteRoute.self) { route in
                SiteDetailScreen(siteID: route.siteID, initialDate: date)
            }
            .navigationDestination(for: SiteCrewRoute.self) { route in
                CrewScreen(siteID: route.siteID)
            }
            .onChange(of: path.count) { _, depth in
                // Back from the site, which may have changed your hours there.
                if depth == 0 { refreshSiteShifts() }
            }
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
                "Delete this day? Hours written on a site stay.",
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
        // The site screen's menu opens the crew through this, onto the same
        // path of values (see `OpenSiteCrewAction`).
        .environment(\.openSiteCrew, OpenSiteCrewAction { path.append($0) })
    }

    // MARK: - Derived

    private var holidays: [HolidayRule] { holidayRecords.map(\.rule) }

    private var computation: DayComputation {
        settingsStore.engine.day(date, record: draft, holidays: holidays)
    }

    private var siteNames: [UUID: String] {
        Dictionary(siteEntries.map { ($0.site.id, $0.site.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// Your hours from site days, as stored right now.
    private func storedSiteShifts() -> [Shift] {
        repository.record(on: date)?.shifts.filter { $0.siteID != nil } ?? []
    }

    /// Site shifts belong to their site days, so the draft never decides
    /// them: whatever it holds is replaced with what is stored. Without this a
    /// draft opened before the site day changed would write the old hours
    /// back over your calendar, and the site and your calendar would disagree.
    private func withStoredSiteShifts(_ record: DayRecord) -> DayRecord {
        var record = record
        record.shifts = record.shifts.filter { $0.siteID == nil } + storedSiteShifts()
        return record
    }

    private func refreshSiteShifts() {
        draft = withStoredSiteShifts(draft)
        storedRecord = repository.record(on: date)
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
            try repository.save(withStoredSiteShifts(draft))
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
            // Your site hours stay: they go when the site day does, on the
            // site. Everything typed in here is deleted.
            let siteShifts = storedSiteShifts()
            if siteShifts.isEmpty {
                try repository.delete(on: date)
            } else {
                try repository.save(DayRecord(date: date, shifts: siteShifts))
            }
        } catch {
            refusal = error
            return
        }
        HoursStack.refreshWidget()
        dismiss()
    }
}
