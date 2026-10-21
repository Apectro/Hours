import XCTest
@testable import Hours

/// "Add from other sites": the people on your other crews, offered once each.
final class CrewCandidatesTests: XCTestCase {
    private let here = UUID()
    private let other = UUID()
    private let archived = UUID()

    private func member(_ name: String, on site: UUID, hidden: Bool = false) -> CrewMember {
        CrewMember(siteID: site, name: name, isHidden: hidden)
    }

    private func day(_ date: CalendarDate, on site: UUID, _ members: [CrewMember]) -> SiteDay {
        SiteDay(siteID: site, date: date, present: members.map { Attendance(memberID: $0.id) })
    }

    private func names(crew: [CrewMember], days: [SiteDay] = []) -> [String] {
        CrewCandidates.candidates(for: here, crew: crew, siteDays: days).map(\.name)
    }

    func testPeopleOnOtherSitesAreOffered() {
        XCTAssertEqual(names(crew: [member("Ivan", on: other), member("Marko", on: archived)]), ["Ivan", "Marko"])
    }

    func testTheSameNameOnTwoSitesIsOfferedOnce() {
        let crew = [member("Ivan Horvat", on: other), member("ivan  horvat ", on: archived)]

        XCTAssertEqual(names(crew: crew).count, 1)
    }

    func testCaseAndDiacriticsDoNotMakeTwoPeople() {
        let crew = [member("Čedo", on: other), member("cedo", on: archived)]

        XCTAssertEqual(names(crew: crew).count, 1)
    }

    /// Someone hidden here is still on this crew; bringing them back is the
    /// crew screen's Show, not a second copy of them.
    func testNamesAlreadyHereAreLeftOutHiddenOrNot() {
        let crew = [
            member("Ivan", on: here),
            member("Marko", on: here, hidden: true),
            member("IVAN", on: other),
            member("Marko", on: other),
            member("Ante", on: other),
        ]

        XCTAssertEqual(names(crew: crew), ["Ante"])
    }

    func testBlankNamesAreNotOffered() {
        XCTAssertEqual(names(crew: [member("  ", on: other)]), [])
    }

    func testMostRecentlyWorkedWithFirstThenByName() {
        let zoran = member("Zoran", on: other)
        let ante = member("Ante", on: other)
        let boris = member("Boris", on: other)
        let mate = member("Mate", on: archived)
        let days = [
            day(Fixture.date(2026, 9, 1), on: other, [ante]),
            day(Fixture.date(2026, 10, 2), on: other, [zoran, ante]),
            day(Fixture.date(2026, 3, 1), on: archived, [mate]),
        ]

        // Zoran and Ante last worked on the 2nd of October; Mate in March;
        // Boris never.
        XCTAssertEqual(names(crew: [boris, mate, zoran, ante], days: days), ["Ante", "Zoran", "Mate", "Boris"])
    }

    func testTheLastWorkedDateCountsEveryCopyOfAName() {
        let old = member("Ivan", on: archived)
        let recent = member("ivan", on: other)
        let mate = member("Mate", on: other)
        let days = [
            day(Fixture.date(2025, 5, 1), on: archived, [old]),
            day(Fixture.date(2026, 6, 1), on: other, [mate]),
            day(Fixture.date(2026, 10, 1), on: other, [recent]),
        ]

        let result = CrewCandidates.candidates(for: here, crew: [old, mate, recent], siteDays: days)

        XCTAssertEqual(result.map(\.name), ["ivan", "Mate"])
        XCTAssertEqual(result.first?.lastWorked, Fixture.date(2026, 10, 1))
    }

    /// The spelling offered is the one from the most recent crew, which is
    /// the one most likely to be how the name is written now.
    func testTheMostRecentSpellingIsOffered() {
        let old = member("Đuro", on: archived)
        let recent = member("Djuro", on: other)
        let newer = member("đuro", on: other)
        let days = [
            day(Fixture.date(2025, 5, 1), on: archived, [old]),
            day(Fixture.date(2026, 10, 1), on: other, [newer]),
        ]

        XCTAssertEqual(names(crew: [old, recent, newer], days: days), ["đuro", "Djuro"])
    }

    func testAMemberMadeFromACandidateBelongsToThisSiteOnly() {
        let candidate = CrewCandidates.candidates(for: here, crew: [member("Ivan", on: other)], siteDays: [])[0]

        let added = candidate.member(on: here, sortOrder: 4)

        XCTAssertEqual(added.siteID, here)
        XCTAssertEqual(added.name, "Ivan")
        XCTAssertEqual(added.sortOrder, 4)
        XCTAssertFalse(added.isHidden)
    }
}
