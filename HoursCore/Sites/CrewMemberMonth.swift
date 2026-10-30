import Foundation

/// One person's month on screen (1.2, mockup Crew): their hours, the days
/// they worked, their sick days, and a line a day across every site.
///
/// Read the way their own sheet reads them (`CrewMemberSheetBuilder`): a day
/// is theirs when they were ticked on it or given a reason for being away; a
/// site day delivered twice counts once; a reason on a day they worked on
/// another site says nothing new. Where the sheet has a row per site, this
/// has one line a day, the sites in the order worked ("Trg Pravde →
/// Jarunski"), since the screen is read by the day.
struct CrewMemberMonth: Equatable, Sendable {
    struct Day: Equatable, Sendable, Identifiable {
        var date: CalendarDate
        /// The sites worked that day, in the order worked. Empty on a day
        /// away.
        var siteIDs: [UUID]
        /// Why they were not there, on a day they did not work anywhere.
        var reason: AbsenceReason?
        /// Their hours that day, on every site together.
        var minutes: Int

        var id: Int { date.key }

        var isSick: Bool {
            guard case let .dayType(id)? = reason else { return false }
            return SiteSheetBuilder.absenceKind(id) == .sick
        }
    }

    /// Newest first: the end of the month is what is being checked.
    var days: [Day]
    var totalMinutes: Int
    var daysWorked: Int
    var sickDays: Int

    /// - Parameters:
    ///   - sites: every site, for the order a reason is taken in when two
    ///     sites both give one.
    ///   - results: site days of every site; those outside `range` are
    ///     left out.
    static func make(
        person: CrewSheetPerson,
        sites: [Site],
        results: [SiteDayResult],
        range: CalendarDateRange
    ) -> CrewMemberMonth {
        let siteOrder = Dictionary(
            sites.enumerated()
                .sorted {
                    $0.element.sortOrder != $1.element.sortOrder
                        ? $0.element.sortOrder < $1.element.sortOrder
                        : $0.offset < $1.offset
                }
                .enumerated()
                .map { ($0.element.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        func order(_ id: UUID) -> Int { siteOrder[id] ?? Int.max }

        struct Worked {
            var siteID: UUID
            var start: Int
            var minutes: Int
        }

        var seen = Set<String>()
        var worked: [CalendarDate: [Worked]] = [:]
        var away: [CalendarDate: (siteID: UUID, reason: AbsenceReason)] = [:]
        for result in results where range.contains(result.day.date) {
            let day = result.day
            guard seen.insert("\(day.siteID.uuidString)-\(day.date.key)").inserted else { continue }
            if let entry = result.people.first(where: { person.memberIDs.contains($0.memberID) }) {
                worked[day.date, default: []].append(Worked(
                    siteID: day.siteID,
                    start: entry.start?.minutes ?? Int.max,
                    minutes: entry.workedMinutes
                ))
                continue
            }
            for id in person.memberIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let reason = day.absenceReason(for: id) else { continue }
                if let known = away[day.date], order(known.siteID) <= order(day.siteID) { break }
                away[day.date] = (day.siteID, reason)
                break
            }
        }

        var days: [Day] = []
        for (date, list) in worked {
            let ordered = list.sorted {
                $0.start != $1.start ? $0.start < $1.start : order($0.siteID) < order($1.siteID)
            }
            var siteIDs: [UUID] = []
            for item in ordered where !siteIDs.contains(item.siteID) { siteIDs.append(item.siteID) }
            days.append(Day(date: date, siteIDs: siteIDs, reason: nil, minutes: list.reduce(0) { $0 + $1.minutes }))
        }
        for (date, item) in away where worked[date] == nil {
            days.append(Day(date: date, siteIDs: [], reason: item.reason, minutes: 0))
        }
        days.sort { $0.date > $1.date }

        return CrewMemberMonth(
            days: days,
            totalMinutes: days.reduce(0) { $0 + $1.minutes },
            daysWorked: worked.count,
            sickDays: days.filter(\.isSick).count
        )
    }
}
