import XCTest
@testable import Hours

/// When the app asks for a rating: after a sheet has really gone to someone,
/// never in the first two weeks, and once a version.
final class ReviewPromptTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func days(_ count: Int) -> Date {
        calendar.date(byAdding: .day, value: count, to: start)!
    }

    func testNeverInTheFirstTwoWeeks() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(firstUse: start, now: days(13), lastAskedVersion: nil, currentVersion: "1.1", calendar: calendar))
    }

    func testAfterTwoWeeksOfUse() {
        XCTAssertTrue(ReviewPrompt.shouldAsk(firstUse: start, now: days(14), lastAskedVersion: nil, currentVersion: "1.1", calendar: calendar))
    }

    func testOnceAVersion() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(firstUse: start, now: days(40), lastAskedVersion: "1.1", currentVersion: "1.1", calendar: calendar))
        XCTAssertTrue(ReviewPrompt.shouldAsk(firstUse: start, now: days(40), lastAskedVersion: "1.0", currentVersion: "1.1", calendar: calendar))
    }

    func testNoFirstUseYetMeansNotYet() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(firstUse: nil, now: days(40), lastAskedVersion: nil, currentVersion: "1.1", calendar: calendar))
    }

    func testTheWriteReviewLinkNamesTheApp() {
        XCTAssertEqual(ReviewPrompt.writeReviewURL.absoluteString, "https://apps.apple.com/app/id6825054128?action=write-review")
    }

    func testTheFeedbackMailCarriesVersionAndDevice() throws {
        let url = try XCTUnwrap(ReviewPrompt.feedbackMailURL(subject: "Zeitkonto feedback", appVersion: "1.1 (42)", system: "iOS 18.2", device: "iPhone16,2"))
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:marijomiksa@pm.me?"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let body = try XCTUnwrap(components.queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(body.contains("1.1 (42)") && body.contains("iOS 18.2") && body.contains("iPhone16,2"))
        XCTAssertEqual(components.queryItems?.first { $0.name == "subject" }?.value, "Zeitkonto feedback")
    }
}
