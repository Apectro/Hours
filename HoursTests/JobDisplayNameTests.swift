import XCTest
@testable import Hours

/// The first job is stored as "Work" in English; on screen and in exports it
/// takes the language's word, as the Work day type does, until it is renamed.
final class JobDisplayNameTests: XCTestCase {
    private let schedule = WorkSchedule()

    func testTheDefaultFirstJobIsTranslated() {
        let job = Job.primary(schedule: schedule)
        XCTAssertEqual(job.displayName(in: .croatian), "Rad")
        XCTAssertEqual(job.displayName(in: .german), "Arbeit")
        XCTAssertEqual(job.displayName(in: .english), "Work")
    }

    func testARenamedJobKeepsItsName() {
        var job = Job.primary(schedule: schedule)
        job.name = "Bau Süd"
        XCTAssertEqual(job.displayName(in: .croatian), "Bau Süd")
    }

    func testAnotherJobCalledWorkIsTheUsersOwn() {
        let job = Job(name: "Work", tint: .green, sortOrder: 1)
        XCTAssertEqual(job.displayName(in: .croatian), "Work")
    }
}
