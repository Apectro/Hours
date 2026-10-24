import XCTest
@testable import Hours

/// When reaching or leaving a site asks about the clock (1.2): which sites
/// are watched, and whether an arrival or a departure says anything.
final class ArrivalReminderPolicyTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let engine = Fixture.engine()
    /// Tuesday 4 August 2026, 07:10 in Zagreb.
    private lazy var now: Date = instant(hour: 7, minute: 10)

    private func instant(_ date: CalendarDate = Fixture.workingTuesday, hour: Int, minute: Int = 0) -> Date {
        var components = date.components
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    private func site(
        _ name: String = "Trg Pravde",
        sortOrder: Int = 0,
        reminds: Bool = true,
        placed: Bool = true,
        archived: Bool = false
    ) -> Site {
        var site = Site(name: name, isArchived: archived, sortOrder: sortOrder)
        if placed { site.place = SitePlace(latitude: 45.8150, longitude: 15.9819) }
        site.remindsOnArrival = reminds
        return site
    }

    private func today(type: DayTypeID? = nil, holidays: [HolidayRule] = [], on date: CalendarDate = Fixture.workingTuesday) -> DayComputation {
        let record = type.map { Fixture.record(on: date, type: $0) }
        return engine.day(date, record: record, holidays: holidays)
    }

    private func decide(
        _ event: ArrivalEvent,
        site: Site? = nil,
        day: DayComputation? = nil,
        clockRunning: Bool = false,
        log: ArrivalReminderLog = ArrivalReminderLog(),
        at instant: Date? = nil
    ) -> ArrivalReminderPolicy.Decision {
        ArrivalReminderPolicy.decide(
            event,
            site: site ?? self.site(),
            today: day ?? today(),
            isClockRunning: clockRunning,
            log: log,
            now: instant ?? now
        )
    }

    // MARK: - Arriving

    func testArrivingOnAWorkingDayWithNoClockAsksToStartIt() {
        XCTAssertEqual(decide(.arrived), .remind)
    }

    func testArrivingWithTheClockRunningSaysNothing() {
        XCTAssertEqual(decide(.arrived, clockRunning: true), .quiet(.clockAlreadyRunning))
    }

    func testArrivingOnAWeekendStillAsks() {
        // Someone at the site on a Saturday is there to work.
        let saturday = today(on: Fixture.saturday)
        XCTAssertEqual(saturday.dayType.id, .weekend)
        XCTAssertEqual(decide(.arrived, day: saturday, at: instant(Fixture.saturday, hour: 7)), .remind)
    }

    func testNothingOnADayOfAbsence() {
        for type: DayTypeID in [.vacation, .sick, .holiday, .personal, .dayOff, .timeOffInLieu, .badWeather] {
            XCTAssertEqual(decide(.arrived, day: today(type: type)), .quiet(.dayOff), "\(type.rawValue)")
        }
    }

    func testOrdinaryTypesStillAsk() {
        for type: DayTypeID in [.work, .other] {
            XCTAssertEqual(decide(.arrived, day: today(type: type)), .remind, "\(type.rawValue)")
        }
    }

    func testNothingOnAPublicHoliday() {
        let holiday = HolidayRule(name: "Dan pobjede", recurrence: .once(on: Fixture.workingTuesday))
        XCTAssertEqual(decide(.arrived, day: today(holidays: [holiday])), .quiet(.dayOff))
    }

    func testAHolidayThatCountsAsAWorkingDayStillAsks() {
        let holiday = HolidayRule(name: "Works anyway", recurrence: .once(on: Fixture.workingTuesday), countsAsWorkingDay: true)
        XCTAssertEqual(decide(.arrived, day: today(holidays: [holiday])), .remind)
    }

    func testACustomTypeFollowsItsPolicy() {
        let training = DayTypeDefinition(id: DayTypeID("training"), name: "Training", symbolName: "book", tint: .blue, expectation: .scheduled, showsTimesByDefault: true)
        let unpaid = DayTypeDefinition(id: DayTypeID("unpaid"), name: "Unpaid leave", symbolName: "moon", tint: .gray, expectation: .zero, showsTimesByDefault: false)
        let settings = Fixture.settings(customDayTypes: [training, unpaid])
        let engine = Fixture.engine(settings: settings)
        let date = Fixture.workingTuesday
        let trainingDay = engine.day(date, record: Fixture.record(on: date, type: training.id), holidays: [])
        let unpaidDay = engine.day(date, record: Fixture.record(on: date, type: unpaid.id), holidays: [])
        XCTAssertEqual(decide(.arrived, day: trainingDay), .remind)
        XCTAssertEqual(decide(.arrived, day: unpaidDay), .quiet(.dayOff))
    }

    // MARK: - Leaving

    func testLeavingWithTheClockRunningAsksToStopIt() {
        XCTAssertEqual(decide(.left, clockRunning: true), .remind)
    }

    func testLeavingWithNoClockSaysNothing() {
        XCTAssertEqual(decide(.left), .quiet(.noClockRunning))
    }

    func testLeavingWithTheClockRunningAsksEvenOnADayOff() {
        // A clock running on a holiday is hours being worked; stopping it is
        // the whole point.
        XCTAssertEqual(decide(.left, day: today(type: .holiday), clockRunning: true), .remind)
    }

    // MARK: - Two hours

    func testTheSameSiteIsNotAskedAgainWithinTwoHours() {
        let site = site()
        var log = ArrivalReminderLog()
        log.record(.arrived, siteID: site.id, at: instant(hour: 6))
        XCTAssertEqual(decide(.arrived, site: site, log: log, at: instant(hour: 7, minute: 59)), .quiet(.askedRecently))
        XCTAssertEqual(decide(.arrived, site: site, log: log, at: instant(hour: 8)), .remind, "two hours on, it may ask again")
    }

    func testTheTwoHoursAreForEachSiteAndEachWay() {
        let site = site()
        let other = self.site("Schulweg 4")
        var log = ArrivalReminderLog()
        log.record(.arrived, siteID: site.id, at: instant(hour: 7))
        XCTAssertEqual(decide(.arrived, site: other, log: log), .remind, "another site is another question")
        XCTAssertEqual(
            decide(.left, site: site, clockRunning: true, log: log, at: instant(hour: 7, minute: 30)),
            .remind,
            "a short job's departure is still asked about"
        )
    }

    func testADepartureAskedRecentlyIsNotAskedAgain() {
        let site = site()
        var log = ArrivalReminderLog()
        log.record(.left, siteID: site.id, at: instant(hour: 12))
        XCTAssertEqual(decide(.left, site: site, clockRunning: true, log: log, at: instant(hour: 13)), .quiet(.askedRecently))
    }

    func testAReminderFromTheFutureDoesNotSilenceForever() {
        // The phone's clock moved back after a reminder: the stored instant
        // is ahead of now. Close ahead still counts as just asked.
        let site = site()
        var log = ArrivalReminderLog()
        log.record(.arrived, siteID: site.id, at: instant(hour: 8))
        XCTAssertEqual(decide(.arrived, site: site, log: log), .quiet(.askedRecently))
        log.record(.arrived, siteID: site.id, at: instant(hour: 23))
        XCTAssertEqual(decide(.arrived, site: site, log: log), .remind, "far ahead is a clock that moved, not a recent question")
    }

    // MARK: - Sites that are not watched

    func testASiteThatIsNoLongerWatchedSaysNothing() {
        XCTAssertEqual(decide(.arrived, site: site(reminds: false)), .quiet(.notWatched))
        XCTAssertEqual(decide(.arrived, site: site(placed: false)), .quiet(.notWatched))
        XCTAssertEqual(decide(.left, site: site(archived: true), clockRunning: true), .quiet(.notWatched))
    }

    // MARK: - The log

    func testTheLogRoundTripsAndForgetsOldEntries() throws {
        let site = site()
        var log = ArrivalReminderLog()
        log.record(.arrived, siteID: site.id, at: instant(hour: 7))
        log.record(.left, siteID: site.id, at: instant(hour: 14))
        let decoded = try JSONDecoder().decode(ArrivalReminderLog.self, from: JSONEncoder().encode(log))
        XCTAssertEqual(decoded, log)
        XCTAssertEqual(decoded.lastReminder(.arrived, siteID: site.id), instant(hour: 7))

        let pruned = log.pruned(now: instant(hour: 15))
        XCTAssertNil(pruned.lastReminder(.arrived, siteID: site.id), "eight hours old silences nothing")
        XCTAssertEqual(pruned.lastReminder(.left, siteID: site.id), instant(hour: 14))
    }

    func testAnUnreadableLogIsAnEmptyOne() throws {
        let log = try JSONDecoder().decode(ArrivalReminderLog.self, from: Data(#"{"entries": "nonsense"}"#.utf8))
        XCTAssertEqual(log, ArrivalReminderLog())
    }

    // MARK: - Which sites are watched

    func testOnlySitesWithTheSwitchOnAndAPlaceAreWatchedInOrder() {
        let b = site("B", sortOrder: 2)
        let a = site("A", sortOrder: 1)
        let off = site("Off", reminds: false)
        let nowhere = site("Nowhere", placed: false)
        let archived = site("Archived", archived: true)
        let plan = ArrivalReminderPolicy.plan(sites: [b, off, nowhere, a, archived])
        XCTAssertEqual(plan.watched.map(\.name), ["A", "B"])
        XCTAssertTrue(plan.leftOut.isEmpty)
    }

    func testNoMoreThanTwentySitesAreWatched() {
        let sites = (0..<23).map { site("Site \($0)", sortOrder: $0) }
        let plan = ArrivalReminderPolicy.plan(sites: sites.reversed())
        XCTAssertEqual(ArrivalReminderPolicy.maximumWatchedSites, 20)
        XCTAssertEqual(plan.watched.count, 20)
        XCTAssertEqual(plan.watched.first?.name, "Site 0")
        XCTAssertEqual(plan.leftOut.map(\.name), ["Site 20", "Site 21", "Site 22"])
    }

    func testTheRegionIdentifierNamesTheSite() {
        let id = UUID()
        let identifier = ArrivalReminderPolicy.regionIdentifier(for: id)
        XCTAssertTrue(identifier.hasPrefix(ArrivalReminderPolicy.regionPrefix))
        XCTAssertEqual(ArrivalReminderPolicy.siteID(fromRegionIdentifier: identifier), id)
        XCTAssertNil(ArrivalReminderPolicy.siteID(fromRegionIdentifier: "site-reminder-20260804"))
        XCTAssertNil(ArrivalReminderPolicy.siteID(fromRegionIdentifier: ArrivalReminderPolicy.regionPrefix + "nonsense"))
    }

    // MARK: - When the clock starts or stops

    func testTheClockStartsWhenYouArrivedNotWhenYouTapped() {
        let arrived = instant(hour: 7)
        XCTAssertEqual(ArrivalReminderPolicy.clockInstant(eventAt: arrived, now: instant(hour: 7, minute: 25)), arrived)
    }

    func testAnArrivalLongAgoOrInTheFutureStartsNow() {
        let tapped = instant(hour: 19)
        XCTAssertEqual(ArrivalReminderPolicy.clockInstant(eventAt: instant(hour: 6), now: tapped), tapped, "over twelve hours is a stale notification")
        XCTAssertEqual(ArrivalReminderPolicy.clockInstant(eventAt: instant(hour: 20), now: tapped), tapped)
        XCTAssertEqual(ArrivalReminderPolicy.clockInstant(eventAt: nil, now: tapped), tapped)
    }

    func testTheClockStopsWhenYouLeftButNeverBeforeItStarted() {
        let started = instant(hour: 7)
        let left = instant(hour: 15, minute: 40)
        let tapped = instant(hour: 16, minute: 5)
        XCTAssertEqual(ArrivalReminderPolicy.clockInstant(eventAt: left, now: tapped, notBefore: started), left)
        XCTAssertEqual(
            ArrivalReminderPolicy.clockInstant(eventAt: instant(hour: 6), now: tapped, notBefore: started),
            tapped,
            "a departure before the clock started is not this shift's"
        )
    }
}
