import SwiftUI

/// Break entry, in whichever form the user has enabled.
///
/// One break is the overwhelmingly common case and gets a single row. Multiple
/// breaks are opt-in, and each can be either a length or a pair of times.
struct BreakEditor: View {
    @Binding var breaks: [BreakSpan]
    let allowsMultiple: Bool
    let calendar: Calendar
    let defaultBreakMinutes: Int
    let shiftStart: TimeOfDay?
    var formatting: DurationFormatting = .display

    var body: some View {
        if allowsMultiple {
            multipleBreaks
        } else {
            DurationStepperRow(
                title: "Break",
                minutes: singleBreakBinding,
                range: 0...(12 * 60),
                step: 5,
                formatting: formatting
            )
        }
    }

    // MARK: - Single

    private var singleBreakBinding: Binding<Int> {
        Binding(
            get: { breaks.reduce(0) { $0 + ($1.explicitMinutes ?? 0) } },
            set: { minutes in
                breaks = minutes > 0 ? [BreakSpan.duration(minutes)] : []
            }
        )
    }

    // MARK: - Multiple

    @ViewBuilder
    private var multipleBreaks: some View {
        ForEach($breaks) { $span in
            BreakRow(
                span: $span,
                calendar: calendar,
                fallbackStart: fallbackBreakStart,
                formatting: formatting
            )
        }
        .onDelete { offsets in
            breaks.remove(atOffsets: offsets)
        }

        Button {
            breaks.append(.duration(defaultBreakMinutes > 0 ? defaultBreakMinutes : 15))
        } label: {
            Label("Add break", systemImage: "plus.circle")
        }
    }

    private var fallbackBreakStart: TimeOfDay {
        // Midday if we have nothing better; otherwise four hours into the shift,
        // which is where a break usually lands.
        guard let shiftStart else { return TimeOfDay(hour: 12, minute: 0) }
        return TimeOfDay(minutes: (shiftStart.minutes + 240) % TimeOfDay.minutesPerDay)
    }
}

private struct BreakRow: View {
    @Binding var span: BreakSpan
    let calendar: Calendar
    let fallbackStart: TimeOfDay
    let formatting: DurationFormatting

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Picker("Break style", selection: modeBinding) {
                Text("Length").tag(BreakMode.length)
                Text("Times").tag(BreakMode.times)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if span.isTimed {
                OptionalTimeRow(title: "From", time: $span.start, calendar: calendar, fallback: fallbackStart)
                OptionalTimeRow(
                    title: "To",
                    time: $span.end,
                    calendar: calendar,
                    fallback: TimeOfDay(minutes: (fallbackStart.minutes + 30) % TimeOfDay.minutesPerDay)
                )
            } else {
                DurationStepperRow(
                    title: "Length",
                    minutes: lengthBinding,
                    range: 0...(12 * 60),
                    step: 5,
                    formatting: formatting
                )
            }
        }
        .padding(.vertical, Metrics.tiny)
    }

    private enum BreakMode: Hashable {
        case length
        case times
    }

    private var modeBinding: Binding<BreakMode> {
        Binding(
            get: { span.isTimed ? .times : .length },
            set: { mode in
                switch mode {
                case .length:
                    let minutes = resolvedLength()
                    span.start = nil
                    span.end = nil
                    span.explicitMinutes = minutes
                case .times:
                    let minutes = span.explicitMinutes ?? 30
                    span.explicitMinutes = nil
                    span.start = fallbackStart
                    span.end = TimeOfDay(minutes: (fallbackStart.minutes + minutes) % TimeOfDay.minutesPerDay)
                }
            }
        )
    }

    private var lengthBinding: Binding<Int> {
        Binding(
            get: { span.explicitMinutes ?? 0 },
            set: { span.explicitMinutes = max(0, $0) }
        )
    }

    /// Converts a timed break back into a length when the user switches modes,
    /// so nothing is silently lost.
    private func resolvedLength() -> Int {
        guard let start = span.start, let end = span.end else { return span.explicitMinutes ?? 0 }
        let raw = end.minutes >= start.minutes
            ? end.minutes - start.minutes
            : end.minutes + TimeOfDay.minutesPerDay - start.minutes
        return max(0, raw)
    }
}
