import XCTest
@testable import Hours

/// Changing many days at once.
final class BulkEditTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// Monday 3 August to Friday 14 August 2026: twelve days, of which ten are
    /// working days and two are the weekend of the 8th and 9th.
    private var fortnight: CalendarDateRange {
        CalendarDateRange(start: Fixture.workingMonday, end: Fixture.date(2026, 8, 14))
    }

    private func plan(
        _ action: BulkAction,
        existing: [Int: DayRecord] = [:],
        skipsNonWorking: Bool = true,
        overwrites: Bool = false,
        settings: AppSettings = Fixture.settings(),
        holidays: [HolidayRule] = []
    ) -> BulkEditPlan {
        BulkEditor.plan(
            BulkEditRequest(
                range: fortnight,
                action: action,
                skipsNonWorkingDays: skipsNonWorking,
                overwritesExistingEntries: overwrites
            ),
            existing: existing,
            settings: settings,
            calendar: calendar,
            holidays: holidays
        )
    }

    func testAFortnightOfLeaveTouchesOnlyTheWorkingDays() {
        let result = plan(.setDayType(.vacation))

        XCTAssertEqual(result.changes.count, 10)
        XCTAssertEqual(result.skippedNonWorking, 2)
        XCTAssertTrue(result.changes.allSatisfy { $0.dayTypeID == .vacation })
    }

    func testIncludingNonWorkingDaysWhenAsked() {
        let result = plan(.setDayType(.vacation), skipsNonWorking: false)

        XCTAssertEqual(result.changes.count, 12)
        XCTAssertEqual(result.skippedNonWorking, 0)
    }

    func testLeaveRemovesHoursBecauseADayOffHasNoneInIt() {
        let worked = DayRecord(
            date: Fixture.workingTuesday,
            start: Fixture.time(8),
            end: Fixture.time(16)
        )
        let result = plan(
            .setDayType(.vacation),
            existing: [worked.date.key: worked],
            overwrites: true
        )

        let tuesday = result.changes.first { $0.date == Fixture.workingTuesday }
        XCTAssertEqual(tuesday?.dayTypeID, .vacation)
        XCTAssertTrue(tuesday?.shifts.isEmpty ?? false, "crediting the absence and counting the work would double it")
    }

    func testDaysAlreadyRecordedAreLeftAloneByDefault() {
        let worked = DayRecord(
            date: Fixture.workingTuesday,
            start: Fixture.time(8),
            end: Fixture.time(16)
        )
        let result = plan(.setDayType(.vacation), existing: [worked.date.key: worked])

        XCTAssertEqual(result.changes.count, 9)
        XCTAssertEqual(result.skippedExisting, 1)
        XCTAssertNil(result.changes.first { $0.date == Fixture.workingTuesday })
    }

    func testABlankRecordDoesNotCountAsAlreadyRecorded() {
        let blank = DayRecord(date: Fixture.workingTuesday)
        let result = plan(.setDayType(.vacation), existing: [blank.date.key: blank])

        XCTAssertEqual(result.changes.count, 10)
        XCTAssertEqual(result.skippedExisting, 0)
    }

    // MARK: - Filling hours

    func testFillingHoursUsesTheUsualPattern() {
        let result = plan(.applyWorkingPattern)

        XCTAssertEqual(result.changes.count, 10)
        let first = result.changes[0]
        XCTAssertEqual(first.start, Fixture.time(8))
        XCTAssertEqual(first.end, Fixture.time(16, 30))
        XCTAssertEqual(first.breaks.first?.explicitMinutes, 30)
        XCTAssertNil(first.dayTypeID, "left automatic, so holidays and weekends still resolve themselves")
    }

    func testFillingHoursLeavesAPublicHolidayAlone() {
        let holiday = HolidayRule(name: "Assumption", recurrence: .annual(month: 8, day: 5))
        let result = plan(.applyWorkingPattern, holidays: [holiday])

        XCTAssertEqual(result.changes.count, 9)
        XCTAssertNil(result.changes.first { $0.date == Fixture.date(2026, 8, 5) })
        XCTAssertEqual(result.skippedNonWorking, 3, "the two weekend days and the holiday")
    }

    func testAWorkingHolidayIsFilledLikeAnyOtherDay() {
        let holiday = HolidayRule(
            name: "Company day",
            recurrence: .annual(month: 8, day: 5),
            countsAsWorkingDay: true
        )
        let result = plan(.applyWorkingPattern, holidays: [holiday])

        XCTAssertEqual(result.changes.count, 10)
        XCTAssertNotNil(result.changes.first { $0.date == Fixture.date(2026, 8, 5) })
    }

    // MARK: - Clearing

    func testClearingOnlyDeletesDaysThatHadSomething() {
        let worked = DayRecord(date: Fixture.workingTuesday, start: Fixture.time(8), end: Fixture.time(16))
        let result = plan(.clear, existing: [worked.date.key: worked], overwrites: true)

        XCTAssertEqual(result.deletions, [Fixture.workingTuesday])
        XCTAssertTrue(result.changes.isEmpty)
        XCTAssertEqual(result.affectedDayCount, 1)
    }

    func testClearingWithoutPermissionToOverwriteChangesNothing() {
        let worked = DayRecord(date: Fixture.workingTuesday, start: Fixture.time(8), end: Fixture.time(16))
        let result = plan(.clear, existing: [worked.date.key: worked])

        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(result.skippedExisting, 1)
    }

    // MARK: - With several jobs

    func testFillingHoursUsesThePrimaryJobsPattern() {
        var settings = Fixture.settings()
        let side = Job(
            id: UUID(),
            name: "Side",
            schedule: WorkSchedule(minutesByWeekday: [0, 0, 240, 0, 0, 0, 0]),
            sortOrder: 1
        )
        settings.jobs = [Job.primary(schedule: WorkSchedule()), side]

        let result = plan(.applyWorkingPattern, settings: settings)

        XCTAssertEqual(result.changes.first?.shifts.first?.jobID, Job.primaryID)
        XCTAssertEqual(result.changes.first?.start, Fixture.time(8))
    }
}
