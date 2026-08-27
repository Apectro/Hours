import XCTest
@testable import Hours

/// The exported file's language, which is not the app's.
///
/// The person reading a timesheet is often not the person who recorded it, so
/// the two can be set apart. What that buys is only worth having if the
/// translation is complete — a sheet that says *Zusammenfassung* over a column
/// headed *Worked* is worse than one that never claimed to be German.
final class ExportLanguageTests: XCTestCase {
    private let languages: [ExportLanguage] = [.english, .german, .croatian]

    // MARK: - Nothing is left in English by accident

    /// Every term is translated into every language, and no two languages
    /// were given the same word by copy-and-paste.
    ///
    /// The switch in `ExportLanguage` is exhaustive, so a term added without
    /// translations does not compile. What that cannot catch is a term added
    /// with the English text pasted into all three arms, which is this.
    func testEveryTermIsTranslatedIntoEveryLanguage() {
        for term in ExportTerm.allCases {
            for language in languages {
                let word = language(term)
                XCTAssertFalse(
                    word.trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(language.rawValue) has nothing to say for \(term.rawValue)"
                )
            }
        }

        // The tripwire. A term added with the English text pasted into all
        // three arms is a term that looks translated and is not, and the
        // switch being exhaustive cannot catch it. German shares exactly one
        // word with English and Croatian shares none, so anything else that
        // matches is a translation nobody did.
        let german = ExportLanguage.german
        let croatian = ExportLanguage.croatian
        let english = ExportLanguage.english

        let germanMatches = ExportTerm.allCases.filter { german($0) == english($0) }
        XCTAssertEqual(
            Set(germanMatches), [.name],
            "German shares a word with English that it probably should not"
        )

        let croatianMatches = ExportTerm.allCases.filter { croatian($0) == english($0) }
        XCTAssertEqual(
            Set(croatianMatches), [],
            "Croatian shares a word with English that it probably should not"
        )
    }

    /// A German timesheet says German things.
    func testTheGermanTimesheetIsGerman() {
        let german = ExportLanguage.german
        XCTAssertEqual(german(.worked), "Gearbeitet")
        XCTAssertEqual(german(.summary), "Zusammenfassung")
        XCTAssertEqual(german(.vacation), "Urlaub")
        XCTAssertEqual(german(.totalWorked), "Gesamt gearbeitet")
    }

    /// And a Croatian one Croatian things.
    func testTheCroatianTimesheetIsCroatian() {
        let croatian = ExportLanguage.croatian
        XCTAssertEqual(croatian(.worked), "Odrađeno")
        XCTAssertEqual(croatian(.summary), "Sažetak")
        XCTAssertEqual(croatian(.vacation), "Godišnji odmor")
        XCTAssertEqual(croatian(.totalWorked), "Ukupno odrađeno")
    }

    /// A language the export does not speak gets English rather than nothing.
    func testAnUnknownDeviceLanguageLandsOnEnglish() {
        // `.device` resolves against whatever the test host is set to, which
        // is not something a test should depend on — but it must always be
        // one of the three the app actually has words for.
        XCTAssertTrue(
            languages.contains(ExportLanguage.device.resolved),
            "following the phone resolved to a language with no vocabulary"
        )
        XCTAssertEqual(ExportLanguage.english.resolved, .english)
    }

    // MARK: - Durations

    /// "8h 30m" is idiomatic English and "8Std 30Min" is not German.
    func testTheUnitsAndTheirSpacingTravelWithTheLanguage() {
        func hoursAndMinutes(_ language: ExportLanguage) -> String {
            DurationFormatting.export(style: .hoursAndMinutes, decimalSeparator: ".", language: language)
                .string(510)
        }

        XCTAssertEqual(hoursAndMinutes(.english), "8h 30m")
        XCTAssertEqual(hoursAndMinutes(.german), "8 Std 30 Min")
        XCTAssertEqual(hoursAndMinutes(.croatian), "8 h 30 min")
    }

    /// Zero keeps the hour unit in every language, for the same reason it does
    /// in English: in a column of hours the unit should not change just
    /// because the value happens to be nothing.
    func testZeroAndTheUnderAnHourCaseAreTranslatedToo() {
        let german = DurationFormatting.export(style: .hoursAndMinutes, decimalSeparator: ".", language: .german)
        XCTAssertEqual(german.string(0), "0 Std")
        XCTAssertEqual(german.string(30), "30 Min")
        XCTAssertEqual(german.string(480), "8 Std")
        XCTAssertEqual(german.signedString(-180), "-3 Std")
    }

    /// The clock and decimal styles carry no units, so they are the same in
    /// every language — and the decimal separator stays the user's choice
    /// rather than the language's, because it is what their spreadsheet reads.
    func testTheUnitlessStylesAreUnaffected() {
        for language in languages {
            XCTAssertEqual(
                DurationFormatting.export(style: .clock, decimalSeparator: ",", language: language).string(510),
                "8:30"
            )
            XCTAssertEqual(
                DurationFormatting.export(style: .decimal, decimalSeparator: ",", language: language).string(510),
                "8,50"
            )
        }
    }
}
