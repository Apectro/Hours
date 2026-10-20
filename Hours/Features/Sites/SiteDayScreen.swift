import SwiftUI
import SwiftData

/// Writing up one day on a site (mockup screen 2): the site's times once for
/// everyone, a tick for each person who was there, and changed times only for
/// whoever came late or left early.
///
/// Edits are saved as they are made, with no Save button. This is a page you
/// move through day by day with the arrows, not a sheet you open and dismiss,
/// and a draft that vanished on the next arrow tap would be a save that
/// silently did nothing. Every write goes through `SiteRepository` with the
/// month lock, which writes your calendar day in the same step; a refusal is
/// shown with the calendar's own message and the screen goes back to what is
/// stored, so it never shows hours that are not recorded.
///
/// A date with nothing recorded opens empty, nobody ticked, with "Same as last
/// day" offered first. Opening it writes nothing: the day is stored on the
/// first tick or time, and deleted again when it is emptied.
struct SiteDayScreen: View {
    let site: Site
    /// One of the extra sites after Pro lapsed: shown, not changed.
    let isReadOnly: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    @Query private var holidayRecords: [HolidayRecord]

    @State private var date: CalendarDate
    /// What the screen shows. Equal to `stored` except for a day that is not
    /// yet worth storing (see `SiteDay.isBlank`).
    @State private var day: SiteDay
    @State private var stored: SiteDay?
    /// What "Same as last day" would fill in, if there is an earlier day.
    @State private var lastDay: SiteDay?
    /// Hidden members included, because a past day may name one.
    @State private var crew: [CrewMember] = []
    /// The note is typed here and saved when the field loses focus, rather
    /// than on every keystroke, which would rewrite your calendar day per letter.
    @State private var noteText = ""
    @State private var yourHoursNotCounted = false
    @State private var editingPerson: PersonReference?
    /// Set when a write is refused. Non-nil is the alert's own trigger, so a
    /// refusal cannot be recorded without being shown.
    @State private var refusal: Error?
    @FocusState private var isNoteFocused: Bool

    init(site: Site, isReadOnly: Bool, date: CalendarDate) {
        self.site = site
        self.isReadOnly = isReadOnly
        _date = State(initialValue: date)
        _day = State(initialValue: SiteDay(siteID: site.id, date: date, jobID: site.jobID))
    }

    var body: some View {
        List {
            dateSection
            noticeSection
            timesSection
            if showsSameAsLastDay {
                sameAsLastDaySection
            }
            crewSection
            totalSection
            noteSection
        }
        .scrollDismissesKeyboard(.interactively)
        // A screen the UI tests wait for. The title above it is the site's name.
        .accessibilityIdentifier("screen-site-day")
        .onAppear { load() }
        .onDisappear { commitNote() }
        .onChange(of: isNoteFocused) { _, focused in
            if !focused { commitNote() }
        }
        .sheet(item: $editingPerson) { person in
            if let attendance = day.attendance(for: person.id) {
                PersonTimesSheet(
                    name: person.name,
                    attendance: attendance,
                    day: day,
                    onSave: replace
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

    // MARK: - Date

    private var dateSection: some View {
        Section {
            HStack(spacing: Metrics.medium) {
                Button {
                    move(to: date.adding(days: -1, in: calendar))
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Previous day")
                .accessibilityIdentifier("site-day-previous")

                Spacer(minLength: 0)

                DatePicker("Date", selection: dateBinding, displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityIdentifier("site-day-date")

                Spacer(minLength: 0)

                Button {
                    move(to: date.adding(days: 1, in: calendar))
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Next day")
                .accessibilityIdentifier("site-day-next")
            }
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { date.date(in: calendar) },
            set: { move(to: CalendarDate($0, calendar: calendar)) }
        )
    }

    // MARK: - Why it cannot be changed

    @ViewBuilder
    private var noticeSection: some View {
        if isLocked {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: Metrics.tiny) {
                        Text("This month is closed")
                            .font(.subheadline.weight(.semibold))
                        Text("Reopen it in Settings › Calculation if you need to change these hours.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("site-day-locked")
            }
        } else if isReadOnly {
            Section {
                Label {
                    Text("Read-only until Zeitkonto Pro is active again or your other sites are archived. Nothing on it is lost.")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "lock.fill")
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("site-day-read-only")
            }
        }
    }

    // MARK: - Site times

    private var timesSection: some View {
        Section {
            OptionalTimeRow(
                title: String(localized: "On site"),
                time: binding(\.start),
                calendar: calendar,
                fallback: settings.primarySchedule.defaultStart
            )
            OptionalTimeRow(
                title: String(localized: "Off site"),
                time: binding(\.end),
                calendar: calendar,
                fallback: settings.primarySchedule.defaultEnd
            )
            DurationStepperRow(
                title: String(localized: "Break"),
                minutes: binding(\.breakMinutes),
                range: 0...(12 * 60),
                step: 5,
                formatting: formatter
            )
        } header: {
            Text("Site times (everyone)")
        } footer: {
            warningsView
        }
        .disabled(!canEdit)
    }

    /// Quiet, as in the day editor: a half-entered day is a normal state while
    /// typing. Each warning once, however many people it applies to — with no
    /// end time it applies to all of them, and saying so per person is noise.
    @ViewBuilder
    private var warningsView: some View {
        let visible = warnings
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                ForEach(visible) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(warning.isProblem ? Color.hoursNegative : Color.secondary)
                }
            }
        }
    }

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

    // MARK: - Same as last day

    /// Only on a day with nothing in it, so it can never overwrite one.
    private var showsSameAsLastDay: Bool {
        lastDay != nil && day.present.isEmpty && day.start == nil && day.end == nil
    }

    private var sameAsLastDaySection: some View {
        Section {
            Button(action: fillFromLastDay) {
                Label("Same as last day", systemImage: "arrow.uturn.backward.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("site-day-same-as-last")
        } footer: {
            if let lastDay {
                Text(String(
                    localized: "Copies the times and who was there from \(formatting.mediumDate(lastDay.date)).",
                    comment: "Under the Same as last day button; the value is a date"
                ))
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .disabled(!canEdit)
    }

    // MARK: - Who was here

    private var crewSection: some View {
        Section {
            ForEach(rows) { row in
                personRow(row)
            }
        } header: {
            Text("Who was here")
        } footer: {
            Text("Tap a name to tick or untick them. Tap their times to change just that person.")
        }
    }

    private func personRow(_ row: PersonReference) -> some View {
        let person = result.people.first { $0.memberID == row.id }
        let exception = SiteException.of(row.id, in: day)

        return HStack(spacing: Metrics.medium) {
            Button {
                toggle(row.id)
            } label: {
                HStack(spacing: Metrics.medium) {
                    Image(systemName: person != nil ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(person != nil ? Color.accentColor : Color.secondary)
                    Text(row.name)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
            .accessibilityLabel(row.name)
            .accessibilityValue(person != nil ? String(localized: "Here") : String(localized: "Not here"))
            .accessibilityAddTraits(person != nil ? .isSelected : [])
            .accessibilityIdentifier(row.id == CrewMember.youID ? "site-person-you" : "site-person-\(row.name)")

            Button {
                editingPerson = row
            } label: {
                timesLabel(person: person, exception: exception)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit || person == nil)
            .accessibilityIdentifier(row.id == CrewMember.youID ? "site-times-you" : "site-times-\(row.name)")
        }
        .listRowBackground(exception != nil ? Color.hoursNegative.opacity(0.12) : nil)
    }

    @ViewBuilder
    private func timesLabel(person: PersonDay?, exception: SiteException?) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let person {
                if let exception {
                    Text(exceptionTitle(exception))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.hoursNegative)
                }
                Text(timeRange(person))
                    .font(.subheadline)
                    .foregroundStyle(exception != nil ? Color.hoursNegative : Color.secondary)
                Text(formatter.string(person.workedMinutes))
                    .font(.hoursFigure(.subheadline, weight: .medium))
                    .foregroundStyle(.primary)
            } else {
                Text("Not here")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: "—")
                    .font(.hoursFigure(.subheadline, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .multilineTextAlignment(.trailing)
    }

    private func exceptionTitle(_ exception: SiteException) -> String {
        switch exception {
        case .cameLate: return String(localized: "Came late")
        case .leftEarly: return String(localized: "Left early")
        case .changedTimes: return String(localized: "Own times")
        }
    }

    private func timeRange(_ person: PersonDay) -> String {
        guard let start = person.start, let end = person.end else { return "—" }
        return "\(formatting.time(start, on: date)) – \(formatting.time(end, on: date))"
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

    // MARK: - Total and note

    private var totalSection: some View {
        Section {
            HStack {
                Text("Crew total today")
                Spacer(minLength: Metrics.medium)
                Text(formatter.string(result.crewTotalMinutes))
                    .font(.hoursFigure(.body))
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("site-crew-total")
        }
    }

    private var noteSection: some View {
        Section {
            TextField("Notes", text: $noteText, axis: .vertical)
                .lineLimit(1...5)
                .focused($isNoteFocused)
                .disabled(!canEdit)
                .accessibilityIdentifier("site-day-note")
        } footer: {
            Text("Printed with this day when the site is exported.")
        }
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }
    private var formatter: DurationFormatting { settings.displayFormatting }

    private var isLocked: Bool { settings.monthLock.isLocked(date) }
    private var canEdit: Bool { !isReadOnly && !isLocked }

    private var result: SiteDayResult {
        SiteDayCalculator(settings: settings, calendar: calendar).compute(day)
    }

    private var repository: SiteRepository {
        SiteRepository(context: modelContext, lock: settings.monthLock)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SiteDay, Value>) -> Binding<Value> {
        Binding(
            get: { day[keyPath: keyPath] },
            set: { value in
                var next = day
                next[keyPath: keyPath] = value
                commit(next)
            }
        )
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
        noteText = day.note
        refreshYourWarning()
    }

    private func move(to newDate: CalendarDate) {
        guard newDate != date else { return }
        commitNote()
        date = newDate
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
        refreshYourWarning()
        HoursStack.refreshWidget()
    }
}

/// A row of the crew list: who, and the name to show.
struct PersonReference: Identifiable, Hashable {
    let id: UUID
    let name: String
}
