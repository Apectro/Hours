import XCTest
@testable import Hours

/// The field allowance and the vehicle's kilometres on a site: who on the
/// crew gets the allowance, how it and the kilometres reach your own day,
/// and the closing lines of the site sheet.
final class SiteAllowanceTests: XCTestCase {
    private let site = Site(name: "Trg Pravde", allowanceByDefault: true)
    private let calendar = Fixture.calendar()
    private let ana = UUID()
    private let ivo = UUID()
    private let you = CrewMember.youID
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))

    private func day(
        _ d: Int = 4,
        present: [UUID],
        allowance: [UUID] = [],
        km: Int = 0,
        start: TimeOfDay? = Fixture.time(7),
        end: TimeOfDay? = Fixture.time(15, 30)
    ) -> SiteDay {
        SiteDay(
            siteID: site.id,
            date: Fixture.date(2026, 8, d),
            start: start,
            end: end,
            breakMinutes: 30,
            present: present.map { Attendance(memberID: $0) },
            allowanceMemberIDs: allowance,
            kilometres: km
        )
    }

    // MARK: - The site

    func testASiteGivesNoAllowanceByDefaultUnlessSet() throws {
        XCTAssertFalse(Site(name: "Bau Süd").allowanceByDefault)
        let decoded = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(site))
        XCTAssertEqual(decoded, site)
        let old = try JSONDecoder().decode(Site.self, from: Data(#"{"name": "Old", "isArchived": false, "sortOrder": 0}"#.utf8))
        XCTAssertFalse(old.allowanceByDefault)
    }

    // MARK: - Who gets it

    func testTickingSomeoneInGivesThemTheAllowanceWhenTheSiteDoes() {
        let empty = SiteDay(siteID: site.id, date: Fixture.date(2026, 8, 4))
        let ticked = empty.togglingPresence(of: ana, allowanceByDefault: true)
        XCTAssertTrue(ticked.hasAllowance(for: ana))
        let plain = empty.togglingPresence(of: ana, allowanceByDefault: false)
        XCTAssertFalse(plain.hasAllowance(for: ana))
        XCTAssertFalse(empty.togglingPresence(of: ana).hasAllowance(for: ana), "off unless the site says so")
    }

    func testTickingSomeoneOutTakesTheirAllowance() {
        let ticked = day(present: [ana, ivo], allowance: [ana, ivo])
        let out = ticked.togglingPresence(of: ana, allowanceByDefault: true)
        XCTAssertFalse(out.hasAllowance(for: ana))
        XCTAssertEqual(out.allowanceMemberIDs, [ivo])
        // And ticking back in starts from the site's default again.
        XCTAssertTrue(out.togglingPresence(of: ana, allowanceByDefault: true).hasAllowance(for: ana))
    }

    func testTheAllowanceIsPerPerson() {
        let ticked = day(present: [ana, ivo], allowance: [ana, ivo])
        let without = ticked.settingAllowance(false, for: ivo)
        XCTAssertTrue(without.hasAllowance(for: ana))
        XCTAssertFalse(without.hasAllowance(for: ivo))
        XCTAssertTrue(without.settingAllowance(true, for: ivo).hasAllowance(for: ivo))
        XCTAssertEqual(without.settingAllowance(true, for: ivo).settingAllowance(true, for: ivo).allowanceMemberIDs.count, 2)
    }

    func testSomeoneNotThereGetsNoAllowance() {
        let stray = day(present: [ana], allowance: [ana, ivo])
        XCTAssertFalse(stray.hasAllowance(for: ivo), "not ticked present, so no allowance whatever the list says")
        XCTAssertEqual(stray.allowanceCount, 1)
        XCTAssertFalse(day(present: [ana]).settingAllowance(true, for: ivo).hasAllowance(for: ivo))
    }

    func testAReasonForBeingAwayTakesTheAllowance() {
        let sick = day(present: [ana], allowance: [ana]).settingAbsence(.sick, for: ana)
        XCTAssertEqual(sick.allowanceMemberIDs, [])
    }

    func testABadWeatherStopKeepsTheAllowance() {
        let stopped = day(present: [ana], allowance: [ana], km: 40).stoppedForBadWeather(at: nil)
        XCTAssertTrue(stopped.hasAllowance(for: ana), "the crew turned up and was sent home")
        XCTAssertEqual(stopped.kilometres, 40)
    }

    func testKilometresAloneAreWorthKeeping() {
        XCTAssertFalse(SiteDay(siteID: site.id, date: Fixture.date(2026, 8, 4), kilometres: 12).isBlank)
    }

    func testASiteDayRoundTripsAndOneWrittenBeforeHasNone() throws {
        let original = day(present: [ana, you], allowance: [ana], km: 84)
        XCTAssertEqual(try JSONDecoder().decode(SiteDay.self, from: JSONEncoder().encode(original)), original)

        let plain = day(present: [ana])
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        XCTAssertFalse(json.contains("allowance"), "a day without them is written as before")
        XCTAssertFalse(json.contains("kilometres"))

        let old = try JSONDecoder().decode(SiteDay.self, from: Data(#"{"date": 20260804, "breakMinutes": 0, "note": ""}"#.utf8))
        XCTAssertEqual(old.allowanceMemberIDs, [])
        XCTAssertEqual(old.kilometres, 0)
    }

    func testTheCalculatorSaysWhoHadTheAllowance() {
        let result = SiteDayCalculator(settings: Fixture.settings(), calendar: calendar)
            .compute(day(present: [ana, ivo], allowance: [ivo]))
        XCTAssertEqual(result.people.first { $0.memberID == ana }?.hasAllowance, false)
        XCTAssertEqual(result.people.first { $0.memberID == ivo }?.hasAllowance, true)
    }

    // MARK: - Your own day

    private var tracking: AppSettings {
        var settings = Fixture.settings()
        settings.allowance = AllowancePreferences(isEnabled: true, dailyAllowanceCents: 25_00, centsPerKilometre: 30)
        return settings
    }

    func testYourAllowanceAndTheKilometresReachYourDay() throws {
        let siteDay = day(present: [you, ana], allowance: [you], km: 84)
        let record = try XCTUnwrap(SiteCalendarSync.merged(personal: nil, siteDays: [siteDay], on: siteDay.date))
        XCTAssertFalse(record.hasFieldAllowance, "the site does not write your own say")
        XCTAssertEqual(record.kilometres, 0)
        XCTAssertEqual(record.shifts.first?.fieldAllowance, true)
        XCTAssertEqual(record.shifts.first?.kilometres, 84)

        let computed = Fixture.calculator(settings: tracking).compute(record: record, on: siteDay.date)
        XCTAssertTrue(computed.hasFieldAllowance)
        XCTAssertEqual(computed.kilometres, 84)
    }

    func testNothingReachesYourDayWhenYouWereNotThere() {
        let siteDay = day(present: [ana], allowance: [ana], km: 84)
        XCTAssertNil(SiteCalendarSync.merged(personal: nil, siteDays: [siteDay], on: siteDay.date))
    }

    func testWhatYouWroteYourselfIsNeverOverwritten() throws {
        let yours = DayRecord(date: Fixture.date(2026, 8, 4), hasFieldAllowance: true, kilometres: 20, travelMinutes: 45)
        let withAllowance = day(present: [you], allowance: [you], km: 84)
        let merged = try XCTUnwrap(SiteCalendarSync.merged(personal: yours, siteDays: [withAllowance], on: yours.date))
        XCTAssertTrue(merged.hasFieldAllowance)
        XCTAssertEqual(merged.kilometres, 20)
        XCTAssertEqual(merged.travelMinutes, 45)

        // The site takes its allowance back: yours stays.
        let without = withAllowance.settingAllowance(false, for: you)
        let again = try XCTUnwrap(SiteCalendarSync.merged(personal: merged, siteDays: [without], on: yours.date))
        XCTAssertTrue(again.hasFieldAllowance)
        XCTAssertEqual(again.shifts.first?.fieldAllowance, false)

        // Your kilometres and the van's are separate drives, and add up.
        let computed = Fixture.calculator(settings: tracking).compute(record: again, on: yours.date)
        XCTAssertEqual(computed.kilometres, 104)
    }

    func testTwoSitesWithTheAllowanceAreOneAllowanceDay() throws {
        let other = Site(name: "Bau Süd")
        let first = day(present: [you], allowance: [you], km: 30)
        var second = day(present: [you], allowance: [you], km: 12, start: Fixture.time(16), end: Fixture.time(18))
        second.siteID = other.id
        let record = try XCTUnwrap(SiteCalendarSync.merged(personal: nil, siteDays: [first, second], on: first.date))
        let computed = Fixture.calculator(settings: tracking).compute(record: record, on: first.date)
        XCTAssertTrue(computed.hasFieldAllowance)
        XCTAssertEqual(computed.kilometres, 42)
        let summary = AllowanceSummary(days: [computed], settings: tracking)
        XCTAssertEqual(summary.allowanceDays, 1)
        XCTAssertEqual(summary.allowanceCents, 25_00)
    }

    func testAFullStopWithTheAllowanceStillTypesYourDayAndKeepsTheAllowance() throws {
        let stopped = day(present: [you], allowance: [you], km: 40).stoppedForBadWeather(at: nil)
        let record = try XCTUnwrap(SiteCalendarSync.merged(personal: nil, siteDays: [stopped], on: stopped.date))
        XCTAssertEqual(record.dayTypeID, .badWeather)
        XCTAssertEqual(record.shifts.count, 1, "kept for what it carries, though it has no hours")
        XCTAssertTrue(Fixture.calculator(settings: tracking).compute(record: record, on: stopped.date).hasFieldAllowance)
    }

    func testMergingAgainChangesNothing() throws {
        let siteDay = day(present: [you], allowance: [you], km: 84)
        let once = try XCTUnwrap(SiteCalendarSync.merged(personal: nil, siteDays: [siteDay], on: siteDay.date))
        XCTAssertEqual(SiteCalendarSync.merged(personal: once, siteDays: [siteDay], on: siteDay.date), once)
    }

    // MARK: - The site sheet

    private func sheet(_ days: [SiteDay], language: ExportLanguage = .english, tracking: Bool = true) -> ReportTable {
        var settings = Fixture.settings(export: ExportPreferences(language: language, ownerName: "Marijo"))
        settings.allowance.isEnabled = tracking
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let crew = [CrewMember(id: ana, siteID: site.id, name: "Ana", sortOrder: 0),
                    CrewMember(id: ivo, siteID: site.id, name: "Ivo", sortOrder: 1)]
        return SiteSheetBuilder(settings: settings, calendar: calendar)
            .makeTable(site: site, crew: crew, results: days.map(calculator.compute), range: august)
    }

    func testTheSheetCountsEachPersonsAllowanceDaysAndTheKilometres() throws {
        let table = sheet([
            day(3, present: [you, ana, ivo], allowance: [you, ana], km: 84),
            day(4, present: [you, ana, ivo], allowance: [ana], km: 16),
            day(5, present: [ana, ivo])
        ])
        let allowance = try XCTUnwrap(table.rows.first { $0.values.first == "Allowance days" })
        // Date, day, then you, Ana and Ivo — two columns each — then notes.
        XCTAssertEqual(allowance.values, ["Allowance days", "", "", "1", "", "2", "", "", ""])
        XCTAssertEqual(allowance.role, .count)
        let km = try XCTUnwrap(table.rows.first { $0.values.first == "Kilometres" })
        XCTAssertEqual(km.values.last, "100 km")
        XCTAssertEqual(table.trailingSummaryRows, 4)
        XCTAssertEqual(table.rows.suffix(4).map { $0.values.first }, ["Month total", "Days worked", "Allowance days", "Kilometres"])
    }

    func testNoAllowanceAndNoKilometresAddNoLines() {
        let table = sheet([day(3, present: [you, ana])])
        XCTAssertEqual(table.trailingSummaryRows, 2)
        XCTAssertFalse(table.rows.contains { $0.values.first == "Allowance days" })
        XCTAssertFalse(table.rows.contains { $0.values.first == "Kilometres" })
    }

    func testNotTrackedTheSheetIsAsBefore() {
        let table = sheet([day(3, present: [ana], allowance: [ana], km: 50)], tracking: false)
        XCTAssertEqual(table.trailingSummaryRows, 2)
    }

    func testTheSheetInGerman() {
        let table = sheet([day(3, present: [ana], allowance: [ana], km: 50)], language: .german)
        XCTAssertTrue(table.rows.contains { $0.values.first == "Auslösetage" })
        XCTAssertTrue(table.rows.contains { $0.values.first == "Kilometer" && $0.values.last == "50 km" })
    }

    func testTheSheetInCroatian() {
        let table = sheet([day(3, present: [ana], allowance: [ana], km: 50)], language: .croatian)
        XCTAssertTrue(table.rows.contains { $0.values.first == "Dani terenskog dodatka" })
        XCTAssertTrue(table.rows.contains { $0.values.first == "Kilometri" && $0.values.last == "50 km" })
    }

    func testASplitSheetKeepsTheKilometresOnEveryPartAndAllowanceOnlyWhereSomeoneHadIt() {
        let table = sheet([day(3, present: [you, ana, ivo], allowance: [ivo], km: 70)])
        let parts = SiteSheetBuilder.split(table, peoplePerPage: 2)
        XCTAssertEqual(parts.count, 2)
        // You and Ana first: nobody there had the allowance.
        XCTAssertFalse(parts[0].rows.contains { $0.values.first == "Allowance days" })
        XCTAssertTrue(parts[1].rows.contains { $0.values.first == "Allowance days" })
        for part in parts {
            XCTAssertTrue(part.rows.contains { $0.values.first == "Kilometres" && $0.values.last == "70 km" })
        }
    }

    func testTheSheetNeverCarriesMoney() {
        let table = sheet([day(3, present: [ana], allowance: [ana], km: 50)])
        let text = table.rows.flatMap(\.values).joined(separator: " ")
        XCTAssertFalse(text.contains("€"))
        XCTAssertFalse(table.columns.contains(.earnings))
    }
}
