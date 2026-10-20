import Foundation

/// Builds the sheet a site's director gets at the start of the month: one row
/// per day, one column per person, each person's total and days worked at the
/// bottom.
///
/// It produces an ordinary `ReportTable`, so CSV, XLSX and the PDF write it
/// through the same code as a timesheet. The columns are all `.worked` (one
/// per person) and the real titles, the people's names, travel in
/// `headingOverrides`. Times and durations are formatted by the same
/// `ReportBuilder` helpers a timesheet uses, so the two cannot disagree about
/// how 07:00 or eight and a half hours is written.
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

        var rows: [ReportRow] = []
        var totalMinutes = Array(repeating: 0, count: people.count)
        var daysWorked = Array(repeating: 0, count: people.count)

        for date in dates {
            guard let result = byDate[date] else { continue }
            var values = [settings.export.dateStyle.string(for: date)]
            for (index, person) in people.enumerated() {
                guard let entry = result.people.first(where: { $0.memberID == person.id }) else {
                    values.append(emptyPlaceholder)
                    continue
                }
                totalMinutes[index] += entry.workedMinutes
                if entry.workedMinutes > 0 { daysWorked[index] += 1 }
                let times = "\(formatter.startText(entry.start))–\(formatter.endText(entry.end, crossesMidnight: crosses(entry)))"
                values.append("\(times) · \(formatter.duration.string(entry.workedMinutes))")
            }
            values.append(result.day.note)
            rows.append(ReportRow(
                id: date.key,
                values: values,
                minutes: Array(repeating: nil, count: values.count),
                isWorkingDay: true,
                balanceMinutes: 0,
                hasEntry: true
            ))
        }

        let totalValues = [language(.monthTotal)] + totalMinutes.map { formatter.duration.string($0) } + [""]
        let totalCells: [Int?] = [nil] + totalMinutes.map { Optional($0) } + [nil]
        let countValues = [language(.daysWorked)] + daysWorked.map { "\($0)" } + [""]

        // Ids 0 and 1 cannot collide with a date key.
        rows.append(ReportRow(id: 0, values: totalValues, minutes: totalCells, isWorkingDay: true, balanceMinutes: 0, hasEntry: true))
        rows.append(ReportRow(
            id: 1,
            values: countValues,
            minutes: Array(repeating: nil, count: countValues.count),
            isWorkingDay: true,
            balanceMinutes: 0,
            hasEntry: true
        ))

        return ReportTable(
            title: site.name,
            subtitle: formatter.subtitle(for: range),
            ownerName: owner,
            language: language,
            columns: [.date] + Array(repeating: .worked, count: people.count) + [.note],
            rows: rows,
            totals: [],
            headingOverrides: [language(.day)] + people.map(\.heading) + [language(.notes)]
        )
    }

    /// The same test the timesheet's end column uses for "(+1)".
    private func crosses(_ entry: PersonDay) -> Bool {
        guard let start = entry.start, let end = entry.end else { return false }
        return end.minutes < start.minutes
    }
}
