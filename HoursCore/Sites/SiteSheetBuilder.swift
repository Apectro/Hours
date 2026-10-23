import Foundation

/// Builds the sheet a site's director gets at the start of the month: one row
/// per day, a group of two columns per person — their times and their hours —
/// and each person's total and days worked at the bottom.
///
/// It produces an ordinary `ReportTable`, so CSV, XLSX and the PDF write it
/// through the same code as a timesheet. Each person is a `.times` column and
/// a `.worked` column under a `ReportColumnGroup` carrying their name, so the
/// page can head the pair once and a CSV can still name both. The hours carry
/// their minutes, so a workbook writes numbers the director can add up. Times
/// and durations are formatted by the same `ReportBuilder` helpers a timesheet
/// uses, so the two cannot disagree about how 07:00 or eight and a half hours
/// is written.
struct SiteSheetBuilder: Sendable {
    let settings: AppSettings
    let calendar: Calendar
    let emptyPlaceholder: String

    init(settings: AppSettings, calendar: Calendar, emptyPlaceholder: String = "—") {
        self.settings = settings
        self.calendar = calendar
        self.emptyPlaceholder = emptyPlaceholder
    }

    private struct Person {
        var id: UUID
        var heading: String
    }

    func makeTable(
        site: Site,
        crew: [CrewMember],
        results: [SiteDayResult],
        range: CalendarDateRange,
        signatures: [CrewSignature] = [],
        includesSignatures: Bool = true
    ) -> ReportTable {
        let language = settings.export.language
        let formatter = ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: emptyPlaceholder)
        let owner = settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)

        // One result per date. Sync can deliver the same site day twice; the
        // first one wins, as it does when the days reach the calendar.
        var byDate: [CalendarDate: SiteDayResult] = [:]
        for result in results where range.contains(result.day.date) && byDate[result.day.date] == nil {
            byDate[result.day.date] = result
        }
        let dates = byDate.keys.sorted()

        // Everyone who has at least one day in the range: you first, then the
        // crew in their order. Hidden members are kept, because hiding only
        // stops them being offered for new days. Someone no longer in the crew
        // list has no name to print, so has no column.
        // Someone away all month, sick or on leave, is on the sheet too: why
        // they were not there is what the director needs to see.
        let present = Set(byDate.values.flatMap { result in
            result.people.map(\.memberID) + result.day.absences.map(\.memberID)
        })
        var people: [Person] = []
        if present.contains(CrewMember.youID) {
            people.append(Person(id: CrewMember.youID, heading: owner.isEmpty ? language(.you) : owner))
        }
        let ordered = crew.enumerated().sorted {
            $0.element.sortOrder != $1.element.sortOrder
                ? $0.element.sortOrder < $1.element.sortOrder
                : $0.offset < $1.offset
        }
        for (_, member) in ordered where present.contains(member.id) {
            people.append(Person(id: member.id, heading: member.name))
        }

        let formatting = CalendarFormatting(locale: language.locale, calendar: calendar)
        let duration = formatter.duration

        var rows: [ReportRow] = []
        var totalMinutes = Array(repeating: 0, count: people.count)
        var daysWorked = Array(repeating: 0, count: people.count)
        var sickDays = Array(repeating: 0, count: people.count)
        var leaveDays = Array(repeating: 0, count: people.count)
        let catalog = settings.dayTypeCatalog

        for date in dates {
            guard let result = byDate[date] else { continue }
            // "Wed 1 Oct": a director reads this sheet looking for a weekday,
            // which an ISO date makes them work out.
            var values = [formatting.mediumDate(date)]
            var minutes: [Int?] = [nil]
            var flagged: Set<Int> = []
            var merged: Set<Int> = []
            for (index, person) in people.enumerated() {
                guard let entry = result.people.first(where: { $0.memberID == person.id }) else {
                    // Group 0 is the day, so a person's group is one along.
                    // Not there: why, when it was given ("Sick leave"), in
                    // the words a timesheet uses for the day type.
                    merged.insert(index + 1)
                    let reason = result.day.absence(for: person.id)
                    values += [reason.map { catalog.definition(for: $0).exportName(in: language) } ?? emptyPlaceholder, ""]
                    minutes += [nil, nil]
                    switch reason.map(Self.absenceKind) {
                    case .sick?: sickDays[index] += 1
                    case .leave?: leaveDays[index] += 1
                    default: break
                    }
                    continue
                }
                totalMinutes[index] += entry.workedMinutes
                if entry.workedMinutes > 0 { daysWorked[index] += 1 }
                if entry.isException {
                    flagged.formUnion([values.count, values.count + 1])
                }
                values.append(formatter.timesText(start: entry.start, end: entry.end, crossesMidnight: crosses(entry)))
                values.append(duration.string(entry.workedMinutes))
                minutes += [nil, entry.workedMinutes]
            }
            values.append(noteText(for: result.day, language: language))
            minutes.append(nil)
            rows.append(ReportRow(
                id: date.key,
                values: values,
                minutes: minutes,
                isWorkingDay: true,
                balanceMinutes: 0,
                hasEntry: true,
                flagged: flagged,
                mergedGroups: merged
            ))
        }

        // Each closing figure sits under the hours, with the times column
        // beside it left empty, so a total lines up with what it adds up.
        var totalValues = [language(.monthTotal)]
        var totalCells: [Int?] = [nil]
        var countValues = [language(.daysWorked)]
        for index in people.indices {
            totalValues += ["", duration.string(totalMinutes[index])]
            totalCells += [nil, totalMinutes[index]]
            countValues += ["", "\(daysWorked[index])"]
        }
        totalValues.append("")
        totalCells.append(nil)
        countValues.append("")

        // Days away sick and on leave, each a row only when anybody had one,
        // and blank for a person with none.
        var absenceRows: [[String]] = []
        for (term, counts) in [(ExportTerm.sickDays, sickDays), (.leaveDays, leaveDays)] where counts.contains(where: { $0 > 0 }) {
            absenceRows.append([language(term)] + counts.flatMap { ["", $0 > 0 ? "\($0)" : ""] } + [""])
        }

        // Ids 0 and 1 cannot collide with a date key.
        rows.append(ReportRow(
            id: 0,
            values: totalValues,
            minutes: totalCells,
            isWorkingDay: true,
            balanceMinutes: 0,
            hasEntry: true,
            role: .total
        ))
        rows.append(ReportRow(
            id: 1,
            values: countValues,
            minutes: Array(repeating: nil, count: countValues.count),
            isWorkingDay: true,
            balanceMinutes: 0,
            hasEntry: true,
            role: .count
        ))
        // Ids 2 and 3, as 0 and 1 above.
        for (offset, values) in absenceRows.enumerated() {
            rows.append(ReportRow(
                id: 2 + offset,
                values: values,
                minutes: Array(repeating: nil, count: values.count),
                isWorkingDay: true,
                balanceMinutes: 0,
                hasEntry: true,
                role: .count
            ))
        }

        let crewMinutes = totalMinutes.reduce(0, +)
        let recorded = owner.isEmpty ? [] : ["\(language(.recordedBy)) \(owner)"]
        let month = range.start.yearMonth == range.end.yearMonth
            ? formatting.monthTitle(range.start.yearMonth)
            : formatter.subtitle(for: range)

        var table = ReportTable(
            title: site.name,
            subtitle: formatter.subtitle(for: range),
            ownerName: owner,
            language: language,
            columns: [.date] + people.flatMap { _ in [ReportColumn.times, .worked] } + [.note],
            rows: rows,
            totals: [],
            headingOverrides: [language(.day)]
                + people.flatMap { _ in [language(.fromTo), language(.hours)] }
                + [language(.notes)],
            trailingSummaryRows: 2 + absenceRows.count
        )
        table.kind = .siteSheet
        table.eyebrow = "\(language(.siteHours)) · \(month)"
        table.detail = (recorded + [language.people(people.count), language.daysOnSite(dates.count)])
            .joined(separator: " · ")
        table.columnGroups = [ReportColumnGroup(title: language(.day), span: 1)]
            + people.map { ReportColumnGroup(title: $0.heading, span: 2) }
            + [ReportColumnGroup(title: language(.notes), span: 1)]
        table.tiles = [
            ReportTile(label: language(.daysOnSite), value: "\(dates.count)"),
            ReportTile(label: language(.crewHours), value: duration.string(crewMinutes)),
            ReportTile(label: language(.people), value: "\(people.count)")
        ]
        // Counted apart, and only when there were any: a month without a stop
        // has nothing to say about the weather.
        let badWeatherDays = byDate.values.filter(\.day.isBadWeatherStop).count
        if badWeatherDays > 0 {
            table.tiles.append(ReportTile(label: language(.badWeatherDays), value: "\(badWeatherDays)"))
        }
        // "Hours after the break" is only true where the break is unpaid. A
        // site follows the job frozen on each day, so a month can hold both.
        let payRule = WorkdayCalculator(settings: settings, calendar: calendar)
        let paid = Set(byDate.values.map { payRule.breaksArePaid(forJob: $0.day.jobID) })
        switch paid {
        case [true]: table.legend = language(.siteLegendPaidBreaks)
        case [true, false]: table.legend = language(.siteLegendMixedBreaks)
        default: table.legend = language(.siteLegend)
        }
        // Signing is optional: switched off, the sheet has no line to sign
        // on and no sign-off boxes, whoever has signed.
        guard includesSignatures else { return table }
        table.signatures = [language(.checkedSignature)]
        table.signOff = signOff(
            people: people.enumerated().map { ($0.element.id, $0.element.heading, duration.string(totalMinutes[$0.offset])) },
            site: site,
            results: Array(byDate.values),
            range: range,
            signatures: signatures,
            language: language,
            formatting: formatting
        )
        return table
    }

    /// A box for everyone on the sheet, once anyone has signed for this
    /// month: their hours, their signature or a blank line, and a mark where
    /// their hours changed after they signed. With nobody signed the sheet
    /// keeps its one "checked" line, as before.
    private func signOff(
        people: [(id: UUID, name: String, hours: String)],
        site: Site,
        results: [SiteDayResult],
        range: CalendarDateRange,
        signatures: [CrewSignature],
        language: ExportLanguage,
        formatting: CalendarFormatting
    ) -> [ReportSignOff] {
        let month = range.start.yearMonth
        let relevant = signatures.filter { $0.siteID == site.id && $0.month == month }
        guard !relevant.isEmpty else { return [] }
        return people.map { person in
            let latest = SignOff.latest(for: person.id, in: relevant, month: month)
            let state = SignOff.state(for: person.id, signatures: relevant, results: results, month: month)
            let status: String
            switch state {
            case .unsigned:
                status = ""
            case let .signed(date):
                status = "\(language(.signedOn)) \(formatting.dateWithYear(date))"
            case let .changedAfterSigning(date):
                status = "\(language(.changedAfterSigning)) · \(language(.signedOn)) \(formatting.dateWithYear(date))"
            }
            var isChanged = false
            if case .changedAfterSigning = state { isChanged = true }
            return ReportSignOff(
                memberID: person.id,
                name: person.name,
                hours: person.hours,
                status: status,
                isChanged: isChanged,
                strokes: latest?.strokes ?? [],
                aspectRatio: latest?.aspectRatio ?? 3
            )
        }
    }

    /// The day's note, led by "Bad weather" on a day the crew was rained
    /// off, so a director scanning the notes sees why the hours stop short.
    private func noteText(for day: SiteDay, language: ExportLanguage) -> String {
        guard day.isBadWeatherStop else { return day.note }
        let note = day.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? language(.badWeather) : "\(language(.badWeather)) · \(note)"
    }

    private enum AbsenceKind { case sick, leave, other }

    /// Sick is sick; leave is Vacation, a personal day and every absence
    /// type of the user's own; a day off and time off in lieu are neither.
    private static func absenceKind(_ id: DayTypeID) -> AbsenceKind {
        switch id {
        case .sick: return .sick
        case .dayOff, .timeOffInLieu: return .other
        default: return .leave
        }
    }

    /// The same test the timesheet's end column uses for "(+1)".
    private func crosses(_ entry: PersonDay) -> Bool {
        guard let start = entry.start, let end = entry.end else { return false }
        return end.minutes < start.minutes
    }
}
