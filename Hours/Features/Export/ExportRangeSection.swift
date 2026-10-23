import SwiftUI

/// Which days of your own go into the timesheet: a day, week, month or year
/// around the one the screen was opened on, or a custom range.
///
/// Every kind but custom steps with ‹ ›, a whole period at a time, so last
/// month is one tap away without going back to the calendar.
struct ExportRangeSection: View {
    @Binding var rangeKind: ExportRangeKind
    @Binding var customStart: Date
    @Binding var customEnd: Date
    /// The resolved range in words, for every kind but custom.
    let description: String
    /// "31 days · 22 with hours recorded".
    let footer: String
    let canStepForward: Bool
    /// -1 back, +1 forward, one period of the chosen kind.
    let onStep: (Int) -> Void

    var body: some View {
        Section {
            Picker("Range", selection: $rangeKind) {
                ForEach(ExportRangeKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if rangeKind == .custom {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                DatePicker("To", selection: $customEnd, displayedComponents: .date)
            } else {
                PeriodStepper(
                    title: description,
                    caption: footer,
                    previousLabel: previousLabel,
                    nextLabel: nextLabel,
                    canGoForward: canStepForward,
                    onPrevious: { onStep(-1) },
                    onNext: { onStep(1) }
                )
            }
        } header: {
            Text("Range")
        } footer: {
            // Under the stepper's title for the other kinds.
            if rangeKind == .custom {
                Text(verbatim: footer)
            }
        }
    }

    private var previousLabel: LocalizedStringKey {
        switch rangeKind {
        case .day: return "Previous day"
        case .week: return "Previous week"
        case .month, .custom: return "Previous month"
        case .year: return "Previous year"
        }
    }

    private var nextLabel: LocalizedStringKey {
        switch rangeKind {
        case .day: return "Next day"
        case .week: return "Next week"
        case .month, .custom: return "Next month"
        case .year: return "Next year"
        }
    }
}
