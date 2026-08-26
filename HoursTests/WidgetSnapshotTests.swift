import XCTest
@testable import Hours

/// The figures a widget shows, and how it survives an app that has moved on.
final class WidgetSnapshotTests: XCTestCase {
    private let noon = Date(timeIntervalSince1970: 1_787_140_800)
    private let calendar = Fixture.calendar()

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
            durationStyle: .hoursAndMinutes,
            isUnlocked: true
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
        XCTAssertEqual(snapshot.todayIncludingRunningClock(at: noon, calendar: calendar), 150)
    }

    func testAStoppedClockAddsNothing() {
        let snapshot = snapshot(startedAt: noon.addingTimeInterval(-90 * 60), todayWorked: 60)

        XCTAssertEqual(snapshot.runningMinutes(at: noon), 0)
        XCTAssertEqual(snapshot.todayIncludingRunningClock(at: noon, calendar: calendar), 60)
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
        XCTAssertEqual(snapshot.todayIncludingRunningClock(at: noon, calendar: calendar), 60)
    }

    // MARK: - Progress

    /// A ring at zero on a Sunday reads as a failure rather than as a day off,
    /// so there is no ring on a day nothing is expected.
    func testNothingExpectedMeansNoProgressToShow() {
        XCTAssertNil(snapshot(todayExpected: 0).todayFraction(at: noon, calendar: calendar))
        XCTAssertNil(snapshot(monthExpected: 0).monthFraction(at: noon, calendar: calendar))
    }

    func testProgressIsWorkedOverExpected() {
        let snapshot = snapshot(todayWorked: 240, todayExpected: 480, monthWorked: 60, monthExpected: 120)

        XCTAssertEqual(snapshot.todayFraction(at: noon, calendar: calendar) ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.monthFraction(at: noon, calendar: calendar) ?? 0, 0.5, accuracy: 0.0001)
    }

    func testProgressCountsTheRunningClock() {
        let snapshot = snapshot(
            running: true,
            startedAt: noon.addingTimeInterval(-120 * 60),
            todayWorked: 120,
            todayExpected: 480
        )

        XCTAssertEqual(snapshot.todayFraction(at: noon, calendar: calendar) ?? 0, 0.5, accuracy: 0.0001)
    }

    // MARK: - After midnight

    /// The bug this guards against fires every night: only the app rewrites the
    /// snapshot, and a widget is drawn whenever someone glances at their phone.
    func testYesterdaysTotalIsNotShownAsTodays() {
        let snapshot = snapshot(todayWorked: 480, todayExpected: 480)
        let tomorrowMorning = noon.addingTimeInterval(20 * 3600)

        XCTAssertFalse(snapshot.describesDay(of: tomorrowMorning, calendar: calendar))
        XCTAssertEqual(
            snapshot.todayIncludingRunningClock(at: tomorrowMorning, calendar: calendar),
            0,
            "a new day has nothing recorded until the app says otherwise"
        )
        XCTAssertEqual(snapshot.expectedMinutes(at: tomorrowMorning, calendar: calendar), 0)
        XCTAssertNil(snapshot.todayFraction(at: tomorrowMorning, calendar: calendar))
    }

    /// A clock is measured from an absolute instant, so it stays true across
    /// midnight even when the day's total does not.
    func testAClockStillRunningAtMidnightKeepsCounting() {
        let snapshot = snapshot(
            running: true,
            startedAt: noon.addingTimeInterval(-60 * 60),
            todayWorked: 300,
            todayExpected: 480
        )
        let afterMidnight = noon.addingTimeInterval(14 * 3600)

        XCTAssertEqual(snapshot.runningMinutes(at: afterMidnight), 900)
        XCTAssertEqual(
            snapshot.todayIncludingRunningClock(at: afterMidnight, calendar: calendar),
            900,
            "the clock survives midnight; the 300 minutes recorded yesterday do not"
        )
    }

    /// Same rule one granularity up: on the first of a month, last month's
    /// total must not be shown under "THIS MONTH".
    func testLastMonthsTotalIsNotShownAsThisMonths() {
        let snapshot = snapshot(monthWorked: 6_000, monthExpected: 6_240)
        let nextMonth = noon.addingTimeInterval(40 * 24 * 3600)

        XCTAssertFalse(snapshot.describesMonth(of: nextMonth, calendar: calendar))
        XCTAssertEqual(snapshot.monthWorked(at: nextMonth, calendar: calendar), 0)
        XCTAssertEqual(snapshot.monthBalance(at: nextMonth, calendar: calendar), 0)
        XCTAssertNil(snapshot.monthFraction(at: nextMonth, calendar: calendar))
    }

    func testTheSameMonthIsStillTrusted() {
        let snapshot = snapshot(monthWorked: 6_000, monthExpected: 6_240)
        let laterThatMonth = noon.addingTimeInterval(3 * 24 * 3600)

        XCTAssertTrue(snapshot.describesMonth(of: laterThatMonth, calendar: calendar))
        XCTAssertEqual(snapshot.monthWorked(at: laterThatMonth, calendar: calendar), 6_000)
    }

    func testTheSameDayIsStillTrusted() {
        let snapshot = snapshot(todayWorked: 480, todayExpected: 480)
        let laterThatDay = noon.addingTimeInterval(2 * 3600)

        XCTAssertTrue(snapshot.describesDay(of: laterThatDay, calendar: calendar))
        XCTAssertEqual(
            snapshot.todayIncludingRunningClock(at: laterThatDay, calendar: calendar),
            480
        )
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
        XCTAssertFalse(
            decoded.isUnlocked,
            "a file written before the widgets were sold must not read as paid for"
        )
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
