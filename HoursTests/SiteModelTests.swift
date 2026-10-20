import XCTest
@testable import Hours

/// The value types behind job sites (Baustelle).
final class SiteModelTests: XCTestCase {
    private let memberA = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!
    private let siteID = UUID(uuidString: "00000000-0000-4000-8000-0000000000C1")!

    func testSiteDayRoundTripsThroughJSON() throws {
        let day = SiteDay(
            siteID: siteID,
            date: CalendarDate(year: 2026, month: 10, day: 20),
            start: TimeOfDay(hour: 7, minute: 0),
            end: TimeOfDay(hour: 16, minute: 30),
            breakMinutes: 45,
            present: [
                Attendance(memberID: CrewMember.youID),
                Attendance(memberID: memberA, start: TimeOfDay(hour: 8, minute: 0), end: nil, breakMinutes: 30)
            ],
            note: "Rain after lunch",
            jobID: Job.primaryID
        )
        let decoded = try JSONDecoder().decode(SiteDay.self, from: JSONEncoder().encode(day))
        XCTAssertEqual(decoded, day)
    }

    func testOldPayloadWithoutNoteOrJobDecodesWithDefaults() throws {
        let json = """
        {"siteID":"\(siteID.uuidString)","date":20261020,"breakMinutes":30,"present":[]}
        """
        let decoded = try JSONDecoder().decode(SiteDay.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.note, "")
        XCTAssertNil(decoded.jobID)
        XCTAssertEqual(decoded.breakMinutes, 30)
        XCTAssertNil(decoded.start)
    }

    func testAttendanceWithNoOverridesHasNoException() {
        let day = SiteDay(
            siteID: siteID,
            date: CalendarDate(year: 2026, month: 10, day: 20),
            breakMinutes: 30,
            present: [
                Attendance(memberID: memberA),
                Attendance(memberID: CrewMember.youID, start: nil, end: TimeOfDay(hour: 15, minute: 0), breakMinutes: nil)
            ]
        )
        XCTAssertFalse(day.hasException(memberA))
        XCTAssertTrue(day.hasException(CrewMember.youID))
        XCTAssertFalse(day.hasException(UUID()), "Absent members have no exception")
        XCTAssertEqual(day.attendance(for: memberA)?.memberID, memberA)
        XCTAssertNil(day.attendance(for: UUID()))
    }

    func testBlankSiteDay() {
        let empty = SiteDay(siteID: UUID(), date: CalendarDate(year: 2026, month: 10, day: 20), breakMinutes: 30, note: "  ")
        XCTAssertTrue(empty.isBlank, "a break and whitespace alone are nothing to keep")

        var ticked = empty
        ticked.present = [Attendance(memberID: CrewMember.youID)]
        XCTAssertFalse(ticked.isBlank)

        var timed = empty
        timed.start = TimeOfDay(hour: 7, minute: 0)
        XCTAssertFalse(timed.isBlank)

        var noted = empty
        noted.note = "Rain, nobody came"
        XCTAssertFalse(noted.isBlank)
    }

    func testYouIDIsStable() {
        XCTAssertEqual(CrewMember.youID.uuidString, "00000000-0000-4000-8000-0000000000B1")
    }
}
