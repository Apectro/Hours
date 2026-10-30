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
    /// The draft as it opened, to tell an edit from a glance: a swipe down
    /// or Cancel after changing something asks first.
    @State private var openedDraft: DayRecord?
    @State private var isConfirmingDiscard = false
    @State private var hasLoaded = false
    /// The stored days of this day's week, read once on opening: a day's
    /// overtime after the contracted week depends on the days before it.
    @State private var weekRecords: [Int: DayRecord] = [:]
    /// The stored days of this day's leave year, read once on opening, for
    /// the "vacation left" line under the day type.
    @State private var leaveYearRecords: [Int: DayRecord] = [:]
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
                automaticType: automaticType,
                siteNames: siteNames,
                onOpenSite: { path.append(SiteRoute(siteID: $0)) },
                earnings: earnings,
                vacationLeft: vacationLeft,
                onOpenExtras: { path.append(DayExtrasRoute()) }
            )
            .navigationDestination(for: SiteRoute.self) { route in
                SiteDetailScreen(siteID: route.siteID, initialDate: date)
            }
            // "Allowance, km, note…": the extras and corrections, on the
            // same draft, pushed by value like the site.
            .navigationDestination(for: DayExtrasRoute.self) { _ in
                DayExtrasScreen(
                    draft: $draft,
                    computation: computation,
                    settings: settingsStore.settings,
                    calendar: settingsStore.workCalendar,
                    formatting: settingsStore.dateFormatting,
                    onDelete: storedRecord == nil ? nil : { delete() },
                    onDone: { if !path.isEmpty { path.removeLast() } }
                )
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
                    Button("Cancel") {
                        if hasChanges { isConfirmingDiscard = true } else { dismiss() }
                    }
                    .accessibilityIdentifier("day-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("day-editor-save")
                }
            }
            .alert(
                "This month is closed",
                isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })
            ) {
                // Reopening here, where the refusal happened: the edit is
                // still on screen, and Save works once the month is open.
                // The alert is the confirmation; nothing is saved by it.
                if let month = refusedMonth {
                    Button(String(
                        localized: "Reopen \(settingsStore.dateFormatting.monthTitle(month))",
                        comment: "Button; the value is a month and year"
                    )) {
                        settingsStore.update { $0.monthLock.unlock(month) }
                        refusal = nil
                    }
                    .accessibilityIdentifier("day-editor-reopen-month")
                }
                Button("OK", role: .cancel) { refusal = nil }
            } message: {
                Text("Reopen it to change these hours. You can close it again from the calendar's ⋯ menu.")
            }
            .task { load() }
        }
        // A sloppy swipe in a glove must not throw away changed times.
        .interactiveDismissDisabled(hasChanges)
        // On the stack rather than beside the delete dialog on the form: two
        // dialogs on one view is asking for one of them not to show.
        .confirmationDialog(
            "Discard changes?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
                .accessibilityIdentifier("day-editor-discard")
            Button("Keep editing", role: .cancel) {}
        }
        // The site screen's menu opens the crew through this, onto the same
        // path of values (see `OpenSiteCrewAction`).
        .environment(\.openSiteCrew, OpenSiteCrewAction { path.append($0) })
    }

    // MARK: - Derived

    /// Only what is typed in here: site shifts follow their site day and
    /// change under the editor when it opens a site, which is not an edit.
    private var hasChanges: Bool {
        guard let openedDraft else { return false }
        return Self.ownPart(of: draft) != Self.ownPart(of: openedDraft)
    }

    private static func ownPart(of record: DayRecord) -> DayRecord {
        var record = record
        record.shifts = record.shifts.filter { $0.siteID == nil }
        return record
    }

    private var refusedMonth: YearMonth? {
        guard case let .monthIsClosed(month)? = refusal as? MonthLock.Refusal else { return nil }
        return month
    }

    private var holidays: [HolidayRule] { holidayRecords.map(\.rule) }

    /// What the day resolves to with no type chosen: the schedule's day, or
    /// a public holiday. The editor's Worked · Away · Day off leave a day
    /// automatic when it already is the kind chosen.
    private var automaticType: DayTypeDefinition {
        var record = draft
        record.dayTypeID = nil
        return settingsStore.engine.day(date, record: record, holidays: holidays).dayType
    }

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
        openedDraft = draft
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
