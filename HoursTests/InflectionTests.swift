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
        let many = 16
        let one = 1

        print("----- inflection -----")
        print("String(localized:) 16   -> \(String(localized: "^[\(many) day](inflect: true) worked"))")
        print("String(localized:) 1    -> \(String(localized: "^[\(one) day](inflect: true) worked"))")
        print("AttributedString 16     -> \(String(AttributedString(localized: "^[\(many) day](inflect: true) worked").characters))")
        print("AttributedString 1      -> \(String(AttributedString(localized: "^[\(one) day](inflect: true) worked").characters))")

        // Whether a bundle is even being consulted, and what it holds. If the
        // catalog compiled to nothing there is no en.lproj to find, and every
        // lookup silently returns its own key.
        print("localizations           -> \(Bundle.main.localizations)")
        print("preferred               -> \(Bundle.main.preferredLocalizations)")
        print("development             -> \(String(describing: Bundle.main.developmentLocalization))")
        print("en.lproj                -> \(String(describing: Bundle.main.path(forResource: "en", ofType: "lproj")))")
        print("Localizable.strings     -> \(String(describing: Bundle.main.path(forResource: "Localizable", ofType: "strings")))")
        print("Localizable.stringsdict -> \(String(describing: Bundle.main.path(forResource: "Localizable", ofType: "stringsdict")))")

        // What the bundle returns for the raw key, with a sentinel for "absent".
        // This separates "the table has no such key" from "the key is there and
        // the markup is simply not being processed" — which is the whole
        // question, and the two have different fixes.
        let key = "^[%lld day](inflect: true) worked"
        let missing = "<<absent>>"
        print("lookup %lld             -> \(Bundle.main.localizedString(forKey: key, value: missing, table: nil))")
        print("----- end inflection -----")
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
