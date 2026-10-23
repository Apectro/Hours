import XCTest
@testable import Hours

/// What a site's month cell says about people who were away that day.
final class SiteDayAwayTests: XCTestCase {
    private let siteID = UUID()
    private let ana = UUID()
    private let ivan = UUID()
    private let marko = UUID()

    private func day(present: [UUID] = [], away: [(UUID, AbsenceReason)] = []) -> SiteDay {
        var day = SiteDay(siteID: siteID, date: Fixture.workingTuesday, present: present.map { Attendance(memberID: $0) })
        for (id, reason) in away { day = day.settingReason(reason, for: id) }
        return day
    }

    func testNobodyAwayHasNoMark() {
        let full = day(present: [ana, ivan])
        XCTAssertEqual(full.awayCount, 0)
        XCTAssertNil(full.leadingAwayReason)
    }

    func testOnlyGivenReasonsCountAsAway() {
        // Ivan is neither ticked nor given a reason: maybe not on this crew
        // yet, so nothing is said about him.
        let partial = day(present: [ana], away: [(marko, .dayType(.vacation))])
        XCTAssertEqual(partial.awayCount, 1)
        XCTAssertEqual(partial.leadingAwayReason, .dayType(.vacation))
    }

    func testSickLeadsWhateverTheOrder() {
        let mixed = day(
            present: [ana],
            away: [(ivan, .otherSite(nil)), (marko, .dayType(.sick))]
        )
        XCTAssertEqual(mixed.awayCount, 2)
        XCTAssertEqual(mixed.leadingAwayReason, .dayType(.sick))
    }

    func testAnAbsenceLeadsAnotherSite() {
        let mixed = day(away: [(ivan, .otherSite(UUID())), (marko, .dayType(.dayOff))])
        XCTAssertEqual(mixed.leadingAwayReason, .dayType(.dayOff))
    }

    func testAnotherSiteAloneStillMarks() {
        let elsewhere = day(present: [ana], away: [(ivan, .otherSite(nil))])
        XCTAssertEqual(elsewhere.awayCount, 1)
        XCTAssertEqual(elsewhere.leadingAwayReason, .otherSite(nil))
    }

    func testAStrayReasonForSomeoneTickedIsIgnored() {
        var stray = day(present: [ana])
        stray.absences.append(CrewAbsence(memberID: ana, dayTypeID: .sick))
        XCTAssertEqual(stray.awayCount, 0)
        XCTAssertNil(stray.leadingAwayReason)
    }
}
