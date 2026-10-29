import XCTest
@testable import Hours

/// One director's sheet for several sites' month (1.2): the crews joined by
/// name, each person's hours a day added up across the sites, a "By site"
/// block, and the sites in the title. One site is exactly the site sheet.
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
        table.columnGroups.dropFirst(2).dropLast().map(\.title)
    }

    /// The times and hours of `person` (0 is the first column group after
    /// the date and the day) on the row for `d`.
    private func cell(_ table: ReportTable, person: Int, day d: Int) -> (times: String, hours: String, minutes: Int?, flagged: Bool) {
        let key = Fixture.date(2026, 8, d).key
        guard let row = table.rows.first(where: { $0.id == key }) else { return ("", "", nil, false) }
        let column = 2 + person * 2
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
        let monday = cell(t, person: 0, day: 3)
        XCTAssertEqual(monday.minutes, 270 + 210)
        XCTAssertEqual(monday.hours, "8h")
        XCTAssertEqual(monday.times, "07:00–16:00", "from the first start to the last end")
        XCTAssertEqual(cell(t, person: 0, day: 4).minutes, 510)
        XCTAssertEqual(closing(t, "Month total")?[3], "16h 30m")
        XCTAssertEqual(closing(t, "Days worked")?[3], "2", "a day on two sites is one day")
        XCTAssertEqual(t.rows.filter { $0.role == .day }.count, 2, "a row per date, not per site day")
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
        let ivanCell = cell(t, person: 1, day: 4)
        XCTAssertEqual(ivanCell.minutes, 480, "4:30 here and 3:30 there")
        XCTAssertEqual(ivanCell.times, "07:00–16:00")
        XCTAssertFalse(ivanCell.flagged, "a whole day across two sites is not someone leaving early")
        XCTAssertEqual(cell(t, person: 2, day: 4).minutes, 510)
    }

    // MARK: - Away

    func testAReasonShowsOnlyWhenTheyWorkedOnNoChosenSite() {
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [marko.id], absences: [CrewAbsence(memberID: ivan.id, dayTypeID: .sick)]),
            day(trg, 3, present: [ivanThere.id]),
            day(haupt, 4, present: [ivan.id], absences: [CrewAbsence(memberID: marko.id, dayTypeID: .sick)])
        ])
        XCTAssertEqual(people(t), ["Ivan", "Marko"])
        XCTAssertEqual(cell(t, person: 0, day: 3).minutes, 510, "worked on the other site, so not away")
        XCTAssertEqual(cell(t, person: 1, day: 4).times, "Sick leave")
        XCTAssertEqual(closing(t, "Sick days")?[5], "1")
        XCTAssertEqual(closing(t, "Sick days")?[3], "", "Ivan's sick note on the 3rd counts for nothing")
    }

    func testOnAnotherChosenSiteIsNotAway() {
        let elsewhere = UUID()
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [marko.id], absences: [CrewAbsence(memberID: ivan.id, reason: .otherSite(trg.id))]),
            day(trg, 3, present: [ivanThere.id]),
            day(haupt, 4, present: [ivan.id], absences: [CrewAbsence(memberID: marko.id, reason: .otherSite(trg.id))]),
            day(haupt, 5, present: [ivan.id], absences: [CrewAbsence(memberID: marko.id, reason: .otherSite(elsewhere))])
        ], siteNames: [elsewhere: "Schulweg 4", trg.id: trg.name])
        XCTAssertEqual(cell(t, person: 0, day: 3).minutes, 510)
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
        XCTAssertEqual(closing(t, "Allowance days")?[3], "2")
        XCTAssertEqual(closing(t, "Kilometres")?.last, "65 km")
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

    func testBadWeatherOnlyWhenEverySiteThatDayWasRainedOff() {
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [ivan.id], end: Fixture.time(11), badWeather: true),
            day(trg, 3, present: [luka.id]),
            day(haupt, 4, present: [ivan.id], end: Fixture.time(10), badWeather: true),
            day(trg, 4, present: [luka.id], end: Fixture.time(10), badWeather: true)
        ])
        let notes = t.columns.count - 1
        XCTAssertEqual(t.rows.first { $0.id == Fixture.date(2026, 8, 3).key }?.values[notes], "")
        XCTAssertEqual(t.rows.first { $0.id == Fixture.date(2026, 8, 4).key }?.values[notes], "Bad weather")
        XCTAssertEqual(t.tiles.first { $0.label == "Bad-weather days" }?.value, "1")
    }

    func testNotesNameTheirSiteOnADayOnTwo() {
        let t = table([haupt, trg], days: [
            day(haupt, 3, present: [ivan.id], note: "Formwork"),
            day(trg, 3, present: [luka.id], note: "Delivery"),
            day(trg, 4, present: [luka.id], note: "Scaffold")
        ])
        let notes = t.columns.count - 1
        XCTAssertEqual(t.rows.first { $0.id == Fixture.date(2026, 8, 3).key }?.values[notes], "Hauptstraße 12: Formwork · Trg Pravde: Delivery")
        XCTAssertEqual(t.rows.first { $0.id == Fixture.date(2026, 8, 4).key }?.values[notes], "Scaffold")
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
