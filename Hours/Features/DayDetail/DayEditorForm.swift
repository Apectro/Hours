import SwiftUI

/// The editor's fields (1.2, mockup DayEditor): Worked · Away · Day off on
/// top, then the times or the kind of absence, a big Worked total with the
/// day's overtime, "+ Another block of work", and "Allowance, km, note…",
/// which opens everything else on a page of its own (`DayExtrasScreen`).
///
/// Every section is conditional on a feature toggle: a switched-off feature
/// leaves no trace here, rather than sitting greyed out taking up space.
struct DayEditorForm: View {
    @Binding var draft: DayRecord
    let computation: DayComputation
    let settings: AppSettings
    let calendar: Calendar
    let formatting: CalendarFormatting
    /// The type the day resolves to with nothing chosen: the schedule, or a
    /// public holiday. Choosing a kind it already is leaves the day automatic.
    var automaticType: DayTypeDefinition? = nil
    /// Names for the shifts that come from a site day, by site.
    var siteNames: [UUID: String] = [:]
    /// Opens a site shift's day on its site, where it is changed.
    var onOpenSite: ((UUID) -> Void)? = nil
    /// What the day earns, when earnings are the main figure.
    var earnings: DayEarnings? = nil
    /// Vacation left in the leave year with this day as drafted; nil unless
    /// the day is a vacation day.
    var vacationLeft: HalfDays? = nil
    /// "Allowance, km, note…": the extras and corrections, pushed.
    var onOpenExtras: (() -> Void)? = nil

    private var formatter: DurationFormatting { settings.displayFormatting }
    /// The week in force on the day being edited: a day before a change of
    /// contract is offered the old contract's times.
    private var schedule: WorkSchedule { settings.primarySchedule(on: draft.date) }
    private var contracted: Int { settings.contractedMinutes(on: draft.date, calendar: calendar) }

    var body: some View {
        Form {
            kindSection
            ForEach(draft.shifts.filter { $0.siteID != nil }) { shift in
                siteShiftSection(shift)
            }
            switch kind {
            case .worked:
                workSections
            case .away, .dayOff:
                absenceSections
            }
            totalsSection
            linksSection
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Worked · Away · Day off

    private var kind: DayKind { DayKind.of(computation.dayType) }

    private var kindBinding: Binding<DayKind> {
        Binding(
            get: { kind },
            set: { newKind in
                guard newKind != kind else { return }
                var applied = newKind.apply(
                    to: draft,
                    automatic: automaticType ?? settings.dayTypeCatalog.definition(for: .work),
                    catalog: settings.dayTypeCatalog,
                    prefilled: settings.prefilledShift(on: draft.date),
                    contractedMinutes: contracted
                )
                // Hours typed as a figure: no times to give the day.
                if !settings.features.autoCalculateWorkedHours && newKind == .worked {
                    applied.shifts = draft.shifts
                }
                withAnimation(.snappy(duration: 0.2)) { draft = applied }
            }
        )
    }

    private var kindSection: some View {
        Section {
            Picker("Kind of day", selection: kindBinding) {
                Text("Worked").tag(DayKind.worked)
                Text("Away").tag(DayKind.away)
                Text("Day off").tag(DayKind.dayOff)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("day-editor-kind")
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            if let holidayName = computation.holidayName {
                Text(String(
                    localized: "\(holidayName) · public holiday",
                    comment: "Day editor: the holiday's name, e.g. Christmas Day · public holiday"
                ))
            }
        }
    }

    // MARK: - Worked

    /// The shifts typed in here. Site shifts are written by their site day
    /// and only shown (see `siteShiftSection`).
    private var manualShifts: [Shift] {
        draft.shifts.filter { $0.siteID == nil }
    }

    @ViewBuilder
    private var workSections: some View {
        if !settings.features.autoCalculateWorkedHours {
            Section {
                DurationStepperRow(
                    title: String(localized: "Worked"),
                    minutes: manualWorkedBinding,
                    range: 0...(24 * 60),
                    step: 5,
                    formatting: formatter
                )
            }
        } else if manualShifts.isEmpty {
            Section {
                Button {
                    draft.shifts.append(defaultShift())
                } label: {
                    Label("Add times", systemImage: "clock")
                }
                .accessibilityIdentifier("day-editor-add-hours")
            }
        } else {
            shiftSections
        }
    }

    /// One section per block of your own.
    ///
    /// Keyed by the shift's own id rather than by its position. Every row
    /// here binds straight into draft.shifts[index], and "Remove this block"
    /// deletes from that same array. Keyed by position, deleting the middle
    /// of three shifts renumbers the one after it, so SwiftUI keeps the view
    /// it already had and evaluates it against an index that is now past the
    /// end. Site shifts are left out here but keep their place in the array,
    /// so every index below still points into draft.shifts itself.
    private var shiftSections: some View {
        ForEach(Array(draft.shifts.enumerated()).filter { $0.element.siteID == nil }, id: \.element.id) { index, _ in
            shiftSection(at: index)
        }
    }

    @ViewBuilder
    private func shiftSection(at index: Int) -> some View {
        // Belt as well as braces: a binding read one frame after a removal
        // would still be out of range. A section that briefly does not draw
        // is a far better outcome than a crash in someone's timesheet.
        if index < draft.shifts.count, draft.shifts[index].siteID == nil {
            Section {
                OptionalTimeRow(
                    title: String(localized: "Start"),
                    time: $draft.shifts[index].start,
                    calendar: calendar,
                    fallback: schedule.defaultStart
                )
                OptionalTimeRow(
                    title: String(localized: "End"),
                    time: $draft.shifts[index].end,
                    calendar: calendar,
                    fallback: schedule.defaultEnd
                )

                if settings.features.trackBreaks {
                    breakRows(at: index)
                }

                if settings.tracksMultipleJobs {
                    jobPicker(at: index)
                }

                if manualShifts.count > 1 {
                    Button("Remove this block", role: .destructive) {
                        // Guarded because the closure captures the index it
                        // was built with, and two quick taps on two blocks
                        // both fire against the longer array.
                        guard index < draft.shifts.count else { return }
                        draft.shifts.remove(at: index)
                    }
                    .accessibilityIdentifier("day-editor-remove-block")
                }
            } header: {
                if let title = sectionTitle(at: index) {
                    Text(verbatim: title)
                }
            } footer: {
                if index == firstManualIndex {
                    Text("An end before the start counts as a night shift.")
                }
            }
        }
    }

    private var firstManualIndex: Int? {
        draft.shifts.firstIndex { $0.siteID == nil }
    }

    /// Only ever shown when there is more than one job to choose between.
    private func jobPicker(at index: Int) -> some View {
        Picker("Job", selection: jobBinding(at: index)) {
            ForEach(settings.activeJobs) { job in
                Text(job.displayName()).tag(job.id)
            }
        }
    }

    private func jobBinding(at index: Int) -> Binding<UUID> {
        Binding(
            get: {
                guard index < draft.shifts.count else { return settings.primaryJob.id }
                // A shift recorded before jobs existed carries no id; it
                // belongs to the primary job.
                return draft.shifts[index].jobID ?? settings.primaryJob.id
            },
            set: { newValue in
                guard index < draft.shifts.count else { return }
                draft.shifts[index].jobID = newValue
            }
        )
    }

    /// "Block 2 · Overtime job" once there is more than one block; nothing
    /// over a single block, as the mockup's working day.
    private func sectionTitle(at index: Int) -> String? {
        guard manualShifts.count > 1, index < draft.shifts.count else { return nil }
        // Counted among the typed-in blocks only, so a site shift ahead of
        // them does not make the first one "Block 2".
        let number = draft.shifts.prefix(index).filter { $0.siteID == nil }.count + 1
        let block = String(
            localized: "Block \(number)",
            comment: "Heading for the second and later blocks of a split shift"
        )
        guard settings.tracksMultipleJobs else { return block }
        let job = settings.job(draft.shifts[index].jobID).displayName()
        return [block, job].joined(separator: " · ")
    }

    private func defaultShift() -> Shift {
        // A second block starts where the schedule's day would have ended,
        // which is a better guess than repeating the morning.
        let isFirst = manualShifts.isEmpty
        return Shift(
            start: isFirst ? schedule.defaultStart : schedule.defaultEnd,
            end: nil,
            breaks: isFirst && schedule.defaultBreakMinutes > 0 && settings.features.trackBreaks
                ? [BreakSpan.duration(schedule.defaultBreakMinutes)]
                : [],
            // A split shift is usually two halves of the same day at the
            // same place.
            jobID: manualShifts.last?.jobID ?? (settings.tracksMultipleJobs ? settings.primaryJob.id : nil)
        )
    }

    private var manualWorkedBinding: Binding<Int> {
        Binding(
            get: { draft.manualWorkedMinutes ?? 0 },
            set: { draft.manualWorkedMinutes = $0 }
        )
    }

    // MARK: - Away and day off

    @ViewBuilder
    private var absenceSections: some View {
        let types = settings.dayTypeCatalog.types(of: kind)
        if types.count > 1 || kind == .away {
            Section {
                DayTypeGrid(
                    types: types,
                    selected: computation.dayType.id,
                    onSelect: choose
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if let vacationLeft {
                    Text(String(
                        localized: "Vacation left after this: \(vacationLeft.localized)",
                        comment: "Day editor, under the day type when it is Vacation; a number of days such as 17 or 17.5"
                    ))
                    .accessibilityIdentifier("day-editor-vacation-left")
                }
            }
        }

        Section {
            if showsHalfDay {
                Toggle("Half day", isOn: halfDayBinding)
                    .accessibilityIdentifier("day-editor-half-day")
            }
            LabeledContent("Counts as") {
                Text(verbatim: countsAs)
                    .foregroundStyle(.hoursSecondaryText)
            }
            .accessibilityIdentifier("day-editor-counts-as")
        } footer: {
            Text(verbatim: explanation)
        }

        if manualShifts.isEmpty || !settings.features.autoCalculateWorkedHours {
            if settings.features.autoCalculateWorkedHours {
                Section {
                    // Hours on top of the absence: a public holiday worked,
                    // a half day of leave with the morning on site. The type
                    // stays, so the absence is still paid.
                    Button {
                        draft.shifts.append(settings.prefilledShift(on: draft.date))
                    } label: {
                        Text("+ I still worked some hours")
                            .fontWeight(.semibold)
                    }
                    .accessibilityIdentifier("day-editor-holiday-worked")
                }
            }
        } else {
            shiftSections
            Section {
                Button("Remove these hours", role: .destructive) {
                    draft.shifts = draft.shifts.filter { $0.siteID != nil }
                }
                .accessibilityIdentifier("day-editor-remove-hours")
            }
        }
    }

    private func choose(_ definition: DayTypeDefinition) {
        withAnimation(.snappy(duration: 0.15)) {
            draft.dayTypeID = definition.id == automaticType?.id ? nil : definition.id
            // A day of leave has no hours in it unless you add them:
            // switching type inside Away keeps whatever is already there.
            if !definition.showsTimesByDefault, draft.manualWorkedMinutes != nil {
                draft.manualWorkedMinutes = nil
            }
        }
    }

    /// Half a day of paid absence: expected hours at half of the week's.
    private var showsHalfDay: Bool {
        settings.features.trackExpectedHours
            && settings.features.allowPerDayExpectedOverride
            && computation.dayType.expectation == .creditedAbsence
            && contracted > 0
    }

    private var halfDayBinding: Binding<Bool> {
        Binding(
            get: { HalfDay.isHalf(expectedOverride: draft.expectedOverrideMinutes, contracted: contracted) },
            set: { isOn in
                draft.expectedOverrideMinutes = isOn ? HalfDay.minutes(contracted: contracted) : nil
            }
        )
    }

    /// "8h 30m paid", "−8h from your balance" or "Nothing paid".
    private var countsAs: String {
        if computation.creditedMinutes > 0 {
            return String(
                localized: "\(formatter.string(computation.creditedMinutes)) paid",
                comment: "Day editor, Counts as: the hours an absence is paid at, e.g. 8h 30m paid"
            )
        }
        if computation.dayType.expectation == .scheduled, computation.expectedMinutes > 0 {
            return String(
                localized: "\(formatter.signedString(-computation.expectedMinutes)) from your balance",
                comment: "Day editor, Counts as: time off taken from overtime, e.g. −8h from your balance"
            )
        }
        return String(localized: "Nothing paid")
    }

    /// What the chosen type means, in a sentence.
    private var explanation: String {
        let type = computation.dayType
        switch type.expectation {
        case .creditedAbsence:
            let share = "\(type.paidPercent)%"
            var text = type.paidPercent >= 100
                ? String(localized: "Paid as a normal day.")
                : String(
                    localized: "Paid at \(share).",
                    comment: "Day editor, under an absence paid at a percentage; the value is like 70%"
                )
            if type.employerPaysFirst42Days {
                text += " " + String(localized: "The employer pays the first 42 days.")
            }
            return text
        case .scheduled:
            return String(localized: "The day's hours are expected and come off your overtime.")
        case .zero:
            return String(localized: "Nothing is expected, so your balance doesn't change.")
        }
    }

    // MARK: - Totals and the rest

    private var totalsSection: some View {
        Section {
            DayResultHeader(computation: computation, settings: settings, earnings: earnings)
                .listRowInsets(EdgeInsets(top: Metrics.medium, leading: Metrics.large, bottom: Metrics.medium, trailing: Metrics.large))
        }
    }

    private var linksSection: some View {
        Section {
            if kind == .worked && settings.features.autoCalculateWorkedHours && !manualShifts.isEmpty {
                Button {
                    draft.shifts.append(defaultShift())
                } label: {
                    Text("+ Another block of work")
                        .fontWeight(.semibold)
                }
                .accessibilityIdentifier("day-editor-add-block")
            }
            if kind == .worked {
                // Every type, Automatic included: the grid above only
                // shows a kind's own types, and a day can still be any.
                DayTypeMenu(
                    selection: $draft.dayTypeID,
                    catalog: settings.dayTypeCatalog,
                    resolved: computation.dayType
                )
            }
            if let onOpenExtras {
                Button(action: onOpenExtras) {
                    HStack(spacing: Metrics.small) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Allowance, km, note…")
                                .fontWeight(.semibold)
                            if !extrasSummary.isEmpty {
                                Text(verbatim: extrasSummary)
                                    .font(.footnote)
                                    .foregroundStyle(.hoursSecondaryText)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                // The identifier the old "More" row had: the tests that
                // open the day's rarer fields still find them by it.
                .accessibilityIdentifier("day-editor-more")
            }
        }
    }

    /// What is set on the extras page, named, so nothing hidden there is
    /// quietly changing the day.
    private var extrasSummary: String {
        var parts: [String] = []
        if draft.hasFieldAllowance { parts.append(String(localized: "Field allowance")) }
        if draft.kilometres > 0 {
            parts.append(String(
                localized: "\(draft.kilometres) km",
                comment: "A distance driven; the value is a number of kilometres"
            ))
        }
        if draft.travelMinutes > 0 { parts.append(String(localized: "Travel time")) }
        if !draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(String(localized: "Note")) }
        if !draft.tags.isEmpty { parts.append(String(localized: "Tags")) }
        if draft.expectedOverrideMinutes != nil && !HalfDay.isHalf(expectedOverride: draft.expectedOverrideMinutes, contracted: contracted) {
            parts.append(String(localized: "Expected hours"))
        }
        if draft.adjustmentMinutes != 0 || draft.manualBalanceMinutes != nil { parts.append(String(localized: "Corrections")) }
        if !draft.isIncluded { parts.append(String(localized: "Not counted")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Site shifts

    /// Your hours from a site day, read-only. The site day is the one place
    /// they are written, so the two can never disagree; changing them here
    /// would only be overwritten the next time the site day is saved.
    private func siteShiftSection(_ shift: Shift) -> some View {
        Section {
            LabeledContent("Start", value: shift.start.map { formatting.time($0, on: draft.date) } ?? "—")
            LabeledContent("End", value: shift.end.map { formatting.time($0, on: draft.date) } ?? "—")
            if shift.totalBreakMinutes > 0 {
                LabeledContent("Break", value: formatter.string(shift.totalBreakMinutes))
            }
            if settings.tracksMultipleJobs {
                LabeledContent("Job", value: settings.job(shift.jobID).displayName())
            }
            if let onOpenSite, let siteID = shift.siteID {
                Button {
                    onOpenSite(siteID)
                } label: {
                    Label("Open on site", systemImage: "building.2")
                }
                .accessibilityIdentifier("day-editor-open-site")
            }
        } header: {
            Text(shift.siteID.flatMap { siteNames[$0] } ?? String(localized: "Site"))
        } footer: {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                Text("Written on the site's day, so it is changed there.")
                // Once, under the first site shift: it is about the day.
                if shift.id == draft.shifts.first(where: { $0.siteID != nil })?.id,
                   computation.warnings.contains(.siteHoursNotCounted) {
                    Label(DayWarning.siteHoursNotCounted.message, systemImage: "exclamationmark.triangle")
                }
                if shift.id == draft.shifts.first(where: { $0.siteID != nil })?.id,
                   computation.warnings.contains(.ownHoursOverlapSite) {
                    Label(DayWarning.ownHoursOverlapSite.message, systemImage: "info.circle")
                }
            }
        }
    }

    // MARK: - Breaks

    /// A single stepper cannot express "12:00–12:30", so a shift holding a
    /// timed break gets the full list whether or not multiple breaks are on.
    /// The flag decides whether someone may *add* further breaks; it never
    /// decides whether what they already recorded stays editable.
    private func needsBreakList(at index: Int) -> Bool {
        guard index < draft.shifts.count else { return false }
        return settings.features.multipleBreaksPerDay
            || draft.shifts[index].breaks.contains(where: \.isTimed)
    }

    @ViewBuilder
    private func breakRows(at index: Int) -> some View {
        if needsBreakList(at: index) {
            ForEach($draft.shifts[index].breaks) { $span in
                BreakRow(
                    span: $span,
                    calendar: calendar,
                    fallbackStart: suggestedBreakStart(at: index),
                    formatting: formatter
                )
            }
            .onDelete { offsets in
                draft.shifts[index].breaks.remove(atOffsets: offsets)
            }

            Button {
                let minutes = schedule.defaultBreakMinutes
                draft.shifts[index].breaks.append(.duration(minutes > 0 ? minutes : 15))
            } label: {
                Label("Add break", systemImage: "plus.circle")
            }
            .accessibilityIdentifier("day-editor-add-break")
        } else {
            DurationStepperRow(
                title: String(localized: "Break"),
                minutes: singleBreakBinding(at: index),
                range: 0...(12 * 60),
                step: 5,
                formatting: formatter
            )
        }
    }

    /// With one break per block the whole thing is a single length, so
    /// switching a day between the two modes never loses what was recorded.
    private func singleBreakBinding(at index: Int) -> Binding<Int> {
        Binding(
            get: {
                guard index < draft.shifts.count else { return 0 }
                return draft.shifts[index].totalBreakMinutes
            },
            set: { minutes in
                guard index < draft.shifts.count else { return }
                // Safe to replace wholesale only because needsBreakList(at:)
                // sends any shift with a timed break to the list instead.
                draft.shifts[index].breaks = minutes > 0 ? [BreakSpan.duration(minutes)] : []
            }
        )
    }

    /// Four hours into the block, which is where a break usually lands.
    private func suggestedBreakStart(at index: Int) -> TimeOfDay {
        guard index < draft.shifts.count, let start = draft.shifts[index].start else {
            return TimeOfDay(hour: 12, minute: 0)
        }
        return TimeOfDay(minutes: (start.minutes + 240) % TimeOfDay.minutesPerDay)
    }
}

/// The day types of one kind as a two-column grid of buttons, each with its
/// colour (mockup DayEditor, Away). The chosen one is outlined in orange,
/// the colour rule's "away".
struct DayTypeGrid: View {
    let types: [DayTypeDefinition]
    let selected: DayTypeID
    let onSelect: (DayTypeDefinition) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.highContrast) private var highContrast

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Metrics.small), count: count)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: Metrics.small) {
            ForEach(types) { definition in
                let isOn = definition.id == selected
                Button {
                    onSelect(definition)
                } label: {
                    HStack(spacing: Metrics.small) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(definition.tint.color)
                            .frame(width: 14, height: 14)
                            .accessibilityHidden(true)
                        Text(definition.displayName())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isOn ? Color.hoursAttention : Color.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Metrics.medium)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(
                        isOn ? Color.hoursAttentionFill.opacity(0.12) : Color.hoursSurface,
                        in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                            .strokeBorder(
                                isOn ? Color.hoursAttention : Color(uiColor: .separator),
                                lineWidth: isOn || highContrast ? 1.5 : 1
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
                .accessibilityIdentifier("day-editor-type-\(definition.id.rawValue)")
            }
        }
    }
}
