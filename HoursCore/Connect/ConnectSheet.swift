import Foundation

/// A month sheet as the protocol's `MonthSheet`: the figures the app's site
/// sheet prints, person by person and day by day, for one site or several
/// on one sheet, with the company's people in it.
///
/// Built from the same `SiteDayResult`s the sheet's PDF is drawn from, so
/// the figures sent are the figures printed.
enum ConnectSheet {
    struct SiteInput: Sendable {
        var site: Site
        var crew: [CrewMember]
        var results: [SiteDayResult]
    }

    /// The sheet's id: one per set of sites and month, so a corrected sheet
    /// is a newer version of the same sheet rather than a second one.
    static func id(siteIDs: [UUID], month: YearMonth) -> UUID {
        let sites = siteIDs.map(ConnectID.string).sorted().joined(separator: ",")
        return ConnectUUID.v5(["sheet", sites, ConnectFormat.month(month)].joined(separator: ":"))
    }

    static func make(
        sites: [SiteInput],
        month: YearMonth,
        title: String,
        holidays: [(date: CalendarDate, name: String)],
        breaksPaid: Bool,
        rounding: RoundingRule,
        people: ConnectPeople,
        yourName: String,
        pdf: ConnectV1.FileRef?,
        attachments: [ConnectV1.FileRef] = [],
        sentAt: Date
    ) -> ConnectV1.MonthSheet {
        let you = yourName.trimmingCharacters(in: .whitespacesAndNewlines)
        struct Person {
            var memberID: String
            var name: String
            var order: Int
            var minutes = 0
            var dates = Set<CalendarDate>()
            var dayTypes: [String: Double] = [:]
            var allowanceDates = Set<CalendarDate>()
            var days: [ConnectV1.SheetDay] = []
        }
        var byPerson: [String: Person] = [:]
        var sheetSites: [ConnectV1.SheetSite] = []

        for (siteIndex, input) in sites.enumerated() {
            let names = Dictionary(input.crew.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            let orders = Dictionary(input.crew.map { ($0.id, $0.sortOrder) }, uniquingKeysWith: { first, _ in first })
            var siteMinutes = 0
            var kilometres = 0
            var seenDates = Set<CalendarDate>()
            for result in input.results.sorted(by: { $0.day.date < $1.day.date }) where result.day.date.yearMonth == month {
                // One result per date, as the sheet prints.
                guard seenDates.insert(result.day.date).inserted else { continue }
                let day = result.day
                kilometres += day.kilometres
                func person(_ memberID: UUID) -> String? {
                    guard let outgoing = people.outgoing(memberID) else { return nil }
                    let id = ConnectID.string(outgoing)
                    if byPerson[id] == nil {
                        let isYou = memberID == CrewMember.youID
                        let name = isYou ? (you.isEmpty ? "?" : you) : (names[memberID] ?? "?")
                        let order = isYou ? -1 : siteIndex * 10_000 + (orders[memberID] ?? 0)
                        byPerson[id] = Person(memberID: id, name: String(name.prefix(200)), order: order)
                    }
                    return id
                }
                for entry in result.people {
                    guard let id = person(entry.memberID) else { continue }
                    byPerson[id]?.minutes += entry.workedMinutes
                    siteMinutes += entry.workedMinutes
                    if entry.workedMinutes > 0 { byPerson[id]?.dates.insert(day.date) }
                    if entry.hasAllowance { byPerson[id]?.allowanceDates.insert(day.date) }
                    byPerson[id]?.days.append(ConnectV1.SheetDay(
                        date: ConnectFormat.date(day.date),
                        siteId: ConnectID.string(day.siteID),
                        start: entry.start.map(ConnectFormat.time),
                        end: entry.end.map(ConnectFormat.time),
                        breakMinutes: entry.breakMinutes,
                        workedMinutes: max(0, entry.workedMinutes),
                        dayType: nil,
                        note: String(day.note.prefix(1000)),
                        allowance: entry.hasAllowance
                    ))
                }
                for absence in day.absences where day.attendance(for: absence.memberID) == nil {
                    guard case let .dayType(type) = absence.reason, let id = person(absence.memberID) else { continue }
                    byPerson[id]?.dayTypes[type.rawValue, default: 0] += 1
                    byPerson[id]?.days.append(ConnectV1.SheetDay(
                        date: ConnectFormat.date(day.date),
                        siteId: ConnectID.string(day.siteID),
                        workedMinutes: 0,
                        dayType: type.rawValue
                    ))
                }
            }
            sheetSites.append(ConnectV1.SheetSite(
                siteId: ConnectID.string(input.site.id),
                name: String((input.site.name.isEmpty ? "?" : input.site.name).prefix(200)),
                address: String(input.site.address.prefix(500)),
                workedMinutes: siteMinutes,
                kilometres: kilometres
            ))
        }

        let ordered = byPerson.values.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
        let sheetPeople = ordered.map { person in
            ConnectV1.SheetPerson(
                memberId: person.memberID,
                name: person.name,
                workedMinutes: person.minutes,
                daysWorked: min(31, person.dates.count),
                dayTypes: person.dayTypes,
                allowanceDays: min(31, person.allowanceDates.count),
                days: Array(person.days.sorted { ($0.date, $0.siteId ?? "") < ($1.date, $1.siteId ?? "") }.prefix(200))
            )
        }
        var dayTypeTotals: [String: Double] = [:]
        for person in sheetPeople {
            for (type, count) in person.dayTypes { dayTypeTotals[type, default: 0] += count }
        }
        let monthHolidays = holidays
            .filter { $0.date.yearMonth == month }
            .sorted { $0.date < $1.date }
            .prefix(31)
            .map { ConnectV1.SheetHoliday(date: ConnectFormat.date($0.date), name: String($0.name.prefix(200))) }
        let siteIDs = sites.map(\.site.id)
        return ConnectV1.MonthSheet(
            id: ConnectID.string(id(siteIDs: siteIDs, month: month)),
            month: ConnectFormat.month(month),
            title: String(title.prefix(300)),
            siteIds: siteIDs.map(ConnectID.string),
            sites: sheetSites,
            people: sheetPeople,
            holidays: Array(monthHolidays),
            totals: ConnectV1.SheetTotals(
                workedMinutes: sheetPeople.map(\.workedMinutes).reduce(0, +),
                people: sheetPeople.count,
                dayTypes: dayTypeTotals,
                allowanceDays: sheetPeople.map(\.allowanceDays).reduce(0, +),
                kilometres: sheetSites.map(\.kilometres).reduce(0, +)
            ),
            rules: ConnectV1.SheetRules(breaksPaid: breaksPaid, rounding: rounding.rawValue),
            pdf: pdf,
            attachments: attachments,
            sentBy: ConnectV1.SentBy(memberId: people.you.map(ConnectID.string), name: String((you.isEmpty ? "?" : you).prefix(200))),
            sentAt: ConnectFormat.moment(sentAt)
        )
    }

    /// The sheet ready to queue, with its PDF to upload first.
    static func outgoing(_ sheet: ConnectV1.MonthSheet, pdfFile: ConnectFileNeed?, siteIDs: [UUID]) throws -> ConnectOutgoing {
        try ConnectOutgoing(
            kind: .sheet,
            id: sheet.id,
            record: sheet,
            files: pdfFile.map { [$0] } ?? [],
            siteIDs: siteIDs,
            month: ConnectFormat.parseMonth(sheet.month)
        )
    }
}
