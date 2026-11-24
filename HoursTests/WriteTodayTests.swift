import XCTest
@testable import Hours

/// "Write today's hours" (2026-11-24): which sites the question lists and
/// what each says about today.
final class WriteTodayTests: XCTestCase {
    private let today = Fixture.date(2026, 11, 24)
    private let jarun = Site(name: "Jarunski Dvori", sortOrder: 0)
    private let trg = Site(name: "Trg Pravde", sortOrder: 1)

    private func time(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    private func written(_ site: Site, people: Int, on date: CalendarDate? = nil) -> SiteDay {
        SiteDay(
            siteID: site.id,
            date: date ?? today,
            start: time(7),
            end: time(12),
            present: (0..<people).map { _ in Attendance(memberID: UUID()) }
        )
    }

    func testWithNoSiteTheButtonIsNotOffered() {
        XCTAssertFalse(WriteToday.isOffered(sites: [], settings: Fixture.settings(), today: today))
    }

    func testAnActiveSiteOffersIt() {
        XCTAssertTrue(WriteToday.isOffered(sites: [jarun], settings: Fixture.settings(), today: today))
    }

    func testOnlyArchivedOrPausedSitesDoNotOfferIt() {
        var archived = jarun
        archived.isArchived = true
        var settings = Fixture.settings()
        var setup = SiteSetup()
        setup.pause = SitePause(start: Fixture.date(2026, 11, 20))
        settings.setSiteSetup(setup, for: trg.id)
        XCTAssertFalse(WriteToday.isOffered(sites: [archived, trg], settings: settings, today: today))
        XCTAssertTrue(
            WriteToday.isOffered(sites: [archived, trg], settings: settings, today: Fixture.date(2026, 11, 19)),
            "the day before the pause began"
        )
    }

    func testEachSiteSaysWhatIsWrittenToday() {
        let rows = WriteToday.rows(
            sites: [trg, jarun],
            siteDays: [written(jarun, people: 5), written(trg, people: 3, on: Fixture.date(2026, 11, 23))],
            settings: Fixture.settings(),
            today: today
        )
        XCTAssertEqual(rows.map(\.siteName), ["Jarunski Dvori", "Trg Pravde"], "in the sites' own order")
        XCTAssertEqual(rows.map(\.state), [.written(people: 5, start: time(7), end: time(12)), .notWritten])
    }

    func testANoWorkDayIsNotWrittenHours() {
        let day = SiteDay.noWork(.noWork, siteID: jarun.id, date: today, jobID: nil)
        let rows = WriteToday.rows(sites: [jarun], siteDays: [day], settings: Fixture.settings(), today: today)
        XCTAssertEqual(rows.map(\.state), [.noWork])
    }

    func testAPausedSiteIsNotListed() {
        var settings = Fixture.settings()
        var setup = SiteSetup()
        setup.pause = SitePause(start: Fixture.date(2026, 11, 1))
        settings.setSiteSetup(setup, for: trg.id)
        let rows = WriteToday.rows(sites: [jarun, trg], siteDays: [], settings: settings, today: today)
        XCTAssertEqual(rows.map(\.siteID), [jarun.id])
    }

    func testADuplicateSiteDayIsReadOnce() {
        let rows = WriteToday.rows(
            sites: [jarun],
            siteDays: [written(jarun, people: 5), written(jarun, people: 2)],
            settings: Fixture.settings(),
            today: today
        )
        XCTAssertEqual(rows.map(\.state), [.written(people: 5, start: time(7), end: time(12))])
    }
}
