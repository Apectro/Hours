import XCTest
@testable import Hours

/// The weekly note that finished extra work has not reached the boss yet:
/// what it says, and where a tap on it leads.
final class ExtraWorkReminderPlanTests: XCTestCase {
    private let trg = Site(name: "Trg Pravde", sortOrder: 0)
    private let kai = Site(name: "Kaiserstrasse 12", sortOrder: 1)

    private func job(_ site: Site, done: Bool = true, status: ExtraWorkStatus = .open,
                     doneAt: Date? = nil, sentAt: Date? = nil) -> ExtraWorkJob {
        ExtraWorkJob(siteID: site.id, date: Fixture.date(2026, 10, 20), description: "Socket",
                     isDone: done, doneAt: doneAt, status: status, sentAt: sentAt)
    }

    func testNothingPendingSaysNothing() {
        XCTAssertNil(ExtraWorkReminderPlan.reminder(sites: [trg, kai], jobs: []))
        XCTAssertNil(ExtraWorkReminderPlan.reminder(sites: [trg], jobs: [job(trg, status: .sent)]))
    }

    /// The boss hears what is done; a job still in progress is not news yet.
    func testJobsStillInProgressAreNotCounted() {
        XCTAssertNil(ExtraWorkReminderPlan.reminder(sites: [trg], jobs: [job(trg, done: false)]))
    }

    func testOneSiteNamesTheSiteAndOpensItsReport() throws {
        let jobs = [job(trg), job(trg), job(trg), job(trg, done: false), job(trg, status: .sent)]
        let reminder = try XCTUnwrap(ExtraWorkReminderPlan.reminder(sites: [trg, kai], jobs: jobs))

        XCTAssertEqual(reminder.count, 3)
        XCTAssertEqual(reminder.scope, .site(id: trg.id, name: "Trg Pravde"))
        XCTAssertEqual(reminder.link, .siteExtraWork(trg.id))
    }

    /// Sent while still under way and finished since: the boss has not heard
    /// it is done, so it is waiting again, as the report has it.
    func testAJobFinishedSinceItWasSentCounts() throws {
        let sent = Date(timeIntervalSince1970: 1_790_000_000)
        let finished = job(trg, status: .sent, doneAt: sent.addingTimeInterval(3600), sentAt: sent)
        let reminder = try XCTUnwrap(ExtraWorkReminderPlan.reminder(sites: [trg], jobs: [finished]))
        XCTAssertEqual(reminder.count, 1)
    }

    func testSeveralSitesGiveTheTotalAndOpenTheSites() throws {
        let jobs = [job(trg), job(trg), job(kai)]
        let reminder = try XCTUnwrap(ExtraWorkReminderPlan.reminder(sites: [trg, kai], jobs: jobs))

        XCTAssertEqual(reminder.count, 3)
        XCTAssertEqual(reminder.scope, .sites(2))
        XCTAssertEqual(reminder.link, .sites)
    }

    /// An archived site is finished with, and a job whose site is gone has
    /// nowhere to be reported from: neither is something to nag about.
    func testArchivedAndUnknownSitesAreLeftOut() throws {
        var old = Site(name: "Altbau", sortOrder: 2)
        old.isArchived = true
        let stray = Site(name: "Gone", sortOrder: 3)
        let jobs = [job(trg), job(old), job(stray)]
        let reminder = try XCTUnwrap(ExtraWorkReminderPlan.reminder(sites: [trg, old], jobs: jobs))

        XCTAssertEqual(reminder.count, 1)
        XCTAssertEqual(reminder.scope, .site(id: trg.id, name: "Trg Pravde"))
    }

    // MARK: - Preferences

    /// Off by default, and Friday at three when switched on.
    func testTheReminderIsOffByDefaultOnFridayAtThree() {
        let prefs = ReminderPreferences()
        XCTAssertFalse(prefs.unsentWorkEnabled)
        XCTAssertEqual(prefs.unsentWorkWeekday, 6, "1 is Sunday, so 6 is Friday")
        XCTAssertEqual(prefs.unsentWorkTime, TimeOfDay(hour: 15, minute: 0))
    }

    /// A blob written before the reminder existed decodes to its defaults.
    func testOlderStoredPreferencesDecodeWithTheDefaults() throws {
        let old = #"{"isEnabled":true,"weekday":2,"time":{"hour":8,"minute":0},"lookBackDays":7}"#
        let prefs = try JSONDecoder().decode(ReminderPreferences.self, from: Data(old.utf8))
        XCTAssertFalse(prefs.unsentWorkEnabled)
        XCTAssertEqual(prefs.unsentWorkWeekday, 6)
        XCTAssertEqual(prefs.unsentWorkTime, TimeOfDay(hour: 15, minute: 0))
    }

    func testTheReminderSettingsRoundTrip() throws {
        let prefs = ReminderPreferences(unsentWorkEnabled: true, unsentWorkWeekday: 2, unsentWorkTime: TimeOfDay(hour: 7, minute: 45))
        let back = try JSONDecoder().decode(ReminderPreferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertEqual(back, prefs)
        XCTAssertEqual(ReminderPreferences(unsentWorkWeekday: 12).unsentWorkWeekday, 7, "a weekday is 1...7")
    }
}
