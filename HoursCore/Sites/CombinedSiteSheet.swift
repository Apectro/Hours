import Foundation

/// One director's sheet for several sites' month (1.2): the site export with
/// more than one site chosen.
///
/// It is the site sheet — the same grid, title block and closing rows — for
/// a crew that worked on several sites. Each site keeps its own crew, so the
/// same person is a different member on each; here they are one column, matched
/// by name as "Add from other sites" matches them (`CrewCandidates.key`), and
/// you once. A day cell is their hours that day added up across the sites, so
/// a day someone moved from one site to the other reads as the whole day. A
/// "By site" block under the days says how the hours divide.
extension SiteSheetBuilder {
    /// The sheet for `sites`, in the order chosen. One site is exactly
    /// `makeTable(site:…)`, today's sheet.
    ///
    /// - Parameters:
    ///   - crew: the crews of the sites, hidden members too; each member's
    ///     `siteID` says whose.
    ///   - results: the site days of the month; days of other sites are left
    ///     out.
    ///   - signatures: the sites' sign-offs. A combined sheet draws none —
    ///     each belongs to one site's month — and says so when there are any.
    func makeTable(
        sites: [Site],
        crew: [CrewMember],
        results: [SiteDayResult],
        range: CalendarDateRange,
        signatures: [CrewSignature] = [],
        includesSignatures: Bool = true,
        siteNames: [UUID: String] = [:]
    ) -> ReportTable {
        var seenSites = Set<UUID>()
        let chosen = sites.filter { seenSites.insert($0.id).inserted }
        guard chosen.count > 1 else {
            return makeTable(
                site: chosen.first ?? Site(name: ""),
                crew: crew,
                results: chosen.isEmpty ? [] : results,
                range: range,
                signatures: signatures,
                includesSignatures: includesSignatures,
                siteNames: siteNames
            )
        }
        return combinedTable(
            sites: chosen,
            crew: crew,
            results: results,
            range: range,
            signatures: signatures,
            includesSignatures: includesSignatures,
            siteNames: siteNames
        )
    }

    /// One column of the combined sheet: you, or everyone of one name.
    private struct CombinedPerson {
        var heading: String
        var memberIDs: Set<UUID>
    }

    private func combinedTable(
        sites: [Site],
        crew: [CrewMember],
        results: [SiteDayResult],
        range: CalendarDateRange,
        signatures: [CrewSignature],
        includesSignatures: Bool,
        siteNames: [UUID: String]
    ) -> ReportTable {
        let language = settings.export.language
        let formatter = ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: emptyPlaceholder)
        let duration = formatter.duration
        let owner = settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenIDs = Set(sites.map(\.id))
        let siteIndex = Dictionary(uniqueKeysWithValues: sites.enumerated().map { ($1.id, $0) })

        // One result per site and date, the first one winning as on a site
        // sheet; a date's site days in the order the sites were chosen.
        var seenDays = Set<String>()
        var byDate: [CalendarDate: [SiteDayResult]] = [:]
        for result in results where chosenIDs.contains(result.day.siteID) && range.contains(result.day.date) {
            guard seenDays.insert("\(result.day.siteID.uuidString)-\(result.day.date.key)").inserted else { continue }
            byDate[result.day.date, default: []].append(result)
        }
        for date in byDate.keys {
            byDate[date]?.sort { (siteIndex[$0.day.siteID] ?? 0) < (siteIndex[$1.day.siteID] ?? 0) }
        }
        let dates = byDate.keys.sorted()
        let allResults = dates.flatMap { byDate[$0] ?? [] }

        // You first; then the first site's crew in its order, then whoever
        // is new on the next site, in that site's order. Someone of the same
        // name is the same person.
        let present = Set(allResults.flatMap { result in
            result.people.map(\.memberID) + result.day.absences.map(\.memberID)
        })
        var people: [CombinedPerson] = []
        if present.contains(CrewMember.youID) {
            people.append(CombinedPerson(heading: owner.isEmpty ? language(.you) : owner, memberIDs: [CrewMember.youID]))
        }
        var personByKey: [String: Int] = [:]
        for site in sites {
            let ordered = crew.enumerated()
                .filter { $0.element.siteID == site.id && present.contains($0.element.id) }
                .sorted {
                    $0.element.sortOrder != $1.element.sortOrder
                        ? $0.element.sortOrder < $1.element.sortOrder
                        : $0.offset < $1.offset
                }
            for (_, member) in ordered {
                let folded = CrewCandidates.key(for: member.name)
                let key = folded.isEmpty ? "member:" + member.id.uuidString : "name:" + folded
                if let index = personByKey[key] {
                    people[index].memberIDs.insert(member.id)
                } else {
                    personByKey[key] = people.count
                    people.append(CombinedPerson(
                        heading: member.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        memberIDs: [member.id]
                    ))
                }
            }
        }

        let formatting = CalendarFormatting(locale: language.locale, calendar: calendar)
        var rows: [ReportRow] = []
        var totalMinutes = Array(repeating: 0, count: people.count)
        var daysWorked = Array(repeating: 0, count: people.count)
        var sickDays = Array(repeating: 0, count: people.count)
        var leaveDays = Array(repeating: 0, count: people.count)
        var allowanceDays = Array(repeating: 0, count: people.count)
        var siteMinutes = Array(repeating: 0, count: sites.count)
        /// Each person's hours on each site, for the closing rows.
        var personSiteMinutes = Array(repeating: Array(repeating: 0, count: people.count), count: sites.count)
        let tracksAllowance = settings.allowance.isEnabled
        let catalog = settings.dayTypeCatalog

        // The date and the day, then the site: on a sheet for several sites
        // every row says where.
        let leadingKinds = Self.leadingColumnKinds + [ReportColumn.site]
        let lead = leadingKinds.count
        let siteName = Dictionary(sites.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        for date in dates {
            let dayResults = byDate[date] ?? []
            // The day's figures, counted once however many sites gave them.
            var dayWorked = Array(repeating: 0, count: people.count)
            var awayText: [String?] = Array(repeating: nil, count: people.count)
            var sitesToday = Array(repeating: 0, count: people.count)
            for (index, person) in people.enumerated() {
                let entries = dayResults.flatMap { result in
                    result.people
                        .filter { person.memberIDs.contains($0.memberID) }
                        .map { (siteID: result.day.siteID, entry: $0) }
                }
                guard !entries.isEmpty else {
                    // Not on any of these sites that day: why, when a site
                    // said. Being on another site of this sheet is not away.
                    switch awayReason(of: person, on: dayResults, chosen: chosenIDs) {
                    case let .dayType(id)?:
                        awayText[index] = catalog.definition(for: id).exportName(in: language)
                        switch Self.absenceKind(id) {
                        case .sick: sickDays[index] += 1
                        case .leave: leaveDays[index] += 1
                        case .other: break
                        }
                    case let .otherSite(siteID)?:
                        awayText[index] = siteID.flatMap { siteNames[$0] } ?? language(.otherSite)
                    case nil:
                        break
                    }
                    continue
                }
                let worked = entries.reduce(0) { $0 + $1.entry.workedMinutes }
                for (siteID, entry) in entries {
                    siteMinutes[siteIndex[siteID] ?? 0] += entry.workedMinutes
                    personSiteMinutes[siteIndex[siteID] ?? 0][index] += entry.workedMinutes
                }
                dayWorked[index] = worked
                sitesToday[index] = Set(entries.map(\.siteID)).count
                totalMinutes[index] += worked
                if worked > 0 { daysWorked[index] += 1 }
                if tracksAllowance && entries.contains(where: { $0.entry.hasAllowance }) { allowanceDays[index] += 1 }
            }

            // A row per site that day, as a timesheet splits a day: each
            // person's times and hours where they were, a dash where they
            // were not. The date and the day on the first. They read as one
            // group, closed by "Total", only when somebody's day was on more
            // than one site: crews side by side on their own sites need no
            // total, and a month of them would print three rows a day.
            //
            // A site nobody on this sheet worked that day, with nothing
            // written about it, is no row while another site has the day: a
            // line of dashes says nothing the other row does not.
            let worksHere = { (result: SiteDayResult) in
                result.people.contains { entry in people.contains { $0.memberIDs.contains(entry.memberID) } }
            }
            let shown = dayResults.contains(where: worksHere)
                ? dayResults.filter { worksHere($0) || !note(of: $0.day, language: language).isEmpty }
                : dayResults
            let isSplit = shown.count > 1 && sitesToday.contains { $0 > 1 }
            for (position, result) in shown.enumerated() {
                let isFirst = position == 0
                var values = isFirst ? [formatter.dateText(date), formatter.weekdayText(date)] : ["", ""]
                values.append(siteName[result.day.siteID] ?? "")
                var minutes: [Int?] = [nil, nil, nil]
                var flagged: Set<Int> = []
                var merged: Set<Int> = []
                for (index, person) in people.enumerated() {
                    let here = result.people.filter { person.memberIDs.contains($0.memberID) }
                    guard !here.isEmpty else {
                        merged.insert(index + lead)
                        // Why they were away all day, once, on the first row.
                        let text = isFirst ? awayText[index] ?? emptyPlaceholder : emptyPlaceholder
                        values += [text, ""]
                        minutes += [nil, nil]
                        continue
                    }
                    // Late or early is a site's own word; leaving one site
                    // for another is neither.
                    if sitesToday[index] == 1 && here.count == 1 && here[0].isException {
                        flagged.formUnion([values.count, values.count + 1])
                    }
                    let worked = here.reduce(0) { $0 + $1.workedMinutes }
                    values.append(timesText(here, formatter: formatter))
                    values.append(duration.string(worked))
                    minutes += [nil, worked]
                }
                values.append(note(of: result.day, language: language))
                minutes.append(nil)
                var row = ReportRow(
                    id: isFirst ? date.key : -(date.key * 10 + position),
                    values: values,
                    minutes: minutes,
                    isWorkingDay: true,
                    balanceMinutes: 0,
                    hasEntry: true,
                    flagged: flagged,
                    mergedGroups: merged
                )
                if isSplit { row.splitDay = .site }
                rows.append(row)
            }

            // "Total": the day added up for each person who worked on more
            // than one site; anyone else's hours are already on their one
            // row. Text in a workbook, not a figure, so the month's sum
            // counts the sites'.
            guard isSplit else { continue }
            var values = ["", "", language(.total)]
            for (index, worked) in dayWorked.enumerated() {
                values += ["", sitesToday[index] > 1 ? duration.string(worked) : ""]
            }
            values.append("")
            var subtotal = ReportRow(
                id: -(date.key * 10 + 9),
                values: values,
                minutes: Array(repeating: nil, count: values.count),
                isWorkingDay: true,
                balanceMinutes: 0,
                hasEntry: true
            )
            subtotal.splitDay = .subtotal
            rows.append(subtotal)
        }

        // The closing rows, as on a site sheet.
        var totalValues = [language(.monthTotal), "", ""]
        var totalCells: [Int?] = [nil, nil, nil]
        var countValues = [language(.daysWorked), "", ""]
        for index in people.indices {
            totalValues += ["", duration.string(totalMinutes[index])]
            totalCells += [nil, totalMinutes[index]]
            countValues += ["", "\(daysWorked[index])"]
        }
        totalValues.append("")
        totalCells.append(nil)
        countValues.append("")
        // How much each person worked on each site, a row per site under
        // the days worked: the month total divided by where. Figures, not
        // sums, so a workbook writes them as hours.
        var closingRows: [(values: [String], minutes: [Int?])] = []
        for (index, site) in sites.enumerated() {
            var values = [site.name, "", ""]
            var minutes: [Int?] = [nil, nil, nil]
            for worked in personSiteMinutes[index] {
                values += ["", worked > 0 ? duration.string(worked) : ""]
                minutes += [nil, worked > 0 ? worked : nil]
            }
            closingRows.append((values + [""], minutes + [nil]))
        }
        var absenceRows: [[String]] = []
        for (term, counts) in [(ExportTerm.sickDays, sickDays), (.leaveDays, leaveDays), (.allowanceDays, allowanceDays)]
        where counts.contains(where: { $0 > 0 }) {
            absenceRows.append([language(term), "", ""] + counts.flatMap { ["", $0 > 0 ? "\($0)" : ""] } + [""])
        }
        // Each site's vehicle, added up.
        let kilometres = tracksAllowance ? allResults.reduce(0) { $0 + $1.day.kilometres } : 0
        if kilometres > 0 {
            absenceRows.append([language(.kilometres), "", ""] + people.flatMap { _ in ["", ""] }
                + ["\(kilometres) \(language(.kilometresShort))"])
        }
        rows.append(ReportRow(
            id: 0, values: totalValues, minutes: totalCells,
            isWorkingDay: true, balanceMinutes: 0, hasEntry: true, role: .total
        ))
        rows.append(ReportRow(
            id: 1, values: countValues, minutes: Array(repeating: nil, count: countValues.count),
            isWorkingDay: true, balanceMinutes: 0, hasEntry: true, role: .count
        ))
        closingRows += absenceRows.map { ($0, Array(repeating: nil, count: $0.count)) }
        for (offset, row) in closingRows.enumerated() {
            rows.append(ReportRow(
                id: 2 + offset, values: row.values, minutes: row.minutes,
                isWorkingDay: true, balanceMinutes: 0, hasEntry: true, role: .count
            ))
        }

        let crewMinutes = totalMinutes.reduce(0, +)
        let recorded = owner.isEmpty ? [] : ["\(language(.recordedBy)) \(owner)"]
        let month = range.start.yearMonth == range.end.yearMonth
            ? formatting.monthTitle(range.start.yearMonth)
            : formatter.subtitle(for: range)

        var table = ReportTable(
            // "Hauptstraße 12 · Trg Pravde"; beyond three, the first two and
            // "+2 more". The addresses are in By site.
            title: language.combinedSiteNames(sites.map(\.name)),
            subtitle: formatter.subtitle(for: range),
            ownerName: owner,
            language: language,
            columns: leadingKinds + people.flatMap { _ in [ReportColumn.times, .worked] } + [.note],
            rows: rows,
            totals: [],
            headingOverrides: leadingKinds.map { $0.heading(in: language) }
                + people.flatMap { _ in [language(.fromTo), language(.hours)] }
                + [language(.notes)],
            trailingSummaryRows: 2 + closingRows.count
        )
        table.kind = .siteSheet
        table.eyebrow = "\(language(.siteHours)) · \(month)"
        table.detail = (recorded + [language.people(people.count), language.daysOnSite(dates.count)])
            .joined(separator: " · ")
        table.columnGroups = leadingKinds.map { ReportColumnGroup(title: $0.heading(in: language), span: 1) }
            + people.map { ReportColumnGroup(title: $0.heading, span: 2) }
            + [ReportColumnGroup(title: language(.notes), span: 1)]
        table.tiles = [
            ReportTile(label: language(.daysOnSite), value: "\(dates.count)"),
            ReportTile(label: language(.crewHours), value: duration.string(crewMinutes)),
            ReportTile(label: language(.people), value: "\(people.count)")
        ]
        let badWeatherDays = dates.filter { date in byDate[date].map(isRainedOff) ?? false }.count
        if badWeatherDays > 0 {
            table.tiles.append(ReportTile(label: language(.badWeatherDays), value: "\(badWeatherDays)"))
        }
        let payRule = WorkdayCalculator(settings: settings, calendar: calendar)
        let paid = Set(allResults.map { payRule.breaksArePaid(forJob: $0.day.jobID) })
        switch paid {
        case [true]: table.legend = language(.siteLegendPaidBreaks)
        case [true, false]: table.legend = language(.siteLegendMixedBreaks)
        default: table.legend = language(.siteLegend)
        }
        table.bySite = sites.enumerated().map { index, site in
            ReportSiteTotal(
                name: site.name,
                address: SiteAddress.singleLine(site.address),
                minutes: siteMinutes[index],
                value: duration.string(siteMinutes[index])
            )
        } + [ReportSiteTotal(
            name: language(.total),
            address: "",
            minutes: crewMinutes,
            value: duration.string(crewMinutes),
            isTotal: true
        )]

        guard includesSignatures else { return table }
        // The line to sign on, as on every site sheet. A drawn sign-off is
        // one person's word for one site's month, so it stays on that
        // site's own sheet; where one was given, the sheet says where.
        table.signatures = [language(.checkedSignature)]
        let signedMonth = range.start.yearMonth
        if signatures.contains(where: { chosenIDs.contains($0.siteID) && $0.month == signedMonth }) {
            table.legend += " " + language(.signOffOnSiteSheets)
        }
        return table
    }

    /// Why `person` was on none of these sites that day: the first reason a
    /// site gave, in the order chosen, leaving out "on another site" that
    /// points at one of them.
    private func awayReason(of person: CombinedPerson, on results: [SiteDayResult], chosen: Set<UUID>) -> AbsenceReason? {
        let ids = person.memberIDs.sorted { $0.uuidString < $1.uuidString }
        for result in results {
            for id in ids {
                guard let reason = result.day.absenceReason(for: id) else { continue }
                if case let .otherSite(siteID?) = reason, chosen.contains(siteID) { continue }
                return reason
            }
        }
        return nil
    }

    /// One shift as the site sheet writes it; several, from the first start
    /// to the last end.
    private func timesText(_ entries: [PersonDay], formatter: ReportBuilder) -> String {
        guard entries.count > 1 else {
            let entry = entries[0]
            return formatter.timesText(start: entry.start, end: entry.end, crossesMidnight: crosses(entry))
        }
        let start = entries.compactMap(\.start).min { $0.minutes < $1.minutes }
        // An end after midnight is later than any end before it.
        let ends = entries.compactMap { entry -> (time: TimeOfDay, at: Int)? in
            guard let end = entry.end else { return nil }
            return (end, end.minutes + (crosses(entry) ? 24 * 60 : 0))
        }
        let last = ends.max { $0.at < $1.at }
        let crossesMidnight = (last?.at ?? 0) >= 24 * 60
        return formatter.timesText(start: start, end: last?.time, crossesMidnight: crossesMidnight)
    }

    /// Rained off on every site that worked that day.
    private func isRainedOff(_ results: [SiteDayResult]) -> Bool {
        !results.isEmpty && results.allSatisfy(\.day.isBadWeatherStop)
    }

    /// One site's day as its row's note: "Bad weather" when it was rained
    /// off, then what was written.
    private func note(of day: SiteDay, language: ExportLanguage) -> String {
        var parts: [String] = []
        if day.isBadWeatherStop { parts.append(language(.badWeather)) }
        let note = day.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}

extension SiteDiaryReport {
    /// Several sites' diaries for one sheet, each site's days together under
    /// its name, in the order the sites were chosen. A site with no diary
    /// adds nothing.
    static func combined(_ parts: [(siteName: String, report: SiteDiaryReport)]) -> SiteDiaryReport {
        let blocks = parts.flatMap { part in
            part.report.blocks.map { block -> SiteDiaryBlock in
                var block = block
                block.heading = "\(part.siteName) · \(block.heading)"
                return block
            }
        }
        return SiteDiaryReport(
            title: parts.first?.report.title ?? "",
            blocks: blocks,
            headings: parts.first?.report.headings ?? []
        )
    }
}
