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

    /// Following the phone must not produce half a translation.
    ///
    /// `device` resolves its words by looking at the phone and falls back to
    /// English for a language the export has no words for. The locale that
    /// names months and weekdays was following the phone regardless, so a
    /// French handset produced English column titles over "août" and "lun" —
    /// worse than either language alone, because a reader cannot tell which
    /// parts were meant.
    func testFollowingThePhoneNeverMixesTwoLanguages() {
        // Whatever the host is set to, the words and the month names have to
        // come from the same place.
        let device = ExportLanguage.device
        XCTAssertEqual(
            String(device.locale.identifier.prefix(2)),
            expectedCode(for: device.resolved),
            "the month names and the column titles are in different languages"
        )

        // The named languages pin their own locale and are unaffected by the
        // host, which is the point of naming them.
        XCTAssertEqual(ExportLanguage.german.locale.identifier, "de_DE")
        XCTAssertEqual(ExportLanguage.croatian.locale.identifier, "hr_HR")
        XCTAssertEqual(ExportLanguage.english.locale.identifier, "en_GB")
    }

    private func expectedCode(for language: ExportLanguage) -> String {
        switch language {
        case .german: return "de"
        case .croatian: return "hr"
        default: return "en"
        }
    }

    // MARK: - Durations

    /// The units are not translated, and that is a decision rather than a gap.
    ///
    /// They were German for a while — "8 Std 30 Min" — and it was the wrong
    /// call: h and m read as symbols rather than words wherever a timesheet is
    /// filled in, and the longer forms pushed every duration column wider than
    /// the page wanted. This test exists so that changing it back is a
    /// decision somebody makes on purpose.
    func testDurationsKeepTheirUnitsInEveryLanguage() {
        let duration = DurationFormatting.export(style: .hoursAndMinutes, decimalSeparator: ".")
        XCTAssertEqual(duration.string(510), "8h 30m")
        XCTAssertEqual(duration.string(0), "0h")
        XCTAssertEqual(duration.string(30), "30m")
        XCTAssertEqual(duration.string(480), "8h")
        XCTAssertEqual(duration.signedString(-180), "-3h")
    }

    /// And the workbook's number format spells out the same two units, so a
    /// cell and the text beside it cannot disagree about what a duration is.
    func testTheWorkbookMaskMatchesTheText() {
        for language in languages {
            var export = ExportPreferences()
            export.language = language
            let table = ReportTable(
                title: "Hours",
                subtitle: "",
                language: language,
                columns: [.date, .worked],
                rows: [],
                totals: []
            )
            let package = String(decoding: XLSXWriter.data(for: table, preferences: export), as: UTF8.self)
            XCTAssertTrue(
                package.contains("[h]&quot;h&quot; mm&quot;m&quot;"),
                "\(language.rawValue): the workbook mask has drifted from the text"
            )
        }
    }

    /// The decimal separator stays the user's choice rather than the
    /// language's, because what matters there is what their spreadsheet reads.
    func testTheUnitlessStylesAreUnaffected() {
        XCTAssertEqual(
            DurationFormatting.export(style: .clock, decimalSeparator: ",").string(510),
            "8:30"
        )
        XCTAssertEqual(
            DurationFormatting.export(style: .decimal, decimalSeparator: ",").string(510),
            "8,50"
        )
    }
}
