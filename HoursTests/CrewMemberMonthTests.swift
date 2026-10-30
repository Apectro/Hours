import XCTest
@testable import Hours

/// One person's month on screen: three figures and a line a day, across
/// every site they were on.
final class CrewMemberMonthTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let october = CalendarDateRange(start: Fixture.date(2026, 10, 1), end: Fixture.date(2026, 10, 31))
    private let trg = Site(name: "Trg Pravde", sortOrder: 0)
    private let jarun = Site(name: "Jarunski", sortOrder: 1)
    private let ivan = UUID()
    private let ivanOnJarun = UUID()

    private var person: CrewSheetPerson {
        CrewSheetPerson(name: "Ivan", memberIDs: [ivan, ivanOnJarun], id: "member:ivan")
    }

    private func day(
        _ site: Site,
        _ d: Int,
        present: [Attendance] = [],
        start: TimeOfDay = Fixture.time(7),
        end: TimeOfDay = Fixture.time(16)
    ) -> SiteDay {
        SiteDay(siteID: site.id, date: Fixture.date(2026, 10, d), start: start, end: end, breakMinutes: 0, present: present)
    }

    private func month(_ days: [SiteDay], range: CalendarDateRange? = nil) -> CrewMemberMonth {
        let calculator = SiteDayCalculator(settings: Fixture.settings(), calendar: calendar)
        return CrewMemberMonth.make(person: person, sites: [jarun, trg], results: days.map(calculator.compute), range: range ?? october)
    }

    func testAWorkedDayHasItsSiteAndHours() {
        let result = month([day(trg, 5, present: [Attendance(memberID: ivan)])])

        XCTAssertEqual(result.days.count, 1)
        XCTAssertEqual(result.days[0].siteIDs, [trg.id])
        XCTAssertNil(result.days[0].reason)
        XCTAssertEqual(result.days[0].minutes, 9 * 60)
        XCTAssertEqual(result.totalMinutes, 9 * 60)
        XCTAssertEqual(result.daysWorked, 1)
        XCTAssertEqual(result.sickDays, 0)
    }

    func testTheNewestDayComesFirst() {
        let result = month([
            day(trg, 5, present: [Attendance(memberID: ivan)]),
            day(trg, 27, present: [Attendance(memberID: ivan)]),
            day(trg, 12, present: [Attendance(memberID: ivan)]),
        ])
        XCTAssertEqual(result.days.map(\.date.day), [27, 12, 5])
    }

    func testADaySplitBetweenTwoSitesIsOneLineInTheOrderWorked() {
        let morning = day(trg, 29, present: [Attendance(memberID: ivan)], start: Fixture.time(7), end: Fixture.time(11))
        let afternoon = day(jarun, 29, present: [Attendance(memberID: ivanOnJarun)], start: Fixture.time(12), end: Fixture.time(16))
        let result = month([afternoon, morning])

        XCTAssertEqual(result.days.count, 1)
        XCTAssertEqual(result.days[0].siteIDs, [trg.id, jarun.id])
        XCTAssertEqual(result.days[0].minutes, 8 * 60)
        XCTAssertEqual(result.daysWorked, 1)
        XCTAssertEqual(result.totalMinutes, 8 * 60)
    }

    func testSickDaysAreCountedAndHaveNoHours() {
        let sick = day(trg, 15).settingAbsence(.sick, for: ivan)
        let vacation = day(trg, 16).settingAbsence(.vacation, for: ivan)
        let result = month([sick, vacation])

        XCTAssertEqual(result.days.map(\.reason), [.dayType(.vacation), .dayType(.sick)])
        XCTAssertEqual(result.days.map(\.minutes), [0, 0])
        XCTAssertEqual(result.sickDays, 1)
        XCTAssertEqual(result.daysWorked, 0)
        XCTAssertTrue(result.days[1].isSick)
    }

    func testAReasonOnADayWorkedElsewhereSaysNothingNew() {
        let worked = day(jarun, 7, present: [Attendance(memberID: ivanOnJarun)])
        let away = day(trg, 7).settingAbsence(.sick, for: ivan)
        let result = month([away, worked])

        XCTAssertEqual(result.days.count, 1)
        XCTAssertNil(result.days[0].reason)
        XCTAssertEqual(result.sickDays, 0)
    }

    func testSomeoneElseAndDaysOutsideTheMonthAreLeftOut() {
        let other = day(trg, 5, present: [Attendance(memberID: UUID())])
        let september = SiteDay(
            siteID: trg.id, date: Fixture.date(2026, 9, 30), start: Fixture.time(7), end: Fixture.time(16),
            breakMinutes: 0, present: [Attendance(memberID: ivan)]
        )
        let result = month([other, september])
        XCTAssertTrue(result.days.isEmpty)
        XCTAssertEqual(result.totalMinutes, 0)
    }

    func testATwiceDeliveredDayCountsOnce() {
        let once = day(trg, 5, present: [Attendance(memberID: ivan)])
        let result = month([once, once])
        XCTAssertEqual(result.totalMinutes, 9 * 60)
        XCTAssertEqual(result.days.count, 1)
    }
}
