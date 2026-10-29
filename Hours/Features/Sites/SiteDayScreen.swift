import SwiftUI
import SwiftData

/// A site's month and one day of it (mockup boards 4–6): the selected day's
/// week (the whole month on request), the day on one card — the site's times
/// once for everyone, a tick for each person who was there, and changed times
/// only for whoever came late or left early — then the weather, extra work,
/// the diary, and this month's figures last.
///
/// The day comes before the month on purpose: ticking the crew is what the
/// screen is opened for, and with the full month above it the crew started
/// below the fold, so a "Same as last day" from the widget filled a day out
/// of sight.
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

    /// A date to show, set from outside — the diary list picks one. Taken
    /// and cleared on arrival.
    var requestedDate: Binding<CalendarDate?> = .constant(nil)
    /// Opens the extra-work report, which the site screen presents.
    var onOpenReport: (() -> Void)? = nil
    /// What the site has, on view above the day (1.2): its address and the
    /// Crew, Diary, Sheet and Extra work buttons (`SiteActionsRow`), which
    /// the site screen draws. Without it, the crew line as before.
    var header: AnyView? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.openSiteCrew) private var openSiteCrew

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
    /// Your other active sites, for "On another site".
    @State private var otherSites: [Site] = []
    /// Every site's name, archived too, for a reason that names one.
    @State private var siteNames: [UUID: String] = [:]
    /// Who was ticked on another of your sites on this date, and where.
    @State private var elsewhere: [UUID: UUID] = [:]
    /// The note is typed here and saved when the field loses focus, rather
    /// than on every keystroke, which would rewrite your calendar day per letter.
    @State private var noteText = ""
    /// The vehicle's kilometres, typed here and saved when the field loses
    /// focus, as the note is.
    @State private var kilometresText = ""
    @FocusState private var isKilometresFocused: Bool
    @State private var yourHoursNotCounted = false
    @State private var activeSheet: ActiveSheet?
    /// Set when a write is refused. Non-nil is the alert's own trigger, so a
    /// refusal cannot be recorded without being shown.
    @State private var refusal: Error?
    /// The closed-month notice's Reopen, asking first as the calendar does.
    @State private var isConfirmingReopen = false
    /// The site widget's "Same as yesterday", not yet acted on. Cleared on
    /// first appearance, so coming back from the crew does not fill it again.
    @State private var requestsSameAsLastDay: Bool
    @FocusState private var isNoteFocused: Bool
    /// The whole month rather than the selected day's week. Remembered, as
    /// a way of looking rather than a piece of data.
    @AppStorage("site.showsWholeMonth") private var showsWholeMonth = false
    /// "Saved" beside the day's title for a moment after each write, since
    /// the day saves itself with no button to press.
    @State private var showsSaved = false
    @State private var savedRevision = 0
    /// Counts ticks and unticks, for the haptic.
    @State private var ticks = 0

    /// One sheet at a time, chosen by value: stacking several `.sheet`
    /// modifiers on one view has undefined behaviour.
    private enum ActiveSheet: Identifiable {
        case person(PersonReference)
        case siteTimes
        case weatherStop
        /// "Moved to another site…": everyone ticked (nil) or one person.
        case move(UUID?)

        var id: String {
            switch self {
            case let .move(memberID): return "move-\(memberID?.uuidString ?? "all")"
            case let .person(person): return "person-\(person.id.uuidString)"
            case .siteTimes: return "site-times"
            case .weatherStop: return "weather-stop"
            }
        }
    }

    init(
        site: Site,
        isReadOnly: Bool,
        date: CalendarDate,
        appliesSameAsLastDay: Bool = false,
        requestedDate: Binding<CalendarDate?> = .constant(nil),
        onOpenReport: (() -> Void)? = nil,
        header: AnyView? = nil
    ) {
        self.site = site
        self.isReadOnly = isReadOnly
        self.requestedDate = requestedDate
        self.onOpenReport = onOpenReport
        self.header = header
        _requestsSameAsLastDay = State(initialValue: appliesSameAsLastDay)
        _date = State(initialValue: date)
        _month = State(initialValue: date.yearMonth)
        _day = State(initialValue: SiteDay(siteID: site.id, date: date, jobID: site.jobID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.large) {
                if let header {
                    header
                } else {
                    Text(crewLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("site-crew-line")
                }

                SiteDayNotice(
                    isLocked: isLocked,
                    isReadOnly: isReadOnly,
                    isArchived: site.isArchived,
                    onReopen: { isConfirmingReopen = true }
                )
                // On the notice rather than beside the refusal alert below:
                // two dialogs on one view is asking for one not to show.
                .confirmationDialog(
                    String(
                        localized: "Reopen \(formatting.monthTitle(YearMonth(date)))?",
                        comment: "Confirmation title; the value is a month and year"
                    ),
                    isPresented: $isConfirmingReopen,
                    titleVisibility: .visible
                ) {
                    Button("Reopen") { reopenMonth() }
                        .accessibilityIdentifier("site-day-reopen-confirm")
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Its days can be changed again. Close it again from the calendar's ⋯ menu when you are done.")
                }

                SiteMonthGrid(
                    layout: layout,
                    weekLayout: weekLayout,
                    isExpanded: showsWholeMonth,
                    presentCounts: presentCounts,
                    selectedDate: date,
                    today: today,
                    calendar: calendar,
                    formatting: formatting,
                    onSelect: select,
                    onStep: step,
                    onToggleExpanded: toggleWholeMonth,
                    diaryDateKeys: diaryDateKeys,
                    badWeatherDateKeys: badWeatherDateKeys,
                    holidayDateKeys: holidayDateKeys,
                    extraWorkDateKeys: extraWorkDateKeys,
                    awayMarks: awayMarks
                )

                dayCard

                if !showsUnwrittenChoice {
                    SiteWeatherStopRow(
                        day: day,
                        canEdit: canEdit,
                        formatting: formatting,
                        onStopAll: { commit(day.stoppedForBadWeather(at: nil)) },
                        onStopAt: { activeSheet = .weatherStop },
                        onLift: { commit(day.liftingBadWeatherStop()) }
                    )
                }

                // Extra work is not hours either (see `ExtraWorkRepository`):
                // only a read-only site stops it. Rebuilt per date, as the
                // diary is.
                ExtraWorkDaySection(
                    site: site,
                    date: date,
                    canEdit: !isReadOnly,
                    onChange: reloadExtraWorkMarks,
                    onOpenReport: onOpenReport
                )
                .id(date.key)

                // Not under the month lock (see `SiteDiaryRepository`): only a
                // read-only site stops the diary. Rebuilt per date, so a draft
                // never lands on another day.
                // Unless the site's settings leave the diary out (1.2). A day
                // that already has one still shows it.
                if setup.keepsDiary || diaryDateKeys.contains(date.key) {
                    SiteDiaryCard(siteID: site.id, date: date, canEdit: !isReadOnly, onChange: reloadDiaryMarks)
                        .id(date.key)
                }

                // Last: the month's figures are read now and then, the day
                // above is written every day.
                monthSummary
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
        .onDisappear {
            commitNote()
            commitKilometres()
        }
        .onChange(of: requestedDate.wrappedValue) { _, requested in
            guard let requested else { return }
            requestedDate.wrappedValue = nil
            select(requested)
        }
        // A tick is felt as well as seen: gloves, sun, a phone held low.
        .sensoryFeedback(.selection, trigger: ticks)
        .onChange(of: isNoteFocused) { _, focused in
            if !focused { commitNote() }
        }
        .onChange(of: isKilometresFocused) { _, focused in
            if !focused { commitKilometres() }
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
                // The site's usual day first (1.2), then the working week's.
                SiteTimesSheet(
                    day: day,
                    defaultStart: setup.start ?? settings.primarySchedule(on: day.date).defaultStart,
                    defaultEnd: setup.end ?? settings.primarySchedule(on: day.date).defaultEnd,
                    onSave: commit
                )
            case let .move(memberID):
                SiteMoveSheet(
                    site: site,
                    day: day,
                    people: movablePeople,
                    preselected: memberID.map { [$0] },
                    otherSites: otherSites,
                    suggestedLeft: SiteMoving.suggestedLeftTime(
                        for: day,
                        now: TimeOfDay(minutes: calendar.component(.hour, from: Date()) * 60 + calendar.component(.minute, from: Date())),
                        isToday: date == today,
                        rounding: settings.rounding
                    ),
                    check: { choice in
                        do {
                            _ = try moveOutcome(choice)
                            return nil
                        } catch let error as SiteMoveError {
                            return error
                        } catch {
                            // A closed month: the sheet is not offered then,
                            // and Move says so through the refusal alert.
                            return nil
                        }
                    },
                    onMove: applyMove,
                    runningClock: HoursStack.clock.running
                )
            case .weatherStop:
                WeatherStopSheet(
                    day: day,
                    suggested: day.end ?? setup.end ?? settings.primarySchedule(on: day.date).defaultEnd,
                    onSave: { stop in commit(stoppedAt(stop)) }
                )
            }
        }
        .alert(
            "This month is closed",
            isPresented: Binding(get: { refusal != nil }, set: { if !$0 { refusal = nil } })
        ) {
            // Reopening here, where the refusal happened, as the day
            // editor does. The alert is the confirmation.
            Button(String(
                localized: "Reopen \(formatting.monthTitle(YearMonth(date)))",
                comment: "Button; the value is a month and year"
            )) {
                reopenMonth()
                refusal = nil
            }
            .accessibilityIdentifier("site-day-reopen-month")
            Button("OK", role: .cancel) { refusal = nil }
        } message: {
            Text("Reopen it to change these hours. You can close it again from the calendar's ⋯ menu.")
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

        var tiles = [
            MonthTile(label: String(localized: "Days written"), value: "\(figures.daysWritten)"),
            MonthTile(label: String(localized: "Crew hours"), value: formatter.string(figures.crewMinutes)),
            MonthTile(label: String(localized: "You"), value: formatter.string(figures.yourMinutes)),
        ]
        // Only in a month the weather stopped work.
        if figures.badWeatherDays > 0 {
            tiles.append(MonthTile(
                label: String(localized: "Bad weather"),
                value: "\(figures.badWeatherDays)",
                identifier: "site-month-bad-weather"
            ))
        }

        return SurfaceCard {
            VStack(alignment: .leading, spacing: Metrics.small) {
                Text(formatting.monthTitle(month))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                // One row while it fits; two by two at large text sizes or on
                // a narrow phone, rather than labels cut off mid-word.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Metrics.small) {
                        ForEach(Array(tiles.enumerated()), id: \.offset) { index, tile in
                            if index > 0 {
                                Divider().frame(maxHeight: .infinity)
                            }
                            tile.view
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Grid(alignment: .topLeading, horizontalSpacing: Metrics.medium, verticalSpacing: Metrics.medium) {
                        ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { start in
                            GridRow {
                                tiles[start].view
                                if start + 1 < tiles.count {
                                    tiles[start + 1].view
                                } else {
                                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                }
                            }
                        }
                    }
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
                copiesYesterday: date == today && lastDayDate == today.adding(days: -1, in: calendar),
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
                showsSaved: showsSaved,
                dayTypes: settings.dayTypeCatalog,
                otherSites: otherSites,
                siteNames: siteNames,
                elsewhere: elsewhere,
                onToggle: toggle,
                onSetReason: setReason,
                onEditPerson: { activeSheet = .person($0) },
                onEditTimes: { activeSheet = .siteTimes },
                onEditCrew: { openSiteCrew(SiteCrewRoute(siteID: site.id)) },
                tracksAllowance: settings.allowance.isEnabled,
                onToggleAllowance: toggleAllowance,
                kilometres: $kilometresText,
                isKilometresFocused: $isKilometresFocused,
                asksKilometres: setup.asksKilometres,
                canMove: canMove,
                onMove: { activeSheet = .move($0) },
                onUndoMove: undoMove
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
        // Someone hidden since, but recorded as away that day, stays too.
        let present = Set(day.present.map(\.memberID) + day.absences.map(\.memberID))
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

    // MARK: - Moving to another site

    /// Ticked here and not moved yet, in the card's order.
    private var movablePeople: [PersonReference] {
        rows.filter { day.attendance(for: $0.id) != nil && day.move(of: $0.id) == nil }
    }

    /// "Moved to another site…" is offered on a day that can be changed,
    /// with someone to move and somewhere to go.
    private var canMove: Bool {
        canEdit && stored != nil && !otherSites.isEmpty && !movablePeople.isEmpty
    }

    /// The move as the engine makes it, read against what is stored now.
    private func moveOutcome(_ choice: SiteMoveChoice) throws -> SiteMoveOutcome {
        let store = repository
        return try SiteMoving.apply(SiteMoveRequest(
            source: day,
            target: store.siteDay(siteID: choice.site.id, on: date),
            targetSite: store.site(id: choice.site.id) ?? choice.site,
            sourceCrew: crew,
            targetCrew: store.crew(for: choice.site.id, includeHidden: true),
            memberIDs: choice.memberIDs,
            left: choice.left,
            started: choice.started,
            breakPlacement: choice.breakPlacement,
            lock: settings.monthLock,
            tracksAllowance: settings.allowance.isEnabled
        ))
    }

    /// Writes both days and your calendar day in one save.
    private func applyMove(_ choice: SiteMoveChoice) {
        commitNote()
        commitKilometres()
        do {
            try repository.applyMove(try moveOutcome(choice))
            followWithClock(choice)
            afterMove()
        } catch {
            refusal = error
        }
    }

    /// Your clock follows you (1.2): stopped at the time you left and
    /// started again at the time you started there, through the same
    /// `TimeClock` as the widgets and Siri. `afterMove` then refreshes the
    /// widget, which brings the Live Activity in line.
    private func followWithClock(_ choice: SiteMoveChoice) {
        guard let handover = ClockFollowsMove.handover(
            running: HoursStack.clock.running,
            youMoved: choice.memberIDs.contains(CrewMember.youID),
            date: date,
            left: choice.left,
            started: choice.started,
            calendar: calendar
        ) else { return }
        let clock = HoursStack.timeClock
        clock.clockOut(at: handover.stopAt)
        clock.clockIn(at: handover.restartAt, jobID: (repository.site(id: choice.site.id) ?? choice.site).jobID)
    }

    private func undoMove(_ move: SiteMove) {
        do {
            try repository.undoMove(move, from: day)
            afterMove()
        } catch {
            refusal = error
        }
    }

    private func afterMove() {
        ticks += 1
        load()
        flashSaved()
        HoursStack.refreshWidget()
        Task { await MonthlySheetRefresher.refresh(context: modelContext, settingsStore: settingsStore) }
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    /// The site's usual day and extras (1.2).
    private var setup: SiteSetup { settings.siteSetup(for: site.id) }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }
    private var formatter: DurationFormatting { settings.displayFormatting }
    private var today: CalendarDate { CalendarDate.today(in: calendar) }

    private var isLocked: Bool { settings.monthLock.isLocked(date) }

    /// Reopens the selected day's month: the same write as the calendar's
    /// Reopen. Closing it again is in the calendar's ⋯ menu.
    private func reopenMonth() {
        settingsStore.update { $0.monthLock.unlock(YearMonth(date)) }
    }
    private var canEdit: Bool { !isReadOnly && !isLocked }

    /// The whole month. Everything under the grid is read over it, the
    /// folded week included: the selected day is always in this month, so
    /// its week is always inside the month's full weeks.
    private var layout: MonthLayout {
        MonthLayout.make(month: month, calendar: calendar, includesWeekends: true)
    }

    private var weekLayout: MonthLayout {
        MonthLayout.week(containing: date, calendar: calendar, includesWeekends: true)
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
        if next.start == nil { next.start = setup.start ?? settings.primarySchedule(on: day.date).defaultStart }
        return next.stoppedForBadWeather(at: stop)
    }

    private var presentCounts: [Int: Int] {
        Dictionary(monthDays.map { ($0.date.key, $0.present.count) }, uniquingKeysWith: { first, _ in first })
    }

    private var awayMarks: [Int: SiteAwayMark] {
        var marks: [Int: SiteAwayMark] = [:]
        for day in monthDays where marks[day.date.key] == nil {
            guard let reason = day.leadingAwayReason else { continue }
            let color: Color
            let title: String
            switch reason {
            case let .dayType(id):
                let definition = settings.dayTypeCatalog.definition(for: id)
                color = definition.tint.color
                title = definition.displayName()
            case .otherSite:
                color = .gray
                title = String(localized: "Another site")
            }
            marks[day.date.key] = SiteAwayMark(count: day.awayCount, color: color, title: title)
        }
        return marks
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
        kilometresText = Self.text(kilometres: day.kilometres)
        startsEmpty = false
        loadOtherSites()
        reloadMonth()
        refreshYourWarning()
    }

    /// The other sites, and who of this crew was ticked on one of them on
    /// this date (`SiteElsewhere`): read once per day shown, not per draw.
    private func loadOtherSites() {
        let store = repository
        let all = store.sites(includeArchived: true)
        siteNames = Dictionary(all.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        otherSites = all.filter { !$0.isArchived && $0.id != site.id }
        let everyone = all.flatMap { store.crew(for: $0.id, includeHidden: true) }
        let onDate = store.siteDays(siteID: nil, in: CalendarDateRange(single: date))
        var found: [UUID: UUID] = [:]
        for memberID in [CrewMember.youID] + crew.map(\.id) {
            if let other = SiteElsewhere.site(of: memberID, on: site.id, date: date, crew: everyone, siteDays: onDate) {
                found[memberID] = other
            }
        }
        elsewhere = found
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
        commitKilometres()
        withAnimation(.snappy(duration: 0.2)) {
            date = newDate
            if !month.contains(newDate) { month = newDate.yearMonth }
        }
        load()
    }

    /// The arrows: a week while the grid is folded, a month while it is open.
    /// The selection follows — today if it is there, otherwise the same
    /// weekday or day of the month — so the card never describes a day the
    /// grid is not showing.
    private func step(_ direction: Int) {
        guard showsWholeMonth else {
            stepWeek(direction)
            return
        }
        commitNote()
        commitKilometres()
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

    private func stepWeek(_ direction: Int) {
        let shifted = date.adding(days: 7 * direction, in: calendar)
        let week = CalendarDateRange.week(containing: shifted, in: calendar)
        let newDate = week.contains(today) ? today : shifted
        commitNote()
        commitKilometres()
        withAnimation(.snappy(duration: 0.25)) {
            date = newDate
            month = newDate.yearMonth
        }
        load()
    }

    /// Opening the month keeps the selected day; folding it shows that day's
    /// week. Nothing needs reading again: every way of moving keeps the
    /// selected day inside the month the data was read for.
    private func toggleWholeMonth() {
        withAnimation(.snappy(duration: 0.25)) {
            showsWholeMonth.toggle()
        }
    }

    /// Whether your calendar counts your hours here. Read from your stored
    /// calendar day, which the save has just written.
    private func refreshYourWarning() {
        let record = WorkdayRepository(context: modelContext, lock: settings.monthLock).record(on: date)
        let computation = settingsStore.engine.day(date, record: record, holidays: holidayRecords.map(\.rule))
        yourHoursNotCounted = computation.warnings.contains(.siteHoursNotCounted)
    }

    // MARK: - Editing

    /// Ticking someone in clears any reason they were away, and gives them
    /// the field allowance when the site does by default — read from the
    /// store, in case the site was changed while this screen was open.
    private func toggle(_ memberID: UUID) {
        ticks += 1
        let byDefault = settings.allowance.isEnabled
            && (repository.site(id: site.id) ?? site).allowanceByDefault
        // A day not written yet starts with the site's usual times (1.2).
        let base = stored == nil && day.present.isEmpty ? day.startingWithUsualTimes(of: setup) : day
        commit(
            base.togglingPresence(of: memberID, allowanceByDefault: byDefault)
                .droppingUnusedUsualTimes(of: setup)
        )
    }

    /// The row menu's switch: the allowance for one person, today.
    private func toggleAllowance(_ memberID: UUID) {
        commit(day.settingAllowance(!day.hasAllowance(for: memberID), for: memberID))
    }

    private func commitKilometres() {
        let typed = Kilometres.parse(kilometresText)
        guard typed != day.kilometres else { return }
        var next = day
        next.kilometres = typed
        commit(next)
    }

    private static func text(kilometres: Int) -> String {
        kilometres > 0 ? "\(kilometres)" : ""
    }

    /// Why someone not ticked was away; nil takes the reason back.
    private func setReason(_ memberID: UUID, _ reason: AbsenceReason?) {
        commit(day.settingReason(reason, for: memberID))
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

    /// Shows "Saved" for a moment. A newer write restarts the moment rather
    /// than being cut short by the older one's timer.
    private func flashSaved() {
        savedRevision += 1
        let revision = savedRevision
        withAnimation(.easeOut(duration: 0.2)) { showsSaved = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard revision == savedRevision else { return }
            withAnimation(.easeIn(duration: 0.3)) { showsSaved = false }
        }
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
        // Kilometres being typed travel with a change made meanwhile, as the
        // note does; otherwise the change decides them ("Same as last day"
        // brings its own).
        if isKilometresFocused { next.kilometres = Kilometres.parse(kilometresText) }
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
                // Emptied by hand on this screen: stay on the crew rather
                // than swapping them for "Same as last day" under the finger.
                startsEmpty = true
            }
            day = next
            flashSaved()
        } catch {
            // Back to what is stored, so the screen never shows hours that
            // were not recorded.
            refusal = error
            day = stored ?? SiteDay(siteID: site.id, date: date, jobID: site.jobID)
            noteText = day.note
        }
        if !isKilometresFocused { kilometresText = Self.text(kilometres: day.kilometres) }
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

extension SiteDayScreen {
    /// One of the month's figures, kept as data so the same tiles can be laid
    /// out in one row or two by two.
    fileprivate struct MonthTile {
        let label: String
        let value: String
        var identifier: String? = nil

        @ViewBuilder
        var view: some View {
            if let identifier {
                StatTile(label: label, value: value)
                    .accessibilityIdentifier(identifier)
            } else {
                StatTile(label: label, value: value)
            }
        }
    }
}

/// Why the selected day cannot be changed, when it cannot: a closed month, an
/// archived site, or a site that is read-only because Pro lapsed.
private struct SiteDayNotice: View {
    let isLocked: Bool
    let isReadOnly: Bool
    let isArchived: Bool
    /// Asks to reopen the closed month, as the calendar's notice does.
    let onReopen: () -> Void

    var body: some View {
        if isLocked {
            // The words read as one element; Reopen stays its own button
            // beside them, so the identifier is not on a container holding it.
            HStack(alignment: .center, spacing: Metrics.small) {
                Label {
                    VStack(alignment: .leading, spacing: Metrics.tiny) {
                        Text("This month is closed")
                            .font(.subheadline.weight(.semibold))
                        Text("Reopen it to change these hours. You can close it again from the calendar's ⋯ menu.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("site-day-locked")
                Spacer(minLength: Metrics.small)
                Button("Reopen", action: onReopen)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("site-day-reopen")
            }
            .padding(Metrics.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
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
