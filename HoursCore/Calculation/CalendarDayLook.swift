import Foundation

/// What a day on the Today calendar is, which decides its tile and what is
/// under the date (`DayTile`): worked days and missed working days on an
/// accent tile, days away and public holidays on a tile in the type's own
/// colour, days off and days with nothing on them without one. Today's
/// tile is filled whatever its look; that is the view's business.
enum CalendarDayLook: Equatable, Sendable {
    case written, missing, away, holiday, dayOff, plain

    static func of(_ computation: DayComputation?, today: CalendarDate) -> CalendarDayLook {
        guard let computation else { return .plain }
        if computation.isUnrecordedWorkingDay(asOf: today) { return .missing }
        if computation.dayType.id == .holiday {
            return computation.workedMinutes > 0 ? .written : .holiday
        }
        switch DayKind.of(computation.dayType) {
        case .away:
            return computation.workedMinutes > 0 ? .written : .away
        case .dayOff:
            return computation.workedMinutes > 0 ? .written : .dayOff
        case .worked:
            if computation.dayType.expectation == .zero && computation.workedMinutes == 0 { return .dayOff }
            return computation.hasEntry || computation.workedMinutes > 0 ? .written : .plain
        }
    }

    /// Whether the day sits on a tile (today aside, which always does).
    var hasTile: Bool {
        switch self {
        case .written, .missing, .away, .holiday: return true
        case .dayOff, .plain: return false
        }
    }
}
