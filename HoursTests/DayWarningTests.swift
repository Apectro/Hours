import XCTest
@testable import Hours

final class DayWarningTests: XCTestCase {
    /// The site-hours notice is shown on screen, so it comes from the app
    /// vocabulary and must exist, and differ from English, in every language.
    func testSiteHoursNoticeIsTranslatedInEveryLanguage() {
        let english = ExportLanguage.english(.siteHoursNotCounted)
        for language in ExportLanguage.allCases where language != .device && language != .english {
            let text = language(.siteHoursNotCounted)
            XCTAssertFalse(text.isEmpty, "\(language) has no text")
            XCTAssertNotEqual(text, english, "\(language) was left in English")
        }
    }

    func testSiteHoursWarningMessageComesFromTheVocabulary() {
        XCTAssertEqual(DayWarning.siteHoursNotCounted.message, ExportLanguage.device(.siteHoursNotCounted))
    }
}
