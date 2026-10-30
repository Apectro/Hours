import SwiftUI
import SwiftData

/// Applies one change across a range of days (1.2, mockup CalendarTools,
/// "Edit a range"): From and To, what to make them as chips, the two
/// switches, a live sentence saying what will happen — "Changes 10 days to
/// vacation. 2 days you don't work skipped · leave left after: 8 days" —
/// and one big button. Then a result screen with the count and OK.
///
/// Booking a fortnight of leave was ten trips through the day editor. This is
/// the same operation in one pass, and it says exactly what it will do before
/// it does any of it. There is no Undo: what a range edit replaces is not
/// kept, so the result screen does not offer to put it back.
struct BulkEditSheet: View {
    let initialRange: CalendarDateRange

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions

    @Query(sort: \HolidayRecord.name) private var holidayRecords: [HolidayRecord]

    @State private var start: CalendarDate
    @State private var end: CalendarDate
    @State private var choice: Choice = .dayType(.vacation)
    @State private var skipsNonWorkingDays = true
    @State private var overwrites = false
    @State private var isConfirming = false
    @State private var paywallReason: ProFeature?
    /// What was done, once it is: the result screen.
    @State private var result: BulkEditPlan?
    /// Months in the range that refused the edit. Non-empty is the alert's own
    /// trigger, so a refusal cannot be recorded without being shown.
    @State private var refusedMonths: [YearMonth] = []

    init(initialRange: CalendarDateRange) {
        self.initialRange = initialRange
        _start = State(initialValue: initialRange.start)
        _end = State(initialValue: initialRange.end)
    }

    /// What to make the days: the existing bulk actions.
    private enum Choice: Hashable {
        case dayType(DayTypeID)
        case workingPattern
        case clear
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    resultView(result)
                } else {
                    form
                }
            }
            .paywall(for: $paywallReason)
            .navigationTitle(result == nil ? String(localized: "Edit a range") : String(localized: "Changed"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if result == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier("bulk-edit-cancel")
                    }
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
            .alert(
                "Some of those months are closed",
                isPresented: Binding(
                    get: { !refusedMonths.isEmpty },
                    set: { if !$0 { refusedMonths = [] } }
                )
            ) {
                // Reopened here, where the edit is still set up; applying is
                // then one more tap. The alert is the confirmation.
                Button("Reopen") {
                    let months = refusedMonths
                    settingsStore.update { settings in
                        for month in months { settings.monthLock.unlock(month) }
                    }
                    refusedMonths = []
                }
                .accessibilityIdentifier("bulk-edit-reopen")
                Button("OK", role: .cancel) { refusedMonths = [] }
            } message: {
                Text(String(
                    localized: "Nothing was changed. Reopen \(refusedMonthNames) to make this change.",
                    comment: "Bulk edit refused; the value is a list of month names"
                ))
            }
        }
        .interactiveDismissDisabled(result != nil)
    }

    // MARK: - The form

    private var form: some View {
        Form {
            Section {
                DatePicker("From", selection: dateBinding($start), displayedComponents: .date)
                    .accessibilityIdentifier("bulk-edit-from")
                DatePicker("To", selection: dateBinding($end), displayedComponents: .date)
                    .accessibilityIdentifier("bulk-edit-to")
            }

            Section {
                ExtraWorkFlow(spacing: Metrics.small) {
                    chip(.dayType(.vacation), title: settings.dayTypeCatalog.definition(for: .vacation).displayName())
                    chip(.dayType(.sick), title: settings.dayTypeCatalog.definition(for: .sick).displayName())
                    chip(.workingPattern, title: String(localized: "Usual workday"))
                    chip(.dayType(.dayOff), title: settings.dayTypeCatalog.definition(for: .dayOff).displayName())
                    chip(.clear, title: String(localized: "Clear"))
                    otherTypeChip
                }
                .padding(.vertical, Metrics.tiny)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } header: {
                Text("Make them")
            } footer: {
                Text(verbatim: actionDescription)
            }

            Section {
                Toggle("Skip days you don't work", isOn: $skipsNonWorkingDays)
                    .accessibilityIdentifier("bulk-edit-skip")
                Toggle("Replace days that have hours", isOn: $overwrites)
                    .accessibilityIdentifier("bulk-edit-overwrite")
            } footer: {
                Text("Days you have already recorded are left alone unless you turn the second one on.")
            }

            Section {
                VStack(alignment: .leading, spacing: Metrics.tiny) {
                    Text(verbatim: sentence)
                        .font(.body.weight(.semibold))
                    if !details.isEmpty {
                        Text(verbatim: details)
                            .font(.subheadline)
                            .foregroundStyle(.hoursSecondaryText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Metrics.tiny)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("bulk-edit-result")
            }

            Section {
                Button {
                    // The plan above is computed and shown either way, so
                    // the offer is "this is what it would do".
                    guard subscriptions.allows(.rangeEditing) else {
                        paywallReason = .rangeEditing
                        return
                    }
                    if choice == .clear || overwrites {
                        isConfirming = true
                    } else {
                        apply()
                    }
                } label: {
                    Text(applyTitle)
                        .proLock(!subscriptions.allows(.rangeEditing))
                }
                .buttonStyle(.bigAction(choice == .clear ? BigActionKind.destructive : BigActionKind.primary, isMain: true))
                .disabled(plan.isEmpty)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("bulk-edit-apply")
            }
        }
    }

    private func chip(_ value: Choice, title: String) -> some View {
        let isOn = choice == value
        return Button {
            withAnimation(.snappy(duration: 0.15)) { choice = value }
        } label: {
            Text(verbatim: title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Metrics.medium + 2)
                .frame(minHeight: 44)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? Color.accentColor : Color.hoursSurface, in: Capsule())
                .overlay { Capsule().strokeBorder(isOn ? Color.clear : Color(uiColor: .separator), lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("bulk-edit-choice-\(identifier(value))")
    }

    /// Every other type, as the old type picker offered.
    private var otherTypeChip: some View {
        let shown: Set<DayTypeID> = [.vacation, .sick, .dayOff]
        let others = settings.dayTypeCatalog.all.filter { !shown.contains($0.id) }
        let current: DayTypeDefinition? = {
            if case let .dayType(id) = choice, !shown.contains(id) { return settings.dayTypeCatalog.definition(for: id) }
            return nil
        }()
        return Menu {
            ForEach(others) { definition in
                Button {
                    choice = .dayType(definition.id)
                } label: {
                    Label(definition.displayName(), systemImage: definition.symbolName)
                }
            }
        } label: {
            Text(verbatim: current?.displayName() ?? String(localized: "Other type…"))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Metrics.medium + 2)
                .frame(minHeight: 44)
                .foregroundStyle(current != nil ? Color.white : Color.accentColor)
                .background(current != nil ? Color.accentColor : Color.hoursSurface, in: Capsule())
                .overlay { Capsule().strokeBorder(current != nil ? Color.clear : Color(uiColor: .separator), lineWidth: 1) }
                .contentShape(Capsule())
        }
        .accessibilityIdentifier("bulk-edit-choice-other")
    }

    private func identifier(_ value: Choice) -> String {
        switch value {
        case let .dayType(id): return id.rawValue
        case .workingPattern: return "usual"
        case .clear: return "clear"
        }
    }

    // MARK: - The result

    private func resultView(_ plan: BulkEditPlan) -> some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            VStack(alignment: .leading, spacing: Metrics.small) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Days changed")
                    Spacer(minLength: Metrics.small)
                    Text(verbatim: "\(plan.affectedDayCount)")
                        .font(.hoursFigure(.largeTitle, weight: .heavy))
                        .foregroundStyle(Color.hoursPositive)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("bulk-edit-changed")
                Divider()
                resultRow(String(localized: "Already had hours, left alone"), plan.skippedExisting)
                Divider()
                resultRow(String(localized: "Days you don't work"), plan.skippedNonWorking)
            }
            .padding(Metrics.large)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: Metrics.large)

            Button {
                dismiss()
            } label: {
                Text("OK")
            }
            .buttonStyle(.bigAction(.primary, isMain: true))
            .accessibilityIdentifier("bulk-edit-done")
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.hoursCanvas)
    }

    private func resultRow(_ label: String, _ count: Int) -> some View {
        HStack {
            Text(verbatim: label)
            Spacer(minLength: Metrics.small)
            Text(verbatim: "\(count)")
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// The closed months, named. Nothing is changed when any of them is in
    /// range, so naming all of them saves a second attempt.
    private var refusedMonthNames: String {
        let formatting = settingsStore.dateFormatting
        return ListFormatter.localizedString(
            byJoining: refusedMonths.map { formatting.monthTitle($0) }
        )
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var repository: WorkdayRepository {
        WorkdayRepository(context: modelContext, lock: settings.monthLock)
    }
    private var range: CalendarDateRange { CalendarDateRange(start: start, end: end) }
    private var holidays: [HolidayRule] { holidayRecords.map(\.rule) }

    private var action: BulkAction {
        switch choice {
        case let .dayType(id): return .setDayType(id)
        case .workingPattern: return .applyWorkingPattern
        case .clear: return .clear
        }
    }

    private var request: BulkEditRequest {
        BulkEditRequest(
            range: range,
            action: action,
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
            holidays: holidays
        )
    }

    private var days: String {
        String(inflected: "^[\(plan.affectedDayCount) day](inflect: true)")
    }

    /// "Changes 10 days to vacation." — what the button will do.
    private var sentence: String {
        guard !plan.isEmpty else { return String(localized: "Nothing to change") }
        switch choice {
        case let .dayType(id):
            let name = settings.dayTypeCatalog.definition(for: id).nameInRunningText()
            return String(
                localized: "Changes \(days) to \(name).",
                comment: "Edit a range, what will happen; a number of days, then a day type, e.g. Changes 10 days to vacation."
            )
        case .workingPattern:
            return String(
                localized: "Fills \(days) with your usual hours.",
                comment: "Edit a range, what will happen; the value is a number of days"
            )
        case .clear:
            return String(
                localized: "Clears \(days).",
                comment: "Edit a range, what will happen; the value is a number of days"
            )
        }
    }

    /// "2 days you don't work skipped · 1 left alone · leave left after:
    /// 8 days", each part only when there is something to say.
    private var details: String {
        let plan = self.plan
        var parts: [String] = []
        if plan.skippedNonWorking > 0 {
            parts.append(String(
                localized: "\(plan.skippedNonWorking) skipped",
                comment: "Bulk edit, days the schedule does not work"
            ))
        }
        if plan.skippedExisting > 0 {
            parts.append(String(
                localized: "\(plan.skippedExisting) left alone",
                comment: "Bulk edit, days that already had hours and were not touched"
            ))
        }
        if let left = leaveLeft(plan) {
            parts.append(String(
                localized: "leave left after: \(left.localized)",
                comment: "Edit a range: vacation left in the leave year once applied; a number of days such as 8 or 7.5"
            ))
        }
        return parts.joined(separator: " · ")
    }

    /// Vacation left once applied, only when the edit books or frees leave.
    private func leaveLeft(_ plan: BulkEditPlan) -> HalfDays? {
        guard !plan.isEmpty else { return nil }
        let touchesLeave: Bool = {
            if case .dayType(.vacation) = choice { return true }
            let existing = repository.records(in: range)
            return plan.deletions.contains { existing[$0.key]?.dayTypeID == .vacation }
                || plan.changes.contains { existing[$0.date.key]?.dayTypeID == .vacation }
        }()
        guard touchesLeave else { return nil }
        let leave = settings.leave
        let year = leave.leaveYear(containing: start, calendar: calendar)
        return BulkEditLeave.remaining(
            after: plan,
            on: start,
            records: repository.records(in: leave.range(ofLeaveYear: year, calendar: calendar)),
            engine: settingsStore.engine,
            holidays: holidays,
            today: CalendarDate.today(in: calendar)
        )
    }

    private var actionDescription: String {
        switch choice {
        case let .dayType(id):
            let name = settings.dayTypeCatalog.definition(for: id).nameInRunningText()
            return String(localized: "Marks each day as \(name). Any hours on those days are removed if the type does not use times.")
        case .workingPattern:
            return String(localized: "Fills each day with your usual start, end and break. Public holidays in the range are left alone.")
        case .clear:
            return String(localized: "Removes everything recorded on those days.")
        }
    }

    private var applyTitle: String {
        let count = plan.affectedDayCount
        guard count > 0 else {
            return choice == .clear ? String(localized: "Nothing to clear") : String(localized: "Nothing to change")
        }
        return choice == .clear
            ? String(inflected: "Clear ^[\(count) day](inflect: true)")
            : String(localized: "Change \(days)", comment: "Edit a range's button; the value is a number of days")
    }

    private var confirmationTitle: String {
        let count = plan.affectedDayCount
        return choice == .clear
            ? String(inflected: "Clear ^[\(count) day](inflect: true)?")
            : String(inflected: "Replace what is on ^[\(count) day](inflect: true)?")
    }

    private func dateBinding(_ binding: Binding<CalendarDate>) -> Binding<Date> {
        Binding(
            get: { binding.wrappedValue.date(in: calendar) },
            set: { binding.wrappedValue = CalendarDate($0, calendar: calendar) }
        )
    }

    private func apply() {
        let plan = self.plan
        // Checked before anything is written rather than caught halfway. A
        // fortnight of leave that applied to the first four days and then
        // stopped is worse than one that refused outright.
        let closed = settingsStore.settings.monthLock.lockedMonths(
            in: CalendarDateRange(start: start, end: end),
            calendar: settingsStore.workCalendar
        )
        guard closed.isEmpty else {
            refusedMonths = closed
            return
        }
        do {
            for record in plan.changes { try repository.save(record) }
            for date in plan.deletions { try repository.delete(on: date) }
        } catch {
            refusedMonths = [YearMonth(start)]
            return
        }
        HoursStack.refreshWidget()
        withAnimation(.snappy(duration: 0.2)) { result = plan }
    }
}
