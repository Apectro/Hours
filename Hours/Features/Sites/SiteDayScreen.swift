import SwiftUI
import SwiftData

/// The crew's day on a site (design v2, mockup Sites phones 3 and 4): one
/// day only, its date as the inline title with the site under it, ‹ › and
/// a calendar button to go to another day, and a swipe for the day before
/// or after. Back returns to the site's page, which has the month.
///
/// Not written yet: "Not written yet" and the usual day, the crew it would
/// tick, each with a filled tick and their times; a name opens that person
/// (Usual, Late/early, Away). **Save · 5 people, 37h 30m** at the bottom
/// writes it, **Someone was different** opens the crew's day. A work day
/// gone by offers **Same as the day before** first. Written: a green tick
/// and "Written" with the crew's hours, a row per person with only the
/// difference under the name, then the day's allowance, kilometres, note,
/// diary, bad weather, the move and the crew, then the day's extra work.
/// Edit opens the crew's day (`SiteCrewDaySheet`).
///
/// Edits are saved as they are made. Every write goes through
/// `SiteRepository` with the month lock, which writes your calendar day in
/// the same step; a refusal is shown with the calendar's own message and
/// the screen goes back to what is stored, so it never shows hours that are
/// not recorded. A day not written yet is a draft until Save.
struct SiteDayScreen: View {
    let site: Site
    /// One of the extra sites after Pro lapsed: shown, not changed.
    let isReadOnly: Bool

    /// A date to show, set from outside — the diary list picks one. Taken
    /// and cleared on arrival.
    var requestedDate: Binding<CalendarDate?> = .constant(nil)
    /// Opens the extra-work report, which the site screen presents.
    var onOpenReport: (() -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.openSiteCrew) private var openSiteCrew

    @Query private var holidayRecords: [HolidayRecord]

    @State private var date: CalendarDate
    /// What the screen shows. Equal to `stored` except for a day that is not
    /// yet worth storing (see `SiteDay.isBlank`).
    @State private var day: SiteDay
    @State private var stored: SiteDay?
    /// This site's days from the look-back before the month to its end:
    /// whether an unwritten day was expected reads the weekdays worked lately.
    @State private var monthDays: [SiteDay] = []
    /// Who the day is checked against for "not here, no reason given"
    /// (`SiteMonthOverview.crew`): joined by then, not on another site.
    @State private var expectedCrew: Set<UUID> = []
    /// Whether the day has a diary.
    @State private var hasDiary = false
    /// The day's extra work.
    @State private var extraWork = ExtraWorkDayModel()
    /// A day not written yet, changed person by person before Save. Nil is
    /// the usual day.
    @State private var pendingDraft: SiteDay?
    /// What "Same as last day" would fill in, if there is an earlier day.
    @State private var lastDay: SiteDay?
    /// The date "Same as last day" copies from. Kept apart from `lastDay`,
    /// which is already re-dated to the day being written.
    @State private var lastDayDate: CalendarDate?
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
    /// "Saved" beside "Written" for a moment after each write, since the day
    /// saves itself with no button to press.
    @State private var showsSaved = false
    @State private var savedRevision = 0
    /// Counts ticks and unticks, for the haptic.
    @State private var ticks = 0

    /// One sheet at a time, chosen by value: stacking several `.sheet`
    /// modifiers on one view has undefined behaviour.
    private enum ActiveSheet: Identifiable {
        /// "Someone was different", "Edit" and "Start from empty": the
        /// crew's day, on a draft that starts as given.
        case crewDay(SiteDay)
        case siteTimes
        /// "Bad weather…", on the day it would stop.
        case weatherStop(SiteDay)
        /// "Moved to another site…": everyone ticked (nil) or one person.
        case move(UUID?)
        case allowance
        case diary
        /// One person's times, from their row.
        case personTimes(PersonReference)
        /// Why one person was not here, from their row or Add reason.
        case away(PersonReference)
        /// The extra-work editor, on a job or a new one.
        case extraWork(ExtraWorkEditorRequest)
        /// The calendar button: go to another day.
        case pickDate

        var id: String {
            switch self {
            case .crewDay: return "crew-day"
            case let .move(memberID): return "move-\(memberID?.uuidString ?? "all")"
            case .siteTimes: return "site-times"
            case .weatherStop: return "weather-stop"
            case .allowance: return "allowance"
            case .diary: return "diary"
            case let .personTimes(person): return "times-\(person.id.uuidString)"
            case let .away(person): return "away-\(person.id.uuidString)"
            case let .extraWork(request): return "extra-work-\(request.id.uuidString)"
            case .pickDate: return "pick-date"
            }
        }
    }

    init(
        site: Site,
        isReadOnly: Bool,
        date: CalendarDate,
        appliesSameAsLastDay: Bool = false,
        requestedDate: Binding<CalendarDate?> = .constant(nil),
        onOpenReport: (() -> Void)? = nil
    ) {
        self.site = site
        self.isReadOnly = isReadOnly
        self.requestedDate = requestedDate
        self.onOpenReport = onOpenReport
        _requestsSameAsLastDay = State(initialValue: appliesSameAsLastDay)
        _date = State(initialValue: date)
        _day = State(initialValue: SiteDay(siteID: site.id, date: date, jobID: site.jobID))
    }

    var body: some View {
        List {
            if isLocked || isReadOnly {
                Section {
                    SiteDayNotice(
                        isLocked: isLocked,
                        isReadOnly: isReadOnly,
                        isArchived: site.isArchived,
                        onReopen: { isConfirmingReopen = true }
                    )
                    // On the notice rather than beside the refusal alert
                    // below: two dialogs on one view is asking for one not
                    // to show.
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
                }
            }

            if stored == nil {
                unwrittenSections
            } else {
                writtenSections
            }

            linksSection

            // Extra work is not hours (see `ExtraWorkRepository`): only a
            // read-only site stops it.
            ExtraWorkDaySection(
                model: extraWork,
                canEdit: !isReadOnly,
                onEdit: { job in activeSheet = .extraWork(ExtraWorkEditorRequest(job: job)) },
                onToggleDone: toggleExtraWorkDone,
                onOpenReport: onOpenReport
            )
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        // A screen the UI tests wait for. The title above it is the day.
        .accessibilityIdentifier("screen-site-day")
        .navigationTitle(Text(verbatim: dayHeading))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleView
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    commitNote()
                    commitKilometres()
                    activeSheet = .pickDate
                } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel(String(localized: "Choose a day"))
                .accessibilityIdentifier("site-day-pick-date")
            }
            if stored != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { activeSheet = .crewDay(day) }
                        .disabled(!canEdit)
                        .accessibilityIdentifier("site-day-change")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if stored == nil {
                unwrittenButtons
            }
        }
        // A clearly sideways swipe goes to the day before or after; it is
        // simultaneous, so scrolling and taps are untouched.
        .simultaneousGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    let width = value.translation.width
                    guard abs(width) > 90, abs(width) > abs(value.translation.height) * 2 else { return }
                    stepDay(width < 0 ? 1 : -1)
                }
        )
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
            sheetContent(sheet)
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

    // MARK: - The title

    /// "Today" or "Thursday, 29 Oct".
    private var dayHeading: String {
        date == today ? String(localized: "Today") : formatting.dayTitle(date)
    }

    /// ‹ the day, the site under it › — two lines, as `.navigationSubtitle`
    /// would draw them on iOS 26.
    private var titleView: some View {
        HStack(spacing: 0) {
            Button {
                stepDay(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 36, minHeight: 44)
            }
            .accessibilityLabel(String(localized: "Previous day"))
            .accessibilityIdentifier("site-day-previous")

            VStack(spacing: 0) {
                Text(verbatim: dayHeading)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: site.name)
                    .font(.caption)
                    .foregroundStyle(.hoursSecondaryText)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            // The day as a date key, so a test can tell which day is shown
            // without reading translated words.
            .accessibilityValue(Text(verbatim: "\(date.key)"))
            .accessibilityIdentifier("site-day-title")

            Button {
                stepDay(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 36, minHeight: 44)
            }
            .accessibilityLabel(String(localized: "Next day"))
            .accessibilityIdentifier("site-day-next")
        }
    }

    // MARK: - Not written yet

    @ViewBuilder
    private var unwrittenSections: some View {
        let kind = unwrittenKind
        Section {
            SiteUnwrittenHeader(
                kind: kind,
                usualTimes: SiteDayStyle.range(usualTimes.start, usualTimes.end, on: date, formatting: formatting),
                usualBreak: SiteDayStyle.breakText(usualTimes.breakMinutes)
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: Metrics.large + 4, bottom: 0, trailing: Metrics.large))
        }

        Section {
            ForEach(rows(for: draftDay)) { person in
                draftRow(person)
            }
        } footer: {
            Text("Tap a name to change their times or say why they weren't here.")
        }

        Section {
            if kind == .missed {
                Button("Someone was different") { activeSheet = .crewDay(draftDay) }
                    .disabled(!canEdit)
                    .accessibilityIdentifier("site-day-something-different")
            } else if let lastDaySummary {
                sameAsLastDayRow(summary: lastDaySummary)
            }
            Button("Start from empty") {
                activeSheet = .crewDay(SiteDay(siteID: site.id, date: date, jobID: site.jobID))
            }
            .disabled(!canEdit)
            .accessibilityIdentifier("site-day-start-empty")
        } footer: {
            if kind == .missed {
                Text("Nobody worked that day? Choose “Start from empty” and leave everyone unticked, or mark it as bad weather.")
            }
        }
    }

    /// One person the draft would tick, or not: a menu to change them.
    private func draftRow(_ person: PersonReference) -> some View {
        let state = SiteCrewState.of(person.id, in: draftDay)
        let mine = draftDay.resolved(for: person.id)
        let value: String
        switch state {
        case .usual, .ownTimes, .moved:
            value = SiteDayStyle.range(mine?.start, mine?.end, on: date, formatting: formatting)
        case let .away(reason):
            value = SiteAwaySheet.title(of: reason, dayTypes: settings.dayTypeCatalog, siteNames: siteNames)
        case .notHere:
            value = String(localized: "Not here")
        }
        return Menu {
            Button("Usual") {
                pendingDraft = draftDay.settingUsual(for: person.id, allowanceByDefault: allowanceByDefault)
            }
            Button("Late/early") { activeSheet = .personTimes(person) }
            Button("Away") { activeSheet = .away(person) }
        } label: {
            SiteDraftPersonRow(
                person: person,
                isHere: state.isHere,
                value: value,
                needsAttention: state.needsAttention
            )
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityLabel(Text(verbatim: person.name))
        .accessibilityValue(Text(verbatim: value))
        .accessibilityAddTraits(state.isHere ? .isSelected : [])
        .accessibilityIdentifier("site-person-\(SiteDayStyle.key(person))")
    }

    /// "Same as yesterday" or "Same as last day", with what it would copy.
    private func sameAsLastDayRow(summary: String) -> some View {
        Button(action: fillFromLastDay) {
            VStack(alignment: .leading, spacing: 2) {
                Text(copiesYesterday ? "Same as yesterday" : "Same as last day")
                Text(verbatim: summary)
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
            }
        }
        .disabled(!canEdit)
        // Read as one sentence, so VoiceOver says what would be copied and
        // a test can check it names the right day.
        .accessibilityLabel(Text(copiesYesterday ? "Same as yesterday" : "Same as last day") + Text(verbatim: ", \(summary)"))
        .accessibilityIdentifier("site-day-same-as-last")
    }

    /// Save the draft and "Someone was different"; on a missed day with an
    /// earlier one to copy, "Same as the day before" first.
    private var unwrittenButtons: some View {
        VStack(spacing: Metrics.small) {
            if unwrittenKind == .missed, let lastDaySummary {
                Text(verbatim: lastDaySummary)
                    .font(.footnote)
                    .foregroundStyle(.hoursSecondaryText)
                    .accessibilityHidden(true)
                Button(action: fillFromLastDay) {
                    Text("Same as the day before")
                }
                .buttonStyle(.bigAction(.primary))
                .disabled(!canEdit)
                .accessibilityLabel(Text("Same as the day before") + Text(verbatim: ", \(lastDaySummary)"))
                .accessibilityIdentifier("site-day-same-as-last")

                saveButton(kind: .secondary)
            } else {
                saveButton(kind: .primary)
                if unwrittenKind != .missed {
                    Button {
                        activeSheet = .crewDay(draftDay)
                    } label: {
                        Text("Someone was different")
                    }
                    .buttonStyle(.bigAction(.secondary))
                    .disabled(!canEdit)
                    .accessibilityIdentifier("site-day-something-different")
                }
            }
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(Color.hoursCanvas)
    }

    /// "Save · 5 people, 37h 30m": the usual day, or the draft as changed.
    private func saveButton(kind: BigActionKind) -> some View {
        let figures = SiteCrewFigures(SiteDayCalculator(settings: settings, calendar: calendar).compute(draftDay).people)
        let people = String(inflected: "^[\(figures.people) person](inflect: true)")
        return Button {
            ticks += 1
            commit(draftDay)
        } label: {
            Text("Save") + Text(verbatim: " · \(people), \(formatter.string(figures.totalMinutes))")
        }
        .buttonStyle(.bigAction(kind))
        .disabled(!canEdit)
        .accessibilityIdentifier("site-day-same-as-usual")
    }

    /// Today, copying yesterday: "Same as yesterday", as the site widget says.
    private var copiesYesterday: Bool {
        date == today && lastDayDate == today.adding(days: -1, in: calendar)
    }

    /// The day not written yet as it stands: the usual day until a person
    /// is changed.
    private var draftDay: SiteDay { pendingDraft ?? usualDay }

    // MARK: - Written

    @ViewBuilder
    private var writtenSections: some View {
        Section {
            SiteWrittenHeader(
                figures: SiteCrewFigures(result.people),
                durations: formatter,
                showsSaved: showsSaved
            )
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: Metrics.large + 4, bottom: 0, trailing: Metrics.large + 4))
        }

        Section {
            ForEach(lines) { line in
                SiteDayLineRow(line: line, canEdit: canEdit) {
                    activeSheet = .away(line.person)
                }
            }
            ForEach(day.moves) { move in
                SiteMoveRow(
                    text: SiteMoveRow.text(
                        move, on: date,
                        names: Dictionary(rows.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }),
                        siteNames: siteNames,
                        formatting: formatting
                    ),
                    canEdit: canEdit,
                    onUndo: { undoMove(move) }
                )
            }
            ForEach(warnings) { warning in
                Label(warning.message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(warning.isProblem ? Color.hoursAttention : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if day.isBadWeatherStop {
            Section {
                SiteWeatherStopRow(
                    day: day,
                    canEdit: canEdit,
                    formatting: formatting,
                    onLift: { commit(day.liftingBadWeatherStop()) }
                )
            }
        }

        Section {
            detailRows
        }
    }

    /// One row per person on the written day: their times on the right and,
    /// under the name, only what was different.
    private var lines: [SiteDayLine] {
        rows.map { person -> SiteDayLine in
            let state = SiteCrewState.of(person.id, in: day)
            let mine = result.people.first { $0.memberID == person.id }
            let times = SiteDayStyle.range(mine?.start, mine?.end, on: date, formatting: formatting)
            switch state {
            case .usual:
                return SiteDayLine(person: person, value: times)
            case .ownTimes:
                return SiteDayLine(person: person, value: times, note: exceptionTitle(person.id), noteStyle: .attention)
            case let .moved(siteID):
                let site = siteNames[siteID] ?? String(localized: "Another site")
                let left = day.move(of: person.id).map { formatting.time($0.left, on: date) } ?? ""
                return SiteDayLine(
                    person: person,
                    value: times,
                    note: String(localized: "Moved to \(site) at \(left)", comment: "A written site day: someone left for another site; the values are the site and a time"),
                    noteStyle: .moved
                )
            case let .away(reason):
                return SiteDayLine(
                    person: person,
                    value: SiteAwaySheet.title(of: reason, dayTypes: settings.dayTypeCatalog, siteNames: siteNames),
                    isQuiet: true
                )
            case .notHere:
                // Only a hint, until it is confirmed on the crew's day.
                if let hint = elsewhere[person.id] {
                    return SiteDayLine(
                        person: person,
                        value: SiteAwaySheet.title(of: .otherSite(hint), dayTypes: settings.dayTypeCatalog, siteNames: siteNames),
                        isQuiet: true
                    )
                }
                if expectedCrew.contains(person.id) {
                    return SiteDayLine(
                        person: person,
                        value: "",
                        note: String(localized: "Not here · no reason given"),
                        noteStyle: .attention,
                        offersReason: true
                    )
                }
                return SiteDayLine(person: person, value: String(localized: "Not here"), isQuiet: true)
            }
        }
    }

    /// The day's times for everyone, field allowance, kilometres and the
    /// note on the sheet.
    @ViewBuilder
    private var detailRows: some View {
        Button { activeSheet = .siteTimes } label: {
            HStack(spacing: Metrics.small) {
                Text("Times for everyone")
                    .foregroundStyle(.primary)
                Spacer(minLength: Metrics.small)
                Text(verbatim: [
                    SiteDayStyle.range(day.start, day.end, on: date, formatting: formatting),
                    SiteDayStyle.breakText(day.breakMinutes),
                ].joined(separator: " · "))
                .monospacedDigit()
                .foregroundStyle(.hoursSecondaryText)
                .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityIdentifier("site-day-times")

        if settings.allowance.isEnabled {
            SiteLinkRow(
                title: String(localized: "Field allowance"),
                detail: String(inflected: "^[\(day.allowanceCount) person](inflect: true)")
            ) {
                activeSheet = .allowance
            }
            .disabled(!canEdit)
            .accessibilityIdentifier("site-day-allowance")

            // A day that already has kilometres shows them, asked or not.
            if setup.asksKilometres || day.kilometres > 0 {
                HStack(spacing: Metrics.small) {
                    Text("Van kilometres")
                    Spacer(minLength: Metrics.small)
                    TextField("Kilometres", text: $kilometresText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(minWidth: 64, maxWidth: 120, minHeight: 44)
                        .focused($isKilometresFocused)
                        .disabled(!canEdit)
                        .accessibilityIdentifier("site-day-kilometres")
                    Text(verbatim: "km")
                        .foregroundStyle(.hoursSecondaryText)
                        .accessibilityHidden(true)
                }
            }
        }

        // The one line for this day that goes on the Site sheet. The diary
        // is the longer record, printed on pages of its own.
        TextField(
            text: $noteText,
            prompt: Text("Note on the sheet"),
            axis: .vertical
        ) {
            Text("Note on the sheet")
        }
        .lineLimit(1...5)
        .focused($isNoteFocused)
        .disabled(!canEdit)
        .frame(minHeight: 44)
        .accessibilityIdentifier("site-day-note")
    }

    /// The diary, bad weather, the move and the crew: on every day.
    private var linksSection: some View {
        Section {
            // Unless the site's settings leave the diary out (1.2). A day
            // that already has one still shows it.
            if setup.keepsDiary || hasDiary {
                SiteLinkRow(
                    title: String(localized: "Diary for this day"),
                    detail: hasDiary ? String(localized: "Written") : nil
                ) {
                    commitNote()
                    commitKilometres()
                    activeSheet = .diary
                }
                .accessibilityIdentifier("site-day-diary")
            }
            if canEdit && !day.isBadWeatherStop {
                SiteLinkRow(title: String(localized: "Bad weather…")) {
                    activeSheet = .weatherStop(stored == nil ? draftDay : day)
                }
                .accessibilityIdentifier("site-weather-menu")
            }
            if canMove {
                SiteLinkRow(title: String(localized: "Moved to another site…")) {
                    activeSheet = .move(nil)
                }
                .accessibilityIdentifier("site-day-move")
            }
            // Open even when the day cannot be changed: the crew list says
            // for itself what can be done there.
            SiteLinkRow(title: String(localized: "Add or edit crew")) {
                openSiteCrew(SiteCrewRoute(siteID: site.id))
            }
            .accessibilityIdentifier("site-day-edit-crew")
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case let .crewDay(initial):
            SiteCrewDaySheet(
                title: dayTitle,
                initial: initial,
                rows: rows(for: initial),
                dayTypes: settings.dayTypeCatalog,
                otherSites: otherSites,
                siteNames: siteNames,
                elsewhere: elsewhere,
                usualTimes: usualTimes,
                allowanceByDefault: allowanceByDefault,
                onSave: saveCrewDay,
                onMove: moveFromCrewDay
            )
        case .siteTimes:
            // The site's usual day first (1.2), then the working week's.
            SiteTimesSheet(
                day: day,
                defaultStart: usualTimes.start,
                defaultEnd: usualTimes.end,
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
                runningClock: HoursStack.clock.running,
                preview: { choice in
                    guard let outcome = try? moveOutcome(choice) else { return nil }
                    return SiteCrewFigures.ofMove(outcome, calculator: SiteDayCalculator(settings: settings, calendar: calendar))
                }
            )
        case let .weatherStop(base):
            WeatherStopSheet(
                day: base.start == nil ? startingAtUsual(base) : base,
                suggested: base.end ?? usualTimes.end,
                figures: { stop in
                    SiteCrewFigures.ifStopped(
                        base, at: stop, startingAt: usualTimes.start,
                        calculator: SiteDayCalculator(settings: settings, calendar: calendar)
                    )
                },
                onSave: { stop in
                    commit(stop.map { stoppedAt($0, base: base) } ?? base.stoppedForBadWeather(at: nil))
                }
            )
        case .allowance:
            SiteAllowanceSheet(
                people: rows.filter { day.attendance(for: $0.id) != nil },
                given: Set(rows.map(\.id).filter(day.hasAllowance(for:))),
                onToggle: toggleAllowance
            )
        case .diary:
            SiteDiarySheet(
                siteID: site.id,
                date: date,
                siteName: site.name,
                canEdit: !isReadOnly,
                onChange: reloadDiaryMarks
            )
        case let .personTimes(person):
            let base = withUsualTimes(personBase)
            PersonTimesSheet(
                name: person.name,
                attendance: base.attendance(for: person.id) ?? Attendance(memberID: person.id),
                day: base,
                onSave: { attendance in
                    applyToPerson(base.settingAttendance(attendance, allowanceByDefault: allowanceByDefault))
                }
            )
        case let .away(person):
            let base = personBase
            SiteAwaySheet(
                person: person,
                date: date,
                current: base.absenceReason(for: person.id),
                hint: elsewhere[person.id],
                dayTypes: settings.dayTypeCatalog,
                otherSites: otherSites,
                onPick: { reason in
                    applyToPerson(reason.map { base.settingReason($0, for: person.id) } ?? base.settingNotHere(for: person.id))
                }
            )
        case let .extraWork(request):
            ExtraWorkEditorSheet(
                site: site,
                date: date,
                job: request.job,
                canEdit: !isReadOnly,
                onDone: reloadExtraWork
            )
        case .pickDate:
            SiteDayPickerSheet(date: date, calendar: calendar) { picked in
                select(picked)
            }
        }
    }

    /// The day a person's sheet changes: the draft while nothing is written,
    /// the stored day after.
    private var personBase: SiteDay { stored == nil ? draftDay : day }

    /// A person changed from their row: into the draft while nothing is
    /// written, saved at once after.
    private func applyToPerson(_ next: SiteDay) {
        if stored == nil {
            pendingDraft = next
        } else {
            ticks += 1
            commit(next)
        }
    }

    /// The day with the site's usual times, when it has none yet and is not
    /// a day the weather stopped before anyone started.
    private func withUsualTimes(_ base: SiteDay) -> SiteDay {
        guard base.start == nil, base.end == nil, !base.isBadWeatherStop else { return base }
        var next = base
        next.start = usualTimes.start
        next.end = usualTimes.end
        next.breakMinutes = usualTimes.breakMinutes
        return next
    }

    // MARK: - Extra work

    private func reloadExtraWork() {
        extraWork = ExtraWorkDayModel.load(siteID: site.id, date: date, context: modelContext)
    }

    private func toggleExtraWorkDone(_ job: ExtraWorkJob) {
        guard !isReadOnly else { return }
        ExtraWorkDayModel.toggleDone(job, context: modelContext, settingsStore: settingsStore)
        reloadExtraWork()
    }

    // MARK: - Moving between days

    /// The chevrons and the swipe: the day before or after.
    private func stepDay(_ direction: Int) {
        select(date.adding(days: direction, in: calendar))
    }

    /// Shows another day: what is being typed is saved first.
    private func select(_ newDate: CalendarDate) {
        guard newDate != date else { return }
        commitNote()
        commitKilometres()
        withAnimation(.snappy(duration: 0.2)) {
            date = newDate
        }
        load()
    }

    // MARK: - The day's people

    /// You and the visible crew: who the usual day ticks.
    private var defaultCrew: [PersonReference] {
        [PersonReference(id: CrewMember.youID, name: String(localized: "You"))]
            + crew.filter { !$0.isHidden }.map { PersonReference(id: $0.id, name: $0.name) }
    }

    /// The site's usual times, or the working week's (`SiteUsualTimes`).
    private var usualTimes: SiteUsualTimes {
        SiteUsualTimes(setup: setup, schedule: settings.primarySchedule(on: date))
    }

    private var allowanceByDefault: Bool {
        settings.allowance.isEnabled && site.allowanceByDefault
    }

    /// "Same as usual": the site's usual day for the default crew.
    private var usualDay: SiteDay {
        SiteDay.usual(
            siteID: site.id,
            date: date,
            jobID: site.jobID,
            times: usualTimes,
            crew: defaultCrew.map(\.id),
            allowanceByDefault: allowanceByDefault
        )
    }

    /// Today or later, a work day missed, or a day off gone by.
    private var unwrittenKind: SiteUnwrittenKind {
        guard date < today else { return .upcoming }
        let status = SiteDayStatus.of(
            siteID: site.id, on: date, siteDays: monthDays, setup: setup, crew: [],
            today: today, calendar: calendar, holidays: holidayDateKeys
        )
        return status == .missing ? .missed : .pastDayOff
    }

    /// "Thursday, 22 Oct · 5 people": what "Same as the day before" copies.
    /// Nil when there is no earlier day.
    private var lastDaySummary: String? {
        guard let lastDay, let lastDayDate else { return nil }
        return [
            formatting.dayTitle(lastDayDate),
            String(inflected: "^[\(lastDay.present.count) person](inflect: true)"),
        ].joined(separator: " · ")
    }

    private func exceptionTitle(_ memberID: UUID) -> String? {
        switch SiteException.of(memberID, in: day) {
        case .cameLate?: return String(localized: "Came late")
        case .leftEarly?: return String(localized: "Left early")
        case .changedTimes?: return String(localized: "Own times")
        case nil: return nil
        }
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
    private var rows: [PersonReference] { rows(for: day) }

    private func rows(for day: SiteDay) -> [PersonReference] {
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

    /// "Stopped at" on the selected day, with the site's start kept, or the
    /// schedule's when the day had none yet.
    private func stoppedAt(_ stop: TimeOfDay, base: SiteDay) -> SiteDay {
        startingAtUsual(base).stoppedForBadWeather(at: stop)
    }

    /// The day with the usual start, when it has none yet.
    private func startingAtUsual(_ base: SiteDay) -> SiteDay {
        var next = base
        if next.start == nil { next.start = usualTimes.start }
        return next
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
        pendingDraft = nil
        lastDay = store.sameAsLastDay(siteID: site.id, on: date)
        lastDayDate = lastDay == nil ? nil : store.lastSiteDay(siteID: site.id, before: date)?.date
        noteText = day.note
        kilometresText = Self.text(kilometres: day.kilometres)
        loadOtherSites()
        reloadMonth()
        reloadExtraWork()
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


    /// This site's days over the look-back and the month, who the day is
    /// checked against, and whether it has a diary. Read again after every
    /// write.
    private func reloadMonth() {
        let store = repository
        let month = date.yearMonth
        let range = month.range(in: calendar)
        let lookBack = CalendarDateRange(
            start: range.start.adding(days: -SiteWorkDays.lookBackDays, in: calendar),
            end: range.end
        )
        let allDays = store.siteDays(siteID: nil, in: lookBack)
        monthDays = allDays.filter { $0.siteID == site.id }
        let members = store.sites(includeArchived: true).flatMap { store.crew(for: $0.id, includeHidden: true) }
        expectedCrew = SiteMonthOverview.crew(
            siteID: site.id, members: members, siteDays: allDays, month: month, calendar: calendar
        ).expected(on: date)
        reloadDiaryMarks()
    }

    private func reloadDiaryMarks() {
        hasDiary = !SiteDiaryRepository(context: modelContext)
            .datesWithEntries(siteID: site.id, in: CalendarDateRange(single: date))
            .isEmpty
    }

    /// Public holidays off in the day's month: never "not written".
    private var holidayDateKeys: Set<Int> {
        guard settings.features.trackHolidays else { return [] }
        let range = date.yearMonth.range(in: calendar)
        return HolidayResolver(rules: holidayRecords.map(\.rule), calendar: calendar, covering: range)
            .daysOffKeys(in: range, calendar: calendar)
    }

    /// Whether your calendar counts your hours here. Read from your stored
    /// calendar day, which the save has just written.
    private func refreshYourWarning() {
        let record = WorkdayRepository(context: modelContext, lock: settings.monthLock).record(on: date)
        let computation = settingsStore.engine.day(date, record: record, holidays: holidayRecords.map(\.rule))
        yourHoursNotCounted = computation.warnings.contains(.siteHoursNotCounted)
    }

    // MARK: - Editing

    /// The crew's day saved: the draft goes through the one place a change
    /// is written. A day still unwritten that comes back with nobody on it
    /// and no reason given drops the times it started with, so it is not
    /// kept.
    private func saveCrewDay(_ draft: SiteDay) {
        var next = draft
        if stored == nil, next.present.isEmpty, next.absences.isEmpty, !next.isBadWeatherStop {
            next.start = nil
            next.end = nil
            next.breakMinutes = 0
        }
        ticks += 1
        commit(next)
    }

    /// "Moved" on the crew's day: what is there is saved first, then the
    /// move opens for that person, once the crew's sheet has gone.
    private func moveFromCrewDay(_ draft: SiteDay, _ memberID: UUID) {
        commit(draft)
        activeSheet = nil
        guard stored != nil, day.attendance(for: memberID) != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            activeSheet = .move(memberID)
        }
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
        guard date == today, canEdit, stored == nil, lastDay != nil else { return }
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
            }
            day = next
            pendingDraft = nil
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The calendar button's sheet: a month to pick a day from, opening on the
/// day shown. A pick goes to that day and closes the sheet.
private struct SiteDayPickerSheet: View {
    let date: CalendarDate
    let calendar: Calendar
    let onPick: (CalendarDate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Date

    init(date: CalendarDate, calendar: Calendar, onPick: @escaping (CalendarDate) -> Void) {
        self.date = date
        self.calendar = calendar
        self.onPick = onPick
        _selection = State(initialValue: date.date(in: calendar))
    }

    var body: some View {
        NavigationStack {
            DatePicker("Date", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.calendar, calendar)
                .padding(.horizontal, Metrics.large)
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityIdentifier("site-day-date-picker")
                .navigationTitle("Choose a day")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onPick(CalendarDate(selection, calendar: calendar))
                            dismiss()
                        }
                        .accessibilityIdentifier("site-day-date-done")
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
