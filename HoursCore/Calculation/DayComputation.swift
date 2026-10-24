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
    case siteHoursNotCounted

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
        // The one warning shown in the phone's language; the others above are
        // still English-only and left alone for now.
        case .siteHoursNotCounted: return ExportLanguage.device(.siteHoursNotCounted)
        }
    }

    var isProblem: Bool {
        switch self {
        case .overlappingBreaksMerged, .excludedFromTotals, .siteHoursNotCounted: return false
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

    /// First shift's start and last shift's end. With one shift — the usual
    /// case — these are simply that shift's times.
    var start: TimeOfDay?
    var end: TimeOfDay?
    var breakMinutes: Int
    /// Every shift the day resolved to, in the order entered.
    var shifts: [ShiftPeriod]

    /// Time actually worked.
    var workedMinutes: Int
    /// Contracted hours credited for paid absence (vacation, sick, holiday).
    var creditedMinutes: Int
    /// Contracted hours owed for this day.
    var expectedMinutes: Int
    /// Manual correction included in the balance.
    var adjustmentMinutes: Int
    var adjustmentReason: AdjustmentReason
    /// `paidMinutes - expectedMinutes + adjustment`, or a manual override.
    var balanceMinutes: Int

    var hasEntry: Bool
    var isIncluded: Bool
    var crossesMidnight: Bool
    /// Before the day the balance starts: the start date when one is set,
    /// otherwise the first day anything was recorded. Such a day is not short,
    /// not owed and not missing — the app was not in use yet. Set by
    /// `PeriodEngine`, which is the one place that knows where the balance
    /// starts.
    var precedesBalanceStart: Bool = false

    var note: String
    var location: String
    var tags: [String]
    var warnings: [DayWarning]

    /// Field allowance, kilometres and travel (1.2), all nothing while they
    /// are not tracked. The allowance and kilometres include what a site day
    /// gave you; see `WorkdayCalculator`.
    var hasFieldAllowance: Bool = false
    var kilometres: Int = 0
    /// Travel as recorded.
    var travelMinutes: Int = 0
    /// The part of `travelMinutes` already in `workedMinutes`: all of it when
    /// travel counts as work, none otherwise.
    var countedTravelMinutes: Int = 0

    var id: Int { date.key }

    /// A public holiday that was paid as one and worked as well: the hours
    /// are on top of the holiday's credit, and the calendar marks the day.
    var isWorkedPublicHoliday: Bool {
        holidayName != nil && dayType.id == .holiday && workedMinutes > 0
    }

    /// Everything the day pays: worked time plus credited absence.
    var paidMinutes: Int { workedMinutes + creditedMinutes }

    var overtimeMinutes: Int { max(0, balanceMinutes) }
    var deficitMinutes: Int { max(0, -balanceMinutes) }

    /// A day the schedule expects to be worked.
    var isScheduledWorkingDay: Bool {
        dayType.expectation == .scheduled && expectedMinutes > 0
    }

    /// A working day taken off against overtime. It is expected like any
    /// working day — that is what takes it off the balance — but nobody is
    /// due at work, so the widget neither draws it as short nor says when it
    /// ends.
    var isTimeOffInLieu: Bool { dayType.id == .timeOffInLieu }

    /// Whether this day counts towards a total at all.
    ///
    /// One definition, because there were three: the period aggregator and
    /// both halves of the balance ledger each carried a copy of these two
    /// conditions. Numbers derived from copies of a rule are fine right up
    /// until someone edits one of them, and the symptom is a screen showing
    /// two totals that disagree while each looks perfectly reasonable alone.
    ///
    /// A day past the cut-off still counts when hours were actually recorded
    /// on it. What the cut-off excludes is expected hours not yet worked —
    /// without it the current month would show a deficit for every day still
    /// to come.
    ///
    /// A day before the balance starts never counts, whatever is on it, so a
    /// month someone began halfway through adds up from the day they began.
    func counts(through cutoff: CalendarDate?) -> Bool {
        guard isIncluded, !precedesBalanceStart else { return false }
        if let cutoff, date > cutoff, !hasEntry { return false }
        return true
    }

    var isPaidAbsence: Bool { creditedMinutes > 0 || dayType.expectation == .creditedAbsence }

    /// Whether the calendar should mark this day as carrying data.
    var hasContent: Bool {
        hasEntry || holidayName != nil || workedMinutes > 0
    }

    var hasProblem: Bool { warnings.contains { $0.isProblem } }

    /// True when the day was worked in more than one block.
    var isSplitShift: Bool { shifts.count > 1 }

    /// A working day in the past with nothing recorded against it.
    ///
    /// The single definition of a gap: the calendar draws these with a dashed
    /// outline and the reminder counts them, so the two can never disagree
    /// about what is missing.
    ///
    /// Nothing before the balance starts is a gap, or the calendar would nag
    /// about every week before the app was installed.
    func isUnrecordedWorkingDay(asOf today: CalendarDate) -> Bool {
        isIncluded
            && !precedesBalanceStart
            && isScheduledWorkingDay
            && !hasEntry
            && workedMinutes == 0
            && date < today
    }

    static func empty(on date: CalendarDate) -> DayComputation {
        DayComputation(
            date: date,
            dayType: DayTypeCatalog.standard.definition(for: .work),
            holidayName: nil,
            start: nil,
            end: nil,
            breakMinutes: 0,
            shifts: [],
            workedMinutes: 0,
            creditedMinutes: 0,
            expectedMinutes: 0,
            adjustmentMinutes: 0,
            adjustmentReason: .correction,
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
