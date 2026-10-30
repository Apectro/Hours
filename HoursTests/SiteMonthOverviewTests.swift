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

    func testOnlyPeopleOnTheMonthsDaysCount() {
        let day = SiteDay(siteID: site, date: d(1), present: [Attendance(memberID: ana)])
        let crew = SiteMonthOverview.crew(siteID: site, visible: [ana, ivo], siteDays: [day], month: october, calendar: Fixture.calendar())
        XCTAssertEqual(crew, [ana], "Ivo, added later, does not make older days partly")
    }

    func testSomeoneAwayForAReasonIsOnTheMonth() {
        let day = SiteDay(siteID: site, date: d(1), present: [Attendance(memberID: ana)]).settingAbsence(.sick, for: ivo)
        let crew = SiteMonthOverview.crew(siteID: site, visible: [ana, ivo], siteDays: [day], month: october, calendar: Fixture.calendar())
        XCTAssertEqual(crew, [ana, ivo])
    }

    func testYouCountWhenYouAreOnADayAndHiddenPeopleNever() {
        let hidden = UUID()
        let day = SiteDay(
            siteID: site,
            date: d(1),
            present: [Attendance(memberID: CrewMember.youID), Attendance(memberID: hidden)]
        )
        let crew = SiteMonthOverview.crew(siteID: site, visible: [ana], siteDays: [day], month: october, calendar: Fixture.calendar())
        XCTAssertEqual(crew, [CrewMember.youID])
    }

    func testOtherSitesAndOtherMonthsDoNotCount() {
        let elsewhere = SiteDay(siteID: UUID(), date: d(1), present: [Attendance(memberID: ana)])
        let september = SiteDay(siteID: site, date: Fixture.date(2026, 9, 30), present: [Attendance(memberID: ivo)])
        let crew = SiteMonthOverview.crew(
            siteID: site, visible: [ana, ivo], siteDays: [elsewhere, september], month: october, calendar: Fixture.calendar()
        )
        XCTAssertEqual(crew, [])
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
