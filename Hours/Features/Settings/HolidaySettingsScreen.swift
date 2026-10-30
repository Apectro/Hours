import SwiftUI
import SwiftData

/// Settings › Day types & holidays › Public holidays (1.2 redesign, board
/// 17): the country, its holidays this year with a tick for each one you
/// get off, and your own days off.
///
/// Empty to begin with, and deliberately so: public holidays differ by country,
/// region, employer and year, and a wrong guess is worse than nothing. Since
/// 1.1 a country's public holidays are one tap away ("Add public holidays"),
/// but still only when picked.
struct HolidaySettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \HolidayRecord.name) private var records: [HolidayRecord]

    @State private var activeSheet: ActiveSheet?
    @State private var isConfirmingRemoval = false

    /// One sheet at a time, chosen by value: two `.sheet` modifiers on one
    /// view is undefined behaviour.
    private enum ActiveSheet: Identifiable {
        case edit(HolidayRule)
        case publicHolidays

        var id: String {
            switch self {
            case let .edit(rule): return "edit-\(rule.id.uuidString)"
            case .publicHolidays: return "public-holidays"
            }
        }
    }
    var body: some View {
        List {
            publicHolidaysSection

            if !publicRecords.isEmpty {
                Section {
                    ForEach(publicRecords) { record in
                        tickRow(record)
                    }
                    .onDelete { delete(publicRecords, at: $0) }
                } header: {
                    Text(String(
                        localized: "\(String(year)) · Tick the ones you get off",
                        comment: "Settings › Public holidays, over the country's list; the value is a year"
                    ))
                }
            }

            Section {
                ForEach(ownRecords) { record in
                    Button {
                        activeSheet = .edit(record.rule)
                    } label: {
                        HolidayRow(
                            rule: record.rule,
                            calendar: calendar,
                            formatting: settingsStore.dateFormatting
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("holidays-row")
                }
                .onDelete { delete(ownRecords, at: $0) }

                Button {
                    activeSheet = .edit(newRule())
                } label: {
                    Label("Add your own day off", systemImage: "plus")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("holidays-add")
            } header: {
                Text("Your own days off")
            } footer: {
                Text("A public holiday is paid at your normal day. Work on one and it counts as overtime.")
            }
        }
        .navigationTitle("Public holidays")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case let .edit(rule):
                HolidayEditor(rule: rule)
            case .publicHolidays:
                PublicHolidayPicker {}
            }
        }
        .confirmationDialog(
            "Remove the public holidays that were added? Holidays you added yourself stay.",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove these holidays", role: .destructive) {
                PublicHolidayActions.removeAdded(context: modelContext, settingsStore: settingsStore)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// The country: which one, and the way back out; or the way in.
    @ViewBuilder
    private var publicHolidaysSection: some View {
        Section {
            if let added = settingsStore.settings.publicHolidays.addedSet {
                LabeledContent("Country") {
                    Text(verbatim: PublicHolidayActions.title(of: added))
                        .foregroundStyle(.hoursSecondaryText)
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("public-holidays-added")
                Button("Remove these holidays", role: .destructive) { isConfirmingRemoval = true }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("public-holidays-remove")
            } else {
                Button {
                    activeSheet = .publicHolidays
                } label: {
                    Label("Add public holidays", systemImage: "globe.europe.africa")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("public-holidays-open")
            }
        } footer: {
            if settingsStore.settings.publicHolidays.addedSet == nil {
                Text("Pick your country, and your state or canton where it matters. You see the list before anything is added.")
            }
        }
    }

    /// One of the country's holidays: its name, this year's date, and a
    /// tick for whether you get it off. The row opens the editor; the tick
    /// switches it on and off.
    private func tickRow(_ record: HolidayRecord) -> some View {
        let rule = record.rule
        return HStack(spacing: Metrics.medium) {
            Button {
                activeSheet = .edit(rule)
            } label: {
                HStack(spacing: Metrics.small) {
                    Text(rule.name.isEmpty ? String(localized: "Untitled") : rule.name)
                        .foregroundStyle(rule.isEnabled ? Color.primary : Color.secondary)
                    Spacer(minLength: Metrics.small)
                    if let date = rule.recurrence.occurrence(inYear: year, calendar: calendar) {
                        Text(settingsStore.dateFormatting.shortDate(date))
                            .foregroundStyle(.hoursSecondaryText)
                            .monospacedDigit()
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("holidays-row")

            Button {
                var changed = rule
                changed.isEnabled.toggle()
                WorkdayRepository(context: modelContext).upsert(changed)
                HoursStack.refreshWidget()
            } label: {
                Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(rule.isEnabled ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(verbatim: rule.name))
            .accessibilityValue(rule.isEnabled ? Text("Day off") : Text("Worked as normal"))
            .accessibilityAddTraits(rule.isEnabled ? .isSelected : [])
            .accessibilityIdentifier("holidays-tick")
        }
    }

    private var year: Int { CalendarDate.today(in: calendar).year }

    /// The ones the country's set added, by this year's date.
    private var publicRecords: [HolidayRecord] {
        let ids = Set(settingsStore.settings.publicHolidays.rulesToRemove(from: records.map(\.rule)))
        return records
            .filter { ids.contains($0.identifier) }
            .sorted { dateKey($0) < dateKey($1) }
    }

    /// Everything you added yourself.
    private var ownRecords: [HolidayRecord] {
        let ids = Set(settingsStore.settings.publicHolidays.rulesToRemove(from: records.map(\.rule)))
        return records.filter { !ids.contains($0.identifier) }
    }

    private func dateKey(_ record: HolidayRecord) -> Int {
        record.rule.recurrence.occurrence(inYear: year, calendar: calendar)?.key ?? Int.max
    }

    private var calendar: Calendar { settingsStore.workCalendar }

    private func newRule() -> HolidayRule {
        HolidayEditor.blankRule(on: CalendarDate.today(in: calendar))
    }

    private func delete(_ list: [HolidayRecord], at offsets: IndexSet) {
        let repository = WorkdayRepository(context: modelContext)
        for index in offsets where index < list.count {
            repository.deleteHoliday(id: list[index].identifier)
        }
    }
}

private struct HolidayRow: View {
    let rule: HolidayRule
    let calendar: Calendar
    let formatting: CalendarFormatting

    var body: some View {
        HStack(spacing: Metrics.medium) {
            Image(systemName: rule.countsAsWorkingDay ? "flag" : "flag.fill")
                .foregroundStyle(rule.isEnabled ? Color.purple : Color.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.name.isEmpty ? "Untitled" : rule.name)
                    .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let next = nextOccurrence {
            parts.append(formatting.mediumDate(next))
        } else {
            parts.append("No upcoming date")
        }
        if rule.recurrence.kind != .once { parts.append("repeats") }
        if rule.countsAsWorkingDay { parts.append("worked as normal") }
        if !rule.isEnabled { parts.append("off") }
        return parts.joined(separator: "  ·  ")
    }

    private var nextOccurrence: CalendarDate? {
        let today = CalendarDate.today(in: calendar)
        for year in today.year...(today.year + 5) {
            if let date = rule.recurrence.occurrence(inYear: year, calendar: calendar), date >= today {
                return date
            }
        }
        return rule.recurrence.occurrence(inYear: today.year, calendar: calendar)
    }
}

/// Creates or edits one holiday rule.
struct HolidayEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: HolidayRule

    init(rule: HolidayRule) {
        _draft = State(initialValue: rule)
    }

    static func blankRule(on date: CalendarDate) -> HolidayRule {
        HolidayRule(name: "", recurrence: .annual(month: date.month, day: date.day))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                }

                Section("Repeats") {
                    if draft.recurrence.kind.isMovable {
                        // Easter-based and the like come from a country's
                        // list and are not built by hand; the dates below
                        // show where they fall.
                        Text(draft.recurrence.kind.title)
                    } else {
                        Picker("Repeats", selection: $draft.recurrence.kind) {
                            ForEach(HolidayRecurrence.Kind.handMade) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                if !draft.recurrence.kind.isMovable {
                    Section("Date") {
                        switch draft.recurrence.kind {
                        case .once:
                            DatePicker("Date", selection: onceDateBinding, displayedComponents: .date)
                        case .annual:
                            monthPicker
                            Stepper(String(
                localized: "Day \(draft.recurrence.day)",
                comment: "Day of the month a holiday falls on"
            ), value: $draft.recurrence.day, in: 1...31)
                        case .nthWeekday:
                            Picker("Which", selection: $draft.recurrence.ordinal) {
                                Text("First").tag(1)
                                Text("Second").tag(2)
                                Text("Third").tag(3)
                                Text("Fourth").tag(4)
                                Text("Last").tag(-1)
                            }
                            Picker("Weekday", selection: $draft.recurrence.weekday) {
                                ForEach(1...7, id: \.self) { weekday in
                                    Text(formatting.weekdayName(for: weekday)).tag(weekday)
                                }
                            }
                            monthPicker
                        case .easter, .weekdayOnOrAfter, .annualOffSunday:
                            EmptyView()
                        }
                    }
                }

                if draft.recurrence.kind != .once {
                    Section {
                        Toggle("Only for certain years", isOn: yearBoundsToggle)
                        if draft.recurrence.startYear != nil || draft.recurrence.endYear != nil {
                            Stepper(
                                String(
                localized: "From \(String(draft.recurrence.startYear ?? currentYear))",
                comment: "First year a repeating holiday applies"
            ),
                                value: startYearBinding,
                                in: 1900...2200
                            )
                            Stepper(
                                String(
                localized: "Through \(String(draft.recurrence.endYear ?? currentYear))",
                comment: "Last year a repeating holiday applies"
            ),
                                value: endYearBinding,
                                in: 1900...2200
                            )
                        }
                    }
                }

                Section {
                    Toggle("Worked as a normal day", isOn: $draft.countsAsWorkingDay)
                    Toggle("Enabled", isOn: $draft.isEnabled)
                } footer: {
                    Text(draft.countsAsWorkingDay
                         ? "The day keeps its contracted hours and is expected to be worked. Only the name is carried through."
                         : "The day is paid absence: your contracted hours are credited, so the balance is unchanged.")
                }

                Section("Notes") {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if !upcoming.isEmpty {
                    Section("Next dates") {
                        ForEach(upcoming, id: \.key) { date in
                            Text(formatting.fullDate(date))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(draft.name.isEmpty ? "New holiday" : draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("holiday-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Pieces

    private var monthPicker: some View {
        Picker("Month", selection: $draft.recurrence.month) {
            ForEach(1...12, id: \.self) { month in
                Text(formatting.monthAbbreviation(YearMonth(year: currentYear, month: month))).tag(month)
            }
        }
    }

    private var calendar: Calendar { settingsStore.workCalendar }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }
    private var currentYear: Int { CalendarDate.today(in: calendar).year }

    private var upcoming: [CalendarDate] {
        var result: [CalendarDate] = []
        for year in currentYear...(currentYear + 4) {
            if let date = draft.recurrence.occurrence(inYear: year, calendar: calendar) {
                result.append(date)
            }
            if result.count == 3 { break }
        }
        return result
    }

    // MARK: - Bindings

    private var onceDateBinding: Binding<Date> {
        Binding(
            get: {
                CalendarDate(
                    year: draft.recurrence.year,
                    month: draft.recurrence.month,
                    day: draft.recurrence.day
                ).date(in: calendar)
            },
            set: { date in
                let value = CalendarDate(date, calendar: calendar)
                draft.recurrence.year = value.year
                draft.recurrence.month = value.month
                draft.recurrence.day = value.day
            }
        )
    }

    private var yearBoundsToggle: Binding<Bool> {
        Binding(
            get: { draft.recurrence.startYear != nil || draft.recurrence.endYear != nil },
            set: { isOn in
                if isOn {
                    draft.recurrence.startYear = currentYear
                    draft.recurrence.endYear = currentYear + 1
                } else {
                    draft.recurrence.startYear = nil
                    draft.recurrence.endYear = nil
                }
            }
        )
    }

    private var startYearBinding: Binding<Int> {
        Binding(
            get: { draft.recurrence.startYear ?? currentYear },
            set: { draft.recurrence.startYear = $0 }
        )
    }

    private var endYearBinding: Binding<Int> {
        Binding(
            get: { draft.recurrence.endYear ?? currentYear },
            set: { draft.recurrence.endYear = $0 }
        )
    }

    private func save() {
        var rule = draft
        rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        WorkdayRepository(context: modelContext).upsert(rule)
        dismiss()
    }
}
