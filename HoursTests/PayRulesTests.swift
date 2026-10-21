import XCTest
@testable import Hours

/// How a job pays, and how that changes over time.
///
/// A raise from November must not rewrite October, for the same reason a new
/// contracted week must not: October was worked, and possibly paid, at the
/// old rate. So pay is kept the way the week is, as versions with the day
/// each one started.
final class PayRulesTests: XCTestCase {
    private let fifteen = PayRules(hourlyRateCents: 15_00)
    private let eighteen = PayRules(hourlyRateCents: 18_00)

    /// Monday 2 November 2026.
    private let november2 = Fixture.date(2026, 11, 2)

    // MARK: - Versions

    func testARateChangeAppliesFromItsOwnDay() {
        var history = PayHistory(fifteen)
        history.change(to: eighteen, from: november2)

        XCTAssertEqual(history.value(on: Fixture.date(2026, 10, 30)), fifteen)
        XCTAssertEqual(history.value(on: november2), eighteen)
        XCTAssertEqual(history.value(on: Fixture.date(2027, 1, 4)), eighteen)
    }

    func testItWasAlwaysLikeThisLeavesOneRate() {
        var history = PayHistory(fifteen)
        history.change(to: eighteen, from: november2)
        history.change(to: eighteen, from: nil)

        XCTAssertEqual(history.versions.count, 1)
        XCTAssertEqual(history.value(on: Fixture.date(2020, 1, 1)), eighteen)
    }

    // MARK: - Where pay lives

    func testNothingIsSetUpUntilARateIs() {
        let settings = Fixture.settings()

        XCTAssertNil(settings.primaryJob.pay)
        XCTAssertFalse(settings.earningsAreSetUp)
    }

    func testThePrimaryJobsPayLivesBesideTheScheduleWhileThereIsOneJob() {
        var settings = Fixture.settings()
        settings.changePay(forJob: Job.primaryID, to: fifteen, from: nil)

        XCTAssertTrue(settings.jobs.isEmpty, "setting a rate does not create a job list")
        XCTAssertEqual(settings.primaryJob.pay?.value(on: november2), fifteen)
        XCTAssertTrue(settings.earningsAreSetUp)
    }

    func testPayFollowsThePrimaryJobIntoTheJobListAndBack() {
        var settings = Fixture.settings()
        settings.changePay(forJob: Job.primaryID, to: fifteen, from: nil)
        let side = Job(name: "Side")
        settings.addJob(side)

        XCTAssertEqual(settings.primaryJob.pay?.value(on: november2), fifteen)
        XCTAssertNil(settings.job(side.id).pay, "a new job earns nothing until it has a rate")

        settings.removeJob(id: side.id)

        XCTAssertTrue(settings.jobs.isEmpty)
        XCTAssertEqual(settings.primaryJob.pay?.value(on: november2), fifteen)
    }

    func testEachJobKeepsItsOwnRate() {
        var settings = Fixture.settings()
        let side = Job(name: "Side")
        settings.addJob(side)
        settings.changePay(forJob: Job.primaryID, to: fifteen, from: nil)
        settings.changePay(forJob: side.id, to: eighteen, from: november2)

        XCTAssertEqual(settings.job(side.id).pay?.value(on: november2), eighteen)
        XCTAssertEqual(settings.job(side.id).pay?.value(on: Fixture.date(2026, 10, 1)), eighteen,
                       "a job's first rate is its rate since always")
        XCTAssertEqual(settings.primaryJob.pay?.value(on: november2), fifteen)
    }

    func testRemovingPayTurnsEarningsOff() {
        var settings = Fixture.settings()
        settings.changePay(forJob: Job.primaryID, to: fifteen, from: nil)
        settings.removePay(forJob: Job.primaryID)

        XCTAssertFalse(settings.earningsAreSetUp)
    }

    // MARK: - What is shown

    func testEarningsAreTheMainFigureOnceARateIsSet() {
        var settings = Fixture.settings()
        XCTAssertFalse(settings.showsEarnings, "no rate: the hours balance, as before")

        settings.changePay(forJob: Job.primaryID, to: fifteen, from: nil)
        XCTAssertTrue(settings.showsEarnings)

        settings.mainFigure = .hoursBalance
        XCTAssertFalse(settings.showsEarnings)
    }

    func testTheCurrencyFallsBackToTheOneGiven() {
        var settings = Fixture.settings()
        XCTAssertEqual(settings.currencyCode(fallback: "EUR"), "EUR")

        settings.currencyCode = "CHF"
        XCTAssertEqual(settings.currencyCode(fallback: "EUR"), "CHF")
    }

    // MARK: - Decoding

    func testOldSettingsDecodeWithNoPay() throws {
        let json = #"{"schemaVersion":1,"jobs":[{"id":"00000000-0000-4000-8000-000000000001","name":"Work"}]}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertNil(settings.primaryJob.pay)
        XCTAssertFalse(settings.earningsAreSetUp)
        XCTAssertEqual(settings.mainFigure, .earnings)
        XCTAssertNil(settings.currencyCode)
        XCTAssertFalse(settings.export.includeEarnings)
    }

    func testPaySurvivesARoundTrip() throws {
        var settings = Fixture.settings()
        var rules = fifteen
        rules.overtimeMode = .afterWeeklyHours
        rules.overtimePercent = 25
        rules.weeklyThresholdMinutes = 38 * 60
        rules.saturdayPercent = 25
        rules.sundayAndHolidayPercent = 50
        rules.nightPercent = 10
        rules.nightStart = Fixture.time(23)
        rules.nightEnd = Fixture.time(5)
        rules.paidAbsenceEarns = false
        settings.changePay(forJob: Job.primaryID, to: rules, from: nil)
        settings.changePay(forJob: Job.primaryID, to: eighteen, from: november2)
        settings.currencyCode = "CHF"
        settings.mainFigure = .hoursBalance

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.primaryJob.pay?.value(on: Fixture.date(2026, 10, 1)), rules)
    }

    func testPayRulesDecodeLeniently() throws {
        let json = #"{"hourlyRateCents":1250}"#
        let rules = try JSONDecoder().decode(PayRules.self, from: Data(json.utf8))

        XCTAssertEqual(rules.hourlyRateCents, 1250)
        XCTAssertEqual(rules.overtimeMode, .sameRate)
        XCTAssertEqual(rules.nightStart, Fixture.time(22))
        XCTAssertEqual(rules.nightEnd, Fixture.time(6))
        XCTAssertTrue(rules.paidAbsenceEarns)
    }

    func testANegativeRateOrPercentIsReadAsNothing() {
        let rules = PayRules(hourlyRateCents: -5, overtimePercent: -10, saturdayPercent: -1)

        XCTAssertEqual(rules.hourlyRateCents, 0)
        XCTAssertEqual(rules.overtimePercent, 0)
        XCTAssertEqual(rules.saturdayPercent, 0)
    }
}
