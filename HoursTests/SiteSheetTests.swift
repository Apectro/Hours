import XCTest
@testable import Hours

final class SiteSheetTests: XCTestCase {
    private let site = Site(name: "Bau Süd")
    private let calendar = Fixture.calendar()
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))

    private func settings(owner: String = "Marijo") -> AppSettings {
        Fixture.settings(export: ExportPreferences(language: .english, ownerName: owner))
    }

    private func results(_ days: [SiteDay], settings: AppSettings) -> [SiteDayResult] {
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return days.map(calculator.compute)
    }

    private func day(
        _ d: Int,
        present: [UUID],
        start: TimeOfDay? = Fixture.time(7),
        end: TimeOfDay? = Fixture.time(16),
        note: String = "",
        month: Int = 8
    ) -> SiteDay {
        SiteDay(
            siteID: site.id,
            date: Fixture.date(2026, month, d),
            start: start,
            end: end,
            breakMinutes: 30,
            present: present.map { Attendance(memberID: $0) },
            note: note
        )
    }

    private func table(
        crew: [CrewMember],
        days: [SiteDay],
        settings: AppSettings? = nil,
        placeholder: String = "—"
    ) -> ReportTable {
        let settings = settings ?? self.settings()
        return SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: placeholder)
            .makeTable(site: site, crew: crew, results: results(days, settings: settings), range: august)
    }

    private func member(_ name: String, order: Int = 0, hidden: Bool = false) -> CrewMember {
        CrewMember(siteID: site.id, name: name, isHidden: hidden, sortOrder: order)
    }

    func testOneRowPerDayOneColumnPerPerson() {
        let ana = member("Ana", order: 1)
        let ivo = member("Ivo", order: 0)
        let t = table(crew: [ana, ivo], days: [
            day(5, present: [ivo.id, CrewMember.youID]),
            day(3, present: [CrewMember.youID, ana.id])
        ])
        // Two day rows in date order, then the two closing rows.
        XCTAssertEqual(t.rows.count, 4)
        XCTAssertEqual(t.columns, [.date, .worked, .worked, .worked, .note])
        XCTAssertEqual(t.headerTitles(), ["Day", "Marijo", "Ivo", "Ana", "Notes"])
        XCTAssertEqual(t.rows[0].values[0], "2026-08-03")
        XCTAssertEqual(t.rows[1].values[0], "2026-08-05")
        XCTAssertEqual(t.title, "Bau Süd")
        XCTAssertEqual(t.ownerName, "Marijo")
        XCTAssertTrue(t.totals.isEmpty)
        XCTAssertEqual(t.rows[0].values[1], "07:00–16:00 · 8h 30m")
    }

    func testYouColumnUsesOwnerNameThenFallsBack() {
        let days = [day(3, present: [CrewMember.youID])]
        XCTAssertEqual(table(crew: [], days: days).headerTitles()[1], "Marijo")
        XCTAssertEqual(table(crew: [], days: days, settings: settings(owner: "")).headerTitles()[1], "You")
    }

    func testAbsentCellIsPlaceholder() {
        let ana = member("Ana")
        let days = [day(3, present: [CrewMember.youID]), day(4, present: [CrewMember.youID, ana.id])]
        let t = table(crew: [ana], days: days)
        XCTAssertEqual(t.rows[0].values[2], "—")
        XCTAssertNil(t.rows[0].minutes[2])
        XCTAssertNil(t.rows[1].minutes[2])
        XCTAssertEqual(table(crew: [ana], days: days, placeholder: "").rows[0].values[2], "")
    }

    func testTotalsRowSumsMinutesAndCountsDays() {
        let ana = member("Ana")
        let t = table(crew: [ana], days: [
            day(3, present: [CrewMember.youID, ana.id]),
            day(4, present: [CrewMember.youID]),
            day(5, present: [CrewMember.youID])
        ])
        let total = t.rows[t.rows.count - 2]
        let count = t.rows[t.rows.count - 1]
        XCTAssertEqual(total.values[0], "Month total")
        XCTAssertEqual(total.minutes[1], 3 * 510)
        XCTAssertEqual(total.values[1], "25h 30m")
        XCTAssertEqual(total.minutes[2], 510)
        XCTAssertEqual(count.values[0], "Days worked")
        XCTAssertEqual(count.values[1], "3")
        XCTAssertEqual(count.values[2], "1")
        for row in [total, count] {
            XCTAssertTrue(row.isWorkingDay)
            XCTAssertTrue(row.hasEntry)
            XCTAssertEqual(row.balanceMinutes, 0)
        }
    }

    func testHiddenMemberStillOnPastSheet() {
        let gone = member("Gone", hidden: true)
        let t = table(crew: [gone], days: [day(3, present: [gone.id])])
        XCTAssertEqual(t.headerTitles(), ["Day", "Gone", "Notes"])
    }

    func testPersonWithNoDaysInRangeHasNoColumn() {
        let ana = member("Ana")
        let ivo = member("Ivo")
        let t = table(crew: [ana, ivo], days: [
            day(3, present: [ana.id]),
            day(3, present: [ivo.id], month: 7)
        ])
        XCTAssertEqual(t.headerTitles(), ["Day", "Ana", "Notes"])
        XCTAssertEqual(t.rows.count, 3)
    }

    func testCSVDefusesFormulaNameAndQuotesComma() {
        let formula = member("=SUM(A1)", order: 0)
        let comma = member("Kovač, Ivan", order: 1)
        let t = table(crew: [formula, comma], days: [day(3, present: [formula.id, comma.id])])
        let csv = CSVExporter.string(for: t, preferences: ExportPreferences())
        let header = csv.components(separatedBy: "\r\n")[0]
        XCTAssertEqual(header, "Day,'=SUM(A1),\"Kovač, Ivan\",Notes")
        // No empty "Summary" block follows the rows.
        XCTAssertFalse(csv.contains("Summary"))
    }

    func testXLSXHeaderUsesOverrides() {
        let ana = member("Ana")
        let t = table(crew: [ana], days: [day(3, present: [ana.id])])
        let package = String(decoding: XLSXWriter.data(for: t, preferences: ExportPreferences()), as: UTF8.self)
        XCTAssertTrue(package.contains(">Ana<"))
        XCTAssertTrue(package.contains(">Day<"))
        XCTAssertFalse(package.contains(">Worked<"))
        XCTAssertFalse(package.contains(">Summary<"))
        // The builder's own closing rows are the totals; no ruled "Total" row follows.
        XCTAssertFalse(package.contains(">Total<"))
        XCTAssertFalse(package.contains("<f>SUM("))
    }

    func testXLSXFilterStopsAtLastDayRow() {
        let ana = member("Ana")
        let t = table(crew: [ana], days: [day(3, present: [ana.id]), day(4, present: [ana.id])])
        let package = String(decoding: XLSXWriter.data(for: t, preferences: ExportPreferences()), as: UTF8.self)
        // Title, subtitle(+owner), blank, header; two days then two closing rows.
        let header = (1...20).first { package.contains("<c r=\"A\($0)\" t=\"inlineStr\" s=\"5\">") } ?? 0
        XCTAssertGreaterThan(header, 0)
        XCTAssertTrue(package.contains("<autoFilter ref=\"A\(header):C\(header + 2)\"/>"))
    }

    func testNoteColumnCarriesDayNote() {
        let t = table(crew: [], days: [
            day(3, present: [CrewMember.youID], note: "Rain, concrete delayed"),
            day(4, present: [CrewMember.youID])
        ])
        let last = t.columns.count - 1
        XCTAssertEqual(t.rows[0].values[last], "Rain, concrete delayed")
        XCTAssertEqual(t.rows[1].values[last], "")
    }
}
