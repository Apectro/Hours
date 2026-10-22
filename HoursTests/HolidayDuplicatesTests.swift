import XCTest
@testable import Hours

/// Holidays two devices made separately, before they synced.
///
/// Every other synced record has a natural key both devices agree on — a date,
/// a site and a date, a person and a month — or an id only one device ever
/// creates. A holiday rule's id is made wherever the rule is made, so the
/// same "Christmas Day" added on the phone and on the iPad, or the same
/// country's list added on both, arrives as two rules with two ids. These
/// say which of them go.
final class HolidayDuplicatesTests: XCTestCase {
    private let early = Date(timeIntervalSince1970: 1_000)
    private let late = Date(timeIntervalSince1970: 2_000)

    private func stored(
        _ name: String,
        _ recurrence: HolidayRecurrence,
        id: String,
        created: Date,
        working: Bool = false,
        enabled: Bool = true,
        notes: String = ""
    ) -> HolidayDuplicates.Stored {
        HolidayDuplicates.Stored(
            rule: HolidayRule(
                id: UUID(uuidString: id)!, name: name, recurrence: recurrence,
                countsAsWorkingDay: working, isEnabled: enabled, notes: notes
            ),
            createdAt: created
        )
    }

    private let idA = "AAAAAAAA-0000-0000-0000-000000000001"
    private let idB = "BBBBBBBB-0000-0000-0000-000000000002"
    private let idC = "CCCCCCCC-0000-0000-0000-000000000003"

    func testTheSameHolidayMadeOnTwoDevicesKeepsTheOlderRule() {
        let phone = stored("Christmas Day", .annual(month: 12, day: 25), id: idB, created: early)
        let iPad = stored("Christmas Day", .annual(month: 12, day: 25), id: idA, created: late)
        XCTAssertEqual(HolidayDuplicates.redundant([phone, iPad]), [UUID(uuidString: idA)!])
        XCTAssertEqual(HolidayDuplicates.redundant([iPad, phone]), [UUID(uuidString: idA)!], "the order they arrived in does not decide it")
    }

    func testTheNameMatchesWhateverItsCaseAndSurroundingSpaces() {
        let one = stored("Christmas Day", .annual(month: 12, day: 25), id: idA, created: early)
        let two = stored(" christmas day ", .annual(month: 12, day: 25), id: idB, created: late)
        XCTAssertEqual(HolidayDuplicates.redundant([one, two]), [UUID(uuidString: idB)!])
    }

    func testATieOnCreationIsBrokenByTheIdWhichEveryDeviceSees() {
        // Unlike a day, a holiday's tie can be broken safely: its id travels
        // with it, so both devices pick the same survivor and neither
        // deletes the rule the other kept.
        let one = stored("Easter Monday", .easter(offset: 1), id: idB, created: early)
        let two = stored("Easter Monday", .easter(offset: 1), id: idA, created: early)
        XCTAssertEqual(HolidayDuplicates.redundant([one, two]), [UUID(uuidString: idB)!])
        XCTAssertEqual(HolidayDuplicates.redundant([two, one]), [UUID(uuidString: idB)!])
    }

    func testThreeCopiesLeaveOne() {
        let rules = [
            stored("Labour Day", .annual(month: 5, day: 1), id: idC, created: late),
            stored("Labour Day", .annual(month: 5, day: 1), id: idA, created: early),
            stored("Labour Day", .annual(month: 5, day: 1), id: idB, created: late),
        ]
        XCTAssertEqual(HolidayDuplicates.redundant(rules), [UUID(uuidString: idB)!, UUID(uuidString: idC)!])
    }

    // MARK: - What is not a duplicate

    func testADifferentDateIsADifferentHoliday() {
        let rules = [
            stored("Holiday", .annual(month: 12, day: 25), id: idA, created: early),
            stored("Holiday", .annual(month: 12, day: 26), id: idB, created: late),
        ]
        XCTAssertEqual(HolidayDuplicates.redundant(rules), [])
    }

    func testADifferentNameOnTheSameDateIsKept() {
        // "Christtag" from a German phone and "Christmas Day" from an English
        // one fall on the same day and say the same thing to the calendar,
        // but which name the person wants is theirs to choose.
        let rules = [
            stored("Christtag", .annual(month: 12, day: 25), id: idA, created: early),
            stored("Christmas Day", .annual(month: 12, day: 25), id: idB, created: late),
        ]
        XCTAssertEqual(HolidayDuplicates.redundant(rules), [])
    }

    func testRulesThatDisagreeAboutTheDayAreBothKept() {
        let base = stored("Carnival", .annual(month: 2, day: 17), id: idA, created: early)
        for other in [
            stored("Carnival", .annual(month: 2, day: 17), id: idB, created: late, working: true),
            stored("Carnival", .annual(month: 2, day: 17), id: idB, created: late, enabled: false),
            stored("Carnival", .annual(month: 2, day: 17), id: idB, created: late, notes: "afternoon only"),
        ] {
            XCTAssertEqual(HolidayDuplicates.redundant([base, other]), [], "\(other.rule)")
        }
    }

    func testTheSameRowTwiceIsLeftToTheIdCollapse() {
        // Two rows with one id are one rule stored twice, which
        // `collapseDuplicates` already handles; this must not delete the id
        // both rows share.
        let one = stored("Christmas Day", .annual(month: 12, day: 25), id: idA, created: early)
        let two = stored("Christmas Day", .annual(month: 12, day: 25), id: idA, created: late)
        XCTAssertEqual(HolidayDuplicates.redundant([one, two]), [])
    }

    func testACountrysListAddedOnBothDevicesCollapsesToOneList() throws {
        let austria = try XCTUnwrap(PublicHolidayCatalog.set(country: .at, region: nil))
        func add() -> [HolidayRule] {
            PublicHolidayImport.plan(
                set: austria, selection: austria.defaultSelection, existing: [],
                language: .german, calendar: Fixture.calendar(), fromYear: 2026
            ).rules
        }
        let phone = add()
        let iPad = add()
        XCTAssertEqual(phone.count, 13)
        XCTAssertEqual(iPad.count, 13)
        XCTAssertNotEqual(Set(phone.map(\.id)), Set(iPad.map(\.id)), "each device makes its own ids")

        let stored = phone.map { HolidayDuplicates.Stored(rule: $0, createdAt: early) }
            + iPad.map { HolidayDuplicates.Stored(rule: $0, createdAt: late) }
        XCTAssertEqual(HolidayDuplicates.redundant(stored), Set(iPad.map(\.id)))
    }
}
