import SwiftUI

/// What the day as drafted credits and earns, and its warnings, as plain
/// rows of the editor (design v2). The hours themselves are the sentence
/// under the times. Updates as you type.
struct DayResultRows: View {
    let computation: DayComputation
    let settings: AppSettings
    var earnings: DayEarnings? = nil

    private var duration: DurationFormatting { settings.displayFormatting }

    private var problems: [DayWarning] { computation.warnings.filter(\.isProblem) }

    /// Nothing to show: the section is left out.
    var isEmpty: Bool {
        !settings.features.showsBalance
            && computation.creditedMinutes == 0
            && !(earnings.map { $0.totalCents > 0 || $0.isPaidByHealthInsurance || $0.absencePaidPercent != nil } ?? false)
            && problems.isEmpty
    }

    var body: some View {
        if settings.features.showsBalance {
            // The day's own balance, by the colour rule: green over, red
            // short, grey at nothing.
            LabeledContent {
                Text(verbatim: computation.balanceMinutes == 0 ? "0" : duration.signedString(computation.balanceMinutes))
                    .monospacedDigit()
                    .foregroundStyle(Color.hoursBalance(computation.balanceMinutes))
            } label: {
                Text("Overtime today")
            }
            .accessibilityIdentifier("day-editor-overtime")
        }

        if computation.creditedMinutes > 0 {
            Label(
                String(
                    localized: "\(duration.string(computation.creditedMinutes)) credited as paid \(computation.dayType.nameInRunningText())",
                    comment: "e.g. 8h 00m credited as paid vacation; the second value is a day type"
                ),
                systemImage: "checkmark.seal"
            )
            .foregroundStyle(.hoursSecondaryText)
        }

        if let earnings, earnings.totalCents > 0 {
            Label(
                String(
                    localized: "\(settings.money.string(earnings.totalCents)) earned",
                    comment: "Day editor, what the day earns; the value is an amount of money"
                ),
                systemImage: "banknote"
            )
            .foregroundStyle(.hoursSecondaryText)
            .accessibilityIdentifier("day-earnings")
        }

        // Paid absence that pays less than in full: past the employer's
        // 42 days of sick leave (HZZO pays), or at a percentage.
        if let earnings, earnings.isPaidByHealthInsurance {
            Label(
                String(
                    localized: "Paid by health insurance",
                    comment: "Day editor, a sick day past the employer's first 42 days; Croatian names HZZO"
                ),
                systemImage: "cross.case"
            )
            .foregroundStyle(.hoursSecondaryText)
        } else if let percent = earnings?.absencePaidPercent {
            let share = "\(percent)%"
            Label(
                String(
                    localized: "Paid at \(share)",
                    comment: "Day editor, paid absence at a percentage; the value is like 70%"
                ),
                systemImage: "percent"
            )
            .foregroundStyle(.hoursSecondaryText)
        }

        ForEach(problems) { warning in
            Label(warning.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(Color.hoursAttention)
        }
    }
}

/// A time that may or may not be set. Clearing a time is a first-class action:
/// a day with a start but no end is a real, if incomplete, state.
struct OptionalTimeRow: View {
    let title: String
    @Binding var time: TimeOfDay?
    let calendar: Calendar
    let fallback: TimeOfDay

    var body: some View {
        if let current = time {
            HStack {
                DatePicker(
                    title,
                    selection: Binding(
                        get: { OptionalTimeRow.date(from: current, in: calendar) },
                        set: { time = OptionalTimeRow.time(from: $0, in: calendar) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                // A full 44-point target with room between it and the picker:
                // a gloved thumb reaching for the time must not clear it.
                Button {
                    time = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, Metrics.small)
                .accessibilityLabel(String(
                    localized: "Clear \(title.lowercased())",
                    comment: "VoiceOver, the button that empties a field named by the value"
                ))
            }
        } else {
            HStack {
                Text(title)
                Spacer()
                Button("Set") { time = fallback }
                    .buttonStyle(.borderless)
            }
        }
    }

    /// A neutral reference day is used for the picker so the control can never
    /// land inside a daylight-saving gap on the day being edited.
    static func date(from time: TimeOfDay, in calendar: Calendar) -> Date {
        var parts = DateComponents()
        parts.year = 2001
        parts.month = 1
        parts.day = 1
        parts.hour = time.hour
        parts.minute = time.minute
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    static func time(from date: Date, in calendar: Calendar) -> TimeOfDay {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}

/// A stepper over a duration in minutes, shown in the app's duration format.
struct DurationStepperRow: View {
    let title: String
    @Binding var minutes: Int
    var range: ClosedRange<Int> = 0...720
    var step: Int = 5
    var signed: Bool = false
    var formatting: DurationFormatting = .display

    var body: some View {
        Stepper(value: $minutes, in: range, step: step) {
            HStack {
                Text(title)
                Spacer(minLength: Metrics.small)
                Text(text)
                    .font(.hoursFigure(.body, weight: .medium))
                    .foregroundStyle(signed ? Color.hoursBalance(minutes) : .primary)
            }
        }
        .accessibilityValue(text)
    }

    private var text: String {
        signed ? formatting.signedString(minutes) : formatting.string(minutes)
    }
}

/// Picks a day type, including the "let the app decide" case that most days
/// should stay on.
struct DayTypeMenu: View {
    @Binding var selection: DayTypeID?
    let catalog: DayTypeCatalog
    let resolved: DayTypeDefinition

    var body: some View {
        Menu {
            Button {
                selection = nil
            } label: {
                Label("Automatic", systemImage: "wand.and.stars")
            }
            Divider()
            ForEach(catalog.all) { definition in
                Button {
                    selection = definition.id
                } label: {
                    Label(definition.displayName(), systemImage: definition.symbolName)
                }
            }
        } label: {
            HStack(spacing: Metrics.small) {
                Text("Type")
                    .foregroundStyle(.primary)
                Spacer(minLength: Metrics.small)
                Image(systemName: resolved.symbolName)
                    .foregroundStyle(resolved.tint.color)
                Text(selection == nil
                    ? String(localized: "\(resolved.name) · automatic",
                             comment: "A day type the app chose rather than the user")
                    : resolved.name)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Day type")
        .accessibilityValue(resolved.name)
        .accessibilityIdentifier("day-editor-day-type")
    }
}
