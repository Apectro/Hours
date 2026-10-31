import Foundation

/// The list under the Today calendar's week: which days of the week get a
/// row, and what each row is.
///
/// A day gets a row when something is on it (hours, a day type written, a
/// public holiday) or when it is a working day: in the past one nobody wrote
/// (`DayComputation.isUnrecordedWorkingDay`, the calendar's red dot), today
/// or to come one not written yet. A weekend or day off with nothing on it,
/// and a day before the balance starts, have no row.
enum CalendarWeekList {
    enum Status: Hashable, Sendable {
        /// Something is on the day.
        case written
        /// A working day in the past with nothing written.
        case missing
        /// Today or a working day to come, nothing written yet.
        case notYet
    }

    struct Row: Identifiable, Hashable, Sendable {
        var day: DayComputation
        var status: Status
        var id: Int { day.date.key }
    }

    static func rows(_ days: [DayComputation], today: CalendarDate) -> [Row] {
        days.compactMap { day in
            if day.isUnrecordedWorkingDay(asOf: today) { return Row(day: day, status: .missing) }
            if day.hasContent { return Row(day: day, status: .written) }
            if day.isIncluded, !day.precedesBalanceStart, day.isScheduledWorkingDay, day.date >= today {
                return Row(day: day, status: .notYet)
            }
            return nil
        }
    }

    /// The sites a day was worked on, each once, in the order of its blocks:
    /// "Trg Pravde → Jarunski".
    static func siteIDs(of day: DayComputation) -> [UUID] {
        var seen: Set<UUID> = []
        return day.shifts.compactMap(\.siteID).filter { seen.insert($0).inserted }
    }
}
