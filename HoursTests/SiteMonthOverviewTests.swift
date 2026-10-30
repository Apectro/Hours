import XCTest
@testable import Hours

/// What a site's card and its own page say about the month at a glance: how
/// many days are not written, the strip of work days, and who counts as the
/// crew a written day is checked against.
final class SiteMonthOverviewTests: XCTestCase {
    private let site = UUID()
    private let ana = UUID()
    private let ivo = UUID()
    private let october = YearMonth(year: 2026, month: 10)

    private func d(_ day: Int) -> CalendarDate { Fixture.date(2026, 10, day) }

    // MARK: - Headline

    func testMissingDaysLead() {
        let statuses: [CalendarDate: SiteDayStatus] = [d(1): .written, d(2): .missing, d(5): .missing, d(6): .future]
        XCTAssertEqual(SiteMonthOverview.headline(statuses), .notWritten(2))
    }

    func testEverythingWrittenSoFarIsAllWritten() {
        let statuses: [CalendarDate: SiteDayStatus] = [d(1): .written, d(2): .partly, d(3): .dayOff, d(30): .future]
        XCTAssertEqual(SiteMonthOverview.headline(statuses), .allWritten)
    }

    func testAMonthWithNothingWrittenAndNothingMissingIsNothingThisMonth() {
        let statuses: [CalendarDate: SiteDayStatus] = [d(1): .dayOff, d(2): .future]
        XCTAssertEqual(SiteMonthOverview.headline(statuses), .nothingThisMonth)
        XCTAssertEqual(SiteMonthOverview.headline([:]), .nothingThisMonth)
    }

    // MARK: - Strip

    func testTheStripHoldsTheWorkDaysInOrderAndLeavesDaysOffOut() {
        let statuses: [CalendarDate: SiteDayStatus] = [
            d(5): .missing, d(1): .written, d(3): .dayOff, d(2): .partly, d(30): .future,
        ]
        let strip = SiteMonthOverview.strip(statuses)
        XCTAssertEqual(strip.map(\.date), [d(1), d(2), d(5), d(30)])
        XCTAssertEqual(strip.map(\.status), [.written, .partly, .missing, .future])
    }

    // MARK: - Crew a day is checked against

    private func member(_ id: UUID, _ name: String, on siteID: UUID? = nil, hidden: Bool = false) -> CrewMember {
        CrewMember(id: id, siteID: siteID ?? site, name: name, isHidden: hidden)
    }

    private var anaAndIvo: [CrewMember] { [member(ana, "Ana"), member(ivo, "Ivo")] }

    private func check(_ members: [CrewMember], _ days: [SiteDay]) -> SiteCrewCheck {
        SiteMonthOverview.crew(siteID: site, members: members, siteDays: days, month: october, calendar: Fixture.calendar())
    }

    func testOnlyPeopleOnTheSitesDaysCount() {
        let day = SiteDay(siteID: site, date: d(1), present: [Attendance(memberID: ana)])
        XCTAssertEqual(check(anaAndIvo, [day]).expected(on: d(1)), [ana], "Ivo, never on a day here, is not checked")
    }

    func testSomeoneAwayForAReasonIsOnTheCrew() {
        let day = SiteDay(siteID: site, date: d(1), present: [Attendance(memberID: ana)]).settingAbsence(.sick, for: ivo)
        XCTAssertEqual(check(anaAndIvo, [day]).expected(on: d(1)), [ana, ivo])
    }

    func testYouCountWhenYouAreOnADayAndHiddenPeopleNever() {
        let hidden = UUID()
        let day = SiteDay(
            siteID: site,
            date: d(1),
            present: [Attendance(memberID: CrewMember.youID), Attendance(memberID: hidden)]
        )
        let members = [member(ana, "Ana"), member(hidden, "Hidden", hidden: true)]
        XCTAssertEqual(check(members, [day]).expected(on: d(1)), [CrewMember.youID])
    }

    func testOtherSitesDoNotPutSomeoneOnThisCrew() {
        let elsewhere = SiteDay(siteID: UUID(), date: d(1), present: [Attendance(memberID: ana)])
        XCTAssertEqual(check(anaAndIvo, [elsewhere]).expected(on: d(1)), [])
    }

    func testSomeoneCountsFromTheFirstDayTheyAppearOnHere() {
        let first = SiteDay(siteID: site, date: d(5), present: [Attendance(memberID: ana)])
        let joined = SiteDay(siteID: site, date: d(20), present: [Attendance(memberID: ana), Attendance(memberID: ivo)])
        let crew = check(anaAndIvo, [first, joined])

        XCTAssertEqual(crew.expected(on: d(5)), [ana], "Ivo joined on the 20th: the 5th is not partly for him")
        XCTAssertEqual(crew.expected(on: d(20)), [ana, ivo])
        XCTAssertEqual(crew.expected(on: d(21)), [ana, ivo])
        XCTAssertEqual(crew.joined[ivo], d(20))
    }

    func testADayBeforeTheMonthStillSetsTheJoinDate() {
        let september = SiteDay(siteID: site, date: Fixture.date(2026, 9, 28), present: [Attendance(memberID: ivo)])
        let october1 = SiteDay(siteID: site, date: d(1), present: [Attendance(memberID: ana)])
        XCTAssertEqual(check(anaAndIvo, [september, october1]).expected(on: d(1)), [ana, ivo])
    }

    func testBeingOnAnotherSiteFirstDoesNotMakeThisSitesEarlierDaysPartly() {
        // Ivo worked on Jarunski from the 1st and came here on the 20th.
        let jarunski = UUID()
        let ivoThere = UUID()
        let members = anaAndIvo + [member(ivoThere, "ivo ", on: jarunski)]
        let days = [
            SiteDay(siteID: jarunski, date: d(1), present: [Attendance(memberID: ivoThere)]),
            SiteDay(siteID: site, date: d(6), present: [Attendance(memberID: ana)]),
            SiteDay(siteID: site, date: d(20), present: [Attendance(memberID: ana), Attendance(memberID: ivo)]),
        ]
        XCTAssertEqual(check(members, days).expected(on: d(6)), [ana])
    }

    func testSomeoneTickedOnAnotherSiteThatDayIsAccountedFor() {
        // Mislav is on both crews; on the 6th he was at Jarunski.
        let jarunski = UUID()
        let mislav = UUID()
        let mislavThere = UUID()
        let members = anaAndIvo + [member(mislav, "Mislav Grbešić"), member(mislavThere, "mislav grbesic", on: jarunski)]
        let days = [
            SiteDay(siteID: site, date: d(5), present: [Attendance(memberID: ana), Attendance(memberID: mislav)]),
            SiteDay(siteID: site, date: d(6), present: [Attendance(memberID: ana)]),
            SiteDay(siteID: jarunski, date: d(6), present: [Attendance(memberID: mislavThere)]),
        ]
        let crew = check(members, days)

        XCTAssertEqual(crew.expected(on: d(5)), [ana, mislav])
        XCTAssertEqual(crew.expected(on: d(6)), [ana], "at Jarunski that day")
        XCTAssertEqual(crew.elsewhere[d(6)], [mislav])
    }

    func testYouOnAnotherSiteThatDayAreAccountedFor() {
        let jarunski = UUID()
        let days = [
            SiteDay(siteID: site, date: d(5), present: [Attendance(memberID: CrewMember.youID), Attendance(memberID: ana)]),
            SiteDay(siteID: site, date: d(6), present: [Attendance(memberID: ana)]),
            SiteDay(siteID: jarunski, date: d(6), present: [Attendance(memberID: CrewMember.youID)]),
        ]
        XCTAssertEqual(check([member(ana, "Ana")], days).expected(on: d(6)), [ana])
    }

    func testAReasonGivenOnAnotherSiteThatDayAccountsForThem() {
        let jarunski = UUID()
        let ivoThere = UUID()
        let members = anaAndIvo + [member(ivoThere, "Ivo", on: jarunski)]
        let days = [
            SiteDay(siteID: site, date: d(5), present: [Attendance(memberID: ana), Attendance(memberID: ivo)]),
            SiteDay(siteID: site, date: d(6), present: [Attendance(memberID: ana)]),
            SiteDay(siteID: jarunski, date: d(6)).settingAbsence(.sick, for: ivoThere),
        ]
        XCTAssertEqual(check(members, days).expected(on: d(6)), [ana], "sick is sick on every site")
    }

    func testANameOnAnotherSiteThatIsNotThereThatDayDoesNotAccountForThem() {
        let jarunski = UUID()
        let ivoThere = UUID()
        let members = anaAndIvo + [member(ivoThere, "Ivo", on: jarunski)]
        let days = [
            SiteDay(siteID: site, date: d(5), present: [Attendance(memberID: ana), Attendance(memberID: ivo)]),
            SiteDay(siteID: site, date: d(6), present: [Attendance(memberID: ana)]),
            SiteDay(siteID: jarunski, date: d(7), present: [Attendance(memberID: ivoThere)]),
        ]
        XCTAssertEqual(check(members, days).expected(on: d(6)), [ana, ivo])
    }

    func testAnEmptyNameNeverMatchesAcrossSites() {
        let jarunski = UUID()
        let blank = UUID()
        let blankThere = UUID()
        let members = [member(ana, "Ana"), member(blank, " "), member(blankThere, "", on: jarunski)]
        let days = [
            SiteDay(siteID: site, date: d(5), present: [Attendance(memberID: ana), Attendance(memberID: blank)]),
            SiteDay(siteID: site, date: d(6), present: [Attendance(memberID: ana)]),
            SiteDay(siteID: jarunski, date: d(6), present: [Attendance(memberID: blankThere)]),
        ]
        XCTAssertEqual(check(members, days).expected(on: d(6)), [ana, blank])
    }

    func testTheOwnersMonthReadsWrittenWhereTheCrewWasAccountedFor() {
        // Trg Pravde, like the owner's October: Mislav and Željko spend most
        // days at Jarunski, Dalibor joins on the 15th, and Ana is sick on the
        // 22nd on Jarunski's day. Every Trg Pravde day is written; none of
        // them should read partly.
        let jarunski = UUID()
        let mislav = UUID(), zeljko = UUID(), dalibor = UUID()
        let mislavThere = UUID(), zeljkoThere = UUID(), anaThere = UUID()
        let members = [
            member(ana, "Ana"), member(mislav, "Mislav"), member(zeljko, "Željko"), member(dalibor, "Dalibor"),
            member(mislavThere, "Mislav", on: jarunski), member(zeljkoThere, "Zeljko", on: jarunski),
            member(anaThere, "Ana", on: jarunski),
        ]
        var days = [
            SiteDay(siteID: site, date: d(1), present: [ana, mislav, zeljko].map { Attendance(memberID: $0) }),
        ]
        for day in [2, 5, 6, 7, 8, 9, 12, 13, 14, 15, 16, 19, 20, 21, 22] {
            var here = [CrewMember.youID]
            if day != 22 { here.append(ana) }
            if day >= 15 { here.append(dalibor) }
            days.append(SiteDay(siteID: site, date: d(day), present: here.map { Attendance(memberID: $0) }))
            var there = SiteDay(siteID: jarunski, date: d(day), present: [Attendance(memberID: mislavThere), Attendance(memberID: zeljkoThere)])
            if day == 22 { there = there.settingAbsence(.sick, for: anaThere) }
            days.append(there)
        }
        let statuses = SiteDayStatus.month(
            october,
            siteID: site,
            siteDays: days,
            setup: SiteSetup(workDays: [2, 3, 4, 5, 6]),
            check: check(members, days),
            today: d(23),
            calendar: Fixture.calendar()
        )
        XCTAssertFalse(statuses.values.contains(.partly))
        XCTAssertEqual(statuses[d(21)], .written)
        XCTAssertEqual(statuses[d(22)], .written)
    }

    // MARK: - Sign-off

    private func results(_ days: [SiteDay]) -> [SiteDayResult] {
        let calculator = SiteDayCalculator(settings: Fixture.settings(), calendar: Fixture.calendar())
        return days.map(calculator.compute)
    }

    private func written(_ day: Int, _ people: [UUID], end: Int = 16) -> SiteDay {
        SiteDay(
            siteID: site, date: d(day), start: Fixture.time(7), end: Fixture.time(end), breakMinutes: 0,
            present: people.map { Attendance(memberID: $0) }
        )
    }

    private func signature(_ member: UUID, for days: [SiteDay]) -> CrewSignature {
        CrewSignature(
            siteID: site, memberID: member, month: october, signedOn: d(31),
            fingerprint: SignatureFingerprint.make(memberID: member, results: results(days), month: october),
            strokes: [[SignaturePoint(x: 0, y: 0), SignaturePoint(x: 1, y: 1)]]
        )
    }

    func testNobodySignedIsNotYet() {
        let days = [written(5, [ana, ivo])]
        XCTAssertEqual(SiteMonthOverview.signOff(siteID: site, month: october, results: results(days), signatures: []), .notYet)
        XCTAssertEqual(SiteMonthOverview.signOff(siteID: site, month: october, results: [], signatures: []), .notYet)
    }

    func testSomeAndAllSigned() {
        let days = [written(5, [ana, ivo])]
        let some = SiteMonthOverview.signOff(
            siteID: site, month: october, results: results(days), signatures: [signature(ana, for: days)]
        )
        XCTAssertEqual(some, .partial(signed: 1, of: 2))
        let all = SiteMonthOverview.signOff(
            siteID: site, month: october, results: results(days),
            signatures: [signature(ana, for: days), signature(ivo, for: days)]
        )
        XCTAssertEqual(all, .all)
    }

    func testASignatureForHoursChangedSinceDoesNotCount() {
        let before = [written(5, [ana])]
        let after = [written(5, [ana], end: 15)]
        let progress = SiteMonthOverview.signOff(
            siteID: site, month: october, results: results(after), signatures: [signature(ana, for: before)]
        )
        XCTAssertEqual(progress, .notYet)
    }
}
