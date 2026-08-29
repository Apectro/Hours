import XCTest
@testable import Hours

/// The exported file's language, which is not the app's.
///
/// The person reading a timesheet is often not the person who recorded it, so
/// the two can be set apart. What that buys is only worth having if the
/// translation is complete — a sheet that says *Zusammenfassung* over a column
/// headed *Worked* is worse than one that never claimed to be German.
final class ExportLanguageTests: XCTestCase {
    /// Every language the export speaks. Derived rather than listed, so a
    /// language added to the enum is tested without anybody remembering to
    /// add it here.
    private let languages = ExportLanguage.allCases.filter { $0 != .device }

    // MARK: - Nothing is left in English by accident

    /// Every term has something to say in every language.
    func testEveryTermIsTranslatedIntoEveryLanguage() {
        XCTAssertGreaterThan(languages.count, 1, "the export speaks only one language")

        for term in ExportTerm.allCases {
            for language in languages {
                XCTAssertFalse(
                    language(term).trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(language.rawValue) has nothing to say for \(term.rawValue)"
                )
            }
        }
    }

    /// Words that legitimately match English, listed language by language.
    ///
    /// The switch is exhaustive, so a term added without translations does
    /// not compile. What that cannot catch is a term added with the English
    /// pasted into every arm — it looks translated and is not. Genuine
    /// coincidences are real and common enough that "differs from English"
    /// would be a false alarm: French really does write Date, Type, Notes,
    /// Correction, Total and page. So they are enumerated, and anything else
    /// that matches is a translation nobody did.
    private static let sharedWithEnglish: [ExportLanguage: Set<ExportTerm>] = [
        .german: [.name],
        .croatian: [],
        .slovenian: [],
        .italian: [],
        .french: [.date, .dayType, .notes, .correction, .total, .page],
        .spanish: [.total],
        .portuguese: [.total],
        .dutch: [.dayType, .weekend],
        .polish: [.weekend]
    ]

    func testNoLanguageQuietlyKeptTheEnglish() {
        let english = ExportLanguage.english

        for language in languages where language != english {
            guard let expected = ExportLanguageTests.sharedWithEnglish[language] else {
                return XCTFail("\(language.rawValue) was added without saying which words it shares with English")
            }
            let matches = Set(ExportTerm.allCases.filter { language($0) == english($0) })
            XCTAssertEqual(
                matches, expected,
                """
                \(language.rawValue) matches English on words this test does not \
                expect it to. Either the translation was left as English, or the \
                coincidence is real and belongs in sharedWithEnglish.
                """
            )
        }

        XCTAssertEqual(
            Set(ExportLanguageTests.sharedWithEnglish.keys).subtracting(languages),
            [],
            "a language named here is no longer one the export speaks"
        )
    }

    /// The picker names each language in that language, and no two share a
    /// name or a code — either would make one of them unreachable.
    func testEveryLanguageIsNamedAndDistinct() {
        let named = languages.map(\.title)
        XCTAssertEqual(Set(named).count, named.count, "two languages answer to the same name")
        XCTAssertFalse(named.contains { $0.isEmpty })

        let locales = languages.map(\.locale.identifier)
        XCTAssertEqual(Set(locales).count, locales.count, "two languages share a locale")
    }

    /// A spot check that the words are the language they claim to be, in the
    /// three the app was built for and the ones added since.
    func testTheWordsAreTheLanguageTheyClaim() {
        let cases: [(ExportLanguage, ExportTerm, String)] = [
            (.german, .summary, "Zusammenfassung"),
            (.german, .vacation, "Urlaub"),
            (.croatian, .summary, "Sažetak"),
            (.croatian, .totalWorked, "Ukupno odrađeno"),
            (.slovenian, .summary, "Povzetek"),
            (.italian, .summary, "Riepilogo"),
            (.french, .summary, "Récapitulatif"),
            (.spanish, .summary, "Resumen"),
            (.portuguese, .summary, "Resumo"),
            (.dutch, .summary, "Samenvatting"),
            (.polish, .summary, "Podsumowanie")
        ]
        for (language, term, expected) in cases {
            XCTAssertEqual(language(term), expected, "\(language.rawValue) \(term.rawValue)")
        }
    }

    /// The phone's ordered preferences decide, not its formatting locale.
    ///
    /// The resolution used to read `Locale.current`, which answers a different
    /// question: it is the formatting locale. Someone whose preferences run
    /// Czech then German is shown a German app — iOS has no Czech
    /// localisation of it to pick — and `Locale.current` still says Czech, so
    /// every label coming from the engine came out English on an otherwise
    /// German screen. The first case below is that bug.
    func testTheFirstPreferenceWithWordsWins() {
        let cases: [(preferences: [String], expected: ExportLanguage, why: String)] = [
            (["cs-CZ", "de-DE"], .german,
             "a language with no localisation should fall through to the next preference"),
            (["de-DE", "en-GB"], .german, "the first preference wins outright"),
            (["en-GB", "de-DE"], .english, "order is the whole point"),
            (["pt-BR"], .portuguese, "a region on the tag must not stop it matching"),
            (["zh-Hans-CN", "pl-PL"], .polish, "nor must a script"),
            (["DE"], .german, "a tag that arrives uppercase is the same tag"),
            (["cs-CZ", "ja-JP"], .english, "nothing recognised falls back to English"),
            ([], .english, "so does a phone that states no preference at all"),
        ]

        for (preferences, expected, why) in cases {
            XCTAssertEqual(ExportLanguage.speaking(preferences), expected, "\(preferences): \(why)")
        }
    }

    /// Every language the table speaks must be reachable from a phone set to
    /// it. A code that does not match its own case is a language nobody can
    /// ever be given, and nothing else would say so.
    func testEveryLanguageIsReachableFromAPhoneSetToIt() {
        for language in languages {
            let code = String(language.locale.identifier.prefix(2))
            XCTAssertEqual(
                ExportLanguage.speaking([code]),
                language,
                "a phone set to \(code) cannot reach \(language.rawValue)"
            )
        }
    }

    /// A language the export does not speak gets English rather than nothing.
    func testAnUnknownDeviceLanguageLandsOnEnglish() {
        // `.device` resolves against whatever the test host is set to, which
        // is not something a test should depend on — but it must always be
        // one of the languages the app actually has words for.
        XCTAssertTrue(
            languages.contains(ExportLanguage.device.resolved),
            "following the phone resolved to a language with no vocabulary"
        )
        XCTAssertEqual(ExportLanguage.english.resolved, .english)
        XCTAssertEqual(ExportLanguage.polish.resolved, .polish)
    }

    /// Following the phone must not produce half a translation.
    ///
    /// The words resolve against the phone and fall back to English for a
    /// language the export has none for. The locale that names months and
    /// weekdays was following the phone regardless, so a French handset
    /// produced English column titles over "août" and "lun" — worse than
    /// either language alone, because a reader cannot tell which parts were
    /// meant.
    func testFollowingThePhoneNeverMixesTwoLanguages() {
        let device = ExportLanguage.device
        XCTAssertEqual(
            String(device.locale.identifier.prefix(2)),
            String(device.resolved.locale.identifier.prefix(2)),
            "the month names and the column titles are in different languages"
        )

        // A named language pins its own locale and is unaffected by the host,
        // which is the point of naming it.
        XCTAssertEqual(ExportLanguage.german.locale.identifier, "de_DE")
        XCTAssertEqual(ExportLanguage.polish.locale.identifier, "pl_PL")
        XCTAssertEqual(ExportLanguage.english.locale.identifier, "en_GB")
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
