import SwiftUI

/// "Allowance, km, note…" (1.2, mockup DayEditor, phone 4): the day's
/// extras and corrections, pushed from the editor onto its own stack. Back
/// and Done both return to the editor; nothing is saved until its Save.
///
/// Everything that was under the editor's old "More" and its lower
/// sections is here: allowance, kilometres and travel; note, location and
/// tags; expected hours, adjustments and a balance set by hand; whether the
/// day counts. Clearing the day is on the editor itself ("Clear this
/// day"), once, not here as well.
struct DayExtrasRoute: Hashable {}

struct DayExtrasScreen: View {
    @Binding var draft: DayRecord
    let computation: DayComputation
    let settings: AppSettings
    let calendar: Calendar
    let formatting: CalendarFormatting
    let onDone: () -> Void

    private var formatter: DurationFormatting { settings.displayFormatting }

    var body: some View {
        Form {
            onTheDaySection
            correctionsSection
            inclusionSection
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(formatting.mediumDate(draft.date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("day-extras-done")
            }
        }
        .accessibilityIdentifier("day-extras")
    }

    // MARK: - On the day

    @ViewBuilder
    private var onTheDaySection: some View {
        // The note is on the editor itself (design v2).
        let tracksDetails = settings.features.trackLocation || settings.features.trackTags
        if settings.allowance.isEnabled || tracksDetails {
            Section {
                if settings.allowance.isEnabled {
                    Toggle("Field allowance", isOn: $draft.hasFieldAllowance)
                        .accessibilityIdentifier("day-editor-allowance")
                    LabeledContent("Kilometres") {
                        TextField("Kilometres", text: kilometresBinding)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.hoursFigure(.body, weight: .medium))
                            .accessibilityIdentifier("day-editor-kilometres")
                    }
                    DurationStepperRow(
                        title: String(localized: "Travel time"),
                        minutes: $draft.travelMinutes,
                        range: 0...(12 * 60),
                        step: 5,
                        formatting: DurationFormatting(style: .clock)
                    )
                    .accessibilityIdentifier("day-editor-travel")
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
            } header: {
                Text("On the day")
                    .textCase(nil)
            } footer: {
                if settings.allowance.isEnabled {
                    VStack(alignment: .leading, spacing: Metrics.tiny) {
                        if siteGivesAllowance {
                            Text("Your site day gives the field allowance.")
                        }
                        if siteKilometres > 0 {
                            Text(String(
                                localized: "Plus \(siteKilometres) km from your site day.",
                                comment: "Day editor, under Kilometres; the value is a number of kilometres"
                            ))
                        }
                        Text(settings.allowance.travelCountsAsWork
                             ? "Travel time counts as work."
                             : "Travel time is recorded, not counted as work.")
                    }
                }
            }
        }
    }

    /// Plain text read on every keystroke, digits only, so Save never
    /// misses what was just typed (a formatted number field hands its value
    /// over only when it loses focus, and a number pad has no Return).
    private var kilometresBinding: Binding<String> {
        Binding(
            get: { draft.kilometres > 0 ? "\(draft.kilometres)" : "" },
            set: { draft.kilometres = Kilometres.parse($0) }
        )
    }

    private var siteGivesAllowance: Bool {
        draft.shifts.contains { $0.siteID != nil && $0.fieldAllowance }
    }

    private var siteKilometres: Int {
        draft.shifts.filter { $0.siteID != nil }.reduce(0) { $0 + $1.kilometres }
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

    // MARK: - Corrections

    @ViewBuilder
    private var correctionsSection: some View {
        if settings.features.trackExpectedHours || settings.features.allowManualAdjustments {
            Section {
                if settings.features.trackExpectedHours {
                    if settings.features.allowPerDayExpectedOverride {
                        Toggle("Custom expected hours", isOn: expectedOverrideToggle)
                    }
                    if draft.expectedOverrideMinutes != nil {
                        DurationStepperRow(
                            title: String(localized: "Expected hours today"),
                            minutes: expectedOverrideBinding,
                            range: 0...(24 * 60),
                            step: 15,
                            formatting: formatter
                        )
                    } else {
                        LabeledContent("Expected hours today") {
                            Text(formatter.string(computation.expectedMinutes))
                                .font(.hoursFigure(.body, weight: .medium))
                        }
                    }
                }
                if settings.features.allowManualAdjustments {
                    DurationStepperRow(
                        title: String(localized: "Adjustment"),
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
                        Toggle("Set balance by hand", isOn: manualBalanceToggle)
                        if draft.manualBalanceMinutes != nil {
                            DurationStepperRow(
                                title: String(localized: "Balance"),
                                minutes: manualBalanceBinding,
                                range: (-24 * 60)...(24 * 60),
                                step: 15,
                                signed: true,
                                formatting: formatter
                            )
                        }
                    }
                }
            } header: {
                Text("Corrections")
                    .textCase(nil)
            } footer: {
                VStack(alignment: .leading, spacing: Metrics.tiny) {
                    if settings.features.trackExpectedHours && draft.expectedOverrideMinutes == nil {
                        Text(String(
                            localized: "From your weekly schedule for \(formatting.weekdayName(for: draft.date.weekday(in: calendar))).",
                            comment: "Where the expected hours came from; the value is a weekday name"
                        ))
                    }
                    if settings.features.allowManualAdjustments {
                        Text(verbatim: draft.adjustmentMinutes == 0
                             ? String(localized: "Use a correction when your employer counted a day differently.")
                             : draft.adjustmentReason.explanation)
                    }
                }
            }
        }
    }

    private var expectedOverrideToggle: Binding<Bool> {
        Binding(
            get: { draft.expectedOverrideMinutes != nil },
            set: { isOn in draft.expectedOverrideMinutes = isOn ? computation.expectedMinutes : nil }
        )
    }

    private var expectedOverrideBinding: Binding<Int> {
        Binding(
            get: { draft.expectedOverrideMinutes ?? 0 },
            set: { draft.expectedOverrideMinutes = $0 }
        )
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

    // MARK: - Inclusion

    private var inclusionSection: some View {
        Section {
            Toggle("Count this day", isOn: $draft.isIncluded)
                .accessibilityIdentifier("day-editor-count-day")
        } footer: {
            Text("Off: kept for reference, not counted in any total.")
        }
    }
}
