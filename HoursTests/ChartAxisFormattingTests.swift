import XCTest
@testable import Hours

/// Insights' chart axes in the user's own duration format (polish, 2026-11):
/// "8h" or "8:00" or "8", never a bare `"\(Int(hours))h"` whatever he chose.
final class ChartAxisFormattingTests: XCTestCase {
    func testHoursAndMinutesAxisReadsWholeHours() {
        let format = DurationFormatting(style: .hoursAndMinutes)
        XCTAssertEqual(format.axisString(hours: 0), "0h")
        XCTAssertEqual(format.axisString(hours: 4), "4h")
        XCTAssertEqual(format.axisString(hours: 12), "12h")
        XCTAssertEqual(format.axisString(hours: 2.5), "2h 30m")
    }

    func testClockAxis() {
        let format = DurationFormatting(style: .clock)
        XCTAssertEqual(format.axisString(hours: 8), "8:00")
        XCTAssertEqual(format.axisString(hours: 0.5), "0:30")
    }

    func testDecimalAxisDropsTrailingZeros() {
        let format = DurationFormatting(style: .decimal, decimalSeparator: ",")
        XCTAssertEqual(format.axisString(hours: 8), "8")
        XCTAssertEqual(format.axisString(hours: 2.5), "2,5")
        XCTAssertEqual(format.axisString(hours: 1.25), "1,25")
    }

    func testNegativeAxisValuesKeepTheMinus() {
        let format = DurationFormatting(style: .hoursAndMinutes)
        XCTAssertEqual(format.axisString(hours: -4), "\u{2212}4h")
        XCTAssertEqual(DurationFormatting(style: .decimal).axisString(hours: -2.5), "\u{2212}2.5")
    }

    func testFloatingNoiseRoundsToTheMinute() {
        let format = DurationFormatting(style: .hoursAndMinutes)
        XCTAssertEqual(format.axisString(hours: 7.999999), "8h")
    }
}
