import XCTest
@testable import Hours

/// What the phone and the watch say to each other, and what the phone does
/// with a command that may arrive late, twice, or after the clock moved on.
final class WatchLinkTests: XCTestCase {
    private let nine = Date(timeIntervalSince1970: 1_787_130_000)
    private let calendar = Fixture.calendar()

    private func command(_ kind: WatchCommand.Kind, at instant: Date, id: UUID = UUID()) -> WatchCommand {
        WatchCommand(id: id, kind: kind, issuedAt: instant)
    }

    // MARK: - Coding

    func testACommandReadsBackAsItself() throws {
        let sent = command(.clockOut, at: nine)
        let data = try XCTUnwrap(sent.encoded())

        XCTAssertEqual(WatchCommand(data: data), sent)
    }

    func testTheContextReadsBackAsItself() throws {
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = nine
        snapshot.isClockRunning = true
        snapshot.clockStartedAt = nine.addingTimeInterval(-3600)
        snapshot.todayWorkedMinutes = 125
        let sent = WatchContext(snapshot: snapshot, handledCommandIDs: [UUID(), UUID()])
        let data = try XCTUnwrap(sent.encoded())

        XCTAssertEqual(WatchContext(data: data), sent)
    }

    /// A watch app updated before the phone app, or the other way round,
    /// reads what it can rather than nothing.
    func testAContextWithoutHandledCommandsStillReads() throws {
        let snapshot = try JSONEncoder().encode(WidgetSnapshot.empty)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot) as? [String: Any])
        let data = try JSONSerialization.data(withJSONObject: ["snapshot": object])

        let context = try XCTUnwrap(WatchContext(data: data))
        XCTAssertEqual(context.handledCommandIDs, [])
    }

    func testGarbageIsNotACommandOrAContext() {
        let garbage = Data("not json".utf8)
        XCTAssertNil(WatchCommand(data: garbage))
        XCTAssertNil(WatchContext(data: garbage))
    }

    // MARK: - What the phone does

    func testClockingInStartsWhenTheWatchWasTapped() {
        var ledger = WatchCommandLedger()
        let tapped = nine.addingTimeInterval(-2 * 3600)

        let decision = ledger.decide(command(.clockIn, at: tapped), runningSince: nil, now: nine)

        // Queued at seven and delivered at nine still starts at seven: the
        // two hours were worked whether or not the phone was in reach.
        XCTAssertEqual(decision, .clockIn(at: tapped))
    }

    func testClockingInWhileRunningLeavesTheClockAlone() {
        var ledger = WatchCommandLedger()
        let decision = ledger.decide(
            command(.clockIn, at: nine),
            runningSince: nine.addingTimeInterval(-600),
            now: nine
        )

        XCTAssertEqual(decision, .ignore(.alreadyRunning))
    }

    func testClockingOutStopsWhenTheWatchWasTapped() {
        var ledger = WatchCommandLedger()
        let tapped = nine.addingTimeInterval(-600)

        let decision = ledger.decide(
            command(.clockOut, at: tapped),
            runningSince: nine.addingTimeInterval(-3 * 3600),
            now: nine
        )

        XCTAssertEqual(decision, .clockOut(at: tapped))
    }

    func testClockingOutWithNothingRunningDoesNothing() {
        var ledger = WatchCommandLedger()

        XCTAssertEqual(
            ledger.decide(command(.clockOut, at: nine), runningSince: nil, now: nine),
            .ignore(.nothingRunning)
        )
    }

    /// A clock-out tapped before the running clock was started belongs to an
    /// earlier shift, already ended on the phone. Obeying it would stop the
    /// new shift at a time before it began.
    func testAClockOutOlderThanTheRunningClockIsIgnored() {
        var ledger = WatchCommandLedger()

        let decision = ledger.decide(
            command(.clockOut, at: nine.addingTimeInterval(-3600)),
            runningSince: nine.addingTimeInterval(-600),
            now: nine
        )

        XCTAssertEqual(decision, .ignore(.predatesRunningClock))
    }

    /// The watch's clock and the phone's can disagree by a little; a command
    /// from "the future" happens now rather than later.
    func testACommandFromTheFutureHappensNow() {
        var ledger = WatchCommandLedger()
        let later = nine.addingTimeInterval(90)

        XCTAssertEqual(
            ledger.decide(command(.clockIn, at: later), runningSince: nil, now: nine),
            .clockIn(at: nine)
        )
        XCTAssertEqual(
            ledger.decide(command(.clockOut, at: later), runningSince: nine.addingTimeInterval(-60), now: nine),
            .clockOut(at: nine)
        )
    }

    /// A message whose reply was lost is sent again as a queued transfer, so
    /// the same command can arrive twice. The second is not obeyed — after a
    /// clock-out and a new clock-in it would otherwise start a shift nobody
    /// asked for.
    func testTheSameCommandIsOnlyObeyedOnce() {
        var ledger = WatchCommandLedger()
        let clockIn = command(.clockIn, at: nine.addingTimeInterval(-3600))

        XCTAssertEqual(ledger.decide(clockIn, runningSince: nil, now: nine), .clockIn(at: clockIn.issuedAt))
        XCTAssertEqual(ledger.decide(clockIn, runningSince: nil, now: nine), .ignore(.alreadyHandled))
    }

    /// Every command the phone has seen is reported back, ignored or not, so
    /// the watch can stop showing it as waiting.
    func testTheLedgerRemembersEveryCommandItSaw() {
        var ledger = WatchCommandLedger()
        let obeyed = command(.clockIn, at: nine)
        let ignored = command(.clockIn, at: nine)

        _ = ledger.decide(obeyed, runningSince: nil, now: nine)
        _ = ledger.decide(ignored, runningSince: nine, now: nine)

        XCTAssertEqual(ledger.handledIDs, [obeyed.id, ignored.id])
    }

    func testTheLedgerKeepsOnlyTheMostRecentCommands() {
        var ledger = WatchCommandLedger()
        let commands = (0..<(WatchCommandLedger.capacity + 5)).map { _ in command(.clockOut, at: nine) }
        for command in commands {
            _ = ledger.decide(command, runningSince: nil, now: nine)
        }

        XCTAssertEqual(ledger.handledIDs, commands.suffix(WatchCommandLedger.capacity).map(\.id))
    }

    func testTheLedgerSurvivesBeingStored() throws {
        var ledger = WatchCommandLedger()
        _ = ledger.decide(command(.clockIn, at: nine), runningSince: nil, now: nine)

        let data = try JSONEncoder().encode(ledger)
        XCTAssertEqual(try JSONDecoder().decode(WatchCommandLedger.self, from: data), ledger)
    }

    // MARK: - What the watch keeps waiting

    func testTheWatchStopsWaitingForWhatThePhoneHandled() {
        let handled = command(.clockIn, at: nine.addingTimeInterval(-60))
        let waiting = command(.clockOut, at: nine)

        let left = WatchCommand.stillWaiting([handled, waiting], handled: [handled.id], now: nine)

        XCTAssertEqual(left, [waiting])
    }

    /// A command the phone never answers — the phone app deleted, or the
    /// watch paired to another phone — must not leave the watch showing a
    /// shift that is not happening for ever.
    func testAWaitingCommandIsDroppedAfterADay() {
        let old = command(.clockIn, at: nine.addingTimeInterval(-25 * 3600))
        let recent = command(.clockOut, at: nine.addingTimeInterval(-23 * 3600))

        XCTAssertEqual(WatchCommand.stillWaiting([old, recent], handled: [], now: nine), [recent])
    }
}
