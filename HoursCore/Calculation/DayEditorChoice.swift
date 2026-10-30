import Foundation

/// The day editor's four main choices (design v2): Work, Vacation, Sick and
/// Day off, a segmented control on top of the editor.
///
/// A grouping of the day types the app already has, as `DayKind` is, not a
/// new field. Every other type (a public holiday, a personal day, time off
/// in lieu, bad weather, your own types) is `other`: none of the segments is
/// selected, and the editor's type list below picks it.
enum DayEditorChoice: String, CaseIterable, Hashable, Sendable {
    case work
    case vacation
    case sick
    case dayOff
    case other

    /// The segments, in the order drawn.
    static let segments: [DayEditorChoice] = [.work, .vacation, .sick, .dayOff]

    static func of(_ definition: DayTypeDefinition) -> DayEditorChoice {
        if definition.id == .vacation { return .vacation }
        if definition.id == .sick { return .sick }
        switch DayKind.of(definition) {
        case .worked: return .work
        case .dayOff: return .dayOff
        case .away: return .other
        }
    }

    /// `record` with this choice made, by the rules `DayKind.apply` already
    /// has: Work is Worked, Day off is Day off, and Vacation and Sick are
    /// Away with that type. A day the schedule or a holiday already makes
    /// the chosen type is left automatic. `other` changes nothing.
    func apply(
        to record: DayRecord,
        automatic: DayTypeDefinition,
        catalog: DayTypeCatalog,
        prefilled: Shift,
        contractedMinutes: Int = 0
    ) -> DayRecord {
        switch self {
        case .work:
            return DayKind.worked.apply(
                to: record, automatic: automatic, catalog: catalog,
                prefilled: prefilled, contractedMinutes: contractedMinutes
            )
        case .dayOff:
            return DayKind.dayOff.apply(
                to: record, automatic: automatic, catalog: catalog,
                prefilled: prefilled, contractedMinutes: contractedMinutes
            )
        case .vacation, .sick:
            let target: DayTypeID = self == .vacation ? .vacation : .sick
            var away = DayKind.away.apply(
                to: record, automatic: automatic, catalog: catalog,
                prefilled: prefilled, contractedMinutes: contractedMinutes
            )
            away.dayTypeID = automatic.id == target ? nil : target
            return away
        case .other:
            return record
        }
    }
}

extension DayComputation {
    /// The day against a normal day (design v2: "30 min more than a normal
    /// day"): what it paid, worked and credited, less what it expected.
    /// Corrections are left out; they are not time. Nil for a day with
    /// nothing written or nothing expected, where there is nothing to
    /// compare.
    var differenceFromNormalDay: Int? {
        guard hasEntry, expectedMinutes > 0 else { return nil }
        return paidMinutes - expectedMinutes
    }
}

extension DurationFormatting {
    /// The calendar's hours under a date (design v2): "8h", "8.5h", rounded
    /// to a tenth of an hour, the tenth left out when it is nought. Empty
    /// for no time at all.
    static func compactHours(_ minutes: Int, decimalSeparator: String = ".") -> String {
        guard minutes > 0 else { return "" }
        let tenths = Int((Double(minutes) / 6).rounded())
        let whole = tenths / 10
        let tenth = tenths % 10
        return tenth == 0 ? "\(whole)h" : "\(whole)\(decimalSeparator)\(tenth)h"
    }
}
