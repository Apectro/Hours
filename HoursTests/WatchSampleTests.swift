import XCTest
@testable import Hours

/// The made-up figures the watch shows in its App Store screenshots: a
/// believable shift on the sample site, whatever hour the CI runner takes
/// them at.
final class WatchSampleTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// 14:20 on a Wednesday in Zagreb time.
    private var afternoon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 14, minute: 20))!
    }

    private func face(_ context: WatchContext, at instant: Date) -> WatchFace {
        WatchFace(snapshot: context.snapshot, pending: [], at: instant, calendar: calendar)
    }

    func testTheRunningShiftStartedAtSevenOnTheSampleSite() throws {
        let context = WatchSample.context(at: afternoon, calendar: calendar, clockRunning: true)
        let face = face(context, at: afternoon)

        XCTAssertTrue(face.hasData)
        XCTAssertTrue(face.isRunning)
        XCTAssertEqual(face.action, .clockOut)
        XCTAssertEqual(face.place, WatchSample.siteName)
        let since = try XCTUnwrap(face.runningSince)
        XCTAssertEqual(calendar.component(.hour, from: since), 7)
        XCTAssertEqual(calendar.component(.minute, from: since), 0)
        XCTAssertEqual(face.workedMinutes, 7 * 60 + 20)
        XCTAssertNotNil(face.expectedText, "a working day has hours expected")
    }

    /// Taken before seven, the shift cannot have started at seven: it is a
    /// couple of hours old, and never from yesterday.
    func testAnEarlyRunStillShowsAShiftFromToday() throws {
        let early = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 1, minute: 10))!
        let context = WatchSample.context(at: early, calendar: calendar, clockRunning: true)
        let since = try XCTUnwrap(face(context, at: early).runningSince)

        XCTAssertTrue(calendar.isDate(since, inSameDayAs: early), "the shift started yesterday")
        XCTAssertLessThan(since, early)
    }

    func testTheWrittenDayIsEightAndAHalfOfEight() {
        let context = WatchSample.context(at: afternoon, calendar: calendar, clockRunning: false)
        let face = face(context, at: afternoon)

        XCTAssertFalse(face.isRunning)
        XCTAssertEqual(face.action, .clockIn)
        XCTAssertEqual(face.workedMinutes, 8 * 60 + 30)
        XCTAssertEqual(face.expectedText, DurationFormatting(style: .hoursAndMinutes).string(8 * 60))
    }

    /// The month leads with euros, as the phone's sample month does, and the
    /// figure grows with the month rather than claiming a full month on the 2nd.
    func testTheMonthShowsEurosInProportionToTheDate() throws {
        let second = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 14))!
        let late = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 14))!

        let early = WatchSample.context(at: second, calendar: calendar, clockRunning: true).snapshot
        let later = WatchSample.context(at: late, calendar: calendar, clockRunning: true).snapshot

        XCTAssertEqual(early.earnings?.currencyCode, "EUR")
        let earlyCents = try XCTUnwrap(early.monthEarnings(at: second, calendar: calendar))
        let laterCents = try XCTUnwrap(later.monthEarnings(at: late, calendar: calendar))
        XCTAssertGreaterThan(earlyCents, 0)
        XCTAssertGreaterThan(laterCents, earlyCents * 5)
        if case .earnings = face(WatchContext(snapshot: later, handledCommandIDs: []), at: late).secondary {
        } else {
            XCTFail("the month should read as earnings")
        }
    }

    /// Only ever behind the launch argument, so a real watch never shows it.
    func testOnlyTheLaunchArgumentTurnsItOn() throws {
        XCTAssertNil(WatchSample.context(arguments: ["HoursWatch"], at: afternoon, calendar: calendar))

        let running = try XCTUnwrap(WatchSample.context(
            arguments: ["HoursWatch", WatchSample.launchArgument], at: afternoon, calendar: calendar
        ))
        XCTAssertTrue(running.snapshot.isClockRunning)

        let stopped = try XCTUnwrap(WatchSample.context(
            arguments: ["HoursWatch", WatchSample.launchArgument, WatchSample.clockStoppedArgument],
            at: afternoon, calendar: calendar
        ))
        XCTAssertFalse(stopped.snapshot.isClockRunning)
    }

    func testTheSnapshotSurvivesTheTripToTheWatch() throws {
        let context = WatchSample.context(at: afternoon, calendar: calendar, clockRunning: true)
        let data = try XCTUnwrap(context.encoded())
        XCTAssertEqual(WatchContext(data: data), context)
    }
}
