import XCTest
@testable import Hours

/// The three questions a fresh install asks once, and who is never asked them.
final class FirstRunSetupTests: XCTestCase {
    // MARK: - Who is asked

    func testAFreshInstallIsAsked() {
        XCTAssertEqual(FirstRunSetup.decide(isDone: false, hasStoredData: false, settings: AppSettings()), .show)
    }

    func testOnceDoneNeverAgain() {
        XCTAssertEqual(FirstRunSetup.decide(isDone: true, hasStoredData: false, settings: AppSettings()), .nothing)
    }

    /// Someone updating from a version without the setup has days, or has
    /// changed a setting. They are not asked, and that is remembered, so
    /// clearing their data later does not suddenly ask them.
    func testSomeoneWithDataIsNotAskedAndThatIsRemembered() {
        XCTAssertEqual(FirstRunSetup.decide(isDone: false, hasStoredData: true, settings: AppSettings()), .skip)
    }

    func testSomeoneWhoChangedAnySettingIsNotAsked() {
        var settings = AppSettings()
        settings.displayDurationStyle = .decimal

        XCTAssertEqual(FirstRunSetup.decide(isDone: false, hasStoredData: false, settings: settings), .skip)
    }

    // MARK: - The answers

    /// Continuing through every step without changing anything must leave a
    /// fresh install exactly as it was: the defaults are already the answers.
    func testUntouchedAnswersChangeNothing() {
        var settings = AppSettings()

        FirstRunAnswers(settings: settings).apply(to: &settings)

        XCTAssertEqual(settings, AppSettings())
    }

    func testTheAnswersStartFromTheSettings() {
        let answers = FirstRunAnswers(settings: AppSettings())

        XCTAssertEqual(answers.name, "")
        XCTAssertEqual(answers.workingWeekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(answers.start, TimeOfDay(hour: 8, minute: 0))
        XCTAssertEqual(answers.end, TimeOfDay(hour: 16, minute: 30))
        XCTAssertEqual(answers.breakMinutes, 30)
        XCTAssertFalse(answers.breaksArePaid)
        XCTAssertEqual(answers.dailyMinutes, 480)
    }

    func testTheNameGoesOnTheSheets() {
        var settings = AppSettings()
        var answers = FirstRunAnswers(settings: settings)
        answers.name = "  Marijo Mikša "

        answers.apply(to: &settings)

        XCTAssertEqual(settings.export.ownerName, "Marijo Mikša")
    }

    /// Four days of 07:00–17:30 with an unpaid half hour: ten hours on each
    /// day ticked, nothing on the others, and the day editor's defaults to
    /// match.
    func testTheWeekBecomesThePrimarySchedule() {
        var settings = AppSettings()
        var answers = FirstRunAnswers(settings: settings)
        answers.workingWeekdays = [2, 3, 4, 5]
        answers.start = TimeOfDay(hour: 7, minute: 0)
        answers.end = TimeOfDay(hour: 17, minute: 30)

        answers.apply(to: &settings)

        let schedule = settings.primarySchedule
        XCTAssertEqual(schedule.minutesByWeekday, [0, 600, 600, 600, 600, 0, 0])
        XCTAssertEqual(schedule.defaultStart, TimeOfDay(hour: 7, minute: 0))
        XCTAssertEqual(schedule.defaultEnd, TimeOfDay(hour: 17, minute: 30))
        XCTAssertEqual(schedule.defaultBreakMinutes, 30)
    }

    /// A paid break is part of the day, so the same shift is worth the
    /// whole of its length.
    func testPaidBreaksAreSetAndCountInTheDay() {
        var settings = AppSettings()
        var answers = FirstRunAnswers(settings: settings)
        answers.breaksArePaid = true

        answers.apply(to: &settings)

        XCTAssertTrue(settings.primaryJob.breaksArePaid)
        XCTAssertEqual(answers.dailyMinutes, 510)
        XCTAssertEqual(settings.primarySchedule.contractedMinutes(forWeekday: 2), 510)
    }
}
