import XCTest
@testable import Hours

/// Whether `^[n day](inflect: true)` actually becomes "16 days" on screen.
///
/// The screenshots say it does not: the calendar reads
/// "^[16 day](inflect: true) worked" and Settings reads "40h over ^[5 day](infl…".
/// Fourteen call sites use this markup and nothing caught it, because the UI
/// tests assert on element identifiers rather than on rendered text.
///
/// These tests run in the app's own bundle — HoursTests is hosted by Hours, so
/// `Bundle.main` here is the app the screenshots came from.
final class InflectionTests: XCTestCase {
    /// The markup, if any of it survived into what the user reads.
    private func leaks(_ rendered: String) -> Bool {
        rendered.contains("^[") || rendered.contains("(inflect:")
    }

    /// Prints what each way of rendering the same markup produces, so the fix
    /// is chosen from evidence rather than from memory of Xcode's internals.
    ///
    /// Deliberately has no assertion: its output is the point. The assertions
    /// are the tests below it.
    func testWhatEachApproachActuallyRenders() {
        let count = 16

        let direct = String(localized: "^[\(count) day](inflect: true) worked")
        let attributed = String(
            AttributedString(localized: "^[\(count) day](inflect: true) worked").characters
        )

        print("----- inflection -----")
        print("String(localized:)      -> \(direct)")
        print("AttributedString        -> \(attributed)")
        print("bundle localizations    -> \(Bundle.main.localizations)")
        print("preferredLocalizations  -> \(Bundle.main.preferredLocalizations)")
        print("has en.lproj            -> \(Bundle.main.path(forResource: "en", ofType: "lproj") != nil)")
        print("----------------------")
    }

    func testTheCalendarSummaryDoesNotShowItsOwnMarkup() {
        let rendered = String(localized: "^[\(16) day](inflect: true) worked")
        XCTAssertFalse(leaks(rendered), "the calendar shows raw markup: \(rendered)")
        XCTAssertEqual(rendered, "16 days worked")
    }

    func testASingleDayReadsAsOneDay() {
        let rendered = String(localized: "^[\(1) day](inflect: true) worked")
        XCTAssertFalse(leaks(rendered), "the calendar shows raw markup: \(rendered)")
        XCTAssertEqual(rendered, "1 day worked")
    }

    func testTheScheduleSummaryDoesNotShowItsOwnMarkup() {
        let rendered = String(localized: "40h over ^[\(5) day](inflect: true)")
        XCTAssertFalse(leaks(rendered), "settings shows raw markup: \(rendered)")
        XCTAssertEqual(rendered, "40h over 5 days")
    }
}
