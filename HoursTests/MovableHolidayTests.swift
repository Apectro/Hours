import XCTest
@testable import Hours

/// The holidays that move: Easter and the feasts counted from it, the
/// "weekday on or after a date" kind (Buß- und Bettag, the Swiss Bettag
/// Monday, the Geneva fast) and a date that steps off a Sunday (King's Day).
/// And, because 1.0 is still out there, how each of them is written down.
final class MovableHolidayTests: XCTestCase {
    private let calendar = Fixture.calendar()

    // MARK: - Easter computus

    func testEasterSundayMatchesKnownDates() {
        let known: [(Int, Int, Int)] = [
            (2000, 4, 23), (2008, 3, 23), (2011, 4, 24), (2019, 4, 21), (2024, 3, 31),
            (2025, 4, 20), (2026, 4, 5), (2027, 3, 28), (2028, 4, 16), (2029, 4, 1),
            (2030, 4, 21), (2038, 4, 25), (2285, 3, 22),
        ]
        for (year, month, day) in known {
            XCTAssertEqual(HolidayRecurrence.easterSunday(inYear: year), Fixture.date(year, month, day), "\(year)")
        }
    }

    func testEveryEasterOffsetHolidayIn2026() {
        let expected: [(Int, Int, Int)] = [
            (-2, 4, 3),   // Good Friday
            (0, 4, 5),    // Easter Sunday
            (1, 4, 6),    // Easter Monday
            (39, 5, 14),  // Ascension
            (49, 5, 24),  // Whit Sunday
            (50, 5, 25),  // Whit Monday
            (60, 6, 4),   // Corpus Christi
        ]
        for (offset, month, day) in expected {
            XCTAssertEqual(
                HolidayRecurrence.easter(offset: offset).occurrence(inYear: 2026, calendar: calendar),
                Fixture.date(2026, month, day),
                "offset \(offset)"
            )
        }
    }

    func testAnEasterRuleHonoursItsYearBounds() {
        var recurrence = HolidayRecurrence.easter(offset: 1)
        recurrence.startYear = 2027
        XCTAssertNil(recurrence.occurrence(inYear: 2026, calendar: calendar))
        XCTAssertEqual(recurrence.occurrence(inYear: 2027, calendar: calendar), Fixture.date(2027, 3, 29))
    }

    // MARK: - Weekday on or after a date

    func testBussUndBettagIsTheWednesdayBefore23November() {
        let recurrence = HolidayRecurrence.weekdayOnOrAfter(month: 11, day: 16, weekday: 4)
        XCTAssertEqual(recurrence.occurrence(inYear: 2026, calendar: calendar), Fixture.date(2026, 11, 18))
        XCTAssertEqual(recurrence.occurrence(inYear: 2025, calendar: calendar), Fixture.date(2025, 11, 19))
        XCTAssertEqual(recurrence.occurrence(inYear: 2027, calendar: calendar), Fixture.date(2027, 11, 17))
        // 16 November 2022 was itself a Wednesday.
        XCTAssertEqual(recurrence.occurrence(inYear: 2022, calendar: calendar), Fixture.date(2022, 11, 16))
    }

    func testTheSwissFastMondayFollowsTheThirdSundayOfSeptember() {
        let recurrence = HolidayRecurrence.weekdayOnOrAfter(month: 9, day: 16, weekday: 2)
        XCTAssertEqual(recurrence.occurrence(inYear: 2026, calendar: calendar), Fixture.date(2026, 9, 21))
        XCTAssertEqual(recurrence.occurrence(inYear: 2025, calendar: calendar), Fixture.date(2025, 9, 22))
    }

    func testTheGenevaFastIsTheThursdayAfterTheFirstSundayOfSeptember() {
        let recurrence = HolidayRecurrence.weekdayOnOrAfter(month: 9, day: 5, weekday: 5)
        XCTAssertEqual(recurrence.occurrence(inYear: 2026, calendar: calendar), Fixture.date(2026, 9, 10))
        XCTAssertEqual(recurrence.occurrence(inYear: 2025, calendar: calendar), Fixture.date(2025, 9, 11))
    }

    // MARK: - A date that steps off a Sunday

    func testKingsDayMovesToSaturdayWhenTheTwentySeventhIsASunday() {
        let recurrence = HolidayRecurrence.annualOffSunday(month: 4, day: 27, sundayOffset: -1)
        XCTAssertEqual(recurrence.occurrence(inYear: 2026, calendar: calendar), Fixture.date(2026, 4, 27))
        // 27 April 2025 was a Sunday.
        XCTAssertEqual(recurrence.occurrence(inYear: 2025, calendar: calendar), Fixture.date(2025, 4, 26))
    }

    // MARK: - Writing them down

    func testMovableRulesRoundTripThroughJSON() throws {
        let rules: [HolidayRecurrence] = [
            .easter(offset: -2),
            .weekdayOnOrAfter(month: 11, day: 16, weekday: 4),
            .annualOffSunday(month: 4, day: 27, sundayOffset: -1),
            .annual(month: 12, day: 25),
            .nthWeekday(ordinal: -1, weekday: 2, month: 5),
            .once(on: Fixture.date(2026, 3, 3)),
        ]
        for recurrence in rules {
            let data = try JSONEncoder().encode(recurrence)
            XCTAssertEqual(try JSONDecoder().decode(HolidayRecurrence.self, from: data), recurrence)
        }
    }

    /// 1.0 decodes `kind` strictly, so a kind it has never heard of would fail
    /// the list of holidays and, with it, the whole restore. What it reads
    /// instead is an annual 31 February: a rule that never occurs, so the
    /// older app shows the holiday without a date rather than on a wrong one.
    func testA10AppReadsAMovableRuleAsOneThatNeverOccurs() throws {
        let data = try JSONEncoder().encode(HolidayRecurrence.easter(offset: 39))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["kind"] as? String, "annual")
        XCTAssertEqual(object["month"] as? Int, 2)
        XCTAssertEqual(object["day"] as? Int, 31)
        for key in ["year", "weekday", "ordinal"] {
            XCTAssertNotNil(object[key] as? Int, "1.0 requires \(key)")
        }

        let asOld = try JSONDecoder().decode(OneZeroRecurrence.self, from: data)
        XCTAssertEqual(asOld.kind, "annual")
        XCTAssertNil(
            HolidayRecurrence.annual(month: asOld.month, day: asOld.day).occurrence(inYear: 2026, calendar: calendar)
        )
    }

    func testAnOldBackupRuleDecodesUnchanged() throws {
        let json = #"{"kind":"nthWeekday","year":2000,"month":11,"day":1,"weekday":5,"ordinal":4}"#
        let decoded = try JSONDecoder().decode(HolidayRecurrence.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, .nthWeekday(ordinal: 4, weekday: 5, month: 11))
    }

    func testAKindFromTheFutureDecodesAsARuleThatNeverOccurs() throws {
        let json = #"{"kind":"lunar","year":2000,"month":3,"day":4,"weekday":2,"ordinal":1}"#
        let decoded = try JSONDecoder().decode(HolidayRecurrence.self, from: Data(json.utf8))
        XCTAssertNil(decoded.occurrence(inYear: 2026, calendar: calendar))
    }

    /// The store keeps the kind as a string, and 1.0 reads a string it does
    /// not know as `annual` on the stored month and day — so a movable rule
    /// stores 31 February there too, and its real shape in the string.
    func testMovableRulesRoundTripThroughTheStoredColumns() {
        let rules: [HolidayRecurrence] = [
            .easter(offset: 60),
            .weekdayOnOrAfter(month: 9, day: 5, weekday: 5),
            .annualOffSunday(month: 4, day: 27, sundayOffset: -1),
            .annual(month: 5, day: 1),
            .once(on: Fixture.date(2026, 3, 3)),
        ]
        for recurrence in rules {
            let stored = recurrence.storedColumns
            XCTAssertEqual(HolidayRecurrence(stored: stored), recurrence)
            if recurrence.kind.isMovable {
                XCTAssertNil(HolidayRecurrence.Kind(rawValue: stored.kindRawValue), "1.0 must not recognise it")
                XCTAssertEqual(stored.month, 2)
                XCTAssertEqual(stored.day, 31)
            } else {
                XCTAssertEqual(stored.kindRawValue, recurrence.kind.rawValue)
            }
        }
    }

    func testAnUnknownStoredKindReadsAsAnnualAsBefore() {
        var stored = HolidayRecurrence.annual(month: 5, day: 1).storedColumns
        stored.kindRawValue = "nonsense"
        XCTAssertEqual(HolidayRecurrence(stored: stored).kind, .annual)
    }
}

/// What 1.0's synthesised decoder demands of a recurrence.
private struct OneZeroRecurrence: Decodable {
    var kind: String
    var year: Int
    var month: Int
    var day: Int
    var weekday: Int
    var ordinal: Int
    var startYear: Int?
    var endYear: Int?
}
