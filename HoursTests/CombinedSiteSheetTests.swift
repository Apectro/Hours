import XCTest
@testable import Hours

/// One director's sheet for several sites' month (1.2): the crews joined by
/// name, a Site column, a day on two sites as a row per site and a "Total",
/// a "By site" block, and the sites in the title. One site is exactly the
/// site sheet.
final class CombinedSiteSheetTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))
    private let haupt = Site(name: "Hauptstraße 12", address: "Hauptstraße 12\n10115 Berlin")
    private let trg = Site(name: "Trg Pravde")

    private lazy var ivan = CrewMember(siteID: haupt.id, name: "Ivan", sortOrder: 0)
    private lazy var marko = CrewMember(siteID: haupt.id, name: "Marko", sortOrder: 1)
    /// Ivan again on the other site's own crew, written differently.
    private lazy var ivanThere = CrewMember(siteID: trg.id, name: " ivan", sortOrder: 1)
    private lazy var luka = CrewMember(siteID: trg.id, name: "Luka", sortOrder: 0)

    private var crew: [CrewMember] { [ivan, marko, ivanThere, luka] }

    private func settings(allowance: Bool = false) -> AppSettings {
        var settings = Fixture.settings(export: ExportPreferences(language: .english, ownerName: "Marijo"))
        if allowance {
            settings.allowance = AllowancePreferences(isEnabled: true, dailyAllowanceCents: 25_00, centsPerKilometre: 30)
        }
        return settings
    }

    private func day(
        _ site: Site,
        _ d: Int,
        present: [UUID],
        start: TimeOfDay = Fixture.time(7),
        end: TimeOfDay = Fixture.time(16),
        breakMinutes: Int = 30,
        own: [UUID: Attendance] = [:],
        absences: [CrewAbsence] = [],
        note: String = "",
        badWeather: Bool = false,
        allowance: [UUID] = [],
        km: Int = 0
    ) -> SiteDay {
        SiteDay(
            siteID: site.id,
            date: Fixture.date(2026, 8, d),
            start: start,
            end: end,
            breakMinutes: breakMinutes,
            present: present.map { own[$0] ?? Attendance(memberID: $0) },
            note: note,
            isBadWeatherStop: badWeather,
            absences: absences,
            allowanceMemberIDs: allowance,
            kilometres: km
        )
    }

    private func table(
        _ sites: [Site],
        days: [SiteDay],
        settings: AppSettings? = nil,
        signatures: [CrewSignature] = [],
        includesSignatures: Bool = true,
        siteNames: [UUID: String] = [:]
    ) -> ReportTable {
        let settings = settings ?? self.settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return SiteSheetBuilder(settings: settings, calendar: calendar)
            .makeTable(
                sites: sites,
                crew: crew,
                results: days.map(calculator.compute),
                range: august,
                signatures: signatures,
                includesSignatures: includesSignatures,
                siteNames: siteNames
            )
    }

    private func people(_ table: ReportTable) -> [String] {
        table.columnGroups.dropFirst(3).dropLast().map(\.title)
    }

    /// The rows for `d`: one per site, then "Total" on a day on more than one.
    private func rows(_ table: ReportTable, day d: Int) -> [ReportRow] {
        let key = Fixture.date(2026, 8, d).key
        return table.rows.filter { $0.role == .day && ($0.id == key || (-$0.id) / 10 == key) }
    }

    /// The times and hours of `person` (0 is the first column group after
    /// the date, the day and the site) on the `row`th row for `d`.
    private func cell(_ table: ReportTable, person: Int, day d: Int, row index: Int = 0) -> (times: String, hours: String, minutes: Int?, flagged: Bool) {
        let dayRows = rows(table, day: d)
        guard index < dayRows.count else { return ("", "", nil, false) }
        let row = dayRows[index]
        let column = 3 + person * 2
        return (row.values[column], row.values[column + 1], row.minutes[column + 1], row.flagged.contains(column))
    }

    private func closing(_ table: ReportTable, _ label: String) -> [String]? {
        table.rows.first { $0.role != .day && $0.values.first == label }?.values
    }

    // MARK: - One site is the site sheet

    func testOneSiteIsExactlyTheSiteSheet() {
        let settings = settings(allowance: true)
        let days = [
            day(haupt, 3, present: [CrewMember.youID, ivan.id], note: "Formwork", allowance: [ivan.id], km: 40),
            day(haupt, 4, present: [ivan.id], own: [ivan.id: Attendance(memberID: ivan.id, end: Fixture.time(12))],
                absences: [CrewAbsence(memberID: marko.id, dayTypeID: .sick)], badWeather: true),
            day(haupt, 5, present: [CrewMember.youID], absences: [CrewAbsence(memberID: ivan.id, reason: .otherSite(trg.id))])
        ]
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let results = days.map(calculator.compute)
        let signature = CrewSignature(
            siteID: haupt.id, memberID: ivan.id, month: august.start.yearMonth, signedOn: Fixture.date(2026, 9, 1),
            fingerprint: "x", strokes: [[SignaturePoint(x: 0, y: 0), SignaturePoint(x: 1, y: 1)]]
        )
        let names = [trg.id: trg.name]
        let builder = SiteSheetBuilder(settings: settings, calendar: calendar)
        let today = builder.makeTable(
            site: haupt, crew: [ivan, marko], results: results, range: august,
            signatures: [signature], siteNames: names
        )
        let combined = builder.makeTable(
            sites: [haupt], crew: [ivan, marko], results: results, range: august,
            signatures: [signature], siteNames: names
        )
        XCTAssertEqual(combined, today)
        XCTAssertTrue(combined.bySite.isEmpty)
    }

    // MARK: - The crew

    func testTheCrewIsBothSitesJoinedByNameYouOnce() {
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [CrewMember.youID, marko.id, ivan.id]),
            day(trg, 4, present: [luka.id, ivanThere.id, CrewMember.youID])
        ])
        XCTAssertEqual(people(t), ["Marijo", "Ivan", "Marko", "Luka"], "the first site's order, then newcomers in theirs")
        XCTAssertEqual(t.kind, .siteSheet)
        XCTAssertEqual(SiteSheetBuilder.peopleCount(in: t), 4)
    }

    func testTheSecondSitesOrderDecidesOnlyForNewcomers() {
        let t = table([trg, haupt], days: [
            day(haupt, 3, present: [marko.id, ivan.id]),
            day(trg, 4, present: [luka.id, ivanThere.id])
        ])
        XCTAssertEqual(people(t), ["Luka", "ivan", "Marko"], "the order chosen leads, and the name as that site has it")
    }

    // MARK: - Hours

    func testHoursAreAddedUpAcrossTheSitesOnADay() {
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [ivan.id], end: Fixture.time(11, 30), breakMinutes: 0),
            day(trg, 3, present: [ivanThere.id], start: Fixture.time(12), end: Fixture.time(16), breakMinutes: 30),
            day(trg, 4, present: [ivanThere.id])
        ])
        let monday = rows(t, day: 3)
        XCTAssertEqual(monday.map { $0.values[2] }, ["Hauptstraße 12", "Trg Pravde", "Total"])
        XCTAssertEqual(monday.map(\.splitDay), [.site, .site, .subtotal])
        XCTAssertFalse(monday[0].values[0].isEmpty, "the date on the first row")
        XCTAssertEqual(monday.dropFirst().map { $0.values[0] }, ["", ""], "and only there")
        XCTAssertEqual(cell(t, person: 0, day: 3, row: 0).times, "07:00–11:30")
        XCTAssertEqual(cell(t, person: 0, day: 3, row: 0).minutes, 270)
        XCTAssertEqual(cell(t, person: 0, day: 3, row: 1).times, "12:00–16:00")
        XCTAssertEqual(cell(t, person: 0, day: 3, row: 1).minutes, 210)
        let total = cell(t, person: 0, day: 3, row: 2)
        XCTAssertEqual(total.hours, "8h", "the day on both sites added up")
        XCTAssertNil(total.minutes, "text, so the month's sum counts the sites' rows only")
        XCTAssertEqual(cell(t, person: 0, day: 4).minutes, 510)
        XCTAssertEqual(rows(t, day: 4).map(\.splitDay), [nil], "a day on one site is one row")
        XCTAssertEqual(rows(t, day: 4).first?.values[2], "Trg Pravde", "and still says where")
        XCTAssertEqual(closing(t, "Month total")?[4], "16h 30m")
        XCTAssertEqual(closing(t, "Days worked")?[4], "2", "a day on two sites is one day")
    }

    func testAMovedDayShowsTheWholeDayOnce() throws {
        let source = day(haupt, 4, present: [CrewMember.youID, ivan.id, marko.id])
        let outcome = try SiteMoving.apply(SiteMoveRequest(
            source: source,
            target: nil,
            targetSite: trg,
            sourceCrew: [ivan, marko],
            targetCrew: [ivanThere, luka],
            memberIDs: [ivan.id],
            left: Fixture.time(11, 30),
            started: Fixture.time(12),
            breakPlacement: .there,
            lock: .unlocked,
            tracksAllowance: false
        ))
        let t = table([haupt, trg], days: [outcome.source, outcome.target])
        XCTAssertEqual(people(t), ["Marijo", "Ivan", "Marko"])
        let here = cell(t, person: 1, day: 4, row: 0)
        let there = cell(t, person: 1, day: 4, row: 1)
        XCTAssertEqual(here.times, "07:00–11:30")
        XCTAssertEqual(there.times, "12:00–16:00")
        XCTAssertEqual((here.minutes ?? 0) + (there.minutes ?? 0), 480, "4:30 here and 3:30 there")
        XCTAssertEqual(cell(t, person: 1, day: 4, row: 2).hours, "8h")
        XCTAssertFalse(here.flagged, "leaving one site for another is not leaving early")
        XCTAssertFalse(there.flagged)
        XCTAssertEqual(cell(t, person: 2, day: 4).minutes, 510)
        XCTAssertEqual(cell(t, person: 2, day: 4, row: 1).times, "—", "Marko stayed")
        XCTAssertEqual(cell(t, person: 2, day: 4, row: 2).hours, "", "one site, so no total: his hours are on his row")
        XCTAssertEqual(cell(t, person: 0, day: 4, row: 2).hours, "", "you stayed too")
    }

    func testASiteNobodyWorkedThatDayIsNoRow() {
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: []),
            day(trg, 3, present: [ivanThere.id, luka.id]),
            day(haupt, 4, present: [], note: "Inspection"),
            day(trg, 4, present: [luka.id]),
            day(haupt, 5, present: [], badWeather: true),
            day(trg, 5, present: [luka.id])
        ])
        XCTAssertEqual(rows(t, day: 3).map { $0.values[2] }, ["Trg Pravde"], "a row of dashes says nothing")
        XCTAssertFalse(rows(t, day: 3)[0].values[0].isEmpty, "the date moves to the first row shown")
        XCTAssertEqual(rows(t, day: 4).map { $0.values[2] }, ["Hauptstraße 12", "Trg Pravde"], "a note keeps its row")
        XCTAssertEqual(rows(t, day: 5).count, 2, "so does bad weather")
    }

    // MARK: - Away

    func testAReasonShowsOnlyWhenTheyWorkedOnNoChosenSite() {
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [marko.id], absences: [CrewAbsence(memberID: ivan.id, dayTypeID: .sick)]),
            day(trg, 3, present: [ivanThere.id]),
            day(haupt, 4, present: [ivan.id], absences: [CrewAbsence(memberID: marko.id, dayTypeID: .sick)])
        ])
        XCTAssertEqual(people(t), ["Ivan", "Marko"])
        XCTAssertEqual(cell(t, person: 0, day: 3, row: 0).times, "—", "worked on the other site, so not away")
        XCTAssertEqual(cell(t, person: 0, day: 3, row: 1).minutes, 510)
        XCTAssertEqual(rows(t, day: 3).count, 2, "nobody was on both sites, so no total")
        XCTAssertEqual(rows(t, day: 3).map(\.splitDay), [nil, nil])
        XCTAssertEqual(cell(t, person: 1, day: 3, row: 0).minutes, 510)
        XCTAssertEqual(cell(t, person: 1, day: 4).times, "Sick leave")
        XCTAssertEqual(closing(t, "Sick days")?[6], "1")
        XCTAssertEqual(closing(t, "Sick days")?[4], "", "Ivan's sick note on the 3rd counts for nothing")
    }

    func testOnAnotherChosenSiteIsNotAway() {
        let elsewhere = UUID()
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [marko.id], absences: [CrewAbsence(memberID: ivan.id, reason: .otherSite(trg.id))]),
            day(trg, 3, present: [ivanThere.id]),
            day(haupt, 4, present: [ivan.id], absences: [CrewAbsence(memberID: marko.id, reason: .otherSite(trg.id))]),
            day(haupt, 5, present: [ivan.id], absences: [CrewAbsence(memberID: marko.id, reason: .otherSite(elsewhere))])
        ], siteNames: [elsewhere: "Schulweg 4", trg.id: trg.name])
        XCTAssertEqual(cell(t, person: 0, day: 3, row: 1).minutes, 510)
        XCTAssertEqual(cell(t, person: 1, day: 4).times, "—", "pointing at a site on this sheet is no reason to print")
        XCTAssertEqual(cell(t, person: 1, day: 5).times, "Schulweg 4", "a site not on the sheet is named, as on a site sheet")
    }

    // MARK: - Closing rows

    func testTheAllowanceIsADayOnceAndTheKilometresAddUp() {
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [ivan.id], end: Fixture.time(11), allowance: [ivan.id], km: 40),
            day(trg, 3, present: [ivanThere.id], start: Fixture.time(12), allowance: [ivanThere.id], km: 25),
            day(trg, 4, present: [ivanThere.id], allowance: [ivanThere.id])
        ], settings: settings(allowance: true))
        XCTAssertEqual(closing(t, "Allowance days")?[4], "2")
        XCTAssertEqual(closing(t, "Kilometres")?.last, "65 km")
    }

    func testEachPersonsHoursOnEachSiteCloseTheSheet() {
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [ivan.id], end: Fixture.time(11, 30), breakMinutes: 0),
            day(trg, 3, present: [ivanThere.id, luka.id], start: Fixture.time(12), end: Fixture.time(16), breakMinutes: 30),
            day(haupt, 4, present: [ivan.id, marko.id])
        ])
        XCTAssertEqual(people(t), ["Ivan", "Marko", "Luka"])
        let labels = t.rows.filter { $0.role != .day }.map { $0.values[0] }
        XCTAssertEqual(labels, ["Month total", "Days worked", "Hauptstraße 12", "Trg Pravde"])
        XCTAssertEqual(closing(t, "Hauptstraße 12")?[4], "13h", "4:30 and 8:30")
        XCTAssertEqual(closing(t, "Trg Pravde")?[4], "3h 30m")
        XCTAssertEqual(closing(t, "Hauptstraße 12")?[8], "", "Luka was never there")
        XCTAssertEqual(closing(t, "Trg Pravde")?[8], "3h 30m")
        XCTAssertEqual(closing(t, "Month total")?[4], "16h 30m", "the sites add up to the month")
        let row = t.rows.first { $0.values[0] == "Trg Pravde" && $0.role == .count }
        XCTAssertEqual(row?.minutes[4], 210, "hours a workbook can add up")
        XCTAssertEqual(t.trailingSummaryRows, 4)
    }

    func testBySiteHasEachSitesHoursTheAddressAndTheTotal() {
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [CrewMember.youID, ivan.id]),
            day(trg, 4, present: [ivanThere.id, luka.id], end: Fixture.time(12), breakMinutes: 0)
        ])
        XCTAssertEqual(t.bySite.map(\.name), ["Hauptstraße 12", "Trg Pravde", "Total"])
        XCTAssertEqual(t.bySite.map(\.address), ["Hauptstraße 12, 10115 Berlin", "", ""])
        XCTAssertEqual(t.bySite.map(\.minutes), [1020, 600, 1620])
        XCTAssertEqual(t.bySite.map(\.isTotal), [false, false, true])
        XCTAssertEqual(t.bySite.last?.value, "27h")
        XCTAssertEqual(t.tiles.first { $0.label == "Crew hours" }?.value, "27h", "the total is the crew's hours")
    }

    func testASiteWithNothingThisMonthIsStillListed() {
        let t = table([haupt, trg], days: [day(haupt, 3, present: [ivan.id])])
        XCTAssertEqual(t.bySite.map(\.minutes), [510, 0, 510])
    }

    // MARK: - Title and header

    func testTheTitleNamesTheSitesInTheOrderChosenAndNoAddress() {
        let t = table([trg, haupt], days: [day(haupt, 3, present: [ivan.id])])
        XCTAssertEqual(t.title, "Trg Pravde · Hauptstraße 12")
        XCTAssertEqual(t.address, "", "addresses go in By site")
        XCTAssertEqual(t.eyebrow, "Site hours · August 2026")
    }

    func testMoreThanThreeSitesAreTheFirstTwoAndMore() {
        let third = Site(name: "Schulweg 4")
        let fourth = Site(name: "Ilica 1")
        let t = table([haupt, trg, third, fourth], days: [day(haupt, 3, present: [ivan.id])])
        XCTAssertEqual(t.title, "Hauptstraße 12 · Trg Pravde +2 more")
        XCTAssertEqual(t.bySite.count, 5)
    }

    func testBadWeatherIsEachSitesOwnAndADayOnlyWhenEverySiteWasRainedOff() {
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [ivan.id], end: Fixture.time(11), badWeather: true),
            day(trg, 3, present: [luka.id]),
            day(haupt, 4, present: [ivan.id], end: Fixture.time(10), badWeather: true),
            day(trg, 4, present: [luka.id], end: Fixture.time(10), badWeather: true)
        ])
        let notes = t.columns.count - 1
        XCTAssertEqual(rows(t, day: 3).map { $0.values[notes] }, ["Bad weather", ""], "each site's own day")
        XCTAssertEqual(rows(t, day: 4).map { $0.values[notes] }, ["Bad weather", "Bad weather"])
        XCTAssertEqual(t.tiles.first { $0.label == "Bad-weather days" }?.value, "1")
    }

    func testNotesSitOnTheirSitesRow() {
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [ivan.id], note: "Formwork"),
            day(trg, 3, present: [luka.id], note: "Delivery"),
            day(trg, 4, present: [luka.id], note: "Scaffold")
        ])
        let notes = t.columns.count - 1
        XCTAssertEqual(rows(t, day: 3).map { $0.values[notes] }, ["Formwork", "Delivery"], "each on its site's row")
        XCTAssertEqual(rows(t, day: 4).map { $0.values[notes] }, ["Scaffold"])
    }

    // MARK: - Signatures

    func testACombinedSheetHasTheLineToSignButNoDrawnSignOff() {
        let signature = CrewSignature(
            siteID: haupt.id, memberID: ivan.id, month: august.start.yearMonth, signedOn: Fixture.date(2026, 9, 1),
            fingerprint: "x", strokes: [[SignaturePoint(x: 0, y: 0), SignaturePoint(x: 1, y: 1)]]
        )
        let days = [day(haupt, 3, present: [ivan.id]), day(trg, 4, present: [luka.id])]
        let signed = table([haupt, trg], days: days, signatures: [signature])
        XCTAssertEqual(signed.signatures, [ExportLanguage.english(.checkedSignature)])
        XCTAssertTrue(signed.signOff.isEmpty)
        XCTAssertTrue(signed.legend.hasSuffix("Crew sign-offs are on each site's own sheet."), signed.legend)

        let unsigned = table([haupt, trg], days: days)
        XCTAssertFalse(unsigned.legend.contains("sign-offs"), "a footnote only where a sign-off was left out")

        let off = table([haupt, trg], days: days, signatures: [signature], includesSignatures: false)
        XCTAssertTrue(off.signatures.isEmpty)
        XCTAssertFalse(off.legend.contains("sign-offs"))
    }

    // MARK: - Pages and files

    func testASplitSheetKeepsBySiteForItsLastPart() {
        let many = (0..<8).map { CrewMember(siteID: trg.id, name: "Person \($0)", sortOrder: 10 + $0) }
        let settings = settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let t = SiteSheetBuilder(settings: settings, calendar: calendar).makeTable(
            sites: [haupt, trg],
            crew: crew + many,
            results: [
                day(haupt, 3, present: [ivan.id, marko.id]),
                day(trg, 3, present: many.map(\.id))
            ].map(calculator.compute),
            range: august
        )
        let parts = SiteSheetBuilder.split(t, peoplePerPage: 5)
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].bySite.isEmpty)
        XCTAssertEqual(parts[1].bySite, t.bySite)
    }

    func testTheWorkbookAndTheCSVCarryBySite() {
        let t = table([haupt, trg], days: [day(haupt, 3, present: [ivan.id]), day(trg, 4, present: [luka.id])])
        let csv = CSVExporter.string(for: t, preferences: ExportPreferences())
        XCTAssertTrue(csv.contains("By site"), csv)
        XCTAssertTrue(csv.contains("Hauptstraße 12,\"Hauptstraße 12, 10115 Berlin\",8h 30m"), csv)
        let workbook = String(decoding: XLSXWriter.data(for: t, preferences: ExportPreferences()), as: UTF8.self)
        XCTAssertTrue(workbook.contains("By site"))
        XCTAssertTrue(workbook.contains("Trg Pravde"))
    }

    func testTheFileNameJoinsTheSitesAndTheMonth() {
        let naming = ExportNaming(settings: settings(), calendar: calendar)
        let month = august.start.yearMonth
        XCTAssertEqual(naming.siteSheetFileName([haupt], month: month), naming.siteFileName(haupt, month: month))
        XCTAssertEqual(naming.siteSheetFileName([haupt, trg], month: month), "Hauptstraße 12 + Trg Pravde – August 2026")
        let more = [haupt, trg, Site(name: "A"), Site(name: "B")]
        XCTAssertEqual(naming.siteSheetFileName(more, month: month), "Hauptstraße 12 + Trg Pravde +2 more – August 2026")
    }

    func testTheDiaryOfEachSiteFollowsUnderItsName() {
        let builder = SiteDiaryReportBuilder(settings: settings(), calendar: calendar)
        var first = SiteDiary(siteID: haupt.id, date: Fixture.date(2026, 8, 4))
        first.weather = .rain
        var second = SiteDiary(siteID: trg.id, date: Fixture.date(2026, 8, 3))
        second.weather = .sunny
        let a = builder.make(diaries: [first], photos: [], badWeatherStops: [], range: august)
        let b = builder.make(diaries: [second], photos: [], badWeatherStops: [], range: august)
        let empty = builder.make(diaries: [], photos: [], badWeatherStops: [], range: august)
        let combined = SiteDiaryReport.combined([("Hauptstraße 12", a), ("Schulweg 4", empty), ("Trg Pravde", b)])
        XCTAssertEqual(combined.blocks.map(\.heading), [
            "Hauptstraße 12 · \(a.blocks[0].heading)",
            "Trg Pravde · \(b.blocks[0].heading)"
        ])
        XCTAssertEqual(combined.title, a.title)
        XCTAssertEqual(combined.headings, a.headings)
        XCTAssertTrue(SiteDiaryReport.combined([("Schulweg 4", empty)]).isEmpty)
    }
}
