import XCTest
@testable import Hours

final class SiteSheetTests: XCTestCase {
    private let site = Site(name: "Bau Süd")
    private let calendar = Fixture.calendar()
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))

    private func settings(owner: String = "Marijo", language: ExportLanguage = .english) -> AppSettings {
        Fixture.settings(export: ExportPreferences(language: language, ownerName: owner))
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
        month: Int = 8,
        own: [UUID: Attendance] = [:]
    ) -> SiteDay {
        SiteDay(
            siteID: site.id,
            date: Fixture.date(2026, month, d),
            start: start,
            end: end,
            breakMinutes: 30,
            present: present.map { own[$0] ?? Attendance(memberID: $0) },
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

    private func workbook(_ table: ReportTable) -> String {
        String(decoding: XLSXWriter.data(for: table, preferences: ExportPreferences()), as: UTF8.self)
    }

    // MARK: - Shape

    func testOneRowPerDayAndAGroupOfTwoColumnsPerPerson() {
        let ana = member("Ana", order: 1)
        let ivo = member("Ivo", order: 0)
        let t = table(crew: [ana, ivo], days: [
            day(5, present: [ivo.id, CrewMember.youID]),
            day(3, present: [CrewMember.youID, ana.id])
        ])
        // Two day rows in date order, then the two closing rows.
        XCTAssertEqual(t.rows.count, 4)
        XCTAssertEqual(t.kind, .siteSheet)
        XCTAssertEqual(t.columns, [.date, .times, .worked, .times, .worked, .times, .worked, .note])
        XCTAssertEqual(t.columnGroups.map(\.title), ["Day", "Marijo", "Ivo", "Ana", "Notes"])
        XCTAssertEqual(t.columnGroups.map(\.span), [1, 2, 2, 2, 1])
        XCTAssertEqual(t.title, "Bau Süd")
        XCTAssertEqual(t.ownerName, "Marijo")
        XCTAssertTrue(t.totals.isEmpty)

        XCTAssertEqual(t.rows[0].values[1], "07:00–16:00")
        XCTAssertEqual(t.rows[0].values[2], "8h 30m")
        // The hours are a real figure, so the workbook can write a number.
        XCTAssertEqual(t.rows[0].minutes[2], 510)
        XCTAssertNil(t.rows[0].minutes[1])
    }

    /// "Mon 3 Aug" in the export language, not the file's date style: the
    /// sheet is read by a person looking for a weekday, not sorted by a machine.
    func testTheDayColumnReadsAsAWeekdayAndADate() {
        let days = [day(3, present: [CrewMember.youID]), day(5, present: [CrewMember.youID])]
        let english = table(crew: [], days: days)
        // Whether a comma follows the weekday is the locale data's business,
        // and Apple's and Linux's disagree; the words and their order are ours.
        let plain = { (text: String) in text.replacingOccurrences(of: ",", with: "") }
        XCTAssertEqual(plain(english.rows[0].values[0]), "Mon 3 Aug")
        XCTAssertEqual(plain(english.rows[1].values[0]), "Wed 5 Aug")

        let german = table(crew: [], days: days, settings: settings(language: .german))
        XCTAssertFalse(german.rows[0].values[0].contains("Mon"), german.rows[0].values[0])
        XCTAssertTrue(german.rows[0].values[0].contains("3"), german.rows[0].values[0])
    }

    func testTheGroupTitleIsTheOwnerNameThenFallsBack() {
        let days = [day(3, present: [CrewMember.youID])]
        XCTAssertEqual(table(crew: [], days: days).columnGroups[1].title, "Marijo")
        XCTAssertEqual(table(crew: [], days: days, settings: settings(owner: "")).columnGroups[1].title, "You")
    }

    /// One flat header row for a CSV importer: the person's name on both of
    /// their columns, each saying what it holds.
    func testFlatHeadingsNameThePersonOnBothColumns() {
        let ana = member("Ana")
        let t = table(crew: [ana], days: [day(3, present: [ana.id])])
        XCTAssertEqual(t.headerTitles(), ["Day", "Ana from–to", "Ana hours", "Notes"])

        let german = table(crew: [ana], days: [day(3, present: [ana.id])], settings: settings(language: .german))
        // German keeps the capital a heading starts with: nearly every one is
        // a noun, and a lowercase noun is wrong where a capital "Von" is not.
        XCTAssertEqual(german.headerTitles(), ["Tag", "Ana Von–bis", "Ana Stunden", "Notizen"])
    }

    func testSomeoneNotThereIsOneDashAcrossTheirGroup() {
        let ana = member("Ana")
        let days = [day(3, present: [CrewMember.youID]), day(4, present: [CrewMember.youID, ana.id])]
        let t = table(crew: [ana], days: days)
        XCTAssertEqual(t.rows[0].values[3], "—")
        XCTAssertEqual(t.rows[0].values[4], "")
        XCTAssertNil(t.rows[0].minutes[4])
        // Group 2 is Ana's: Day, you, Ana, Notes.
        XCTAssertEqual(t.rows[0].mergedGroups, [2])
        XCTAssertEqual(t.rows[1].mergedGroups, [])

        // Files get empty cells.
        let file = table(crew: [ana], days: days, placeholder: "")
        XCTAssertEqual(file.rows[0].values[3], "")
        XCTAssertEqual(file.rows[0].values[4], "")
    }

    /// Someone who came late or left early is the line the director looks
    /// for, so both of their cells that day carry the flag.
    func testAnExceptionFlagsBothCellsOfThatPersonOnly() {
        let ana = member("Ana")
        let late = Attendance(memberID: ana.id, start: Fixture.time(8, 15))
        let t = table(crew: [ana], days: [
            day(3, present: [CrewMember.youID, ana.id], own: [ana.id: late]),
            day(4, present: [CrewMember.youID, ana.id])
        ])
        XCTAssertEqual(t.rows[0].flagged, [3, 4])
        XCTAssertEqual(t.rows[0].values[3], "08:15–16:00")
        XCTAssertEqual(t.rows[0].values[4], "7h 15m")
        XCTAssertEqual(t.rows[1].flagged, [])
    }

    func testTheClosingRowsSumMinutesAndCountDays() {
        let ana = member("Ana")
        let t = table(crew: [ana], days: [
            day(3, present: [CrewMember.youID, ana.id]),
            day(4, present: [CrewMember.youID]),
            day(5, present: [CrewMember.youID])
        ])
        let total = t.rows[t.rows.count - 2]
        let count = t.rows[t.rows.count - 1]
        XCTAssertEqual(t.trailingSummaryRows, 2)
        XCTAssertEqual(total.role, .total)
        XCTAssertEqual(count.role, .count)
        XCTAssertEqual(total.values[0], "Month total")
        // Under the hours column, with the times column beside it empty.
        XCTAssertEqual(total.values[1], "")
        XCTAssertEqual(total.values[2], "25h 30m")
        XCTAssertEqual(total.minutes[2], 3 * 510)
        XCTAssertEqual(total.minutes[4], 510)
        XCTAssertEqual(count.values[0], "Days worked")
        XCTAssertEqual(count.values[2], "3")
        XCTAssertEqual(count.values[4], "1")
        for row in [total, count] {
            XCTAssertTrue(row.isWorkingDay)
            XCTAssertTrue(row.hasEntry)
            XCTAssertEqual(row.balanceMinutes, 0)
        }
        XCTAssertEqual(t.rows[0].role, .day)
    }

    func testHiddenMemberStillOnPastSheet() {
        let gone = member("Gone", hidden: true)
        let t = table(crew: [gone], days: [day(3, present: [gone.id])])
        XCTAssertEqual(t.columnGroups.map(\.title), ["Day", "Gone", "Notes"])
    }

    func testPersonWithNoDaysInRangeHasNoColumn() {
        let ana = member("Ana")
        let ivo = member("Ivo")
        let t = table(crew: [ana, ivo], days: [
            day(3, present: [ana.id]),
            day(3, present: [ivo.id], month: 7)
        ])
        XCTAssertEqual(t.columnGroups.map(\.title), ["Day", "Ana", "Notes"])
        XCTAssertEqual(t.rows.count, 3)
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

    // MARK: - The header block

    func testTheHeaderBlockSaysWhoseSiteWhichMonthAndWhoRecordedIt() {
        let ana = member("Ana")
        let ivo = member("Ivo")
        let t = table(crew: [ana, ivo], days: [
            day(3, present: [CrewMember.youID, ana.id]),
            day(4, present: [CrewMember.youID, ana.id, ivo.id])
        ])
        XCTAssertEqual(t.eyebrow, "Site hours · August 2026")
        XCTAssertEqual(t.headline, "Bau Süd")
        XCTAssertEqual(t.byline, "Recorded by Marijo · 3 people · 2 days on site")
        XCTAssertEqual(t.tiles.map(\.label), ["Days on site", "Crew hours", "People"])
        XCTAssertEqual(t.tiles.map(\.value), ["2", "42h 30m", "3"])
        XCTAssertFalse(t.tiles.contains(where: \.isNegative))
        XCTAssertEqual(t.signatures, ["Checked · date, signature"])
        XCTAssertTrue(t.legend.hasPrefix("Each person: on site – off site"), t.legend)
    }

    // MARK: - Legend and paid breaks

    private let paidJobID = UUID(uuidString: "00000000-0000-4000-8000-0000000000DD")!

    /// The primary job keeps its breaks unpaid; a second job pays them.
    private func settingsWithAPaidJob() -> AppSettings {
        var settings = settings()
        settings.jobs = [
            Job(id: Job.primaryID, name: "Main", breaksArePaid: false, sortOrder: 0),
            Job(id: paidJobID, name: "Builder", breaksArePaid: true, sortOrder: 1)
        ]
        return settings
    }

    private func onPaidJob(_ siteDay: SiteDay) -> SiteDay {
        var siteDay = siteDay
        siteDay.jobID = paidJobID
        return siteDay
    }

    func testTheLegendSaysAfterTheBreakWhenBreaksAreUnpaid() {
        let t = table(crew: [], days: [day(3, present: [CrewMember.youID])], settings: settingsWithAPaidJob())
        XCTAssertEqual(t.legend, ExportLanguage.english(.siteLegend))
    }

    func testTheLegendSaysTheBreakIsIncludedWhenEveryDayPaysIt() {
        let t = table(
            crew: [],
            days: [onPaidJob(day(3, present: [CrewMember.youID])), onPaidJob(day(4, present: [CrewMember.youID]))],
            settings: settingsWithAPaidJob()
        )
        XCTAssertEqual(t.legend, ExportLanguage.english(.siteLegendPaidBreaks))
        XCTAssertEqual(t.rows[0].minutes[2], 540, "07:00–16:00 with the break paid is nine hours")
    }

    func testTheLegendStaysNeutralWhenAMonthMixesPaidAndUnpaidDays() {
        let t = table(
            crew: [],
            days: [onPaidJob(day(3, present: [CrewMember.youID])), day(4, present: [CrewMember.youID])],
            settings: settingsWithAPaidJob()
        )
        XCTAssertEqual(t.legend, ExportLanguage.english(.siteLegendMixedBreaks))
    }

    func testWithoutANameTheBylineLeavesOutWhoRecordedIt() {
        let t = table(crew: [], days: [day(3, present: [CrewMember.youID])], settings: settings(owner: ""))
        XCTAssertEqual(t.byline, "1 person · 1 day on site")
    }

    // MARK: - CSV

    func testCSVDefusesFormulaNameAndQuotesComma() {
        let formula = member("=SUM(A1)", order: 0)
        let comma = member("Kovač, Ivan", order: 1)
        let t = table(crew: [formula, comma], days: [day(3, present: [formula.id, comma.id])], placeholder: "")
        let csv = CSVExporter.string(for: t, preferences: ExportPreferences())
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(
            lines[0],
            "Day,'=SUM(A1) from–to,'=SUM(A1) hours,\"Kovač, Ivan from–to\",\"Kovač, Ivan hours\",Notes"
        )
        let date = CSVExporter.escape(t.rows[0].values[0], separator: ",")
        XCTAssertEqual(lines[1], "\(date),07:00–16:00,8h 30m,07:00–16:00,8h 30m,")
        // No empty "Summary" block follows the rows.
        XCTAssertFalse(csv.contains("Summary"))
    }

    func testCSVHoursFollowTheExportDurationStyle() {
        var settings = self.settings()
        settings.export.durationStyle = .decimal
        let t = table(crew: [], days: [day(3, present: [CrewMember.youID])], settings: settings, placeholder: "")
        let csv = CSVExporter.string(for: t, preferences: settings.export)
        XCTAssertTrue(csv.components(separatedBy: "\r\n")[1].hasSuffix(",8.50,"), csv)
    }

    // MARK: - Workbook

    func testXLSXHasAMergedGroupRowAboveTheSubHeadings() {
        let ana = member("Ana")
        let t = table(crew: [ana], days: [day(3, present: [CrewMember.youID, ana.id])], placeholder: "")
        let package = workbook(t)
        guard let group = headingRow(in: package, text: "Ana") else { return XCTFail("no group row") }
        // You in B:C, Ana in D:E, on the group row; Day and Notes run down
        // through the sub-heading row beneath.
        XCTAssertTrue(package.contains("<mergeCell ref=\"B\(group):C\(group)\"/>"))
        XCTAssertTrue(package.contains("<mergeCell ref=\"D\(group):E\(group)\"/>"))
        XCTAssertTrue(package.contains("<mergeCell ref=\"A\(group):A\(group + 1)\"/>"))
        XCTAssertTrue(package.contains(">From–to<"))
        XCTAssertTrue(package.contains(">Hours<"))
        XCTAssertFalse(package.contains(">Worked<"))
        XCTAssertFalse(package.contains(">Summary<"))
        // The builder's own closing rows are the totals; no ruled "Total" row follows.
        XCTAssertFalse(package.contains(">Total<"))
        // Frozen under the second heading row.
        XCTAssertTrue(package.contains("ySplit=\"\(group + 1)\""))
        XCTAssertTrue(package.contains(">Bau Süd — Site hours · August 2026<"))
        XCTAssertTrue(package.contains(">Recorded by Marijo · 2 people · 1 day on site<"))
    }

    func testXLSXHoursAreNumbersAndTheMonthTotalIsASum() {
        let ana = member("Ana")
        let t = table(crew: [ana], days: [
            day(3, present: [CrewMember.youID, ana.id]),
            day(4, present: [CrewMember.youID])
        ], placeholder: "")
        let package = workbook(t)
        guard let group = headingRow(in: package, text: "Ana") else { return XCTFail("no group row") }
        let first = group + 2
        // 8h 30m as a fraction of a day, behind the duration mask.
        XCTAssertTrue(package.contains("<c r=\"C\(first)\" s=\"1\"><v>0.354167</v></c>"), "hours are not numbers")
        XCTAssertTrue(package.contains("<f>SUM(C\(first):C\(first + 1))</f><v>0.708333</v>"))
        XCTAssertTrue(package.contains("<f>SUM(E\(first):E\(first + 1))</f><v>0.354167</v>"))
        // Someone not there is an empty cell, not a zero.
        XCTAssertFalse(package.contains("<c r=\"E\(first + 1)\" s=\"1\"><v>"))
    }

    func testXLSXFilterStopsAtLastDayRow() {
        let ana = member("Ana")
        let t = table(crew: [ana], days: [day(3, present: [ana.id]), day(4, present: [ana.id])], placeholder: "")
        let package = workbook(t)
        guard let group = headingRow(in: package, text: "Ana") else { return XCTFail("no group row") }
        XCTAssertTrue(package.contains("<autoFilter ref=\"A\(group + 1):D\(group + 3)\"/>"), package)
    }

    func testXLSXWritesAnExceptionInDarkOrange() {
        let ana = member("Ana")
        let late = Attendance(memberID: ana.id, end: Fixture.time(13))
        let t = table(crew: [ana], days: [day(3, present: [ana.id], own: [ana.id: late])], placeholder: "")
        let package = workbook(t)
        XCTAssertTrue(package.contains("FFC55A00"), "no dark orange in the styles")
        guard let group = headingRow(in: package, text: "Ana") else { return XCTFail("no group row") }
        let row = group + 2
        XCTAssertFalse(package.contains("<c r=\"C\(row)\" s=\"1\">"), "the exception is written like any other day")
    }

    /// The row whose column A carries the group heading style.
    private func headingRow(in package: String, text: String) -> Int? {
        guard let range = package.range(of: ">\(text)</t>") else { return nil }
        let before = package[..<range.lowerBound]
        guard let open = before.range(of: "<row r=\"", options: .backwards) else { return nil }
        let digits = package[open.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }
}
