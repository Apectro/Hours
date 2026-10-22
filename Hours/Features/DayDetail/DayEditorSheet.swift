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
    /// "I worked" on a public holiday: a day with nothing typed in opens
    /// with the week's times, its type left as it resolves so the holiday
    /// is still paid.
    var startsWorking = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    @Query private var holidayRecords: [HolidayRecord]
    @Query private var siteEntries: [SiteEntry]

    @State private var draft: DayRecord
    @State private var storedRecord: DayRecord?
    @State private var hasLoaded = false
    /// The stored days of this day's week, read once on opening: a day's
    /// overtime after the contracted week depends on the days before it.
    @State private var weekRecords: [Int: DayRecord] = [:]
    /// The stored days of this day's leave year, read once on opening, for
    /// the "vacation left" line under the day type.
    @State private var leaveYearRecords: [Int: DayRecord] = [:]
    @State private var isConfirmingDelete = false
    /// Set when a write is refused. Non-nil is the alert's own trigger, so a
    /// refusal cannot be recorded without being shown.
    @State private var refusal: Error?
    /// The site screens pushed from here: a site shift's day, and from it
    /// the site's crew. A path of values, like the Sites tab, rather than a
    /// presented binding: mixing the two kinds of destination in one stack
    /// is what hung the site screen when it was opened from the Sites tab.
    @State private var path = NavigationPath()

    init(date: CalendarDate, startsWorking: Bool = false) {
        self.date = date
        self.startsWorking = startsWorking
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
                onOpenSite: { path.append(SiteRoute(siteID: $0)) },
                earnings: earnings,
                vacationLeft: vacationLeft
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

    /// What the day as drafted earns, while earnings are the main figure.
    /// The rest of the week is as stored; this day is the draft.
    private var earnings: DayEarnings? {
        guard settingsStore.settings.showsEarnings else { return nil }
        var records = weekRecords
        records[date.key] = draft
        return settingsStore.engine
            .earnings(in: CalendarDateRange(single: date), records: records, holidays: holidays)?
            .days.first
    }

    /// Vacation left in the leave year once this day is saved as drafted.
    /// Only while the day is a vacation day: the line is about that choice.
    private var vacationLeft: HalfDays? {
        guard computation.dayType.id == .vacation else { return nil }
        let settings = settingsStore.settings
        let calendar = settingsStore.workCalendar
        let leaveYear = settings.leave.leaveYear(containing: date, calendar: calendar)
        var records = leaveYearRecords
        records[date.key] = draft
        let days = settingsStore.engine.days(
            in: settings.leave.range(ofLeaveYear: leaveYear, calendar: calendar),
            records: records,
            holidays: holidays
        )
        return LeaveCalculator.balance(
            leaveYear: leaveYear,
            days: days,
            settings: settings,
            calendar: calendar,
            today: CalendarDate.today(in: calendar)
        ).remaining
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
        if settingsStore.settings.showsEarnings {
            weekRecords = repository.records(in: settingsStore.engine.earningsRange(covering: CalendarDateRange(single: date)))
        }
        let calendar = settingsStore.workCalendar
        let leave = settingsStore.settings.leave
        leaveYearRecords = repository.records(
            in: leave.range(ofLeaveYear: leave.leaveYear(containing: date, calendar: calendar), calendar: calendar)
        )
        draft = stored ?? settingsStore.engine.draftRecord(for: date, holidays: holidays, working: startsWorking)
        if startsWorking, !draft.shifts.contains(where: { $0.siteID == nil }), draft.manualWorkedMinutes == nil {
            draft.shifts.append(settingsStore.settings.prefilledShift(on: date))
        }
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
