import SwiftUI
import SwiftData

/// A site's month and one day of it (mockup boards 4–6): the month as the
/// calendar draws yours, this month's figures, and the selected day on one
/// card — the site's times once for everyone, a tick for each person who was
/// there, and changed times only for whoever came late or left early.
///
/// Edits are saved as they are made, with no Save button. This is a page you
/// move through day by day, not a sheet you open and dismiss, and a draft that
/// vanished on the next tap in the grid would be a save that silently did
/// nothing. Every write goes through `SiteRepository` with the month lock,
/// which writes your calendar day in the same step; a refusal is shown with
/// the calendar's own message and the screen goes back to what is stored, so
/// it never shows hours that are not recorded.
///
/// A date with nothing recorded offers "Same as last day" and "Start from
/// empty" first. Neither writes anything on its own beyond what it says: the
/// day is stored on the first tick or time, and deleted again when emptied.
struct SiteDayScreen: View {
    let site: Site
    /// One of the extra sites after Pro lapsed: shown, not changed.
    let isReadOnly: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    @Query private var holidayRecords: [HolidayRecord]

    @State private var date: CalendarDate
    /// The month the grid shows. Usually the selected date's, but the arrows
    /// move it on their own.
    @State private var month: YearMonth
    /// What the card shows. Equal to `stored` except for a day that is not
    /// yet worth storing (see `SiteDay.isBlank`).
    @State private var day: SiteDay
    @State private var stored: SiteDay?
    /// Every stored day under the grid, borrowed neighbouring days included.
    @State private var monthDays: [SiteDay] = []
    /// What "Same as last day" would fill in, if there is an earlier day.
    @State private var lastDay: SiteDay?
    /// The date "Same as last day" copies from. Kept apart from `lastDay`,
    /// which is already re-dated to the day being written.
    @State private var lastDayDate: CalendarDate?
    /// "Start from empty" was chosen for the selected day, so the ordinary
    /// card shows although nothing is stored yet.
    @State private var startsEmpty = false
    /// Hidden members included, because a past day may name one.
    @State private var crew: [CrewMember] = []
    /// The note is typed here and saved when the field loses focus, rather
    /// than on every keystroke, which would rewrite your calendar day per letter.
    @State private var noteText = ""
    @State private var yourHoursNotCounted = false
    @State private var activeSheet: ActiveSheet?
    /// Set when a write is refused. Non-nil is the alert's own trigger, so a
    /// refusal cannot be recorded without being shown.
    @State private var refusal: Error?
    @FocusState private var isNoteFocused: Bool

    /// One sheet at a time, chosen by value: stacking several `.sheet`
    /// modifiers on one view has undefined behaviour.
    private enum ActiveSheet: Identifiable {
        case person(PersonReference)
        case siteTimes

        var id: String {
            switch self {
            case let .person(person): return "person-\(person.id.uuidString)"
            case .siteTimes: return "site-times"
            }
        }
    }

    init(site: Site, isReadOnly: Bool, date: CalendarDate) {
        self.site = site
        self.isReadOnly = isReadOnly
        _date = State(initialValue: date)
        _month = State(initialValue: date.yearMonth)
        _day = State(initialValue: SiteDay(siteID: site.id, date: date, jobID: site.jobID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.large) {
                Text(crewLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("site-crew-line")

                SiteDayNotice(isLocked: isLocked, isReadOnly: isReadOnly, isArchived: site.isArchived)

                SiteMonthGrid(
                    layout: layout,
                    presentCounts: presentCounts,
                    selectedDate: date,
                    today: today,
                    calendar: calendar,
                    formatting: formatting,
                    onSelect: select,
                    onStep: step
                )

                monthSummary

                dayCard
            }
            .padding(.horizontal, Metrics.large)
            .padding(.bottom, Metrics.extraLarge)
        }
        .background(Color.hoursCanvas)
        .scrollDismissesKeyboard(.interactively)
        // A screen the UI tests wait for. The title above it is the site's name.
        .accessibilityIdentifier("screen-site-day")
        .onAppear { load() }
        .onDisappear { commitNote() }
        .onChange(of: isNoteFocused) { _, focused in
            if !focused { commitNote() }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case let .person(person):
                if let attendance = day.attendance(for: person.id) {
                    PersonTimesSheet(
                        name: person.name,
                        attendance: attendance,
                        day: day,
                        onSave: replace
                    )
                }
            case .siteTimes:
                SiteTimesSheet(
                    day: day,
                    defaultStart: settings.primarySchedule.defaultStart,
                    defaultEnd: settings.primarySchedule.defaultEnd,
                    onSave: commit
                )
            }
        }
        .alert(
            "This month is closed",
            isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })
        ) {
            Button("OK", role: .cancel) { refusal = nil }
        } message: {
            Text("Reopen it in Settings › Calculation if you need to change these hours.")
        }
    }

    // MARK: - Parts

    private var crewLine: String {
        let coworkers = crew.filter { !$0.isHidden }.count
        guard coworkers > 0 else { return String(localized: "Just you") }
        return String(inflected: "You + ^[\(coworkers) coworker](inflect: true)")
    }

    private var monthSummary: some View {
        let written = monthDays.filter { month.contains($0.date) }
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let results = written.map { calculator.compute($0) }
        let crewMinutes = results.reduce(0) { $0 + $1.crewTotalMinutes }
        let yourMinutes = results.reduce(0) { total, result in
            total + (result.people.first(where: { $0.memberID == CrewMember.youID })?.workedMinutes ?? 0)
        }

        return SurfaceCard {
            HStack(alignment: .top, spacing: Metrics.small) {
                StatTile(label: String(localized: "Days written"), value: "\(written.count)")
                Divider().frame(height: 34)
                StatTile(label: String(localized: "Crew hours"), value: formatter.string(crewMinutes))
                Divider().frame(height: 34)
                StatTile(label: String(localized: "You"), value: formatter.string(yourMinutes))
            }
        }
    }

    @ViewBuilder
    private var dayCard: some View {
        if showsUnwrittenChoice, let lastDay, let lastDayDate {
            SiteUnwrittenDayCard(
                title: dayTitle,
                lastDayDate: lastDayDate,
                lastDay: lastDay,
                formatting: formatting,
                onSameAsLastDay: fillFromLastDay,
                onStartEmpty: { startsEmpty = true }
            )
        } else {
            SiteDayCard(
                title: dayTitle,
                day: day,
                result: result,
                rows: rows,
                isWritten: stored != nil,
                canEdit: canEdit,
                warnings: warnings,
                formatting: formatting,
                durations: formatter,
                noteText: $noteText,
                isNoteFocused: $isNoteFocused,
                onToggle: toggle,
                onEditPerson: { activeSheet = .person($0) },
                onEditTimes: { activeSheet = .siteTimes }
            )
        }
    }

    /// Only on a day with nothing in it, so it can never stand in front of
    /// one, and only where it could be used: a closed month or a read-only
    /// site shows the ordinary card, greyed, which also says who is not there.
    private var showsUnwrittenChoice: Bool {
        canEdit
            && !startsEmpty
            && stored == nil
            && lastDay != nil
            && day.present.isEmpty && day.start == nil && day.end == nil
    }

    private var dayTitle: String { formatting.dayTitle(date) }

    private var warnings: [DayWarning] {
        var seen: [DayWarning] = []
        for warning in result.people.flatMap(\.warnings) where warning.isProblem && !seen.contains(warning) {
            seen.append(warning)
        }
        // Worked out from your calendar day, which is where the reason lives:
        // a day type, a day left out of totals, or hours typed in by hand.
        if yourHoursNotCounted, day.attendance(for: CrewMember.youID) != nil {
            seen.append(.siteHoursNotCounted)
        }
        return seen
    }

    /// You first, then the crew in their order. Someone hidden from the crew
    /// appears only on a day that already has them, so the record stays
    /// honest without offering them for new days.
    private var rows: [PersonReference] {
        let present = Set(day.present.map(\.memberID))
        var rows = [PersonReference(id: CrewMember.youID, name: String(localized: "You"))]
        for member in crew where !member.isHidden || present.contains(member.id) {
            rows.append(PersonReference(id: member.id, name: member.name))
        }
        // Present but not (yet) on this device's crew list, which sync can do
        // for a moment. Shown rather than left out of a total they count in.
        let listed = Set(rows.map(\.id))
        for attendance in day.present where !listed.contains(attendance.memberID) {
            rows.append(PersonReference(id: attendance.memberID, name: String(localized: "Unknown")))
        }
        return rows
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }
    private var formatter: DurationFormatting { settings.displayFormatting }
    private var today: CalendarDate { CalendarDate.today(in: calendar) }

    private var isLocked: Bool { settings.monthLock.isLocked(date) }
    private var canEdit: Bool { !isReadOnly && !isLocked }

    private var layout: MonthLayout {
        MonthLayout.make(month: month, calendar: calendar, includesWeekends: true)
    }

    private var presentCounts: [Int: Int] {
        Dictionary(monthDays.map { ($0.date.key, $0.present.count) }, uniquingKeysWith: { first, _ in first })
    }

    private var result: SiteDayResult {
        SiteDayCalculator(settings: settings, calendar: calendar).compute(day)
    }

    private var repository: SiteRepository {
        SiteRepository(context: modelContext, lock: settings.monthLock)
    }

    // MARK: - Loading

    /// Read outside of `body`: the repository's reads collapse duplicates,
    /// which writes, and a view must not write while it is being drawn.
    private func load() {
        let store = repository
        crew = store.crew(for: site.id, includeHidden: true)
        stored = store.siteDay(siteID: site.id, on: date)
        day = stored ?? SiteDay(siteID: site.id, date: date, jobID: site.jobID)
        lastDay = store.sameAsLastDay(siteID: site.id, on: date)
        lastDayDate = lastDay == nil ? nil : store.lastSiteDay(siteID: site.id, before: date)?.date
        noteText = day.note
        startsEmpty = false
        reloadMonth()
        refreshYourWarning()
    }

    private func reloadMonth() {
        monthDays = repository.siteDays(siteID: site.id, in: layout.coveredRange)
    }

    /// A tap in the grid. A day borrowed from a neighbouring month moves the
    /// grid there, as in the calendar, rather than selecting something the
    /// month on screen no longer shows.
    private func select(_ newDate: CalendarDate) {
        guard newDate != date else { return }
        commitNote()
        withAnimation(.snappy(duration: 0.2)) {
            date = newDate
            if !month.contains(newDate) { month = newDate.yearMonth }
        }
        load()
    }

    /// The month arrows. The selection follows into the new month — today if
    /// it is there, otherwise the same day of the month — so the card never
    /// describes a day the grid is not showing.
    private func step(_ direction: Int) {
        commitNote()
        let next = month.adding(months: direction)
        let newDate = next.contains(today)
            ? today
            : CalendarDate(year: next.year, month: next.month, day: min(date.day, next.dayCount(in: calendar)))
        withAnimation(.snappy(duration: 0.25)) {
            month = next
            date = newDate
        }
        load()
    }

    /// Whether your calendar counts your hours here. Read from your stored
    /// calendar day, which the save has just written.
    private func refreshYourWarning() {
        let record = WorkdayRepository(context: modelContext, lock: settings.monthLock).record(on: date)
        let computation = settingsStore.engine.day(date, record: record, holidays: holidayRecords.map(\.rule))
        yourHoursNotCounted = computation.warnings.contains(.siteHoursNotCounted)
    }

    // MARK: - Editing

    private func toggle(_ memberID: UUID) {
        var next = day
        if let index = next.present.firstIndex(where: { $0.memberID == memberID }) {
            next.present.remove(at: index)
        } else {
            next.present.append(Attendance(memberID: memberID))
        }
        commit(next)
    }

    private func replace(_ attendance: Attendance) {
        var next = day
        guard let index = next.present.firstIndex(where: { $0.memberID == attendance.memberID }) else { return }
        next.present[index] = attendance
        commit(next)
    }

    private func fillFromLastDay() {
        guard let lastDay else { return }
        commit(lastDay)
    }

    private func commitNote() {
        guard noteText != day.note else { return }
        commit(day)
    }

    /// The one place a change is written. The note being typed travels with
    /// every change, so a tick made mid-sentence does not lose it.
    private func commit(_ proposed: SiteDay) {
        guard canEdit else { return }
        var next = proposed
        next.note = noteText
        // A new day freezes the site's job as it stands now (see `SiteDay.jobID`).
        if stored == nil { next.jobID = site.jobID }
        guard next != stored else {
            day = next
            return
        }

        do {
            if !next.isBlank {
                try repository.save(next)
                stored = next
                // Written, so tonight's nudge about it would be wrong.
                ReminderScheduler().cancelSiteReminder(on: next.date)
            } else if stored != nil {
                try repository.delete(siteID: site.id, on: next.date)
                stored = nil
            }
            day = next
        } catch {
            // Back to what is stored, so the screen never shows hours that
            // were not recorded.
            refusal = error
            day = stored ?? SiteDay(siteID: site.id, date: date, jobID: site.jobID)
            noteText = day.note
        }
        reloadMonth()
        refreshYourWarning()
        HoursStack.refreshWidget()
    }
}

/// Why the selected day cannot be changed, when it cannot: a closed month, an
/// archived site, or a site that is read-only because Pro lapsed.
private struct SiteDayNotice: View {
    let isLocked: Bool
    let isReadOnly: Bool
    let isArchived: Bool

    var body: some View {
        if isLocked {
            notice(systemImage: "lock.fill") {
                VStack(alignment: .leading, spacing: Metrics.tiny) {
                    Text("This month is closed")
                        .font(.subheadline.weight(.semibold))
                    Text("Reopen it in Settings › Calculation if you need to change these hours.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("site-day-locked")
        } else if isReadOnly, isArchived {
            // Archiving, not a lapsed Pro, is what stops this one, and the
            // way back is the site's own editor.
            notice(systemImage: "archivebox") {
                Text("Archived. Switch off Archived under Edit to change its days.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("site-day-archived")
        } else if isReadOnly {
            notice(systemImage: "lock.fill") {
                Text("Read-only until Zeitkonto Pro is active again or your other sites are archived. Nothing on it is lost.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("site-day-read-only")
        }
    }

    private func notice<Content: View>(systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        Label {
            content()
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .padding(Metrics.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
