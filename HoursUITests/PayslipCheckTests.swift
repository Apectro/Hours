import XCTest

/// Insights › Month › Check your payslip: type what the payslip says, see
/// how it compares.
///
/// Found by identifier and by position, never by label, which is translated.
final class PayslipCheckTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// The sample month has nowhere near 250 hours of overtime, so the
    /// payslip shows more, and the line says so.
    func testOvertimeTypedInShowsADifference() {
        let app = XCUIApplication.hours()
        app.launchArguments += ["-hours-sample-data"]
        app.launch()
        XCTAssertTrue(app.tab(.insights).waitForExistence(timeout: 20))
        app.tab(.insights).tap()
        XCTAssertTrue(app.screen("screen-insights").waitForExistence(timeout: 10))

        let row = app.buttons.matching(identifier: "insights-payslip-check").firstMatch
        XCTAssertTrue(reveal(row, in: app), "the month has no payslip check")
        row.tap()

        let overtime = app.textFields.matching(identifier: "payslip-field-overtime").firstMatch
        XCTAssertTrue(overtime.waitForExistence(timeout: 5), "the check does not ask for overtime")
        overtime.tap()
        overtime.typeText("250")

        let check = app.buttons.matching(identifier: "payslip-check").firstMatch
        XCTAssertTrue(check.isEnabled)
        check.tap()

        let difference = app.descendants(matching: .any).matching(identifier: "payslip-difference-overtime").firstMatch
        XCTAssertTrue(difference.waitForExistence(timeout: 5), "no difference line for overtime")
        XCTAssertTrue(app.buttons.matching(identifier: "payslip-share").firstMatch.exists)

        app.buttons.matching(identifier: "payslip-done").firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }
}
