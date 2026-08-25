import XCTest
@testable import Hours

/// The figures a widget shows, and how it survives an app that has moved on.
final class WidgetSnapshotTests: XCTestCase {
    private let noon = Date(timeIntervalSince1970: 1_787_140_800)

    private func snapshot(
        running: Bool = false,
        startedAt: Date? = nil,
        todayWorked: Int = 0,
        todayExpected: Int = 480,
        monthWorked: Int = 0,
        monthExpected: Int = 0
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: noon,
            isClockRunning: running,
            clockStartedAt: startedAt,
            clockJobName: nil,
            todayWorkedMinutes: todayWorked,
            todayExpectedMinutes: todayExpected,
            monthWorkedMinutes: monthWorked,
            monthExpectedMinutes: monthExpected,
            monthBalanceMinutes: monthWorked - monthExpected,
            showsBalance: true,
            unrecordedDayCount: 0,
            durationStyle: .hoursAndMinutes
        )
    }

    // MARK: - The running clock

    /// The widget works the elapsed time out itself. If it did not, the app
    /// would have to rewrite the file every minute of every shift.
    func testTheRunningClockIsCountedFromTheInstantItStarted() {
        let snapshot = snapshot(
            running: true,
            startedAt: noon.addingTimeInterval(-90 * 60),
            todayWorked: 60
        )

        XCTAssertEqual(snapshot.runningMinutes(at: noon), 90)
        XCTAssertEqual(snapshot.todayIncludingRunningClock(at: noon), 150)
    }

    func testAStoppedClockAddsNothing() {
        let snapshot = snapshot(startedAt: noon.addingTimeInterval(-90 * 60), todayWorked: 60)

        XCTAssertEqual(snapshot.runningMinutes(at: noon), 0)
        XCTAssertEqual(snapshot.todayIncludingRunningClock(at: noon), 60)
    }

    /// A timeline entry can be rendered slightly before its own date, and a
    /// clock started "in the future" must not read as negative hours worked.
    func testAStartInTheFutureIsClampedToZero() {
        let snapshot = snapshot(
            running: true,
            startedAt: noon.addingTimeInterval(120),
            todayWorked: 60
        )

        XCTAssertEqual(snapshot.runningMinutes(at: noon), 0)
        XCTAssertEqual(snapshot.todayIncludingRunningClock(at: noon), 60)
    }

    // MARK: - Progress

    /// A ring at zero on a Sunday reads as a failure rather than as a day off,
    /// so there is no ring on a day nothing is expected.
    func testNothingExpectedMeansNoProgressToShow() {
        XCTAssertNil(snapshot(todayExpected: 0).todayFraction(at: noon))
        XCTAssertNil(snapshot(monthExpected: 0).monthFraction)
    }

    func testProgressIsWorkedOverExpected() {
        let snapshot = snapshot(todayWorked: 240, todayExpected: 480, monthWorked: 60, monthExpected: 120)

        XCTAssertEqual(snapshot.todayFraction(at: noon) ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.monthFraction ?? 0, 0.5, accuracy: 0.0001)
    }

    func testProgressCountsTheRunningClock() {
        let snapshot = snapshot(
            running: true,
            startedAt: noon.addingTimeInterval(-120 * 60),
            todayWorked: 120,
            todayExpected: 480
        )

        XCTAssertEqual(snapshot.todayFraction(at: noon) ?? 0, 0.5, accuracy: 0.0001)
    }

    // MARK: - Reading a file written by a different version

    func testASnapshotSurvivesARoundTrip() throws {
        let original = snapshot(running: true, startedAt: noon, todayWorked: 123, monthWorked: 456)
        let data = try JSONEncoder().encode(original)

        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: data), original)
    }

    /// The app updates while a widget is still on a Home Screen showing the
    /// old one, and vice versa. Neither direction may fail to decode.
    func testMissingKeysFallBackInsteadOfFailing() throws {
        let json = Data(#"{"todayWorkedMinutes": 90}"#.utf8)

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: json)

        XCTAssertEqual(decoded.todayWorkedMinutes, 90)
        XCTAssertEqual(decoded.todayExpectedMinutes, 0)
        XCTAssertFalse(decoded.isClockRunning)
        XCTAssertNil(decoded.clockStartedAt)
        XCTAssertEqual(decoded.durationStyle, .hoursAndMinutes)
    }

    func testAnUnreadableValueFallsBackRatherThanFailingTheWholeFile() throws {
        let json = Data(#"{"todayWorkedMinutes": 90, "durationStyle": "roman-numerals"}"#.utf8)

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: json)

        XCTAssertEqual(decoded.todayWorkedMinutes, 90)
        XCTAssertEqual(decoded.durationStyle, .hoursAndMinutes)
    }

    /// The widget formats the way the app does, rather than picking its own
    /// notation and looking like a different app on the same Home Screen.
    func testTheChosenDurationStyleTravelsWithTheSnapshot() {
        var snapshot = snapshot(todayWorked: 150)
        snapshot.durationStyle = .clock

        XCTAssertEqual(snapshot.formatting.string(150), "2:30")
    }
}
