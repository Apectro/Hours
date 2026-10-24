import XCTest
@testable import Hours

/// The calculation audit, sites: a person's hours on a site day, your own
/// row against the shift it puts in your calendar, and the director's sheet
/// against the cells it is made of.
final class AuditSiteTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let site = Site(name: "Bau Nord")
    private let august = YearMonth(year: 2026, month: 8)

    private func randomDays(
        crew: [CrewMember],
        jobID: UUID?,
        seed: UInt64
    ) -> [SiteDay] {
        var generator = SeededGenerator(seed: seed)
        var days: [SiteDay] = []
        for date in august.range(in: calendar).days(in: calendar) where Int.random(in: 0..<10, using: &generator) < 7 {
            let start = Int.random(in: 300...600, using: &generator)
            let length = Int.random(in: 0...720, using: &generator)
            var present: [Attendance] = []
            for id in [CrewMember.youID] + crew.map(\.id) where Int.random(in: 0..<5, using: &generator) > 0 {
                var attendance = Attendance(memberID: id)
                switch Int.random(in: 0..<6, using: &generator) {
                case 0: attendance.start = TimeOfDay(minutes: start + Int.random(in: 1...120, using: &generator))
                case 1: attendance.end = TimeOfDay(minutes: (start + length - Int.random(in: 0...60, using: &generator) + 1440) % 1440)
                case 2: attendance.breakMinutes = Int.random(in: 0...90, using: &generator)
                default: break
                }
                present.append(attendance)
            }
            days.append(SiteDay(
                siteID: site.id,
                date: date,
                start: TimeOfDay(minutes: start),
                end: TimeOfDay(minutes: (start + length) % 1440),
                breakMinutes: Int.random(in: 0...60, using: &generator),
                present: present,
                jobID: jobID
            ))
        }
        return days
    }

    /// Your row on the site day is what the site day puts in your calendar:
    /// for every shape of day, paid or unpaid breaks, any rounding.
    func testYourSiteRowEqualsTheDayItPutsInYourCalendar() {
        for paid in [false, true] {
            for rounding in RoundingRule.allCases {
                var settings = Fixture.settings(rounding: rounding)
                let employer = Job(name: "Employer", breaksArePaid: paid)
                settings.addJob(employer)
                let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
                let engine = Fixture.engine(settings: settings, calendar: calendar)

                for day in randomDays(crew: [], jobID: employer.id, seed: paid ? 7 : 11) {
                    let result = calculator.compute(day)
                    let mine = result.people.first { $0.memberID == CrewMember.youID }
                    let record = SiteCalendarSync.merged(personal: nil, siteDays: [day], on: day.date)
                    let calendarDay = engine.day(day.date, record: record, holidays: [])

                    XCTAssertEqual(calendarDay.workedMinutes, mine?.workedMinutes ?? 0, "\(day.date) paid \(paid) \(rounding)")
                    if let mine {
                        XCTAssertEqual(calendarDay.breakMinutes, mine.breakMinutes, "\(day.date)")
                        XCTAssertEqual(calendarDay.start, mine.start)
                        XCTAssertEqual(calendarDay.shifts.first?.jobID, employer.id)
                    }
                }
            }
        }
    }

    /// The director's sheet: each person's month total is the sum of their
    /// cells, their days worked are the cells above zero, the crew-hours tile
    /// is the sum of the totals, and all of it is what the site screen's
    /// `crewTotalMinutes` adds up to.
    func testTheSheetTotalsAreTheSumsOfTheirCells() {
        let crew = [
            CrewMember(siteID: site.id, name: "Ana", sortOrder: 0),
            CrewMember(siteID: site.id, name: "Ivan", sortOrder: 1),
            CrewMember(siteID: site.id, name: "Hidden", isHidden: true, sortOrder: 2)
        ]
        for paid in [false, true] {
            var settings = Fixture.settings(rounding: .nearestFiveMinutes)
            settings.setPrimaryBreaksArePaid(paid)
            settings.export.durationStyle = .clock
            let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
            let results = randomDays(crew: crew, jobID: nil, seed: paid ? 3 : 5).map(calculator.compute)
            let table = SiteSheetBuilder(settings: settings, calendar: calendar)
                .makeTable(site: site, crew: crew, results: results, range: august.range(in: calendar))

            let dayRows = table.written
            let total = table.rows.first { $0.role == .total }!
            let counts = table.rows.first { $0.role == .count }!
            XCTAssertEqual(dayRows.count, results.count)

            var crewMinutes = 0
            for (index, column) in table.columns.enumerated() where column == .worked {
                let cells = dayRows.compactMap { $0.minutes[index] }
                XCTAssertEqual(total.minutes[index], cells.reduce(0, +), "column \(index)")
                XCTAssertEqual(counts.values[index], "\(cells.filter { $0 > 0 }.count)", "column \(index)")
                // The printed total is the printed figure of that sum.
                XCTAssertEqual(total.values[index], DurationFormatting.export(style: .clock, decimalSeparator: ".").string(cells.reduce(0, +)))
                crewMinutes += cells.reduce(0, +)
            }
            XCTAssertEqual(crewMinutes, results.map(\.crewTotalMinutes).reduce(0, +))
            let tile = table.tiles.first { $0.label == settings.export.language(.crewHours) }
            XCTAssertEqual(tile?.value, DurationFormatting.export(style: .clock, decimalSeparator: ".").string(crewMinutes))
            XCTAssertEqual(table.tiles.first?.value, "\(results.count)")
        }
    }
}
