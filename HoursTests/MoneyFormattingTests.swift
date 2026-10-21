import XCTest
@testable import Hours

/// Amounts are whole cents in the engine and become text only here.
final class MoneyFormattingTests: XCTestCase {
    func testAnAmountIsWrittenTheLocalesWay() {
        let money = MoneyFormatting(currencyCode: "USD", locale: Locale(identifier: "en_US"))

        XCTAssertEqual(money.string(234_050), "$2,340.50")
    }

    func testTheCurrencyIsTheChosenOneNotTheLocales() {
        let money = MoneyFormatting(currencyCode: "EUR", locale: Locale(identifier: "de_DE"))
        let text = money.string(234_050)

        XCTAssertTrue(text.contains("2.340,50"), text)
        XCTAssertTrue(text.contains("€"), text)
    }

    func testAHeadlineFigureLeavesTheCentsOut() {
        let money = MoneyFormatting(currencyCode: "USD", locale: Locale(identifier: "en_US"))

        XCTAssertEqual(money.string(234_050, showsCents: false), "$2,341")
        XCTAssertEqual(money.string(234_049, showsCents: false), "$2,340")
    }

    func testAFileGetsAPlainNumber() {
        XCTAssertEqual(MoneyFormatting.plain(234_050, decimalSeparator: ","), "2340,50")
        XCTAssertEqual(MoneyFormatting.plain(5, decimalSeparator: "."), "0.05")
        XCTAssertEqual(MoneyFormatting.plain(-1_99, decimalSeparator: "."), "-1.99")
    }
}
