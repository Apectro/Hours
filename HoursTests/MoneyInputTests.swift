import XCTest
@testable import Hours

/// An hourly rate as somebody types it on a phone in any of the app's
/// languages: a comma or a point, two decimals or none.
final class MoneyInputTests: XCTestCase {
    func testCommaAndPointBothMarkTheCents() {
        XCTAssertEqual(MoneyInput.cents(from: "18,50"), 1_850)
        XCTAssertEqual(MoneyInput.cents(from: "18.50"), 1_850)
        XCTAssertEqual(MoneyInput.cents(from: "18,5"), 1_850)
        XCTAssertEqual(MoneyInput.cents(from: "18"), 1_800)
        XCTAssertEqual(MoneyInput.cents(from: ",75"), 75)
    }

    func testSpacesAndACurrencySignAreIgnored() {
        XCTAssertEqual(MoneyInput.cents(from: " 22,00 € "), 2_200)
        XCTAssertEqual(MoneyInput.cents(from: "CHF 31.20"), 3_120)
    }

    /// A third decimal rounds to the cent, half up.
    func testMoreThanTwoDecimalsRoundToTheCent() {
        XCTAssertEqual(MoneyInput.cents(from: "18,505"), 1_851)
        XCTAssertEqual(MoneyInput.cents(from: "18,504"), 1_850)
    }

    /// "1.250,50" — the last mark is the decimal one, the others group
    /// thousands.
    func testGroupingMarksBeforeTheDecimalOneAreDropped() {
        XCTAssertEqual(MoneyInput.cents(from: "1.250,50"), 125_050)
        XCTAssertEqual(MoneyInput.cents(from: "1,250.50"), 125_050)
    }

    func testNothingTypedIsNoRate() {
        XCTAssertEqual(MoneyInput.cents(from: ""), 0)
        XCTAssertEqual(MoneyInput.cents(from: "  "), 0)
        XCTAssertEqual(MoneyInput.cents(from: "abc"), 0)
    }

    func testAnAbsurdlyLongNumberDoesNotOverflow() {
        XCTAssertEqual(MoneyInput.cents(from: String(repeating: "9", count: 40)), MoneyInput.maximumCents)
    }
}
