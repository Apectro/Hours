import XCTest
@testable import Hours

/// The figures the 1.2 widgets draw: the week day by day, the month as dots,
/// the balance as days off, leave, what the month earned and the site's crew
/// today. Like the rest of the snapshot, everything is decided here from days
/// the engine has already resolved, so a widget only draws.
final class WidgetFiguresTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let settings = Fixture.settings()

    /// Thursday 6 August 2026. The week runs Monday 3 to Sunday 9.
    private let thursday = Fixture.date(2026, 8, 6)

    private func days(
        in range: CalendarDateRange,
        records: [DayRecord],
        settings: AppSettings? = nil
    ) -> [DayComputation] {
        Fixture.engine(settings: settings ?? self.settings, calendar: calendar).days(
            in: range,
            records: Dictionary(records.map { ($0.date.key, $0) }, uniquingKeysWith: { first, _ in first }),
            holidays: []
        )
    }

    private func noon(on date: CalendarDate) -> Date {
        date.date(in: calendar)
    }

    private var week: CalendarDateRange { CalendarDateRange.week(containing: thursday, in: calendar) }
    private var august: CalendarDateRange { YearMonth(year: 2026, month: 8).range(in: calendar) }

    private func worked(_ day: Int, _ from: Int, _ to: Int, month: Int = 8) -> DayRecord {
        Fixture.record(on: Fixture.date(2026, month, day), start: Fixture.time(from), end: Fixture.time(to))
    }

    // MARK: - The week, day by day

    func testTheWeekHasSevenDaysWithTheirTimesAndKinds() {
        let resolved = days(in: week, records: [
            worked(3, 7, 15),
            Fixture.record(on: Fixture.date(2026, 8, 4), type: .vacation),
            Fixture.record(on: Fixture.date(2026, 8, 5), type: .sick),
        ])

        let built = WidgetSnapshotBuilder.weekDays(resolved, today: thursday, settings: settings, calendar: calendar, language: .english)

        XCTAssertEqual(built.count, 7)
        XCTAssertEqual(built.map(\.date), week.days(in: calendar))
        XCTAssertEqual(built[0].kind, .work)
        XCTAssertEqual(built[0].start, Fixture.time(7))
        XCTAssertEqual(built[0].end, Fixture.time(15))
        XCTAssertEqual(built[0].workedMinutes, 480)
        XCTAssertNil(built[0].typeName, "a working day needs no name")
        XCTAssertEqual(built[1].kind, .leave)
        XCTAssertEqual(built[1].creditedMinutes, 480)
        XCTAssertEqual(built[1].typeName, "Vacation")
        XCTAssertEqual(built[2].kind, .sick)
        XCTAssertEqual(built[5].kind, .off, "Saturday")
        XCTAssertEqual(built[0].usualStart, settings.schedule.defaultStart)
        XCTAssertNil(built[5].usualStart, "nobody is usually at work on a Saturday")
    }

    func testAPublicHolidayIsItsOwnKind() {
        let resolved = days(in: week, records: [Fixture.record(on: Fixture.date(2026, 8, 3), type: .holiday)])

        let built = WidgetSnapshotBuilder.weekDays(resolved, today: thursday, settings: settings, calendar: calendar, language: .english)

        XCTAssertEqual(built[0].kind, .holiday)
    }

    func testTimeOffInLieuIsDrawnAsADayOffTaken() {
        let resolved = days(in: week, records: [Fixture.record(on: Fixture.date(2026, 8, 3), type: .timeOffInLieu)])

        let built = WidgetSnapshotBuilder.weekDays(resolved, today: thursday, settings: settings, calendar: calendar, language: .english)

        XCTAssertEqual(built[0].kind, .leave)
    }

    /// What has not been counted yet is not on the widget either: a day still
    /// to come adds nothing, an excluded day adds nothing.
    func testUncountedDaysAddNothing() {
        var excluded = worked(3, 7, 15)
        excluded.isIncluded = false
        let resolved = days(in: week, records: [excluded])

        let built = WidgetSnapshotBuilder.weekDays(resolved, today: thursday, settings: settings, calendar: calendar, language: .english)

        XCTAssertEqual(built[0].workedMinutes, 0)
        XCTAssertEqual(built[0].balanceMinutes, 0)
        XCTAssertEqual(built[6].balanceMinutes, 0, "Sunday has not happened")
        XCTAssertEqual(built[4].expectedMinutes, 480, "Friday's target is known before Friday")
    }

    private func snapshot(at instant: Date, records: [DayRecord] = [], running since: Date? = nil) -> WidgetSnapshot {
        let today = CalendarDate(instant, calendar: calendar)
        let resolved = days(in: CalendarDateRange.week(containing: today, in: calendar), records: records)
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = instant
        snapshot.week = WidgetSnapshotBuilder.week(resolved, today: today, calendar: calendar)
        snapshot.weekDays = WidgetSnapshotBuilder.weekDays(resolved, today: today, settings: settings, calendar: calendar, language: .english)
        snapshot.averageDayMinutes = 480
        let todayDay = resolved.first { $0.date == today }
        snapshot.todayWorkedMinutes = todayDay?.workedMinutes ?? 0
        snapshot.todayExpectedMinutes = todayDay?.expectedMinutes ?? 0
        if let since {
            snapshot.isClockRunning = true
            snapshot.clockStartedAt = since
        }
        return snapshot
    }

    func testTheChartPutsTheRunningClockInTodaysColumn() {
        let now = noon(on: thursday)
        let snapshot = snapshot(
            at: now,
            records: [worked(3, 8, 16), worked(4, 8, 18), Fixture.record(on: Fixture.date(2026, 8, 5), type: .vacation)],
            running: now.addingTimeInterval(-120 * 60)
        )

        let chart = snapshot.weekChart(at: now, calendar: calendar)

        XCTAssertEqual(chart?.columns.count, 7)
        XCTAssertEqual(chart?.columns[0].style, .worked)
        XCTAssertEqual(chart?.columns[2].style, .leave, "leave is drawn outlined, at the hours it credits")
        XCTAssertEqual(chart?.columns[2].minutes, 480)
        XCTAssertEqual(chart?.columns[3].style, .today)
        XCTAssertEqual(chart?.columns[3].minutes, 120)
        XCTAssertTrue(chart?.columns[3].isRunning ?? false)
        XCTAssertEqual(chart?.columns[4].style, .empty)
        XCTAssertEqual(chart?.paidMinutes, 480 + 600 + 480 + 120)
        XCTAssertEqual(chart?.expectedMinutes, 2_400)
        // +0 +2:00 +0, and today 2:00 of 8:00 so far.
        XCTAssertEqual(chart?.balanceMinutes, 120 - 360)
    }

    /// Ten hours fill a bar; a longer day stretches the scale rather than
    /// running off the top, and the target line sits at a normal day.
    func testBarsAreScaledToTheLongestDayOrTenHours() {
        let now = noon(on: thursday)
        let short = snapshot(at: now, records: [worked(3, 8, 16)])
        let long = snapshot(at: now, records: [worked(3, 6, 18)])

        let shortChart = short.weekChart(at: now, calendar: calendar)
        let longChart = long.weekChart(at: now, calendar: calendar)

        XCTAssertEqual(shortChart?.columns[0].fraction ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(shortChart?.targetFraction ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(longChart?.columns[0].fraction ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(longChart?.targetFraction ?? 0, 480.0 / 720.0, accuracy: 0.001)
    }

    func testNoChartOnceTheWeekIsOver() {
        let snapshot = snapshot(at: noon(on: thursday))

        XCTAssertNil(snapshot.weekChart(at: noon(on: Fixture.date(2026, 8, 10)), calendar: calendar))
        XCTAssertNil(snapshot.weekRows(at: noon(on: Fixture.date(2026, 8, 10)), calendar: calendar))
    }

    func testTheWeekListMarksTodayAndWhatIsStillToCome() {
        let now = noon(on: thursday)
        let snapshot = snapshot(at: now, records: [worked(3, 7, 15)], running: now.addingTimeInterval(-60 * 60))

        let rows = snapshot.weekRows(at: now, calendar: calendar)

        XCTAssertEqual(rows?.count, 7)
        XCTAssertEqual(rows?[0].paidMinutes, 480)
        XCTAssertFalse(rows?[0].isToday ?? true)
        XCTAssertTrue(rows?[3].isToday ?? false)
        XCTAssertTrue(rows?[3].isRunning ?? false)
        XCTAssertEqual(rows?[3].paidMinutes, 60)
        XCTAssertTrue(rows?[4].isFuture ?? false)
    }

    // MARK: - Which state Today is in

    func testTodayIsRunningWhileTheClockRuns() {
        let now = noon(on: thursday)
        let since = now.addingTimeInterval(-3600)

        XCTAssertEqual(snapshot(at: now, running: since).todayState(at: now, calendar: calendar), .running(since: since))
    }

    func testBeforeWorkTodaySaysWhenYouUsuallyStart() {
        let now = noon(on: thursday)

        XCTAssertEqual(
            snapshot(at: now).todayState(at: now, calendar: calendar),
            .idle(usualStart: settings.schedule.defaultStart)
        )
    }

    func testASaturdayWithNothingWorkedIsADayOff() {
        let now = noon(on: Fixture.saturday)

        XCTAssertEqual(snapshot(at: now).todayState(at: now, calendar: calendar), .dayOff)
    }

    func testASaturdayWorkedIsNotADayOff() {
        let now = noon(on: Fixture.saturday)

        XCTAssertEqual(
            snapshot(at: now, records: [Fixture.record(on: Fixture.saturday, start: Fixture.time(8), end: Fixture.time(12))])
                .todayState(at: now, calendar: calendar),
            .idle(usualStart: nil)
        )
    }

    /// Past midnight the week still knows what the new day expects, so
    /// Saturday morning reads as a day off before the app has run.
    func testAfterMidnightTheWeekSaysWhetherTheNewDayIsOff() {
        let snapshot = snapshot(at: noon(on: Fixture.date(2026, 8, 7)), records: [worked(7, 8, 16)])

        XCTAssertEqual(snapshot.todayState(at: noon(on: Fixture.saturday), calendar: calendar), .dayOff)
    }

    /// A new week is something the file knows nothing about: no day off, no
    /// usual start, just the button.
    func testInANewWeekNothingIsAssumed() {
        let snapshot = snapshot(at: noon(on: Fixture.date(2026, 8, 9)))

        XCTAssertEqual(snapshot.todayState(at: noon(on: Fixture.date(2026, 8, 10)), calendar: calendar), .idle(usualStart: nil))
    }

    // MARK: - The month as dots

    func testEveryDayOfTheMonthHasADot() {
        let resolved = days(in: august, records: [
            worked(3, 8, 16),
            Fixture.record(on: Fixture.date(2026, 8, 4), type: .vacation),
            Fixture.record(on: Fixture.date(2026, 8, 5), type: .sick),
            Fixture.record(on: Fixture.date(2026, 8, 20), type: .vacation),
        ])

        let dots = WidgetSnapshotBuilder.monthDays(resolved, today: thursday)
        let kind = { (day: Int) in dots.first { $0.date == Fixture.date(2026, 8, day) }?.kind }

        XCTAssertEqual(dots.count, 31)
        XCTAssertEqual(kind(3), .worked)
        XCTAssertEqual(kind(4), .leave)
        XCTAssertEqual(kind(5), .sick)
        XCTAssertEqual(kind(6), .today)
        XCTAssertEqual(kind(7), .future)
        XCTAssertEqual(kind(8), .off, "Saturday")
        XCTAssertEqual(kind(20), .leave, "booked leave shows ahead")
        XCTAssertEqual(kind(31), .future)
    }

    func testAPastWorkingDayWithNothingIsMissing() {
        let dots = WidgetSnapshotBuilder.monthDays(days(in: august, records: []), today: thursday)

        XCTAssertEqual(dots.first { $0.date == Fixture.date(2026, 8, 3) }?.kind, .missing)
    }

    func testDaysBeforeTheBalanceStartsAreNotMissing() {
        let resolved = Fixture.engine(settings: settings, calendar: calendar, firstRecorded: Fixture.date(2026, 8, 5))
            .days(in: august, records: [:], holidays: [])

        let dots = WidgetSnapshotBuilder.monthDays(resolved, today: thursday)

        XCTAssertEqual(dots.first { $0.date == Fixture.date(2026, 8, 3) }?.kind, .off)
    }

    func testTheDotsMoveOnAtMidnight() {
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = noon(on: thursday)
        snapshot.todayWorkedMinutes = 300
        snapshot.monthDays = WidgetSnapshotBuilder.monthDays(days(in: august, records: []), today: thursday)

        let dots = snapshot.monthDays(at: noon(on: Fixture.date(2026, 8, 7)), calendar: calendar)
        let kind = { (day: Int) in dots.first { $0.date == Fixture.date(2026, 8, day) }?.kind }

        XCTAssertEqual(kind(6), .worked)
        XCTAssertEqual(kind(7), .today)
        XCTAssertTrue(snapshot.monthDays(at: noon(on: Fixture.date(2026, 9, 1)), calendar: calendar).isEmpty)
    }

    func testYesterdayWithNothingWorkedBecomesMissingAtMidnight() {
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = noon(on: thursday)
        snapshot.todayExpectedMinutes = 480
        snapshot.monthDays = WidgetSnapshotBuilder.monthDays(days(in: august, records: []), today: thursday)

        let dots = snapshot.monthDays(at: noon(on: Fixture.date(2026, 8, 7)), calendar: calendar)

        XCTAssertEqual(dots.first { $0.date == thursday }?.kind, .missing)
    }

    // MARK: - The balance as days off

    func testHalfDaysAreWrittenWithAHalf() {
        XCTAssertEqual(HalfDays(halves: 3).withHalfSign, "1½")
        XCTAssertEqual(HalfDays(halves: 1).withHalfSign, "½")
        XCTAssertEqual(HalfDays(halves: 4).withHalfSign, "2")
        XCTAssertEqual(HalfDays(halves: -3).withHalfSign, "-1½")
        XCTAssertEqual(HalfDays(halves: 0).withHalfSign, "0")
    }

    func testTheBalanceReadsAsDaysOffAtANormalDay() {
        XCTAssertEqual(WidgetSnapshotBuilder.daysOff(balanceMinutes: 750, on: thursday, settings: settings), HalfDays(halves: 3))
        XCTAssertNil(WidgetSnapshotBuilder.daysOff(balanceMinutes: -60, on: thursday, settings: settings))
        XCTAssertNil(WidgetSnapshotBuilder.daysOff(balanceMinutes: 0, on: thursday, settings: settings))
    }

    func testTheBalanceIsOnlyCarriedWhileTheAppKeepsOne() {
        var off = settings
        off.features.trackOvertime = false

        XCTAssertEqual(WidgetSnapshotBuilder.totalBalance(750, settings: settings), 750)
        XCTAssertNil(WidgetSnapshotBuilder.totalBalance(750, settings: off))
    }

    // MARK: - Leave

    private func leaveSettings(_ change: (inout LeavePolicy) -> Void = { _ in }) -> AppSettings {
        var settings = self.settings
        change(&settings.leave)
        return settings
    }

    private func leave(_ settings: AppSettings, records: [DayRecord]) -> WidgetLeave? {
        let year = YearMonth(year: 2026, month: 1).range(in: calendar).start
        let range = CalendarDateRange(start: year, end: Fixture.date(2026, 12, 31))
        let resolved = days(in: range, records: records, settings: settings)
        let balance = LeaveCalculator.balance(
            leaveYear: 2026, days: resolved, settings: settings, calendar: calendar, today: thursday
        )
        return WidgetSnapshotBuilder.leave(balance: balance, days: resolved, settings: settings, today: thursday, calendar: calendar)
    }

    func testLeaveSaysWhatIsLeftOfWhatTheYearGives() {
        let records = (6...10).map { Fixture.record(on: Fixture.date(2026, 7, $0), type: .vacation) }
            + [22, 23, 24].map { Fixture.record(on: Fixture.date(2026, 12, $0), type: .vacation) }

        let result = leave(leaveSettings(), records: records)

        XCTAssertEqual(result?.available, HalfDays(halves: 50))
        XCTAssertEqual(result?.taken, HalfDays(halves: 10))
        XCTAssertEqual(result?.booked, HalfDays(halves: 6))
        XCTAssertEqual(result?.remaining, HalfDays(halves: 34))
        XCTAssertEqual(result?.leaveYear, 2026)
        XCTAssertEqual(result?.nextStart, Fixture.date(2026, 12, 22))
        XCTAssertEqual(result?.nextEnd, Fixture.date(2026, 12, 24))
    }

    func testCarriedDaysAreAvailable() {
        let result = leave(leaveSettings { $0.carriedOverDays = 3; $0.carriedOverYear = 2026 }, records: [])

        XCTAssertEqual(result?.available, HalfDays(halves: 56))
    }

    /// A week of leave over a weekend is one stretch, Friday to the
    /// following Friday, not two.
    func testTheNextLeaveRunsOverAWeekend() {
        let records = [14, 17, 18, 19, 20, 21].map { Fixture.record(on: Fixture.date(2026, 8, $0), type: .vacation) }
            + [Fixture.record(on: Fixture.date(2026, 8, 28), type: .vacation)]

        let result = leave(leaveSettings(), records: records)

        XCTAssertEqual(result?.nextStart, Fixture.date(2026, 8, 14))
        XCTAssertEqual(result?.nextEnd, Fixture.date(2026, 8, 21))
    }

    func testLeaveAlreadyStartedIsNotNext() {
        let records = [5, 6, 7, 10].map { Fixture.record(on: Fixture.date(2026, 8, $0), type: .vacation) }
            + [Fixture.record(on: Fixture.date(2026, 9, 1), type: .vacation)]

        let result = leave(leaveSettings(), records: records)

        XCTAssertEqual(result?.nextStart, Fixture.date(2026, 9, 1))
    }

    func testNoLeaveBookedMeansNoNext() {
        let result = leave(leaveSettings { $0.allowanceDays = 30 }, records: [])

        XCTAssertNil(result?.nextStart)
        XCTAssertEqual(result?.remaining, HalfDays(halves: 60))
    }

    /// Someone who has never mentioned leave sees the invitation to set it,
    /// not "25 of 25 days left" for an allowance they never gave.
    func testLeaveNobodyHasMentionedIsNotShown() {
        XCTAssertNil(leave(leaveSettings(), records: []))
    }

    func testTheLeaveRingIsWhatIsLeft() {
        let leave = WidgetLeave(leaveYear: 2026, available: HalfDays(halves: 50), taken: HalfDays(halves: 22), booked: .zero)

        XCTAssertEqual(leave.remainingFraction, 28.0 / 50.0, accuracy: 0.0001)
        XCTAssertEqual(WidgetLeave(leaveYear: 2026, available: .zero, taken: .zero, booked: .zero).remainingFraction, 0)
    }

    // MARK: - What the month earned

    private func earned(rate: Int? = 15_00, allowance: AllowancePreferences? = nil, records: [DayRecord]) -> WidgetMonthEarned? {
        var settings = self.settings
        if let rate { settings.changePay(forJob: Job.primaryID, to: PayRules(hourlyRateCents: rate), from: nil) }
        if let allowance { settings.allowance = allowance }
        let engine = Fixture.engine(settings: settings, calendar: calendar)
        let byKey = Dictionary(records.map { ($0.date.key, $0) }, uniquingKeysWith: { first, _ in first })
        let summary = engine.earnings(in: august, records: byKey, holidays: [], countingThrough: thursday)
        let resolved = engine.days(in: august, records: byKey, holidays: [])
        return WidgetSnapshotBuilder.monthEarned(
            summary: summary,
            days: resolved,
            settings: settings,
            today: thursday,
            currencyCode: "EUR"
        )
    }

    func testTheMonthEarnedIsSplitIntoHoursAllowanceAndKilometres() {
        var allowance = AllowancePreferences()
        allowance.isEnabled = true
        allowance.dailyAllowanceCents = 14_00
        allowance.centsPerKilometre = 20
        var monday = worked(3, 8, 16)
        monday.hasFieldAllowance = true
        monday.kilometres = 60
        var tuesday = worked(4, 8, 16)
        tuesday.hasFieldAllowance = true

        let result = earned(allowance: allowance, records: [monday, tuesday])

        XCTAssertEqual(result?.year, 2026)
        XCTAssertEqual(result?.month, 8)
        XCTAssertEqual(result?.hoursCents, 240_00)
        XCTAssertEqual(result?.paidMinutes, 960)
        XCTAssertEqual(result?.allowanceDays, 2)
        XCTAssertEqual(result?.allowanceCents, 28_00)
        XCTAssertEqual(result?.kilometres, 60)
        XCTAssertEqual(result?.mileageCents, 12_00)
        XCTAssertEqual(result?.totalCents, 280_00)
        XCTAssertEqual(result?.rows.map(\.kind), [.hours(960), .allowance(2), .kilometres(60)])
        XCTAssertEqual(result?.rows.map(\.cents), [240_00, 28_00, 12_00])
    }

    func testOnlyRowsWithSomethingInThemAreShown() {
        let result = earned(records: [worked(3, 8, 16)])

        XCTAssertEqual(result?.rows.map(\.kind), [.hours(480)])
    }

    func testWithoutARateNothingIsEarned() {
        XCTAssertNil(earned(rate: nil, records: [worked(3, 8, 16)]))
    }

    func testLastMonthsEarningsAreNotThisMonths() {
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = noon(on: thursday)
        snapshot.monthEarned = earned(records: [worked(3, 8, 16)])

        XCTAssertEqual(snapshot.monthEarned(at: noon(on: Fixture.date(2026, 8, 31)), calendar: calendar)?.totalCents, 120_00)
        let september = snapshot.monthEarned(at: noon(on: Fixture.date(2026, 9, 1)), calendar: calendar)
        XCTAssertEqual(september?.totalCents, 0, "a rate is still set, so the new month starts at nothing")
        XCTAssertEqual(september?.rows, [])
        XCTAssertEqual(september?.month, 9)
    }

    // MARK: - The site's crew today

    func testTheCrewIsListedPresentFirstThenWhyTheOthersAreAway() {
        let site = Site(name: "Hauptstraße 12")
        let other = Site(name: "Trg Pravde")
        let ivan = CrewMember(siteID: site.id, name: "Ivan Horvat", sortOrder: 0)
        let luka = CrewMember(siteID: site.id, name: "Luka Šimić", sortOrder: 1)
        let ana = CrewMember(siteID: site.id, name: "Ana Babić", sortOrder: 2)
        let marko = CrewMember(siteID: site.id, name: "Marko Perić", sortOrder: 3)
        let hidden = CrewMember(siteID: site.id, name: "Old Hand", isHidden: true, sortOrder: 4)
        let fresh = CrewMember(siteID: site.id, name: "New Face", sortOrder: 5)
        let day = SiteDay(
            siteID: site.id,
            date: thursday,
            start: Fixture.time(7),
            present: [Attendance(memberID: ana.id), Attendance(memberID: CrewMember.youID), Attendance(memberID: ivan.id)],
            absences: [
                CrewAbsence(memberID: luka.id, dayTypeID: .sick),
                CrewAbsence(memberID: marko.id, reason: .otherSite(other.id)),
            ]
        )

        let rows = WidgetSnapshotBuilder.crew(
            day: day,
            crew: [ivan, luka, ana, marko, hidden, fresh],
            catalog: settings.dayTypeCatalog,
            siteNames: [other.id: other.name],
            language: .english
        )

        XCTAssertEqual(rows.map(\.name), ["You", "Ivan Horvat", "Ana Babić", "Luka Šimić", "Marko Perić", "New Face"])
        XCTAssertEqual(rows.map(\.isPresent), [true, true, true, false, false, false])
        XCTAssertEqual(rows.map(\.reason), [nil, nil, nil, "Sick leave", "Trg Pravde", nil])
    }

    func testFourRowsFitAndTheRestAreCounted() {
        let rows = (0..<6).map { WidgetCrewRow(name: "P\($0)", isPresent: true, reason: nil) }

        let few = WidgetCrewRow.fitting(Array(rows.prefix(4)), lines: 4)
        let many = WidgetCrewRow.fitting(rows, lines: 4)

        XCTAssertEqual(few.rows.count, 4)
        XCTAssertEqual(few.more, 0)
        XCTAssertEqual(many.rows.count, 3, "the fourth line says how many more")
        XCTAssertEqual(many.more, 3)
    }

    func testTheSiteCardCarriesTheCrew() throws {
        let site = Site(name: "Hauptstraße 12")
        var card = WidgetSnapshotBuilder.site(site, today: thursday, lastDay: nil, crew: [])
        card.crew = [WidgetCrewRow(name: "You", isPresent: true, reason: nil)]
        var snapshot = WidgetSnapshot.empty
        snapshot.site = card

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(decoded.site?.crew, card.crew)
        XCTAssertEqual(decoded.site?.presentCount, 1)
    }

    // MARK: - Short names

    func testASitesShortNameFitsInACircle() {
        XCTAssertEqual(WidgetSnapshotBuilder.shortName(of: "Hauptstraße 12"), "H 12")
        XCTAssertEqual(WidgetSnapshotBuilder.shortName(of: "Trg Pravde"), "TP")
        XCTAssertEqual(WidgetSnapshotBuilder.shortName(of: "Kino"), "Kino")
        XCTAssertEqual(WidgetSnapshotBuilder.shortName(of: "Neubau Wohnanlage Süd"), "NWS")
        XCTAssertEqual(WidgetSnapshotBuilder.shortName(of: "  "), "")
    }

    // MARK: - The file

    func testAFileWithoutTheNewFiguresStillDecodes() throws {
        let json = Data(#"{"todayWorkedMinutes": 90, "monthMarks": [], "week": {"start": 20260803, "firstWeekday": 2, "workedMinutes": [0,0,0,0,0,0,0], "expectedMinutes": 2400}}"#.utf8)

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: json)

        XCTAssertEqual(decoded.todayWorkedMinutes, 90)
        XCTAssertTrue(decoded.weekDays.isEmpty)
        XCTAssertTrue(decoded.monthDays.isEmpty)
        XCTAssertNil(decoded.totalBalanceMinutes)
        XCTAssertNil(decoded.leave)
        XCTAssertNil(decoded.monthEarned)
        XCTAssertTrue(decoded.usesTimeClock)
    }

    func testTheNewFiguresSurviveARoundTrip() throws {
        var snapshot = snapshot(at: noon(on: thursday), records: [worked(3, 7, 15)])
        snapshot.monthDays = WidgetSnapshotBuilder.monthDays(days(in: august, records: []), today: thursday)
        snapshot.totalBalanceMinutes = 750
        snapshot.balanceDaysOff = HalfDays(halves: 3)
        snapshot.weekNumber = 32
        snapshot.usesTimeClock = false
        snapshot.leave = WidgetLeave(
            leaveYear: 2026, available: HalfDays(halves: 50), taken: HalfDays(halves: 10), booked: HalfDays(halves: 2),
            nextStart: Fixture.date(2026, 12, 22), nextEnd: Fixture.date(2026, 12, 24)
        )
        snapshot.monthEarned = earned(records: [worked(3, 8, 16)])

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))

        XCTAssertEqual(decoded, snapshot)
    }

    func testADayOfAKindThisVersionDoesNotKnowIsDroppedNotTheWeek() throws {
        let json = Data(#"{"weekDays": [{"date": 20260803, "kind": "work", "workedMinutes": 480}, {"date": 20260804, "kind": "somethingNew"}]}"#.utf8)

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: json)

        XCTAssertEqual(decoded.weekDays.count, 2)
        XCTAssertEqual(decoded.weekDays[0].workedMinutes, 480)
        XCTAssertEqual(decoded.weekDays[1].kind, .off, "an unknown kind reads as a quiet day")
    }
}
