import SwiftUI

/// WHICH PERIOD (Export board, phone 2): Week · Month · Year · Dates, and
/// under it ‹ October 2026 › for the first three, or the two dates.
///
/// Every kind but Dates steps a whole period at a time, so last month is one
/// tap away without going back to the calendar. A single day is Dates with
/// the same day at both ends.
struct ExportRangeSection: View {
    @Binding var rangeKind: ExportRangeKind
    @Binding var customStart: Date
    @Binding var customEnd: Date
    /// "October 2026", "2026" or the week's dates.
    let title: String
    let canStepForward: Bool
    /// -1 back, +1 forward, one period of the chosen kind.
    let onStep: (Int) -> Void

    /// The kinds offered, in the board's order. `.day` is not offered on its
    /// own (the screen turns it into Dates).
    static let kinds: [ExportRangeKind] = [.week, .month, .year, .custom]

    var body: some View {
        Section {
            Picker("Which period", selection: $rangeKind) {
                ForEach(ExportRangeSection.kinds) { kind in
                    Text(Self.title(of: kind)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("export-range-kind")
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if rangeKind == .custom {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                    .frame(minHeight: 44)
                DatePicker("To", selection: $customEnd, in: customStart..., displayedComponents: .date)
                    .frame(minHeight: 44)
            } else {
                PeriodStepper(
                    title: title,
                    caption: "",
                    previousLabel: previousLabel,
                    nextLabel: nextLabel,
                    canGoForward: canStepForward,
                    onPrevious: { onStep(-1) },
                    onNext: { onStep(1) }
                )
            }
        } header: {
            Text("Which period")
        }
    }

    /// The segment's word: the export language's names for the periods,
    /// and "Dates" for a range picked by hand.
    static func title(of kind: ExportRangeKind) -> String {
        kind == .custom ? String(localized: "Dates", comment: "Export: the period segment for two dates picked by hand") : kind.title
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
