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
        let rendered = String(inflected: "^[\(16) day](inflect: true) worked")
        XCTAssertFalse(leaks(rendered), "the calendar shows raw markup: \(rendered)")
        XCTAssertEqual(rendered, "16 days worked")
    }

    func testASingleDayReadsAsOneDay() {
        let rendered = String(inflected: "^[\(1) day](inflect: true) worked")
        XCTAssertFalse(leaks(rendered), "the calendar shows raw markup: \(rendered)")
        XCTAssertEqual(rendered, "1 day worked")
    }

    func testTheScheduleSummaryDoesNotShowItsOwnMarkup() {
        let rendered = String(inflected: "40h over ^[\(5) day](inflect: true)")
        XCTAssertFalse(leaks(rendered), "settings shows raw markup: \(rendered)")
        XCTAssertEqual(rendered, "40h over 5 days")
    }

    func testZeroIsPluralToo() {
        XCTAssertEqual(String(inflected: "^[\(0) day](inflect: true) worked"), "0 days worked")
    }

    /// The guard that outlives this fix.
    ///
    /// The bug was not that one string was written wrong — all fourteen were
    /// written correctly and none of them worked. What was missing was anything
    /// that looked at rendered text, so a call site added tomorrow with
    /// `String(localized:)` would put the markup straight back on screen with
    /// every existing test still green. This is the test that notices.
    func testNoSourceFileStillUsesTheUninflectingCall() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HoursTests
            .deletingLastPathComponent()   // repository root

        var offenders: [String] = []
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        )
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            // This file quotes the broken form on purpose, in the diagnostic.
            guard url.lastPathComponent != "InflectionTests.swift" else { continue }
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in source.split(separator: "\n", omittingEmptySubsequences: false)
            where line.contains("inflect: true") && line.contains("String(localized:") {
                offenders.append("\(url.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertEqual(
            offenders, [],
            "String(localized:) does not inflect in this app; use String(inflected:)"
        )
    }
}
