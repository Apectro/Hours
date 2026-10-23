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

        let schedule = settings.primarySchedules.latest
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
        XCTAssertEqual(settings.primarySchedules.latest.contractedMinutes(forWeekday: 2), 510)
    }

    // MARK: - Report language, crew and pay (1.1)

    func testTheNewAnswersStartFromTheSettings() {
        var settings = AppSettings()
        settings.export.language = .slovenian
        settings.leadsCrew = true
        settings.currencyCode = "CHF"
        settings.changePay(forJob: settings.primaryJob.id, to: PayRules(hourlyRateCents: 2_150), from: nil)

        let answers = FirstRunAnswers(settings: settings)

        XCTAssertEqual(answers.reportLanguage, .slovenian)
        XCTAssertTrue(answers.leadsCrew)
        XCTAssertEqual(answers.currencyCode, "CHF")
        XCTAssertEqual(answers.hourlyRateCents, 2_150)
    }

    func testAFreshInstallStartsWithThePhonesLanguageNoCrewAndNoRate() {
        let answers = FirstRunAnswers(settings: AppSettings())

        XCTAssertEqual(answers.reportLanguage, .device)
        XCTAssertFalse(answers.leadsCrew)
        XCTAssertNil(answers.currencyCode)
        XCTAssertEqual(answers.hourlyRateCents, 0)
    }

    /// Croatia: the sheets in Croatian and pay in euros — on a phone whose
    /// region pays in Swiss francs, so the euro has to be stored.
    func testPickingACountryPreselectsItsLanguageAndCurrency() {
        var answers = FirstRunAnswers(settings: AppSettings())

        answers.preselect(country: .hr, region: nil, settings: AppSettings(), deviceCurrency: "CHF")

        XCTAssertEqual(answers.reportLanguage, .croatian)
        XCTAssertEqual(answers.currencyCode, "EUR")
    }

    /// The phone's own currency is stored as none, as Settings › Pay does,
    /// so the phone keeps deciding.
    func testTheCountrysCurrencyIsNotStoredWhenThePhoneAlreadyUsesIt() {
        var answers = FirstRunAnswers(settings: AppSettings())

        answers.preselect(country: .at, region: nil, settings: AppSettings(), deviceCurrency: "EUR")

        XCTAssertEqual(answers.reportLanguage, .german)
        XCTAssertNil(answers.currencyCode)
    }

    func testWithoutACountryNothingIsPreselected() {
        var answers = FirstRunAnswers(settings: AppSettings())
        answers.reportLanguage = .dutch
        answers.currencyCode = "PLN"

        answers.preselect(country: nil, region: nil, settings: AppSettings(), deviceCurrency: "EUR")

        XCTAssertEqual(answers.reportLanguage, .device, "back to the setting: the phone's language, or English")
        XCTAssertNil(answers.currencyCode, "back to the phone's currency")
    }

    func testTheReportLanguageAndTheCrewAnswerAreWritten() {
        var settings = AppSettings()
        var answers = FirstRunAnswers(settings: settings)
        answers.reportLanguage = .croatian
        answers.leadsCrew = true

        answers.apply(to: &settings)

        XCTAssertEqual(settings.export.language, .croatian)
        XCTAssertTrue(settings.leadsCrew)
    }

    /// A rate is the primary job's pay since always, through the helper
    /// Settings › Pay saves with; the currency goes with it.
    func testARateSetsUpEarningsInTheChosenCurrency() {
        var settings = AppSettings()
        var answers = FirstRunAnswers(settings: settings)
        answers.hourlyRateCents = 1_850
        answers.currencyCode = "CHF"

        answers.apply(to: &settings)

        XCTAssertTrue(settings.earningsAreSetUp)
        XCTAssertEqual(settings.primaryJob.pay?.latest.hourlyRateCents, 1_850)
        XCTAssertEqual(settings.primaryJob.pay?.hasChanges, false)
        XCTAssertNil(settings.primaryJob.pay?.versions.first?.from, "since always")
        XCTAssertEqual(settings.currencyCode, "CHF")
    }

    /// Pay skipped: no rate, so no earnings and no currency stored either,
    /// even when the country preselected one.
    func testNoRateWritesNoPayAndNoCurrency() {
        var settings = AppSettings()
        var answers = FirstRunAnswers(settings: settings)
        answers.preselect(country: .pl, region: nil, settings: settings, deviceCurrency: "EUR")

        answers.apply(to: &settings)

        XCTAssertFalse(settings.earningsAreSetUp)
        XCTAssertNil(settings.currencyCode)
        XCTAssertEqual(settings.export.language, .polish, "the language step was answered")
    }

    /// A job that already has pay is left as it is: the wizard is not the
    /// place to rewrite a history of raises.
    func testExistingPayIsLeftAlone() {
        var settings = AppSettings()
        settings.changePay(forJob: settings.primaryJob.id, to: PayRules(hourlyRateCents: 2_000), from: nil)
        settings.changePay(forJob: settings.primaryJob.id, to: PayRules(hourlyRateCents: 2_200), from: Fixture.date(2026, 6, 1))
        let before = settings
        var answers = FirstRunAnswers(settings: settings)
        answers.hourlyRateCents = 2_500

        answers.apply(to: &settings)

        XCTAssertEqual(settings.primaryJob.pay, before.primaryJob.pay)
    }

    /// The new steps, continued past untouched, still change nothing.
    func testUntouchedNewAnswersChangeNothing() {
        var settings = AppSettings()
        settings.export.language = .italian
        settings.leadsCrew = true
        let before = settings

        FirstRunAnswers(settings: settings).apply(to: &settings)

        XCTAssertEqual(settings, before)
    }
}
