import XCTest
@testable import Hours

/// Every switch in Settings must reach the engine, or say that it doesn't.
///
/// The two worst bugs this app has had were the same bug twice. A weekly target
/// the user could type, that was stored, that was displayed back to them
/// correctly — and that nothing in the calculation ever read. And a worked
/// figure that went on outranking the clock long after the setting that
/// produced it was switched off. Both were silent. Both were wrong in the
/// direction of money. Neither was caught by two hundred passing tests, because
/// a test that was never written cannot fail.
///
/// Writing two more specific tests would only catch those two. The failure is
/// not really arithmetic, it is *reach*: a control that claims to change a
/// calculation and does not. So this asserts reach directly, and asserts it
/// exhaustively — `Mirror` enumerates the toggles, and a toggle that appears in
/// neither table below fails the suite until somebody decides which it is.
/// Adding a setting and forgetting to wire it up is now a red build rather than
/// a quiet subtraction from somebody's year.
final class SettingsReachTests: XCTestCase {
    private let date = Fixture.workingTuesday

    // MARK: - The record every toggle is tried against

    /// One day carrying something for every toggle to act on: times, a break, a
    /// note, a location, a tag, an adjustment, a per-day expectation and a
    /// typed worked figure. A toggle that changes nothing here changes nothing.
    private func loadedRecord() -> DayRecord {
        var record = Fixture.record(
            on: date,
            start: Fixture.time(8),
            end: Fixture.time(16, 30),
            breaks: [.duration(30)]
        )
        record.note = "note"
        record.location = "office"
        record.tags = ["tag"]
        record.adjustmentMinutes = 45
        record.expectedOverrideMinutes = 300
        record.manualWorkedMinutes = 400
        return record
    }

    /// Flips one toggle and returns what the engine produced either way.
    private func computations(
        flipping change: (inout FeatureToggles) -> Void,
        record: DayRecord,
        holiday: HolidayRule? = nil
    ) -> (on: DayComputation, off: DayComputation) {
        var flipped = FeatureToggles()
        change(&flipped)

        func compute(_ features: FeatureToggles) -> DayComputation {
            Fixture.calculator(settings: Fixture.settings(features: features))
                .compute(record: record, on: date, holiday: holiday)
        }
        return (compute(FeatureToggles()), compute(flipped))
    }

    /// Everything about a day that the user can see and that a toggle might
    /// move. Compared as one value so a toggle reaching *any* of it counts.
    private func fingerprint(_ day: DayComputation) -> String {
        [
            day.dayType.id.rawValue,
            "\(day.workedMinutes)", "\(day.creditedMinutes)", "\(day.expectedMinutes)",
            "\(day.breakMinutes)", "\(day.adjustmentMinutes)", "\(day.balanceMinutes)",
            day.note, day.location, day.tags.joined(separator: ","),
            day.holidayName ?? "—"
        ].joined(separator: "|")
    }

    // MARK: - The toggles that must reach the engine

    func testEveryCalculationToggleActuallyChangesACalculation() {
        let record = loadedRecord()
        let holiday = HolidayRule(name: "Holiday", recurrence: .annual(month: 8, day: 4))

        // Each entry flips one toggle away from its default and says nothing
        // more; the assertion is simply that the day comes out different.
        let flips: [(name: String, change: (inout FeatureToggles) -> Void)] = [
            ("trackBreaks", { $0.trackBreaks = false }),
            ("trackExpectedHours", { $0.trackExpectedHours = false }),
            ("trackOvertime", { $0.trackOvertime = false }),
            ("trackHolidays", { $0.trackHolidays = false }),
            ("trackNotes", { $0.trackNotes = false }),
            ("trackLocation", { $0.trackLocation = true }),
            ("trackTags", { $0.trackTags = true }),
            ("allowManualAdjustments", { $0.allowManualAdjustments = false }),
            ("allowPerDayExpectedOverride", { $0.allowPerDayExpectedOverride = false }),
            ("autoCalculateWorkedHours", { $0.autoCalculateWorkedHours = false }),
            ("autoCalculateOvertime", { $0.autoCalculateOvertime = false })
        ]

        for flip in flips {
            let pair = computations(flipping: flip.change, record: record, holiday: holiday)
            XCTAssertNotEqual(
                fingerprint(pair.on),
                fingerprint(pair.off),
                "\(flip.name) is a switch in Settings that changes nothing the engine computes"
            )
        }

        XCTAssertEqual(
            Set(flips.map(\.name)).count,
            flips.count,
            "a toggle is listed twice, so one of them is not being tried"
        )
    }

    /// Toggles that legitimately only move the interface.
    ///
    /// Listed rather than omitted: an exemption should be a decision somebody
    /// wrote down, not a gap. `multipleBreaksPerDay` decides whether you may
    /// *add* a second break — a break already recorded still happened, and is
    /// still deducted. `useTimeClock` shows or hides a button.
    private static let cosmeticToggles: Set<String> = [
        "multipleBreaksPerDay",
        "useTimeClock"
    ]

    private static let calculationToggles: Set<String> = [
        "trackBreaks", "trackExpectedHours", "trackOvertime", "trackHolidays",
        "trackNotes", "trackLocation", "trackTags", "allowManualAdjustments",
        "allowPerDayExpectedOverride", "autoCalculateWorkedHours",
        "autoCalculateOvertime"
    ]

    /// The tripwire. A toggle added tomorrow and wired to nothing fails here.
    func testEveryToggleIsAccountedForOneWayOrTheOther() {
        let known = SettingsReachTests.calculationToggles
            .union(SettingsReachTests.cosmeticToggles)
        let actual = Set(Mirror(reflecting: FeatureToggles()).children.compactMap(\.label))

        XCTAssertFalse(actual.isEmpty, "reflection found no toggles, so this test proves nothing")

        XCTAssertEqual(
            actual.subtracting(known),
            [],
            """
            A new toggle exists that no test has an opinion about. Add it to \
            calculationToggles if it is meant to change what the app computes \
            — and then to the flips above, which will fail until it does — or \
            to cosmeticToggles if it only moves the interface.
            """
        )
        XCTAssertEqual(
            known.subtracting(actual),
            [],
            "a toggle named here no longer exists, so its case is being skipped silently"
        )
    }

    // MARK: - The same property, for the schedule

    /// The weekly override was the first instance of this bug, and it lives on
    /// `WorkSchedule` rather than on the toggles, so reflection above cannot
    /// see it. Held to the same standard by hand.
    func testTheContractedWeekReachesTheEngine() {
        let record = Fixture.record(on: date, start: Fixture.time(8), end: Fixture.time(16, 30))

        var shortened = WorkSchedule()
        shortened.weeklyTargetOverrideMinutes = 37 * 60 + 30

        let asWritten = Fixture.calculator(settings: Fixture.settings())
            .compute(record: record, on: date)
        let asContracted = Fixture.calculator(settings: Fixture.settings(schedule: shortened))
            .compute(record: record, on: date)

        XCTAssertEqual(asWritten.expectedMinutes, 480)
        XCTAssertEqual(asContracted.expectedMinutes, 450, "37½ hours over five days is 7½ a day")
        XCTAssertNotEqual(
            asWritten.balanceMinutes,
            asContracted.balanceMinutes,
            "the weekly target is displayed in Settings and must be what the balance uses"
        )
    }

    /// Rounding and the duration policy are settings too, and the same argument
    /// applies to them.
    func testRoundingAndTheDurationPolicyReachTheEngine() {
        let record = Fixture.record(on: date, start: Fixture.time(8), end: Fixture.time(16, 22))

        let exact = Fixture.calculator(settings: Fixture.settings(rounding: .exact))
            .compute(record: record, on: date)
        let quarter = Fixture.calculator(settings: Fixture.settings(rounding: .nearestQuarterHour))
            .compute(record: record, on: date)

        XCTAssertEqual(exact.workedMinutes, 502)
        XCTAssertEqual(quarter.workedMinutes, 495, "8h 22m to the nearest quarter is 8h 15m")

        // The policy only diverges on a day the clocks change, which is what
        // DaylightSavingTests covers in full; this asserts the setting is read
        // at all rather than re-testing the arithmetic. Midnight to eight on
        // the autumn Sunday is the case that spans the 03:00 transition.
        let night = Fixture.record(on: Fixture.fallBack, start: Fixture.time(0), end: Fixture.time(8))
        let wall = Fixture.calculator(settings: Fixture.settings(durationPolicy: .wallClock))
            .compute(record: night, on: Fixture.fallBack)
        let elapsed = Fixture.calculator(settings: Fixture.settings(durationPolicy: .elapsedReal))
            .compute(record: night, on: Fixture.fallBack)

        XCTAssertEqual(wall.workedMinutes, 480)
        XCTAssertEqual(elapsed.workedMinutes, 540, "an hour was lived through twice")
        XCTAssertNotEqual(
            wall.workedMinutes,
            elapsed.workedMinutes,
            "the duration policy is a setting and must be read on a clock-change night"
        )
    }
}
