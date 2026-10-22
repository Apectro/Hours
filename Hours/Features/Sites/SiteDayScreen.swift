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
    /// Date keys under the grid with a diary or a diary photo.
    @State private var diaryDateKeys: Set<Int> = []
    /// Date keys under the grid with extra work.
    @State private var extraWorkDateKeys: Set<Int> = []
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
    /// The site widget's "Same as yesterday", not yet acted on. Cleared on
    /// first appearance, so coming back from the crew does not fill it again.
    @State private var requestsSameAsLastDay: Bool
    @FocusState private var isNoteFocused: Bool

    /// One sheet at a time, chosen by value: stacking several `.sheet`
    /// modifiers on one view has undefined behaviour.
    private enum ActiveSheet: Identifiable {
        case person(PersonReference)
        case siteTimes
        case weatherStop

        var id: String {
            switch self {
            case let .person(person): return "person-\(person.id.uuidString)"
            case .siteTimes: return "site-times"
            case .weatherStop: return "weather-stop"
            }
        }
    }

    init(site: Site, isReadOnly: Bool, date: CalendarDate, appliesSameAsLastDay: Bool = false) {
        self.site = site
        self.isReadOnly = isReadOnly
        _requestsSameAsLastDay = State(initialValue: appliesSameAsLastDay)
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
                    onStep: step,
                    diaryDateKeys: diaryDateKeys,
                    badWeatherDateKeys: badWeatherDateKeys,
                    holidayDateKeys: holidayDateKeys,
                    extraWorkDateKeys: extraWorkDateKeys
                )

                monthSummary

                dayCard

                if !showsUnwrittenChoice {
                    SiteWeatherStopRow(
                        day: day,
                        canEdit: canEdit,
                        onStopAll: { commit(day.stoppedForBadWeather(at: nil)) },
                        onStopAt: { activeSheet = .weatherStop },
                        onLift: { commit(day.liftingBadWeatherStop()) }
                    )
                }

                // Extra work is not hours either (see `ExtraWorkRepository`):
                // only a read-only site stops it. Rebuilt per date, as the
                // diary is.
                ExtraWorkDaySection(site: site, date: date, canEdit: !isReadOnly, onChange: reloadExtraWorkMarks)
                    .id(date.key)

                // Not under the month lock (see `SiteDiaryRepository`): only a
                // read-only site stops the diary. Rebuilt per date, so a draft
                // never lands on another day.
                SiteDiaryCard(siteID: site.id, date: date, canEdit: !isReadOnly, onChange: reloadDiaryMarks)
                    .id(date.key)
            }
            .padding(.horizontal, Metrics.large)
            .padding(.bottom, Metrics.extraLarge)
        }
        .background(Color.hoursCanvas)
        .scrollDismissesKeyboard(.interactively)
        // A screen the UI tests wait for. The title above it is the site's name.
        .accessibilityIdentifier("screen-site-day")
        .onAppear {
            load()
            applyRequestedSameAsLastDay()
        }
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
                    defaultStart: settings.primarySchedule(on: day.date).defaultStart,
                    defaultEnd: settings.primarySchedule(on: day.date).defaultEnd,
                    onSave: commit
                )
            case .weatherStop:
                WeatherStopSheet(
                    day: day,
                    suggested: day.end ?? settings.primarySchedule(on: day.date).defaultEnd,
                    onSave: { stop in commit(stoppedAt(stop)) }
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
        let figures = SiteMonthFigures(
            days: monthDays,
            month: month,
            calculator: SiteDayCalculator(settings: settings, calendar: calendar)
        )

        return SurfaceCard {
            HStack(alignment: .top, spacing: Metrics.small) {
                StatTile(label: String(localized: "Days written"), value: "\(figures.daysWritten)")
                Divider().frame(height: 34)
                StatTile(label: String(localized: "Crew hours"), value: formatter.string(figures.crewMinutes))
                Divider().frame(height: 34)
                StatTile(label: String(localized: "You"), value: formatter.string(figures.yourMinutes))
                // Only in a month the weather stopped work.
                if figures.badWeatherDays > 0 {
                    Divider().frame(height: 34)
                    StatTile(label: String(localized: "Bad weather"), value: "\(figures.badWeatherDays)")
                        .accessibilityIdentifier("site-month-bad-weather")
                }
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

    /// Public holidays off in the shown month: never outlined as unwritten.
    private var holidayDateKeys: Set<Int> {
        guard settings.features.trackHolidays, let first = layout.days.first, let last = layout.days.last else {
            return []
        }
        let range = CalendarDateRange(start: first, end: last)
        return HolidayResolver(rules: holidayRecords.map(\.rule), calendar: calendar, covering: range)
            .daysOffKeys(in: range, calendar: calendar)
    }

    private var badWeatherDateKeys: Set<Int> {
        Set(monthDays.filter(\.isBadWeatherStop).map(\.date.key))
    }

    /// "Stopped at" on the selected day, with the site's start kept, or the
    /// schedule's when the day had none yet.
    private func stoppedAt(_ stop: TimeOfDay) -> SiteDay {
        var next = day
        if next.start == nil { next.start = settings.primarySchedule(on: day.date).defaultStart }
        return next.stoppedForBadWeather(at: stop)
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
        reloadDiaryMarks()
        reloadExtraWorkMarks()
    }

    private func reloadExtraWorkMarks() {
        extraWorkDateKeys = ExtraWorkRepository(context: modelContext)
            .dateKeys(siteID: site.id, in: layout.coveredRange)
    }

    private func reloadDiaryMarks() {
        diaryDateKeys = Set(
            SiteDiaryRepository(context: modelContext)
                .datesWithEntries(siteID: site.id, in: layout.coveredRange)
                .map(\.key)
        )
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

    /// The widget's button does exactly what this screen's own "Same as last
    /// day" would, and only where that button is offered: today, nothing
    /// written yet, a day to copy, and a month and site that can be changed.
    /// Anywhere else the site simply opens, which is what the person sees
    /// the widget do on a day already written.
    private func applyRequestedSameAsLastDay() {
        guard requestsSameAsLastDay else { return }
        requestsSameAsLastDay = false
        guard date == today, showsUnwrittenChoice else { return }
        fillFromLastDay()
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

        let wasStored = stored != nil
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
        // A day written or removed can decide whether its site gets a note
        // on the 1st. A change to a day already there cannot, so it does not
        // reschedule.
        if (stored != nil) != wasStored {
            Task { await MonthlySheetRefresher.refresh(context: modelContext, settingsStore: settingsStore) }
        }
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
