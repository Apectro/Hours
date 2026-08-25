import SwiftUI
import SwiftData

/// Applies one change across a range of days.
///
/// Booking a fortnight of leave was ten trips through the day editor. This is
/// the same operation in one pass, and it says exactly what it will do before
/// it does any of it.
struct BulkEditSheet: View {
    let initialRange: CalendarDateRange

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    @Query(sort: \HolidayRecord.name) private var holidayRecords: [HolidayRecord]

    @State private var start: CalendarDate
    @State private var end: CalendarDate
    @State private var actionKind: ActionKind = .dayType
    @State private var dayTypeID: DayTypeID = .vacation
    @State private var skipsNonWorkingDays = true
    @State private var overwrites = false
    @State private var isConfirming = false

    init(initialRange: CalendarDateRange) {
        self.initialRange = initialRange
        _start = State(initialValue: initialRange.start)
        _end = State(initialValue: initialRange.end)
    }

    private enum ActionKind: String, CaseIterable, Identifiable {
        case dayType
        case workingPattern
        case clear

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dayType: return "Set type"
            case .workingPattern: return "Fill hours"
            case .clear: return "Clear"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Days") {
                    DatePicker("From", selection: dateBinding($start), displayedComponents: .date)
                    DatePicker("To", selection: dateBinding($end), displayedComponents: .date)
                }

                Section {
                    Picker("What to do", selection: $actionKind) {
                        ForEach(ActionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if actionKind == .dayType {
                        Picker("Type", selection: $dayTypeID) {
                            ForEach(settings.dayTypeCatalog.all) { definition in
                                Label(definition.name, systemImage: definition.symbolName)
                                    .tag(definition.id)
                            }
                        }
                    }
                } header: {
                    Text("Change")
                } footer: {
                    Text(actionDescription)
                }

                Section {
                    Toggle("Skip non-working days", isOn: $skipsNonWorkingDays)
                    Toggle("Replace days that already have hours", isOn: $overwrites)
                } footer: {
                    Text("Days you have already recorded are left alone unless you turn the second one on.")
                }

                Section("Result") {
                    LabeledContent("Days changed", value: "\(plan.affectedDayCount)")
                    if plan.skippedExisting > 0 {
                        LabeledContent("Already recorded", value: "\(plan.skippedExisting) left alone")
                    }
                    if plan.skippedNonWorking > 0 {
                        LabeledContent("Not working days", value: "\(plan.skippedNonWorking) skipped")
                    }
                }

                Section {
                    Button(role: actionKind == .clear ? .destructive : nil) {
                        if actionKind == .clear || overwrites {
                            isConfirming = true
                        } else {
                            apply()
                        }
                    } label: {
                        Text(applyTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(plan.isEmpty)
                }
            }
            .navigationTitle("Edit a range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                confirmationTitle,
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button(applyTitle, role: .destructive, action: apply)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var repository: WorkdayRepository { WorkdayRepository(context: modelContext) }
    private var range: CalendarDateRange { CalendarDateRange(start: start, end: end) }

    private var request: BulkEditRequest {
        BulkEditRequest(
            range: range,
            action: {
                switch actionKind {
                case .dayType: return .setDayType(dayTypeID)
                case .workingPattern: return .applyWorkingPattern
                case .clear: return .clear
                }
            }(),
            skipsNonWorkingDays: skipsNonWorkingDays,
            overwritesExistingEntries: overwrites
        )
    }

    private var plan: BulkEditPlan {
        BulkEditor.plan(
            request,
            existing: repository.records(in: range),
            settings: settings,
            calendar: calendar,
            holidays: holidayRecords.map(\.rule)
        )
    }

    private var actionDescription: String {
        switch actionKind {
        case .dayType:
            let name = settings.dayTypeCatalog.definition(for: dayTypeID).name.lowercased()
            return "Marks each day as \(name). Any hours on those days are removed if the type does not use times."
        case .workingPattern:
            return "Fills each day with your usual start, end and break. Public holidays in the range are left alone."
        case .clear:
            return "Removes everything recorded on those days."
        }
    }

    private var applyTitle: String {
        let count = plan.affectedDayCount
        let noun = count == 1 ? "day" : "days"
        switch actionKind {
        case .clear: return count == 0 ? "Nothing to clear" : "Clear \(count) \(noun)"
        default: return count == 0 ? "Nothing to change" : "Apply to \(count) \(noun)"
        }
    }

    private var confirmationTitle: String {
        actionKind == .clear
            ? "Clear \(plan.affectedDayCount) days?"
            : "Replace what is on \(plan.affectedDayCount) days?"
    }

    private func dateBinding(_ binding: Binding<CalendarDate>) -> Binding<Date> {
        Binding(
            get: { binding.wrappedValue.date(in: calendar) },
            set: { binding.wrappedValue = CalendarDate($0, calendar: calendar) }
        )
    }

    private func apply() {
        let plan = self.plan
        for record in plan.changes { repository.save(record) }
        for date in plan.deletions { repository.delete(on: date) }
        HoursStack.refreshWidget()
        dismiss()
    }
}
