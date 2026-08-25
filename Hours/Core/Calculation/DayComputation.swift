import Foundation

/// Something worth telling the user about a day, without blocking them.
///
/// The app validates rather than forbids: a half-entered day is a normal state
/// while typing, so problems surface as quiet inline notices instead of alerts.
enum DayWarning: String, Hashable, Sendable, Identifiable, CaseIterable {
    case missingStartTime
    case missingEndTime
    case zeroLengthShift
    case breakLongerThanShift
    case breakOutsideShift
    case overlappingBreaksMerged
    case timeSkippedByClockChange
    case excludedFromTotals

    var id: String { rawValue }

    var message: String {
        switch self {
        case .missingStartTime: return "No start time — this day counts as 0 h worked."
        case .missingEndTime: return "No end time — this day counts as 0 h worked."
        case .zeroLengthShift: return "Start and end are the same, so nothing is counted."
        case .breakLongerThanShift: return "Breaks are longer than the shift; worked time is capped at 0 h."
        case .breakOutsideShift: return "A break falls outside the shift and was ignored."
        case .overlappingBreaksMerged: return "Overlapping breaks were merged so the time is not deducted twice."
        case .timeSkippedByClockChange: return "This time does not exist on this date because the clocks changed."
        case .excludedFromTotals: return "This day is excluded from all totals."
        }
    }

    var isProblem: Bool {
        switch self {
        case .overlappingBreaksMerged, .excludedFromTotals: return false
        default: return true
        }
    }
}

/// The fully resolved state of one day: what the user entered, what the rules
/// say, and what it adds up to. Views and exports read this and never
/// recalculate anything themselves.
struct DayComputation: Identifiable, Hashable, Sendable {
    var date: CalendarDate
    var dayType: DayTypeDefinition
    var holidayName: String?

    var start: TimeOfDay?
    var end: TimeOfDay?
    var breakMinutes: Int

    /// Time actually worked.
    var workedMinutes: Int
    /// Contracted hours credited for paid absence (vacation, sick, holiday).
    var creditedMinutes: Int
    /// Contracted hours owed for this day.
    var expectedMinutes: Int
    /// Manual correction included in the balance.
    var adjustmentMinutes: Int
    /// `paidMinutes - expectedMinutes + adjustment`, or a manual override.
    var balanceMinutes: Int

    var hasEntry: Bool
    var isIncluded: Bool
    var crossesMidnight: Bool

    var note: String
    var location: String
    var tags: [String]
    var warnings: [DayWarning]

    var id: Int { date.key }

    /// Everything the day pays: worked time plus credited absence.
    var paidMinutes: Int { workedMinutes + creditedMinutes }

    var overtimeMinutes: Int { max(0, balanceMinutes) }
    var deficitMinutes: Int { max(0, -balanceMinutes) }

    /// A day the schedule expects to be worked.
    var isScheduledWorkingDay: Bool {
        dayType.expectation == .scheduled && expectedMinutes > 0
    }

    var isPaidAbsence: Bool { creditedMinutes > 0 || dayType.expectation == .creditedAbsence }

    /// Whether the calendar should mark this day as carrying data.
    var hasContent: Bool {
        hasEntry || holidayName != nil || workedMinutes > 0
    }

    var hasProblem: Bool { warnings.contains { $0.isProblem } }

    static func empty(on date: CalendarDate) -> DayComputation {
        DayComputation(
            date: date,
            dayType: DayTypeCatalog.standard.definition(for: .work),
            holidayName: nil,
            start: nil,
            end: nil,
            breakMinutes: 0,
            workedMinutes: 0,
            creditedMinutes: 0,
            expectedMinutes: 0,
            adjustmentMinutes: 0,
            balanceMinutes: 0,
            hasEntry: false,
            isIncluded: true,
            crossesMidnight: false,
            note: "",
            location: "",
            tags: [],
            warnings: []
        )
    }
}
