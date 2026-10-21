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
        range: CalendarDateRange
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
        let present = Set(byDate.values.flatMap { $0.people.map(\.memberID) })
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
                    merged.insert(index + 1)
                    values += [emptyPlaceholder, ""]
                    minutes += [nil, nil]
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
            values.append(result.day.note)
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
            trailingSummaryRows: 2
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
        table.legend = language(.siteLegend)
        table.signatures = [language(.checkedSignature)]
        return table
    }

    /// The same test the timesheet's end column uses for "(+1)".
    private func crosses(_ entry: PersonDay) -> Bool {
        guard let start = entry.start, let end = entry.end else { return false }
        return end.minutes < start.minutes
    }
}
