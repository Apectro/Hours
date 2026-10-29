import Foundation

/// Whose own sheet: you, or one person of your crews.
///
/// Each site keeps its own crew, so the same person is a different member on
/// every site they work on. They are one person here the way "Add from other
/// sites" makes them one (`CrewCandidates.key`): the same name, ignoring
/// case, accents and spacing. You are the same id everywhere.
struct CrewSheetPerson: Identifiable, Hashable, Sendable {
    /// What the sheet is headed with. Empty for you without a name; the
    /// builder then uses the name in Export options, or "You".
    var name: String
    /// Their member on every site, or `CrewMember.youID`.
    var memberIDs: Set<UUID>
    /// The folded name, or "you": stable across sites and devices.
    var id: String

    var isYou: Bool { memberIDs == [CrewMember.youID] }

    static func you(name: String) -> CrewSheetPerson {
        CrewSheetPerson(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            memberIDs: [CrewMember.youID],
            id: "you"
        )
    }

    /// `member` and everyone of the same name on your other crews.
    static func matching(_ member: CrewMember, in crew: [CrewMember]) -> CrewSheetPerson {
        let key = CrewCandidates.key(for: member.name)
        var ids: Set<UUID> = [member.id]
        if !key.isEmpty {
            ids.formUnion(crew.filter { CrewCandidates.key(for: $0.name) == key }.map(\.id))
        }
        return CrewSheetPerson(
            name: member.name.trimmingCharacters(in: .whitespacesAndNewlines),
            memberIDs: ids,
            // An identifier, never shown.
            id: "member:" + (key.isEmpty ? member.id.uuidString : key)
        )
    }
}

/// One person's own sheet for a period, across every site they were on: what
/// a worker checks against their payslip, and what the supervisor hands them
/// to sign.
///
/// It is the personal timesheet's table — a `.timesheet` `ReportTable`
/// headed by the person's name — so the PDF, the workbook and the CSV print
/// it through exactly the code and the look the hours export has. A row per
/// day they were ticked present (one per site, should they have been on two
/// that day) and per day a reason was given for them not being there; a day
/// with neither has no row, as on the site sheet, which is also how weekends
/// and public holidays are treated: a day is on the sheet when it was
/// written for them, whatever the calendar says about it.
struct CrewMemberSheetBuilder: Sendable {
    let settings: AppSettings
    let calendar: Calendar
    let emptyPlaceholder: String

    init(settings: AppSettings, calendar: Calendar, emptyPlaceholder: String = "—") {
        self.settings = settings
        self.calendar = calendar
        self.emptyPlaceholder = emptyPlaceholder
    }

    /// Everyone on `siteID`'s sheet for the range — ticked present or given a
    /// reason at least once — you first, then the crew in their order, each
    /// with their members on every other site.
    static func people(
        on siteID: UUID,
        crew: [CrewMember],
        results: [SiteDayResult],
        range: CalendarDateRange,
        ownerName: String
    ) -> [CrewSheetPerson] {
        let here = results.filter { $0.day.siteID == siteID && range.contains($0.day.date) }
        let present = Set(here.flatMap { result in
            result.people.map(\.memberID)
                + result.day.absences.compactMap { result.day.absenceReason(for: $0.memberID) == nil ? nil : $0.memberID }
        })
        var people: [CrewSheetPerson] = []
        if present.contains(CrewMember.youID) {
            people.append(.you(name: ownerName))
        }
        let ordered = crew.enumerated()
            .filter { $0.element.siteID == siteID && present.contains($0.element.id) }
            .sorted {
                $0.element.sortOrder != $1.element.sortOrder
                    ? $0.element.sortOrder < $1.element.sortOrder
                    : $0.offset < $1.offset
            }
        var seen = Set(people.map(\.id))
        for (_, member) in ordered {
            let person = CrewSheetPerson.matching(member, in: crew)
            if seen.insert(person.id).inserted { people.append(person) }
        }
        return people
    }

    private struct Line {
        var date: CalendarDate
        var siteID: UUID?
        var entry: PersonDay?
        var day: SiteDay
        var reason: AbsenceReason?
    }

    /// - Parameters:
    ///   - sites: every site, archived ones too, for their names and order.
    ///   - results: the site days of every site in the range.
    ///   - includesSignatures: the site export's Signatures switch; off, the
    ///     sheet has no lines to sign on.
    func makeTable(
        person: CrewSheetPerson,
        sites: [Site],
        results: [SiteDayResult],
        range: CalendarDateRange,
        includesSignatures: Bool = true
    ) -> ReportTable {
        let language = settings.export.language
        let formatter = ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: emptyPlaceholder)
        let duration = formatter.duration
        let catalog = settings.dayTypeCatalog
        let owner = settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = !person.name.isEmpty ? person.name : (person.isYou && !owner.isEmpty ? owner : language(.you))

        let siteOrder = Dictionary(
            sites.enumerated().sorted {
                $0.element.sortOrder != $1.element.sortOrder
                    ? $0.element.sortOrder < $1.element.sortOrder
                    : $0.offset < $1.offset
            }.enumerated().map { ($0.element.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        let siteNames = Dictionary(sites.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        func order(_ id: UUID?) -> Int { id.flatMap { siteOrder[$0] } ?? Int.max }

        // One result per site and date: sync can deliver a site day twice,
        // and the first one wins, as on the site sheet.
        var seenDays = Set<String>()
        var worked: [Line] = []
        var away: [CalendarDate: Line] = [:]
        for result in results where range.contains(result.day.date) {
            guard seenDays.insert("\(result.day.siteID.uuidString)-\(result.day.date.key)").inserted else { continue }
            if let entry = result.people.first(where: { person.memberIDs.contains($0.memberID) }) {
                worked.append(Line(date: result.day.date, siteID: result.day.siteID, entry: entry, day: result.day))
                continue
            }
            for id in person.memberIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let reason = result.day.absenceReason(for: id) else { continue }
                let line = Line(date: result.day.date, siteID: result.day.siteID, day: result.day, reason: reason)
                // One reason a day, the first site's, should two sites both say.
                if let known = away[line.date], order(known.siteID) <= order(line.siteID) { break }
                away[line.date] = line
                break
            }
        }
        // A reason on a day they worked somewhere else says nothing new.
        let workedDates = Set(worked.map(\.date))
        let lines = (worked + away.values.filter { !workedDates.contains($0.date) })
            .sorted { $0.date != $1.date ? $0.date < $1.date : order($0.siteID) < order($1.siteID) }

        // The sites they worked on, in the sites' order; for someone away
        // the whole period, the sites that gave the reasons.
        let shownSites = Set(worked.compactMap(\.siteID))
        // In the order first worked, as the personal timesheet names them
        // (lines are in date order, then the sites' order).
        let titleSet = shownSites.isEmpty ? Set(lines.compactMap(\.siteID)) : shownSites
        var seenSites = Set<UUID>()
        let titleSiteIDs = lines.compactMap(\.siteID).filter { titleSet.contains($0) && seenSites.insert($0).inserted }
        let titleSites = titleSiteIDs.compactMap { siteNames[$0] }
        let showsSite = shownSites.count > 1
        let showsReason = lines.contains { $0.reason != nil }
        let showsNote = lines.contains { !noteText(for: $0).isEmpty }

        var columns: [ReportColumn] = [.date, .weekday]
        var headings = [language(.date), language(.weekday)]
        if showsSite {
            columns.append(.location)
            headings.append(language(.site))
        }
        columns += [.times, .breakTime, .worked]
        headings += [language(.fromTo), language(.breakTime), language(.hours)]
        if showsReason {
            columns.append(.dayType)
            headings.append(language(.reason))
        }
        if showsNote {
            columns.append(.note)
            headings.append(language(.notes))
        }

        var rows: [ReportRow] = []
        var totalMinutes = 0
        var breakMinutes = 0
        var sickDays = 0
        var leaveDays = 0
        var usedIDs = Set<Int>()
        for line in lines {
            var values: [String] = []
            var minutes: [Int?] = []
            var isAbsence = false
            var reasonText = emptyPlaceholder
            if let reason = line.reason {
                switch reason {
                case let .dayType(id):
                    reasonText = catalog.definition(for: id).exportName(in: language)
                    isAbsence = true
                    switch SiteSheetBuilder.absenceKind(id) {
                    case .sick: sickDays += 1
                    case .leave: leaveDays += 1
                    case .other: break
                    }
                case let .otherSite(siteID):
                    reasonText = siteID.flatMap { siteNames[$0] } ?? language(.otherSite)
                }
            }
            for column in columns {
                switch column {
                case .date:
                    values.append(formatter.dateText(line.date)); minutes.append(nil)
                case .weekday:
                    values.append(formatter.weekdayText(line.date)); minutes.append(nil)
                case .location:
                    let site = line.entry == nil ? nil : line.siteID.flatMap { siteNames[$0] }
                    values.append(site ?? emptyPlaceholder); minutes.append(nil)
                case .times:
                    if let entry = line.entry, entry.start != nil || entry.end != nil {
                        values.append(formatter.timesText(start: entry.start, end: entry.end, crossesMidnight: crosses(entry)))
                    } else {
                        values.append(emptyPlaceholder)
                    }
                    minutes.append(nil)
                case .breakTime:
                    if let entry = line.entry, entry.breakMinutes > 0 {
                        values.append(duration.string(entry.breakMinutes)); minutes.append(entry.breakMinutes)
                    } else {
                        values.append(emptyPlaceholder); minutes.append(nil)
                    }
                case .worked:
                    if let entry = line.entry {
                        values.append(duration.string(entry.workedMinutes)); minutes.append(entry.workedMinutes)
                    } else {
                        values.append(emptyPlaceholder); minutes.append(nil)
                    }
                case .dayType:
                    values.append(reasonText); minutes.append(nil)
                default:
                    let note = noteText(for: line)
                    values.append(note.isEmpty ? emptyPlaceholder : note); minutes.append(nil)
                }
            }
            if let entry = line.entry {
                totalMinutes += entry.workedMinutes
                breakMinutes += entry.breakMinutes
            }
            // The date's key, as every other report's day rows; a second site
            // the same day takes a negative id no date can have.
            var id = line.date.key
            var extra = 1
            while !usedIDs.insert(id).inserted {
                id = -(line.date.key * 10 + extra)
                extra += 1
            }
            rows.append(ReportRow(
                id: id,
                values: values,
                minutes: minutes,
                isWorkingDay: true,
                balanceMinutes: 0,
                hasEntry: true,
                isAbsence: isAbsence
            ))
        }
        let daysOnSite = workedDates.count

        let isMonth = range.start.day == 1 && range.start.yearMonth == range.end.yearMonth
            && range.end == range.start.yearMonth.range(in: calendar).end
        let formatting = CalendarFormatting(locale: language.locale, calendar: calendar)
        let dates = formatter.subtitle(for: range)
        let period = isMonth ? formatting.monthTitle(range.start.yearMonth) : dates
        // "Hauptstraße 12 · Trg Pravde", or the first two and "+2 more".
        let sitesText = language.combinedSiteNames(titleSites)

        var table = ReportTable(
            title: sitesText.isEmpty ? "\(language(.hours)) — \(period)" : "\(sitesText) — \(period)",
            subtitle: dates,
            ownerName: name,
            language: language,
            columns: columns,
            rows: rows,
            totals: [],
            headingOverrides: headings
        )
        table.kind = .timesheet
        // One site's sheet says where it is; across several, no one address.
        if titleSiteIDs.count == 1, let site = sites.first(where: { $0.id == titleSiteIDs[0] }) {
            table.address = SiteAddress.singleLine(site.address)
        }
        table.eyebrow = sitesText.isEmpty ? language(.timesheet) : "\(language(.timesheet)) · \(sitesText)"
        let recorded = person.isYou || owner.isEmpty ? [] : ["\(language(.recordedBy)) \(owner)"]
        table.detail = ((isMonth ? [period, dates] : [dates]) + recorded).joined(separator: " · ")

        table.totals = [
            ReportTotal(label: language(.totalWorked), value: duration.string(totalMinutes), isEmphasised: true, minutes: totalMinutes),
            ReportTotal(label: language(.daysOnSite), value: "\(daysOnSite)", isEmphasised: false, count: daysOnSite)
        ]
        table.tiles = [
            ReportTile(label: language(.worked), value: duration.string(totalMinutes)),
            ReportTile(label: language(.daysOnSite), value: "\(daysOnSite)")
        ]
        // Sick and leave days only when there were any, as on the site sheet.
        for (term, count) in [(ExportTerm.sickDays, sickDays), (.leaveDays, leaveDays)] where count > 0 {
            table.totals.append(ReportTotal(label: language(term), value: "\(count)", isEmphasised: false, count: count))
            table.tiles.append(ReportTile(label: language(term), value: "\(count)"))
        }

        // The ruled total under the days: the hours, and the break where
        // there was one. The label stands in the date column.
        var totalValues = Array(repeating: "", count: columns.count)
        var totalCells = Array(repeating: Int?.none, count: columns.count)
        if !columns.isEmpty { totalValues[0] = language(.total) }
        if let index = columns.firstIndex(of: .worked) {
            totalValues[index] = duration.string(totalMinutes)
            totalCells[index] = totalMinutes
        }
        if breakMinutes > 0, let index = columns.firstIndex(of: .breakTime) {
            totalValues[index] = duration.string(breakMinutes)
            totalCells[index] = breakMinutes
        }
        // Id -1 cannot collide with a date key, as on the timesheet.
        table.totalRow = ReportRow(
            id: -1,
            values: totalValues,
            minutes: totalCells,
            isWorkingDay: true,
            balanceMinutes: 0,
            hasEntry: true,
            role: .total
        )
        // The worker signs for their hours and the supervisor that they are
        // right: the timesheet's line and the site sheet's "checked" line,
        // under the site export's Signatures switch.
        if includesSignatures {
            table.signatures = [language(.employeeSignature), language(.checkedSignature)]
        }
        return table
    }

    /// The site day's note on a day they were there, led by "Bad weather" on
    /// a day the crew was rained off, as the site sheet writes it.
    private func noteText(for line: Line) -> String {
        guard line.entry != nil else { return "" }
        let note = line.day.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.day.isBadWeatherStop else { return note }
        let language = settings.export.language
        return note.isEmpty ? language(.badWeather) : "\(language(.badWeather)) · \(note)"
    }

    /// The same test the timesheet's end column uses for "(+1)".
    private func crosses(_ entry: PersonDay) -> Bool {
        guard let start = entry.start, let end = entry.end else { return false }
        return end.minutes < start.minutes
    }
}
