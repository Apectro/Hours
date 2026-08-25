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
            if showsTimes { timesSection }
            if settings.features.trackBreaks && showsTimes { breakSection }
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

    // MARK: - Times

    private var showsTimes: Bool {
        computation.dayType.showsTimesByDefault || draft.start != nil || draft.end != nil
    }

    private var timesSection: some View {
        Section {
            if settings.features.autoCalculateWorkedHours {
                OptionalTimeRow(title: "Start", time: $draft.start, calendar: calendar, fallback: settings.schedule.defaultStart)
                OptionalTimeRow(title: "End", time: $draft.end, calendar: calendar, fallback: settings.schedule.defaultEnd)
                if computation.crossesMidnight {
                    Label("Ends the next day", systemImage: "moon.stars")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                DurationStepperRow(
                    title: "Worked",
                    minutes: manualWorkedBinding,
                    range: 0...(24 * 60),
                    step: 5,
                    formatting: formatter
                )
            }
        } header: {
            Text("Work")
        } footer: {
            if settings.features.autoCalculateWorkedHours {
                Text("An end time earlier than the start is treated as an overnight shift.")
            }
        }
    }

    private var manualWorkedBinding: Binding<Int> {
        Binding(
            get: { draft.manualWorkedMinutes ?? 0 },
            set: { draft.manualWorkedMinutes = $0 }
        )
    }

    // MARK: - Breaks

    @ViewBuilder
    private var breakSection: some View {
        Section("Break") {
            if settings.features.multipleBreaksPerDay {
                ForEach($draft.breaks) { $span in
                    BreakRow(
                        span: $span,
                        calendar: calendar,
                        fallbackStart: suggestedBreakStart,
                        formatting: formatter
                    )
                }
                .onDelete { offsets in
                    draft.breaks.remove(atOffsets: offsets)
                }

                Button {
                    let minutes = settings.schedule.defaultBreakMinutes
                    draft.breaks.append(.duration(minutes > 0 ? minutes : 15))
                } label: {
                    Label("Add break", systemImage: "plus.circle")
                }
            } else {
                DurationStepperRow(
                    title: "Break",
                    minutes: singleBreakBinding,
                    range: 0...(12 * 60),
                    step: 5,
                    formatting: formatter
                )
            }
        }
    }

    /// With one break the whole section is a single length, so switching a day
    /// between the two modes never loses the time already recorded.
    private var singleBreakBinding: Binding<Int> {
        Binding(
            get: { draft.breaks.reduce(0) { $0 + ($1.explicitMinutes ?? 0) } },
            set: { minutes in
                draft.breaks = minutes > 0 ? [BreakSpan.duration(minutes)] : []
            }
        )
    }

    /// Four hours into the shift, which is where a break usually lands.
    private var suggestedBreakStart: TimeOfDay {
        guard let start = draft.start else { return TimeOfDay(hour: 12, minute: 0) }
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
            Text("An adjustment changes the balance without changing the hours you worked.")
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
