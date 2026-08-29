import XCTest
@testable import Hours

/// Whether the things Siri says are actually in the catalogue.
///
/// Siri answering in English on a German phone is worse than a label in
/// English: there is no surrounding screen to give it context, and nothing
/// visible to notice. Every one of these lines was a plain Swift literal —
/// some appended to a `[String]`, where no conformance could ever have looked
/// them up — and the two intent titles beside them were translated, which is
/// what made the gap invisible.
///
/// Asserted against the compiled bundle rather than against
/// `Scripts/translations.json`. The generator writing a key and the app
/// shipping it are two different claims, and only the second one matters: the
/// German capture once showed English labels whose translations were sitting
/// correctly in the source table all along.
///
/// Excluded from the Linux job in `Package.swift`, because the whole point is
/// what the app bundle holds.
final class SpokenLocalizationTests: XCTestCase {
    private static let absent = "<<absent>>"

    /// Every literal `ClockIntents.swift` hands to `String(localized:)`, in the
    /// placeholder form the catalogue keys on.
    private let spoken = [
        "You were already clocked in at %@.",
        "The clock could not be started.",
        "Clocked in at %@.",
        "You are not clocked in.",
        "Clocked out. That shift had been running over a day, so %@ was capped — worth checking.",
        "Clocked out. %@ recorded for %@.",
        "You have been clocked in for %@.",
        "This month you have worked %@.",
        "You are exactly on target.",
        "You are %@ ahead.",
        "You are %@ behind.",
    ]

    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj"),
            "the app has no \(language).lproj — the catalogue did not compile"
        )
        return try XCTUnwrap(Bundle(path: path), "\(language).lproj is not a bundle")
    }

    /// The key is in the table at all. A missing key returns itself, which
    /// reads as perfectly good English and is the failure this exists for.
    func testEverySpokenLineIsInEveryLanguage() throws {
        for language in Bundle.main.localizations where language != "Base" {
            let bundle = try self.bundle(language)
            for key in spoken {
                let value = bundle.localizedString(forKey: key, value: Self.absent, table: nil)
                XCTAssertNotEqual(value, Self.absent, "\(language) has no \(key)")
                XCTAssertFalse(value.isEmpty, "\(language) has an empty \(key)")
            }
        }
    }

    /// And the table actually says something different in another language.
    ///
    /// A key present in de.lproj with the English text still against it passes
    /// the test above and fails the only test that matters, which is whether a
    /// German speaker hears German.
    func testGermanDoesNotSimplyRepeatTheEnglish() throws {
        let german = try bundle("de")
        for key in spoken {
            let value = german.localizedString(forKey: key, value: Self.absent, table: nil)
            XCTAssertNotEqual(value, key, "German still says the English for \(key)")
        }
    }

    /// The placeholders survive translation, in the same number.
    ///
    /// A translation that drops a `%@` does not merely read oddly: the format
    /// is applied to arguments that are no longer there, which is a crash in
    /// the one code path nobody watches.
    func testThePlaceholdersSurviveTranslation() throws {
        for language in Bundle.main.localizations where language != "Base" {
            let bundle = try self.bundle(language)
            for key in spoken {
                let value = bundle.localizedString(forKey: key, value: Self.absent, table: nil)
                guard value != Self.absent else { continue }
                XCTAssertEqual(
                    value.components(separatedBy: "%@").count,
                    key.components(separatedBy: "%@").count,
                    "\(language) changed the number of placeholders in \(key)"
                )
            }
        }
    }

    /// What a status answer is actually built from.
    ///
    /// The month line, the balance line and the duration inside them are
    /// separate lookups, and the duration comes from `SpokenDuration`, which
    /// was already localised. This asserts the join produces one sentence in
    /// one language rather than a translated frame around an English middle.
    func testAStatusSentenceComesOutWhole() {
        let rendered = String(
            localized: "You are \(SpokenDuration.string(165)) ahead.",
            comment: "Siri status, a balance in credit"
        )
        XCTAssertFalse(rendered.contains("%@"), "an argument was never substituted: \(rendered)")
        XCTAssertFalse(rendered.contains("^["), "inflection markup reached the sentence: \(rendered)")
        XCTAssertTrue(rendered.contains("2"), "the duration is missing from: \(rendered)")
    }
}
