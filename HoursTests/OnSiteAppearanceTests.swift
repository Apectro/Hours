import XCTest
@testable import Hours

/// Appearance › On site: Bigger buttons and High contrast (1.2).
final class OnSiteAppearanceTests: XCTestCase {
    func testBothAreOffUntilSwitchedOn() {
        let settings = AppSettings()
        XCTAssertFalse(settings.biggerButtons)
        XCTAssertFalse(settings.highContrast)
    }

    func testTheyRoundTrip() throws {
        var settings = AppSettings()
        settings.biggerButtons = true
        settings.highContrast = true

        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertTrue(restored.biggerButtons)
        XCTAssertTrue(restored.highContrast)
        XCTAssertEqual(restored, settings)
    }

    func testABackupCarriesThem() throws {
        var settings = AppSettings()
        settings.biggerButtons = true
        settings.highContrast = true

        let back = try BackupArchive.decoded(from: BackupArchive(settings: settings, days: [], holidays: []).encoded())

        XCTAssertTrue(back.settings.biggerButtons)
        XCTAssertTrue(back.settings.highContrast)
    }

    /// Off means nothing written, so settings without them are written
    /// exactly as before.
    func testOffIsNotWritten() throws {
        let json = String(decoding: try JSONEncoder().encode(AppSettings()), as: UTF8.self)

        XCTAssertFalse(json.contains("biggerButtons"))
        XCTAssertFalse(json.contains("highContrast"))
    }

    func testOlderOrUnreadableSettingsReadAsOff() throws {
        let older = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"appearance":"dark"}"#.utf8))
        XCTAssertFalse(older.biggerButtons)
        XCTAssertFalse(older.highContrast)
        XCTAssertEqual(older.appearance, .dark)

        let junk = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"biggerButtons":"yes","highContrast":7}"#.utf8)
        )
        XCTAssertFalse(junk.biggerButtons)
        XCTAssertFalse(junk.highContrast)
    }

    func testAnOlderBackupRestoresWithThemOff() throws {
        let json = """
        {"formatVersion": 1, "exportedAt": "2026-10-01T08:00:00Z",
         "settings": {"appearance": "light"}, "days": [], "holidays": []}
        """
        let archive = try BackupArchive.decoded(from: Data(json.utf8))
        XCTAssertEqual(archive.settings.appearance, .light)
        XCTAssertFalse(archive.settings.biggerButtons)
        XCTAssertFalse(archive.settings.highContrast)
    }
}
