import XCTest
@testable import Hours

/// "For the sheet title combine site names": the sites a sheet covers, named
/// in the order first worked, a long list cut to two and "+N more".
final class SiteNamesTitleTests: XCTestCase {
    func testOneSiteIsItsName() {
        XCTAssertEqual(ExportLanguage.english.combinedSiteNames(["Trg Pravde"]), "Trg Pravde")
    }

    func testTwoOrThreeAreAllNamedInOrder() {
        XCTAssertEqual(
            ExportLanguage.german.combinedSiteNames(["Hauptstraße 12", "Trg Pravde"]),
            "Hauptstraße 12 · Trg Pravde"
        )
        XCTAssertEqual(
            ExportLanguage.croatian.combinedSiteNames(["Trg Pravde", "Hauptstraße 12", "Solarka"]),
            "Trg Pravde · Hauptstraße 12 · Solarka"
        )
    }

    func testMoreThanThreeAreTheFirstTwoAndHowManyMore() {
        let names = ["Hauptstraße 12", "Trg Pravde", "Solarka", "Kaiserstraße 12", "Jarun"]
        XCTAssertEqual(ExportLanguage.english.combinedSiteNames(names), "Hauptstraße 12 · Trg Pravde +3 more")
        XCTAssertEqual(ExportLanguage.german.combinedSiteNames(names), "Hauptstraße 12 · Trg Pravde +3 weitere")
        XCTAssertEqual(ExportLanguage.croatian.combinedSiteNames(names), "Hauptstraße 12 · Trg Pravde + još 3")
    }

    func testBlankAndRepeatedNamesCountOnce() {
        XCTAssertEqual(ExportLanguage.english.combinedSiteNames(["A", " ", "A ", "B"]), "A · B")
        XCTAssertEqual(ExportLanguage.english.combinedSiteNames([]), "")
    }

    func testEveryLanguageSaysHowManyMore() {
        for language in ExportLanguage.allCases {
            XCTAssertTrue(language.moreSites(4).contains("4"), "\(language)")
            XCTAssertFalse(language.moreSites(4).contains("{"), "\(language)")
        }
    }
}
