import XCTest
@testable import Hours

/// What the watch shows, worked out from the snapshot the phone sent and the
/// taps the phone has not heard about yet.
final class WatchFaceTests: XCTestCase {
    private let noon = Date(timeIntervalSince1970: 1_787_140_800)
    private let calendar = Fixture.calendar()

    private func snapshot(
        running: Bool = false,
        startedAt: Date? = nil,
        todayWorked: Int = 402,
        todayExpected: Int = 480,
        balance: Int = 90,
        showsBalance: Bool = true,
        style: DurationStyle = .clock
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: noon,
            isClockRunning: running,
            clockStartedAt: startedAt,
            clockJobName: nil,
            todayWorkedMinutes: todayWorked,
            todayExpectedMinutes: todayExpected,
            monthWorkedMinutes: 6_000,
            monthExpectedMinutes: 6_000 - balance,
            monthBalanceMinutes: balance,
            showsBalance: showsBalance,
            unrecordedDayCount: 0,
            durationStyle: style,
            isUnlocked: true
        )
    }

    private func face(_ snapshot: WidgetSnapshot?, pending: [WatchCommand] = [], at instant: Date? = nil) -> WatchFace {
        WatchFace(snapshot: snapshot, pending: pending, at: instant ?? noon, calendar: calendar)
    }

    func testNothingFromThePhoneYetSaysSo() {
        let face = face(nil)

        XCTAssertFalse(face.hasData)
        XCTAssertEqual(face.action, .clockIn)
        XCTAssertFalse(face.isRunning)
    }

    /// "6:42 of 8:00", in the duration style the app uses.
    func testTodayReadsAsWorkedOfExpected() {
        let face = face(snapshot())

        XCTAssertTrue(face.hasData)
        XCTAssertEqual(face.workedText, "6:42")
        XCTAssertEqual(face.expectedText, "8:00")
        XCTAssertEqual(try XCTUnwrap(face.fraction), 402.0 / 480.0, accuracy: 0.0001)
    }

    func testTheDurationStyleIsTheApps() {
        let face = face(snapshot(style: .decimal))

        XCTAssertEqual(face.workedText, "6.70")
        XCTAssertEqual(face.expectedText, "8.00")
    }

    /// A day off has nothing to be measured against, and a ring at zero on a
    /// Sunday reads as a failure.
    func testADayOffHasNoExpectedFigure() {
        let face = face(snapshot(todayWorked: 0, todayExpected: 0))

        XCTAssertNil(face.expectedText)
        XCTAssertNil(face.fraction)
    }

    func testTheRunningClockCountsTowardsToday() {
        let start = noon.addingTimeInterval(-90 * 60)
        var snapshot = snapshot(running: true, startedAt: start, todayWorked: 60)
        snapshot.clockSiteName = "Trg Pravde"
        snapshot.clockJobName = "Bau GmbH"

        let face = face(snapshot)

        XCTAssertTrue(face.isRunning)
        XCTAssertEqual(face.runningSince, start)
        XCTAssertEqual(face.workedMinutes, 150)
        XCTAssertEqual(face.workedText, "2:30")
        XCTAssertEqual(face.place, "Trg Pravde")
        XCTAssertEqual(face.action, .clockOut)
    }

    func testTheJobNamesTheClockWhenThereIsNoSite() {
        var snapshot = snapshot(running: true, startedAt: noon)
        snapshot.clockJobName = "Bau GmbH"

        XCTAssertEqual(face(snapshot).place, "Bau GmbH")
    }

    func testAStoppedClockOffersClockingIn() {
        let face = face(snapshot())

        XCTAssertFalse(face.isRunning)
        XCTAssertNil(face.runningSince)
        XCTAssertNil(face.place)
        XCTAssertEqual(face.action, .clockIn)
    }

    /// Glanced at the next morning, yesterday's hours are not today's.
    func testYesterdaysSnapshotShowsNothingForToday() {
        let tomorrow = noon.addingTimeInterval(24 * 3600)
        let face = face(snapshot(), at: tomorrow)

        XCTAssertEqual(face.workedMinutes, 0)
        XCTAssertNil(face.expectedText)
    }

    // MARK: - The second figure

    func testTheMonthBalanceIsSigned() {
        XCTAssertEqual(face(snapshot(balance: 90)).secondary, .balance("+1:30", isBehind: false))
        XCTAssertEqual(face(snapshot(balance: -45)).secondary, .balance("\u{2212}0:45", isBehind: true))
    }

    func testWithTheBalanceSwitchedOffTheMonthsHoursShow() {
        XCTAssertEqual(face(snapshot(showsBalance: false)).secondary, .monthWorked("100:00"))
    }

    /// Earnings are in the snapshot only while they are the main figure, so
    /// their presence is that choice.
    func testEarningsLeadWhenTheyAreTheMainFigure() {
        var snapshot = snapshot()
        snapshot.earnings = WidgetEarnings(currencyCode: "EUR", todayCents: 12_000, weekCents: 40_000, monthCents: 182_550)

        let expected = MoneyFormatting(currencyCode: "EUR").string(182_550)
        XCTAssertEqual(face(snapshot).secondary, .earnings(expected))
    }

    // MARK: - Taps the phone has not heard about yet

    func testAWaitingClockInShowsTheClockRunningFromTheTap() {
        let tapped = noon.addingTimeInterval(-30 * 60)
        let face = face(snapshot(todayWorked: 60), pending: [WatchCommand(id: UUID(), kind: .clockIn, issuedAt: tapped)])

        XCTAssertTrue(face.isRunning)
        XCTAssertEqual(face.runningSince, tapped)
        XCTAssertEqual(face.workedMinutes, 90)
        XCTAssertEqual(face.action, .clockOut)
        XCTAssertTrue(face.isWaitingForPhone)
    }

    /// Until the phone records the shift, the watch keeps the minutes it ran
    /// for, so stopping the clock does not appear to throw them away.
    func testAWaitingClockOutKeepsTheMinutesItRan() {
        let start = noon.addingTimeInterval(-2 * 3600)
        let tapped = noon.addingTimeInterval(-30 * 60)
        let face = face(
            snapshot(running: true, startedAt: start, todayWorked: 60),
            pending: [WatchCommand(id: UUID(), kind: .clockOut, issuedAt: tapped)]
        )

        XCTAssertFalse(face.isRunning)
        XCTAssertEqual(face.workedMinutes, 60 + 90)
        XCTAssertEqual(face.action, .clockIn)
        XCTAssertTrue(face.isWaitingForPhone)
    }

    func testAWaitingTapThatChangesNothingIsStillShownAsWaiting() {
        let face = face(snapshot(), pending: [WatchCommand(id: UUID(), kind: .clockOut, issuedAt: noon)])

        XCTAssertFalse(face.isRunning)
        XCTAssertEqual(face.workedMinutes, 402)
        XCTAssertTrue(face.isWaitingForPhone)
    }

    func testInAndOutWhileThePhoneIsAwayAddUp() {
        let face = face(snapshot(todayWorked: 0), pending: [
            WatchCommand(id: UUID(), kind: .clockIn, issuedAt: noon.addingTimeInterval(-3 * 3600)),
            WatchCommand(id: UUID(), kind: .clockOut, issuedAt: noon.addingTimeInterval(-3600)),
        ])

        XCTAssertFalse(face.isRunning)
        XCTAssertEqual(face.workedMinutes, 120)
    }

    func testWithNothingWaitingTheFaceIsNotWaiting() {
        XCTAssertFalse(face(snapshot()).isWaitingForPhone)
    }
}
