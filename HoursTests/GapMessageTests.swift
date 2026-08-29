import XCTest
@testable import Hours

/// What the gap reminder actually says, now that it says it in ten languages.
///
/// These four moved here from `GapReminderTests` when the sentence moved out
/// of the engine. They cannot stay on the Linux job: `GapMessage` lives in the
/// app target because it needs the localisation APIs, and asserting an exact
/// English sentence is the wrong assertion for a string that is supposed to
/// change with the phone.
///
/// So the structure is asserted instead — a date is named, a count is present,
/// nothing is left unsubstituted — plus one test that the German is genuinely
/// different, which is the claim the whole exercise rests on.
///
/// Excluded from the Linux job in `Package.swift`.
final class GapMessageTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// en_GB by name, so the dates in the assertions come from the same
    /// formatter the message uses rather than from the test host's locale.
    private var formatting: CalendarFormatting {
        CalendarFormatting(locale: Locale(identifier: "en_GB"), calendar: calendar)
    }

    func testNothingMissingMeansNoNotification() {
        XCTAssertNil(GapMessage.text(for: [], formatting: formatting))
    }

    /// The dates are compared through the formatter rather than spelled out.
    /// How a locale abbreviates a date is Foundation's business, and the two
    /// platforms this suite has run on disagree: Apple's en_GB gives
    /// "Mon 3 Aug", Linux's gives "Mon, 3 Aug".
    func testOneMissingDayIsNamed() throws {
        let day = Fixture.workingMonday
        let message = try XCTUnwrap(GapMessage.text(for: [day], formatting: formatting))

        XCTAssertTrue(
            message.contains(formatting.mediumDate(day)),
            "the day is not named in \(message)"
        )
        XCTAssertFalse(message.contains("%"), "an argument was never substituted: \(message)")
    }

    func testTwoMissingDaysAreBothNamed() throws {
        let first = Fixture.workingMonday
        let second = Fixture.workingTuesday
        let message = try XCTUnwrap(GapMessage.text(for: [first, second], formatting: formatting))

        XCTAssertNotEqual(
            formatting.mediumDate(first),
            formatting.mediumDate(second),
            "both days have to be named, so they must be distinguishable"
        )
        XCTAssertTrue(message.contains(formatting.mediumDate(first)), message)
        XCTAssertTrue(message.contains(formatting.mediumDate(second)), message)
    }

    /// Four days: the count, and only the first date. Naming all four makes a
    /// notification nobody reads to the end of.
    func testManyMissingDaysAreCounted() throws {
        let dates = [3, 4, 5, 6].map { Fixture.date(2026, 8, $0) }
        let message = try XCTUnwrap(GapMessage.text(for: dates, formatting: formatting))

        XCTAssertTrue(message.contains("4"), "the count is missing from \(message)")
        XCTAssertTrue(message.contains(formatting.mediumDate(dates[0])), message)
        XCTAssertFalse(
            message.contains(formatting.mediumDate(dates[3])),
            "the last day should not be named: \(message)"
        )
        XCTAssertFalse(message.contains("^["), "inflection markup leaked: \(message)")
        XCTAssertFalse(message.contains("%"), "an argument was never substituted: \(message)")
    }

    /// The point of moving it. Every one of these sentences was a plain Swift
    /// literal in the engine, under a comment claiming they were "extracted
    /// from the app that calls it" — so a German phone was notified in
    /// English, and nothing said so.
    ///
    /// Asserted against the compiled bundle, because the generator writing a
    /// key and the app shipping it are two different claims.
    func testTheSentencesAreInGerman() throws {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: "de", ofType: "lproj"),
            "the app has no de.lproj — the catalogue did not compile"
        )
        let german = try XCTUnwrap(Bundle(path: path))
        let absent = "<<absent>>"

        for key in [
            "%@ has no hours recorded.",
            "%@ and %@ have no hours recorded.",
            "%@ have no hours recorded, starting %@.",
        ] {
            let value = german.localizedString(forKey: key, value: absent, table: nil)
            XCTAssertNotEqual(value, absent, "German has no \(key)")
            XCTAssertNotEqual(value, key, "German still says the English for \(key)")
            XCTAssertEqual(
                value.components(separatedBy: "%@").count,
                key.components(separatedBy: "%@").count,
                "German changed the number of placeholders in \(key)"
            )
        }
    }
}
