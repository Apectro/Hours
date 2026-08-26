import SwiftUI

/// One break, edited either as a length or as a pair of clock times.
///
/// This is a single list row by design. The section that holds several of them
/// builds the `ForEach` itself, so swipe-to-delete and the "add" button are
/// real rows of the form rather than views nested inside another view.
struct BreakRow: View {
    @Binding var span: BreakSpan
    let calendar: Calendar
    let fallbackStart: TimeOfDay
    var formatting: DurationFormatting = .display

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Picker("Break style", selection: modeBinding) {
                Text("Length").tag(BreakMode.length)
                Text("Times").tag(BreakMode.times)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if span.isTimed {
                OptionalTimeRow(title: String(localized: "From"), time: $span.start, calendar: calendar, fallback: fallbackStart)
                OptionalTimeRow(
                    title: String(localized: "To"),
                    time: $span.end,
                    calendar: calendar,
                    fallback: TimeOfDay(minutes: (fallbackStart.minutes + 30) % TimeOfDay.minutesPerDay)
                )
            } else {
                DurationStepperRow(
                    title: String(localized: "Length"),
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
