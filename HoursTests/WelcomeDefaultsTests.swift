import XCTest
@testable import Hours

/// What the welcome's report-language and pay steps start from once a
/// country has been picked, and the crew answer they store.
final class WelcomeDefaultsTests: XCTestCase {
    // MARK: - The language of the sheets for the boss

    func testEachCountryWritesItsSheetsInItsOwnLanguage() {
        let expected: [HolidayCountry: ExportLanguage] = [
            .de: .german, .at: .german, .ch: .german,
            .hr: .croatian, .si: .slovenian, .it: .italian, .fr: .french,
            .es: .spanish, .pt: .portuguese, .nl: .dutch, .pl: .polish,
        ]
        for country in HolidayCountry.allCases {
            XCTAssertEqual(country.reportLanguage(region: nil), expected[country], "\(country)")
        }
    }

    /// Switzerland is German unless the canton speaks French or Italian.
    func testASwissCantonCanChangeTheLanguage() {
        XCTAssertEqual(HolidayCountry.ch.reportLanguage(region: "ZH"), .german)
        XCTAssertEqual(HolidayCountry.ch.reportLanguage(region: "GE"), .french)
        XCTAssertEqual(HolidayCountry.ch.reportLanguage(region: "VD"), .french)
        XCTAssertEqual(HolidayCountry.ch.reportLanguage(region: "TI"), .italian)
        XCTAssertEqual(HolidayCountry.ch.reportLanguage(region: HolidayCountry.otherSwissCanton), .german)
        XCTAssertEqual(HolidayCountry.de.reportLanguage(region: "BY"), .german, "a German state stays German")
    }

    /// No country: whatever the setting already says, which on a fresh
    /// install is "Same as the phone" — the app's language when the export
    /// speaks it, otherwise English.
    func testWithoutACountryTheSettingStays() {
        XCTAssertEqual(ExportLanguage.suggested(for: nil, region: nil, otherwise: .device), .device)
        XCTAssertEqual(ExportLanguage.suggested(for: nil, region: nil, otherwise: .polish), .polish)
        XCTAssertEqual(ExportLanguage.suggested(for: .hr, region: nil, otherwise: .device), .croatian)
        XCTAssertEqual(ExportLanguage.speaking(["cs-CZ"]), .english, "a language the export lacks is English")
        XCTAssertEqual(ExportLanguage.speaking(["de-AT"]), .german)
    }

    // MARK: - The currency

    func testEachCountryPaysInItsCurrency() {
        let expected: [HolidayCountry: String] = [
            .de: "EUR", .at: "EUR", .ch: "CHF", .hr: "EUR", .si: "EUR", .it: "EUR",
            .fr: "EUR", .es: "EUR", .pt: "EUR", .nl: "EUR", .pl: "PLN",
        ]
        for country in HolidayCountry.allCases {
            XCTAssertEqual(country.currencyCode, expected[country], "\(country)")
        }
    }

    // MARK: - Leading a crew

    func testNobodyLeadsACrewUntilTheySaySo() {
        XCTAssertFalse(AppSettings().leadsCrew)
    }

    func testTheCrewAnswerRoundTrips() throws {
        var settings = AppSettings()
        settings.leadsCrew = true

        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertTrue(restored.leadsCrew)
    }

    /// Settings and backups from 1.0 have no such key.
    func testSettingsFromBeforeTheQuestionReadAsNoCrew() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"appearance":"dark"}"#.utf8))
        XCTAssertFalse(settings.leadsCrew)
        XCTAssertEqual(settings.appearance, .dark)

        let unreadable = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"leadsCrew":"perhaps"}"#.utf8))
        XCTAssertFalse(unreadable.leadsCrew, "an unreadable value falls back rather than failing the load")
    }

    func testABackupFromOnePointZeroStillRestoresItsSettings() throws {
        let json = """
        {"formatVersion": 1, "exportedAt": "2026-10-01T08:00:00Z",
         "settings": {"export": {"ownerName": "Marijo"}}, "days": [], "holidays": []}
        """
        let archive = try BackupArchive.decoded(from: Data(json.utf8))
        XCTAssertEqual(archive.settings.export.ownerName, "Marijo")
        XCTAssertFalse(archive.settings.leadsCrew)
    }

    /// The shape 1.0 decodes settings with: keys it does not know, like this
    /// one, are skipped.
    private struct VersionOneSettings: Decodable {
        var appearance: AppearancePreference
    }

    func testOnePointZeroSkipsTheNewKey() throws {
        var settings = AppSettings()
        settings.leadsCrew = true
        settings.appearance = .light

        let old = try JSONDecoder().decode(VersionOneSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(old.appearance, .light)
    }
}

/// The guided tour's stops: which tab each is on, what it points at, and how
/// it counts.
final class GuidedTourTests: XCTestCase {
    func testSixStopsInOrder() {
        XCTAssertEqual(TourStop.allCases, [.welcome, .today, .summary, .sites, .insights, .export])
    }

    func testEachStopIsOnItsTabAndPointsAtItsTarget() {
        XCTAssertEqual(TourStop.welcome.tab, .calendar)
        XCTAssertNil(TourStop.welcome.target, "the welcome is centred")
        XCTAssertEqual(TourStop.today.tab, .calendar)
        XCTAssertEqual(TourStop.today.target, .calendarToday)
        XCTAssertEqual(TourStop.summary.tab, .calendar)
        XCTAssertEqual(TourStop.summary.target, .calendarSummary)
        XCTAssertEqual(TourStop.sites.tab, .sites)
        XCTAssertEqual(TourStop.sites.target, .sites)
        XCTAssertEqual(TourStop.insights.tab, .insights)
        XCTAssertEqual(TourStop.insights.target, .insights)
        XCTAssertEqual(TourStop.export.tab, .settings)
        XCTAssertEqual(TourStop.export.target, .settingsExport)
    }

    func testTheTourCountsAndEnds() {
        var tour = GuidedTour(leadsCrew: true)
        XCTAssertEqual(tour.stop, .welcome)
        XCTAssertEqual(tour.number, 1)
        XCTAssertEqual(tour.count, 6)
        XCTAssertFalse(tour.isLast)

        var visited: [TourStop] = [tour.stop]
        while tour.advance() { visited.append(tour.stop) }

        XCTAssertEqual(visited, TourStop.allCases)
        XCTAssertEqual(tour.stop, .export, "advancing past the end stays on the last stop")
        XCTAssertEqual(tour.number, 6)
        XCTAssertTrue(tour.isLast)
    }

    /// Someone without a crew sees the same six stops; only the Sites stop
    /// says less.
    func testWithoutACrewTheStopsAreTheSame() {
        var tour = GuidedTour(leadsCrew: false)
        var visited: [TourStop] = [tour.stop]
        while tour.advance() { visited.append(tour.stop) }
        XCTAssertEqual(visited, TourStop.allCases)
        XCTAssertFalse(tour.leadsCrew)
    }
}
