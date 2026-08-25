import SwiftUI

/// The editor's fields.
///
/// Every section is conditional on a feature toggle: a switched-off feature
/// leaves no trace here, rather than sitting greyed out taking up space.
struct DayEditorForm: View {
    @Binding var draft: DayRecord
    let computation: DayComputation
    let settings: AppSettings
    let calendar: Calendar
    let formatting: CalendarFormatting

    private var formatter: DurationFormatting { settings.displayFormatting }

    var body: some View {
        Form {
            summarySection
            dayTypeSection
            workSections
            if settings.features.trackExpectedHours { expectedSection }
            if settings.features.allowManualAdjustments { adjustmentSection }
            detailsSection
            inclusionSection
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            DayResultHeader(computation: computation, settings: settings)
                .listRowInsets(EdgeInsets(top: Metrics.medium, leading: Metrics.large, bottom: Metrics.medium, trailing: Metrics.large))
        }
    }

    // MARK: - Day type

    private var dayTypeSection: some View {
        Section("Day type") {
            DayTypeMenu(
                selection: $draft.dayTypeID,
                catalog: settings.dayTypeCatalog,
                resolved: computation.dayType
            )
            if let holidayName = computation.holidayName {
                LabeledContent("Holiday", value: holidayName)
            }
        }
    }

    // MARK: - Work

    /// True once the day is one where times make sense, or the user has already
    /// entered some.
    private var showsTimes: Bool {
        computation.dayType.showsTimesByDefault || !draft.shifts.isEmpty
    }

    @ViewBuilder
    private var workSections: some View {
        if !settings.features.autoCalculateWorkedHours {
            Section {
                DurationStepperRow(
                    title: "Worked",
                    minutes: manualWorkedBinding,
                    range: 0...(24 * 60),
                    step: 5,
                    formatting: formatter
                )
            } header: {
                Text("Work")
            }
        } else if draft.shifts.isEmpty {
            Section {
                Button {
                    draft.shifts = [defaultShift()]
                } label: {
                    Label(showsTimes ? "Add hours" : "Add work times", systemImage: "clock")
                }
            } footer: {
                if !showsTimes {
                    Text("Working a day off or a public holiday is a real thing, so times can be added to any day.")
                }
            }
        } else {
            ForEach(draft.shifts.indices, id: \.self) { index in
                shiftSection(at: index)
            }
            Section {
                Button {
                    draft.shifts.append(defaultShift())
                } label: {
                    Label("Add another block", systemImage: "plus.circle")
                }
            } footer: {
                Text("A second block records a split shift — the time between blocks is neither worked nor a break.")
            }
        }
    }

    @ViewBuilder
    private func shiftSection(at index: Int) -> some View {
        Section {
            OptionalTimeRow(
                title: "Start",
                time: $draft.shifts[index].start,
                calendar: calendar,
                fallback: settings.primarySchedule.defaultStart
            )
            OptionalTimeRow(
                title: "End",
                time: $draft.shifts[index].end,
                calendar: calendar,
                fallback: settings.primarySchedule.defaultEnd
            )

            if settings.tracksMultipleJobs {
                jobPicker(at: index)
            }

            if settings.features.trackBreaks {
                breakRows(at: index)
            }

            if draft.shifts.count > 1 {
                Button("Remove this block", role: .destructive) {
                    draft.shifts.remove(at: index)
                }
            }
        } header: {
            Text(sectionTitle(at: index))
        } footer: {
            if index == 0 {
                Text("An end time earlier than the start is treated as an overnight shift.")
            }
        }
    }

    /// Only ever shown when there is more than one job to choose between.
    @ViewBuilder
    private func jobPicker(at index: Int) -> some View {
        Picker("Job", selection: jobBinding(at: index)) {
            ForEach(settings.activeJobs) { job in
                Text(job.name).tag(job.id)
            }
        }
    }

    private func jobBinding(at index: Int) -> Binding<UUID> {
        Binding(
            get: {
                guard index < draft.shifts.count else { return settings.primaryJob.id }
                // A shift recorded before jobs existed carries no id; it belongs
                // to the primary job, and saying so explicitly is what makes the
                // picker show the right thing.
                return draft.shifts[index].jobID ?? settings.primaryJob.id
            },
            set: { newValue in
                guard index < draft.shifts.count else { return }
                draft.shifts[index].jobID = newValue
            }
        )
    }

    private func sectionTitle(at index: Int) -> String {
        guard draft.shifts.count > 1 else { return "Work" }
        guard settings.tracksMultipleJobs, index < draft.shifts.count else {
            return "Block \(index + 1)"
        }
        return settings.job(draft.shifts[index].jobID).name
    }

    private func defaultShift() -> Shift {
        // A second block starts where the schedule's day would have ended,
        // which is a better guess than repeating the morning.
        let isFirst = draft.shifts.isEmpty
        let schedule = settings.primarySchedule
        return Shift(
            start: isFirst ? schedule.defaultStart : schedule.defaultEnd,
            end: nil,
            breaks: isFirst && schedule.defaultBreakMinutes > 0
                ? [BreakSpan.duration(schedule.defaultBreakMinutes)]
                : [],
            // Carry the previous block's job forward: a split shift is usually
            // two halves of the same day at the same place.
            jobID: draft.shifts.last?.jobID ?? (settings.tracksMultipleJobs ? settings.primaryJob.id : nil)
        )
    }

    private var manualWorkedBinding: Binding<Int> {
        Binding(
            get: { draft.manualWorkedMinutes ?? 0 },
            set: { draft.manualWorkedMinutes = $0 }
        )
    }

    // MARK: - Breaks

    @ViewBuilder
    private func breakRows(at index: Int) -> some View {
        if settings.features.multipleBreaksPerDay {
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
                let minutes = settings.primarySchedule.defaultBreakMinutes
                draft.shifts[index].breaks.append(.duration(minutes > 0 ? minutes : 15))
            } label: {
                Label("Add break", systemImage: "plus.circle")
            }
        } else {
            DurationStepperRow(
                title: "Break",
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
                return draft.shifts[index].breaks.reduce(0) { $0 + ($1.explicitMinutes ?? 0) }
            },
            set: { minutes in
                guard index < draft.shifts.count else { return }
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

    // MARK: - Expected

    private var expectedSection: some View {
        Section {
            if settings.features.allowPerDayExpectedOverride {
                Toggle("Custom expected hours", isOn: expectedOverrideToggle)
                if draft.expectedOverrideMinutes != nil {
                    DurationStepperRow(
                        title: "Expected",
                        minutes: expectedOverrideBinding,
                        range: 0...(24 * 60),
                        step: 15,
                        formatting: formatter
                    )
                }
            }
            if draft.expectedOverrideMinutes == nil {
                LabeledContent("Expected") {
                    Text(formatter.string(computation.expectedMinutes))
                        .font(.hoursFigure(.body, weight: .medium))
                }
            }
        } header: {
            Text("Expected hours")
        } footer: {
            if draft.expectedOverrideMinutes == nil {
                Text("From your weekly schedule for \(formatting.weekdayName(for: draft.date.weekday(in: calendar))).")
            }
        }
    }

    private var expectedOverrideToggle: Binding<Bool> {
        Binding(
            get: { draft.expectedOverrideMinutes != nil },
            set: { isOn in
                draft.expectedOverrideMinutes = isOn ? computation.expectedMinutes : nil
            }
        )
    }

    private var expectedOverrideBinding: Binding<Int> {
        Binding(
            get: { draft.expectedOverrideMinutes ?? 0 },
            set: { draft.expectedOverrideMinutes = $0 }
        )
    }

    // MARK: - Adjustment

    private var adjustmentSection: some View {
        Section {
            DurationStepperRow(
                title: "Adjustment",
                minutes: $draft.adjustmentMinutes,
                range: (-12 * 60)...(12 * 60),
                step: 15,
                signed: true,
                formatting: formatter
            )
            if draft.adjustmentMinutes != 0 {
                Picker("Reason", selection: $draft.adjustmentReason) {
                    ForEach(AdjustmentReason.allCases) { reason in
                        Label(reason.title, systemImage: reason.symbolName).tag(reason)
                    }
                }
            }

            if !settings.features.autoCalculateOvertime {
                Toggle("Set balance manually", isOn: manualBalanceToggle)
                if draft.manualBalanceMinutes != nil {
                    DurationStepperRow(
                        title: "Balance",
                        minutes: manualBalanceBinding,
                        range: (-24 * 60)...(24 * 60),
                        step: 15,
                        signed: true,
                        formatting: formatter
                    )
                }
            }
        } header: {
            Text("Corrections")
        } footer: {
            Text(draft.adjustmentMinutes == 0
                 ? "An adjustment changes the balance without changing the hours you worked."
                 : draft.adjustmentReason.explanation)
        }
    }

    private var manualBalanceToggle: Binding<Bool> {
        Binding(
            get: { draft.manualBalanceMinutes != nil },
            set: { isOn in draft.manualBalanceMinutes = isOn ? computation.balanceMinutes : nil }
        )
    }

    private var manualBalanceBinding: Binding<Int> {
        Binding(
            get: { draft.manualBalanceMinutes ?? 0 },
            set: { draft.manualBalanceMinutes = $0 }
        )
    }

    // MARK: - Details

    @ViewBuilder
    private var detailsSection: some View {
        if settings.features.trackNotes || settings.features.trackLocation || settings.features.trackTags {
            Section("Details") {
                if settings.features.trackNotes {
                    TextField("Notes", text: $draft.note, axis: .vertical)
                        .lineLimit(1...5)
                }
                if settings.features.trackLocation {
                    TextField("Location", text: $draft.location)
                        .textInputAutocapitalization(.words)
                }
                if settings.features.trackTags {
                    TextField("Tags, separated by commas", text: tagsBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
        }
    }

    private var tagsBinding: Binding<String> {
        Binding(
            get: { draft.tags.joined(separator: ", ") },
            set: { text in
                draft.tags = text
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    // MARK: - Inclusion

    private var inclusionSection: some View {
        Section {
            Toggle("Include in totals", isOn: $draft.isIncluded)
        } footer: {
            Text("Turn this off to keep a day's details without counting it towards any total.")
        }
    }
}
