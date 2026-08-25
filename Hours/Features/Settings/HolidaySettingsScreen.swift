import SwiftUI
import SwiftData

/// The holiday list.
///
/// Empty to begin with, and deliberately so: public holidays differ by country,
/// region, employer and year, and a wrong guess is worse than nothing.
struct HolidaySettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \HolidayRecord.name) private var records: [HolidayRecord]

    @State private var editingRule: HolidayRule?
    @State private var isCreating = false

    var body: some View {
        List {
            if records.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No holidays yet", systemImage: "flag")
                    } description: {
                        Text("Add the days that apply where you work. A recurring holiday only has to be entered once.")
                    } actions: {
                        Button("Add a holiday") { isCreating = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Section {
                    ForEach(records) { record in
                        Button {
                            editingRule = record.rule
                        } label: {
                            HolidayRow(
                                rule: record.rule,
                                calendar: calendar,
                                formatting: settingsStore.dateFormatting
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
            }

            Section {
                Button {
                    isCreating = true
                } label: {
                    Label("Add a holiday", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("Holidays")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingRule) { rule in
            HolidayEditor(rule: rule)
        }
        .sheet(isPresented: $isCreating) {
            HolidayEditor(rule: HolidayEditor.blankRule(on: CalendarDate.today(in: calendar)))
        }
    }

    private var calendar: Calendar { settingsStore.workCalendar }

    private func delete(at offsets: IndexSet) {
        let repository = WorkdayRepository(context: modelContext)
        for index in offsets where index < records.count {
            repository.deleteHoliday(id: records[index].identifier)
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
                    Picker("Repeats", selection: $draft.recurrence.kind) {
                        ForEach(HolidayRecurrence.Kind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Date") {
                    switch draft.recurrence.kind {
                    case .once:
                        DatePicker("Date", selection: onceDateBinding, displayedComponents: .date)
                    case .annual:
                        monthPicker
                        Stepper("Day \(draft.recurrence.day)", value: $draft.recurrence.day, in: 1...31)
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
                    }
                }

                if draft.recurrence.kind != .once {
                    Section {
                        Toggle("Only for certain years", isOn: yearBoundsToggle)
                        if draft.recurrence.startYear != nil || draft.recurrence.endYear != nil {
                            Stepper(
                                "From \(String(draft.recurrence.startYear ?? currentYear))",
                                value: startYearBinding,
                                in: 1900...2200
                            )
                            Stepper(
                                "Through \(String(draft.recurrence.endYear ?? currentYear))",
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
