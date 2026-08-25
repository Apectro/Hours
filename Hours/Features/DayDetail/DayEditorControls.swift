import SwiftUI

/// The live result at the top of the editor. Updates as you type, so the
/// consequence of a change is visible without leaving the screen.
struct DayResultHeader: View {
    let computation: DayComputation
    let settings: AppSettings

    private var duration: DurationFormatting { settings.displayFormatting }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            HStack(alignment: .top, spacing: Metrics.small) {
                StatTile(label: "Worked", value: duration.string(computation.workedMinutes))

                if settings.features.trackExpectedHours {
                    Divider().frame(height: 34)
                    StatTile(label: "Expected", value: duration.string(computation.expectedMinutes))
                }

                if settings.features.showsBalance {
                    Divider().frame(height: 34)
                    StatTile(
                        label: computation.balanceMinutes < 0 ? "Short" : "Overtime",
                        value: duration.signedString(computation.balanceMinutes),
                        tint: Color.hoursBalance(computation.balanceMinutes)
                    )
                }
            }

            if computation.creditedMinutes > 0 {
                Label(
                    "\(duration.string(computation.creditedMinutes)) credited as paid \(computation.dayType.name.lowercased())",
                    systemImage: "checkmark.seal"
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
                Button {
                    time = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(title.lowercased())")
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
                    Label(definition.name, systemImage: definition.symbolName)
                }
            }
        } label: {
            HStack(spacing: Metrics.small) {
                Text("Type")
                    .foregroundStyle(.primary)
                Spacer(minLength: Metrics.small)
                Image(systemName: resolved.symbolName)
                    .foregroundStyle(resolved.tint.color)
                Text(selection == nil ? "\(resolved.name) · automatic" : resolved.name)
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
    }
}
