import SwiftUI

/// The live result at the top of the editor. Updates as you type, so the
/// consequence of a change is visible without leaving the screen.
struct DayResultHeader: View {
    let computation: DayComputation
    let settings: AppSettings
    /// Small, under the hours: the hours are what is being edited.
    var earnings: DayEarnings? = nil

    private var duration: DurationFormatting { settings.displayFormatting }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            HStack(alignment: .top, spacing: Metrics.small) {
                StatTile(label: String(localized: "Worked"), value: duration.string(computation.workedMinutes))

                if settings.features.trackExpectedHours {
                    Divider()
                    StatTile(label: String(localized: "Expected"), value: duration.string(computation.expectedMinutes))
                }

                if settings.features.showsBalance {
                    Divider()
                    // "Balance", as on the calendar and in the month's totals:
                    // the sign and the colour say which way it went.
                    StatTile(
                        label: String(localized: "Balance"),
                        value: duration.signedString(computation.balanceMinutes),
                        tint: Color.hoursBalance(computation.balanceMinutes)
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if computation.creditedMinutes > 0 {
                Label(
                    String(
                        localized: "\(duration.string(computation.creditedMinutes)) credited as paid \(computation.dayType.nameInRunningText())",
                        comment: "e.g. 8h 00m credited as paid vacation; the second value is a day type"
                    ),
                    systemImage: "checkmark.seal"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let earnings, earnings.totalCents > 0 {
                Label(
                    String(
                        localized: "\(settings.money.string(earnings.totalCents)) earned",
                        comment: "Day editor, what the day earns; the value is an amount of money"
                    ),
                    systemImage: "banknote"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if let percent = earnings?.absencePaidPercent {
                let share = "\(percent)%"
                Label(
                    String(
                        localized: "Paid at \(share)",
                        comment: "Day editor, paid absence at a percentage; the value is like 70%"
                    ),
                    systemImage: "percent"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            ForEach(computation.warnings.filter(\.isProblem)) { warning in
                Label(warning.message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.hoursNegative)
            }
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
