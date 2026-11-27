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
/// It is the site sheet for one person (2026-11): a `.siteSheet`
/// `ReportTable` marked `isOnePersonSheet`, so the PDF, the workbook and
/// the CSV print it through the code the crew's sheet goes through — the
/// same header, the same month, the same closing rows, legend and footer —
/// with columns that suit one person: the date, the day, the site when
/// there are several, from–to, the break, the hours and the notes.
///
/// The month is the site sheet's (`SiteSheetMonth`): every day of the range
/// has a row when it lists every day. A day they were ticked present is a
/// row per site; a day a reason was given for them not being there says the
/// reason, on that day type's wash, in the words the crew's sheet uses; a
/// day with neither is what the crew's sheet makes of a day nobody wrote —
/// a quiet weekend, a public holiday by its name, "Paused", a day their
/// site recorded as no work — or is left empty. A day the crew worked
/// without them, with no reason given, is such an empty day: not on the
/// crew is not away. A holiday they worked keeps its mark.
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
    ///   - sheetMonth: the public holidays off and whether every day of the
    ///     range is listed, as for the crew's sheet. Without it only the
    ///     days written for them are listed and no holiday is marked.
    func makeTable(
        person: CrewSheetPerson,
        sites: [Site],
        results: [SiteDayResult],
        range: CalendarDateRange,
        includesSignatures: Bool = true,
        month sheetMonth: SiteSheetMonth = .writtenDaysOnly
    ) -> ReportTable {
        let language = settings.export.language
        let formatter = ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: emptyPlaceholder)
        // The crew sheet's own pieces: what an empty day says, a worked
        // holiday's mark, the note of a site's day.
        let sheet = SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: emptyPlaceholder)
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
        var unique: [SiteDayResult] = []
        var worked: [Line] = []
        var away: [CalendarDate: Line] = [:]
        for result in results where range.contains(result.day.date) {
            guard seenDays.insert("\(result.day.siteID.uuidString)-\(result.day.date.key)").inserted else { continue }
            unique.append(result)
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
        let linesByDate = Dictionary(grouping: lines, by: \.date)

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

        // Their sites decide what a day with nothing of theirs is: the
        // work days, a pause, a day one of them recorded as no work.
        let setups = titleSiteIDs.map { settings.siteSetup(for: $0) }
        let ownSiteDays = Dictionary(grouping: unique.filter { titleSet.contains($0.day.siteID) }, by: \.day.date)

        // The date and the day, the site when there are several, then the
        // person's own three columns and the notes: always the same, so a
        // month with no break and no note still reads as the sheet it is.
        var columns: [ReportColumn] = [.date, .weekday]
        var headings = [language(.date), language(.weekday)]
        if showsSite {
            columns.append(.site)
            headings.append(language(.site))
        }
        let lead = columns.count
        columns += [.times, .breakTime, .worked, .note]
        headings += [language(.fromTo), language(.breakTime), language(.hours), language(.notes)]
        let timesIndex = lead
        let breakIndex = lead + 1
        let workedIndex = lead + 2

        /// A row with the date and the day, nothing under the person's
        /// columns, and `note` in the notes.
        func bareRow(_ date: CalendarDate, note: String) -> (values: [String], minutes: [Int?]) {
            var values = [formatter.dateText(date), formatter.weekdayText(date)]
            if showsSite { values.append("") }
            values += [emptyPlaceholder, emptyPlaceholder, emptyPlaceholder, note]
            return (values, Array(repeating: nil, count: values.count))
        }

        var rows: [ReportRow] = []
        var totalMinutes = 0
        var breakMinutes = 0
        var sickDays = 0
        var leaveDays = 0
        var daysWorked = Set<CalendarDate>()
        var allowanceDays = Set<CalendarDate>()
        var paidBreaks = Set<Bool>()
        let tracksAllowance = settings.allowance.isEnabled
        let payRule = WorkdayCalculator(settings: settings, calendar: calendar)
        let holidayDates = sheet.holidayDates(in: range, month: sheetMonth)
        var usedIDs = Set<Int>()

        for date in sheet.listedDates(written: linesByDate.keys.sorted(), range: range, month: sheetMonth) {
            guard let dayLines = linesByDate[date], !dayLines.isEmpty else {
                // Nothing of theirs that day. A day every one of their sites
                // that wrote it recorded as no work says so, as the crew's
                // sheet does; any other is a weekend, a public holiday, a
                // pause, or simply empty — the crew working without them,
                // with no reason given, included.
                let written = (ownSiteDays[date] ?? []).sorted { order($0.day.siteID) < order($1.day.siteID) }
                var row: ReportRow
                if let noWork = written.first, written.allSatisfy(\.day.isNoWorkDay) {
                    let bare = bareRow(date, note: sheet.holidayNote(
                        sheet.noteText(for: noWork.day, language: language), on: date, month: sheetMonth
                    ))
                    row = ReportRow(
                        id: date.key, values: bare.values, minutes: bare.minutes,
                        isWorkingDay: true, balanceMinutes: 0, hasEntry: false
                    )
                    row.dayTint = ReportDayHighlight.rowTint(for: noWork.day, catalog: catalog)
                } else {
                    let kind = SiteSheetEmptyDay.of(date, setups: setups, holidays: sheetMonth.holidays, calendar: calendar)
                    let mark = sheet.emptyDayMark(kind)
                    let bare = bareRow(date, note: mark.note)
                    row = ReportRow(
                        id: date.key, values: bare.values, minutes: bare.minutes,
                        isWorkingDay: kind != .notAWorkDay, balanceMinutes: 0, hasEntry: false,
                        isAbsence: mark.isHoliday
                    )
                    row.dayTint = mark.tint
                }
                usedIDs.insert(date.key)
                rows.append(row)
                continue
            }
            for (position, line) in dayLines.enumerated() {
                let isFirst = position == 0
                var values = [formatter.dateText(date), formatter.weekdayText(date)]
                if showsSite {
                    values.append(line.entry == nil ? "" : (line.siteID.flatMap { siteNames[$0] } ?? emptyPlaceholder))
                }
                var minutes: [Int?] = Array(repeating: nil, count: values.count)
                var flagged: Set<Int> = []
                var isAbsence = false
                var dayTint: TypeTint?
                var note = ""
                if let entry = line.entry {
                    if entry.start != nil || entry.end != nil {
                        values.append(formatter.timesText(start: entry.start, end: entry.end, crossesMidnight: sheet.crosses(entry)))
                    } else {
                        values.append(emptyPlaceholder)
                    }
                    minutes.append(nil)
                    if entry.breakMinutes > 0 {
                        values.append(duration.string(entry.breakMinutes)); minutes.append(entry.breakMinutes)
                    } else {
                        values.append(emptyPlaceholder); minutes.append(nil)
                    }
                    values.append(duration.string(entry.workedMinutes)); minutes.append(entry.workedMinutes)
                    // Different hours from the site's, in orange as on the
                    // crew's sheet: the times and the hours.
                    if entry.isException { flagged = [timesIndex, workedIndex] }
                    totalMinutes += entry.workedMinutes
                    breakMinutes += entry.breakMinutes
                    if entry.workedMinutes > 0 { daysWorked.insert(date) }
                    if tracksAllowance && entry.hasAllowance { allowanceDays.insert(date) }
                    paidBreaks.insert(payRule.breaksArePaid(forJob: line.day.jobID))
                    // The site day's note, led by "Bad weather" on a day the
                    // crew was rained off, as the site sheet writes it.
                    note = line.day.sheetNote(in: language)
                    // A day recorded as no work that still has them ticked
                    // (rained off) stands out as it does on the crew's sheet.
                    dayTint = ReportDayHighlight.rowTint(for: line.day, catalog: catalog)
                } else {
                    values += [emptyPlaceholder, emptyPlaceholder, emptyPlaceholder]
                    minutes += [nil, nil, nil]
                    // Why they were not there, in the words and on the wash
                    // the crew's sheet gives their cell.
                    switch line.reason {
                    case let .dayType(id)?:
                        note = catalog.definition(for: id).exportName(in: language)
                        isAbsence = true
                        dayTint = ReportDayHighlight.tint(for: catalog.definition(for: id))
                        switch SiteSheetBuilder.absenceKind(id) {
                        case .sick: sickDays += 1
                        case .leave: leaveDays += 1
                        case .other: break
                        }
                    case let .otherSite(siteID)?:
                        // The site's name alone would read as a note.
                        let other = language(.otherSite)
                        note = siteID.flatMap { siteNames[$0] }.map { "\(other) · \($0)" } ?? other
                    case nil:
                        break
                    }
                }
                // A public holiday they worked keeps its mark, once: its
                // name leads the note, and the date and the day are shaded.
                var tints: [Int: TypeTint] = [:]
                if isFirst {
                    note = sheet.holidayNote(note, on: date, month: sheetMonth)
                    if line.entry != nil { tints = sheet.holidayMark(on: date, month: sheetMonth) }
                }
                values.append(note)
                minutes.append(nil)

                // The date's key, as every other report's day rows; a second
                // site the same day takes a negative id no date can have.
                var id = date.key
                var extra = 1
                while !usedIDs.insert(id).inserted {
                    id = -(date.key * 10 + extra)
                    extra += 1
                }
                var row = ReportRow(
                    id: id,
                    values: values,
                    minutes: minutes,
                    isWorkingDay: true,
                    balanceMinutes: 0,
                    hasEntry: true,
                    isAbsence: isAbsence,
                    flagged: flagged
                )
                row.dayTint = dayTint
                row.groupTints = tints
                rows.append(row)
            }
        }
        let daysOnSite = workedDates.count

        // The closing rows, as on the crew's sheet: the month's hours under
        // the hours (and the breaks under the break), then counts of days
        // under the hours — days worked always; sick, leave, public holidays
        // off and allowance days only when there were any. The vehicle's
        // kilometres belong to the day, not to a person, and stay on the
        // crew's sheet.
        func closing(_ label: String, role: ReportRowRole, id: Int, _ fill: (inout [String], inout [Int?]) -> Void) -> ReportRow {
            var values = Array(repeating: "", count: columns.count)
            var cells = Array(repeating: Int?.none, count: columns.count)
            values[0] = label
            fill(&values, &cells)
            return ReportRow(
                id: id, values: values, minutes: cells,
                isWorkingDay: true, balanceMinutes: 0, hasEntry: true, role: role
            )
        }
        // Ids 0 and up cannot collide with a date key.
        var closingRows = [
            closing(language(.monthTotal), role: .total, id: 0) { values, cells in
                values[workedIndex] = duration.string(totalMinutes)
                cells[workedIndex] = totalMinutes
                if breakMinutes > 0 {
                    values[breakIndex] = duration.string(breakMinutes)
                    cells[breakIndex] = breakMinutes
                }
            },
            closing(language(.daysWorked), role: .count, id: 1) { values, _ in
                values[workedIndex] = "\(daysWorked.count)"
            }
        ]
        let holidaysOff = holidayDates.subtracting(daysWorked).count
        for (term, count) in [
            (ExportTerm.sickDays, sickDays), (.leaveDays, leaveDays), (.publicHolidays, holidaysOff),
            (.allowanceDays, allowanceDays.count)
        ] where count > 0 {
            closingRows.append(closing(language(term), role: .count, id: closingRows.count) { values, _ in
                values[workedIndex] = "\(count)"
            })
        }
        rows += closingRows

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
            headingOverrides: headings,
            trailingSummaryRows: closingRows.count
        )
        table.kind = .siteSheet
        table.isOnePersonSheet = true
        // Every column is ruled off from the next, as the crew's sheet rules
        // off its people: a group of one each.
        table.columnGroups = headings.map { ReportColumnGroup(title: $0, span: 1) }
        // One site's sheet says where it is; across several, no one address.
        if titleSiteIDs.count == 1, let site = sites.first(where: { $0.id == titleSiteIDs[0] }) {
            table.address = SiteAddress.singleLine(site.address)
        }
        table.eyebrow = "\(language(.siteHours)) · \(period)"
        table.period = period
        table.sitesText = sitesText
        let recorded = person.isYou || owner.isEmpty ? [] : ["\(language(.recordedBy)) \(owner)"]
        table.detail = ((isMonth ? [period, dates] : [dates]) + recorded).joined(separator: " · ")

        table.tiles = [
            ReportTile(label: language(.worked), value: duration.string(totalMinutes)),
            ReportTile(label: language(.daysOnSite), value: "\(daysOnSite)")
        ]
        // Sick and leave days only when there were any, as on the site sheet.
        for (term, count) in [(ExportTerm.sickDays, sickDays), (.leaveDays, leaveDays)] where count > 0 {
            table.tiles.append(ReportTile(label: language(term), value: "\(count)"))
        }
        // The hours and the days on site, as two plain figures at the top.
        table.keyFigures = Array(table.tiles.prefix(2))

        // The legend names only what the sheet has: what its hours are
        // (nothing to say of a month with paid and unpaid breaks both, or
        // with no day worked), orange where someone came late or left
        // early, and the shading where a day is shaded.
        var legend: [String] = []
        switch paidBreaks {
        case [true]: legend.append(language(.hoursWithPaidBreakLegend))
        case [false]: legend.append(language(.hoursAfterBreakLegend))
        default: break
        }
        if rows.contains(where: { !$0.flagged.isEmpty }) { legend.append(language(.lateOrEarlyLegend)) }
        if table.hasDayHighlights { legend.append(language(.dayHighlightLegend)) }
        table.legend = legend.joined(separator: " ")

        // The worker signs for their hours and the supervisor that they are
        // right: the timesheet's line and the site sheet's "checked" line,
        // under the site export's Signatures switch.
        if includesSignatures {
            table.signatures = [language(.employeeSignature), language(.checkedSignature)]
        }
        return table
    }
}
