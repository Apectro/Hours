import XCTest
@testable import Hours

/// "Bad weather" (Schlechtwetter): a built-in day type, and a site day the
/// crew was rained off.
final class BadWeatherTests: XCTestCase {
    private let calendar = Fixture.calendar()

    // MARK: - The day type

    func testBadWeatherIsABuiltInTypeEveryCatalogueHas() {
        let catalog = DayTypeCatalog(custom: [])
        let definition = catalog.definition(for: .badWeather)
        XCTAssertEqual(definition.name, "Bad weather")
        XCTAssertTrue(definition.isBuiltIn)
        XCTAssertTrue(DayTypeCatalog.isBuiltIn(.badWeather))
        XCTAssertTrue(catalog.all.contains { $0.id == .badWeather })
    }

    /// Someone with custom types from 1.0 gets the new built-in alongside
    /// them, with nothing to migrate.
    func testExistingCustomTypesKeepTheirPlaceAndTheNewTypeAppears() {
        let custom = DayTypeDefinition(
            id: DayTypeID(UUID().uuidString), name: "Training", symbolName: "book",
            tint: .green, expectation: .scheduled, showsTimesByDefault: true
        )
        let catalog = DayTypeCatalog(custom: [custom])
        XCTAssertTrue(catalog.all.contains { $0.id == custom.id })
        XCTAssertTrue(catalog.all.contains { $0.id == .badWeather })
    }

    func testBadWeatherIsPaidAbsenceByDefault() {
        let definition = DayTypeCatalog.standard.definition(for: .badWeather)
        XCTAssertEqual(definition.expectation, .creditedAbsence)
    }

    func testBadWeatherCreditsTheContractedHoursOnAWorkingDay() {
        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .badWeather)
        let day = Fixture.calculator().compute(record: record, on: Fixture.workingTuesday)
        XCTAssertEqual(day.dayType.id, .badWeather)
        XCTAssertEqual(day.expectedMinutes, 480)
        XCTAssertEqual(day.creditedMinutes, 480)
        XCTAssertEqual(day.balanceMinutes, 0)
    }

    func testBadWeatherCanBeMadeUnpaidLikeAnyBuiltIn() {
        var unpaid = DayTypeCatalog.standard.definition(for: .badWeather)
        unpaid.expectation = .zero
        let settings = Fixture.settings(customDayTypes: [unpaid])
        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .badWeather)
        let day = Fixture.calculator(settings: settings).compute(record: record, on: Fixture.workingTuesday)
        XCTAssertEqual(day.creditedMinutes, 0)
        XCTAssertEqual(day.expectedMinutes, 0)
    }

    func testBadWeatherIsTranslatedInEveryExportLanguage() {
        let definition = DayTypeCatalog.standard.definition(for: .badWeather)
        XCTAssertEqual(definition.exportName(in: .german), "Schlechtwetter")
        XCTAssertEqual(definition.exportName(in: .english), "Bad weather")
        XCTAssertEqual(definition.exportName(in: .croatian), "Loše vrijeme")
        for language in ExportLanguage.allCases {
            XCTAssertFalse(definition.exportName(in: language).isEmpty, "\(language)")
        }
    }

    func testInsightsCountBadWeatherDaysLikeAnyOtherType() {
        let engine = Fixture.engine()
        let range = CalendarDateRange(start: Fixture.workingMonday, end: Fixture.workingTuesday)
        let records = [
            DayRecord(date: Fixture.workingMonday, dayTypeID: .badWeather),
            DayRecord(date: Fixture.workingTuesday, dayTypeID: .badWeather)
        ]
        let summary = engine.summary(
            in: range,
            records: Dictionary(uniqueKeysWithValues: records.map { ($0.date.key, $0) }),
            holidays: []
        )
        XCTAssertEqual(summary.countsByType[.badWeather], 2)
        XCTAssertEqual(summary.paidAbsenceDays, 2)
    }

    // MARK: - A rained-off site day

    private let site = Site(name: "Bau Süd")
    private let ivan = UUID()

    private func siteDay(
        start: TimeOfDay? = Fixture.time(7),
        end: TimeOfDay? = Fixture.time(16),
        present: [Attendance]? = nil
    ) -> SiteDay {
        SiteDay(
            siteID: site.id,
            date: Fixture.workingTuesday,
            start: start,
            end: end,
            breakMinutes: 30,
            present: present ?? [Attendance(memberID: CrewMember.youID), Attendance(memberID: ivan)]
        )
    }

    func testASiteDayFromBeforeWeatherStopsDecodesAsNotStopped() throws {
        let json = #"{"siteID":"\#(UUID().uuidString)","date":20260804,"breakMinutes":0,"present":[]}"#
        let day = try JSONDecoder().decode(SiteDay.self, from: Data(json.utf8))
        XCTAssertFalse(day.isBadWeatherStop)
    }

    func testAStoppedSiteDayRoundTrips() throws {
        let day = siteDay().stoppedForBadWeather(at: nil)
        let decoded = try JSONDecoder().decode(SiteDay.self, from: JSONEncoder().encode(day))
        XCTAssertEqual(decoded, day)
        XCTAssertTrue(decoded.isBadWeatherStop)
    }

    func testAStopWithNoHoursKeepsWhoWasThereAndClearsTheTimes() {
        let late = Attendance(memberID: ivan, start: Fixture.time(9))
        let day = siteDay(present: [Attendance(memberID: CrewMember.youID), late]).stoppedForBadWeather(at: nil)
        XCTAssertTrue(day.isBadWeatherStop)
        XCTAssertNil(day.start)
        XCTAssertNil(day.end)
        XCTAssertEqual(day.present.map(\.memberID), [CrewMember.youID, ivan])
        XCTAssertNil(day.attendance(for: ivan)?.start)
        XCTAssertFalse(day.isBlank)
    }

    func testAStoppedDayWithNobodyAndNoTimesIsStillWorthKeeping() {
        let day = siteDay(start: nil, end: nil, present: []).stoppedForBadWeather(at: nil)
        XCTAssertFalse(day.isBlank)
    }

    func testStoppedAtElevenKeepsTheHoursUntilThen() {
        let leftEarly = Attendance(memberID: ivan, end: Fixture.time(10))
        let day = siteDay(present: [Attendance(memberID: CrewMember.youID, end: Fixture.time(15)), leftEarly])
            .stoppedForBadWeather(at: Fixture.time(11))
        XCTAssertEqual(day.start, Fixture.time(7))
        XCTAssertEqual(day.end, Fixture.time(11))
        // Someone whose own end was later stops with everyone else...
        XCTAssertEqual(day.resolved(for: CrewMember.youID)?.end, Fixture.time(11))
        // ...and someone who had already gone keeps the time they left.
        XCTAssertEqual(day.resolved(for: ivan)?.end, Fixture.time(10))
    }

    func testAPartialStopCountsTheHoursWorked() {
        let day = siteDay().stoppedForBadWeather(at: Fixture.time(11))
        let result = SiteDayCalculator(settings: Fixture.settings(), calendar: calendar).compute(day)
        // 07:00–11:00 less the 30-minute break.
        XCTAssertEqual(result.people.first?.workedMinutes, 210)
    }

    func testAFullStopIsNotNaggedForMissingTimes() {
        let day = siteDay().stoppedForBadWeather(at: nil)
        let result = SiteDayCalculator(settings: Fixture.settings(), calendar: calendar).compute(day)
        XCTAssertEqual(result.crewTotalMinutes, 0)
        XCTAssertTrue(result.people.allSatisfy { $0.warnings.isEmpty })
    }

    func testLiftingTheStopKeepsEverythingElse() {
        let stopped = siteDay().stoppedForBadWeather(at: Fixture.time(11))
        let lifted = stopped.liftingBadWeatherStop()
        XCTAssertFalse(lifted.isBadWeatherStop)
        XCTAssertEqual(lifted.end, Fixture.time(11))
        XCTAssertEqual(lifted.present, stopped.present)
    }

    // MARK: - Your own day

    func testAFullStopGivesYourEmptyDayTheBadWeatherType() {
        let day = siteDay().stoppedForBadWeather(at: nil)
        let merged = SiteCalendarSync.merged(personal: nil, siteDays: [day], on: day.date)
        XCTAssertEqual(merged?.dayTypeID, .badWeather)
    }

    func testMergingAStoppedDayTwiceChangesNothing() {
        let day = siteDay().stoppedForBadWeather(at: nil)
        let once = SiteCalendarSync.merged(personal: nil, siteDays: [day], on: day.date)
        let twice = SiteCalendarSync.merged(personal: once, siteDays: [day], on: day.date)
        XCTAssertEqual(once, twice)
    }

    func testAPartialStopLeavesYourDayAsHoursWorked() {
        let day = siteDay().stoppedForBadWeather(at: Fixture.time(11))
        let merged = SiteCalendarSync.merged(personal: nil, siteDays: [day], on: day.date)
        XCTAssertNil(merged?.dayTypeID)
        XCTAssertEqual(merged?.shifts.first?.end, Fixture.time(11))
    }

    func testAStopDoesNotOverwriteATypeYouChose() {
        let personal = DayRecord(date: Fixture.workingTuesday, dayTypeID: .vacation)
        let day = siteDay().stoppedForBadWeather(at: nil)
        let merged = SiteCalendarSync.merged(personal: personal, siteDays: [day], on: day.date)
        XCTAssertEqual(merged?.dayTypeID, .vacation)
    }

    func testAStopDoesNotTypeADayWithOtherHoursOnIt() {
        let personal = DayRecord(
            date: Fixture.workingTuesday,
            shifts: [Shift(start: Fixture.time(13), end: Fixture.time(17))]
        )
        let day = siteDay().stoppedForBadWeather(at: nil)
        let merged = SiteCalendarSync.merged(personal: personal, siteDays: [day], on: day.date)
        XCTAssertNil(merged?.dayTypeID)
    }

    func testAStopYouWereNotOnLeavesYourDayAlone() {
        let day = siteDay(present: [Attendance(memberID: ivan)]).stoppedForBadWeather(at: nil)
        XCTAssertNil(SiteCalendarSync.merged(personal: nil, siteDays: [day], on: day.date))
    }

    func testLiftingTheStopTakesTheBadWeatherTypeBackOff() {
        let stopped = siteDay().stoppedForBadWeather(at: nil)
        let typed = SiteCalendarSync.merged(personal: nil, siteDays: [stopped], on: stopped.date)
        let lifted = stopped.liftingBadWeatherStop()
        let merged = SiteCalendarSync.merged(
            personal: typed, siteDays: [lifted], on: lifted.date, previousSiteDays: [stopped]
        )
        XCTAssertNil(merged?.dayTypeID)
    }

    func testDeletingAStoppedDayTakesTheTypeAndTheDayWithIt() {
        let stopped = siteDay().stoppedForBadWeather(at: nil)
        let typed = SiteCalendarSync.merged(personal: nil, siteDays: [stopped], on: stopped.date)
        let merged = SiteCalendarSync.merged(
            personal: typed, siteDays: [], on: stopped.date, previousSiteDays: [stopped]
        )
        XCTAssertNil(merged)
    }

    func testBadWeatherYouChoseYourselfStaysWhenNoStopWasLifted() {
        let personal = DayRecord(date: Fixture.workingTuesday, dayTypeID: .badWeather)
        let day = siteDay()
        let merged = SiteCalendarSync.merged(personal: personal, siteDays: [day], on: day.date, previousSiteDays: [day])
        XCTAssertEqual(merged?.dayTypeID, .badWeather)
    }

    // MARK: - Counting them

    private func sheet(_ days: [SiteDay], language: ExportLanguage = .english) -> ReportTable {
        let settings = Fixture.settings(export: ExportPreferences(language: language, ownerName: "Marijo"))
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return SiteSheetBuilder(settings: settings, calendar: calendar)
            .makeTable(
                site: site,
                crew: [CrewMember(id: ivan, siteID: site.id, name: "Ivan")],
                results: days.map(calculator.compute),
                range: CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))
            )
    }

    private func onDay(_ day: Int, _ build: (SiteDay) -> SiteDay = { $0 }) -> SiteDay {
        var siteDay = self.siteDay()
        siteDay.date = Fixture.date(2026, 8, day)
        return build(siteDay)
    }

    func testTheSiteMonthCountsBadWeatherDaysApart() {
        let days = [
            onDay(3),
            onDay(4) { $0.stoppedForBadWeather(at: nil) },
            onDay(5) { $0.stoppedForBadWeather(at: Fixture.time(11)) },
            // Another month's stop is not this month's.
            { var d = self.siteDay().stoppedForBadWeather(at: nil); d.date = Fixture.date(2026, 9, 1); return d }()
        ]
        let figures = SiteMonthFigures(
            days: days,
            month: YearMonth(year: 2026, month: 8),
            calculator: SiteDayCalculator(settings: Fixture.settings(), calendar: calendar)
        )
        XCTAssertEqual(figures.daysWritten, 3)
        XCTAssertEqual(figures.badWeatherDays, 2)
        // 8h on the 3rd, nothing on the 4th, 3h 30m on the 5th; twice, for two people.
        XCTAssertEqual(figures.yourMinutes, 510 + 210)
        XCTAssertEqual(figures.crewMinutes, (510 + 210) * 2)
    }

    func testTheSheetCountsBadWeatherDaysInItsSummary() {
        let table = sheet([onDay(3), onDay(4) { $0.stoppedForBadWeather(at: nil) }])
        XCTAssertEqual(table.tiles.first { $0.label == "Bad-weather days" }?.value, "1")
    }

    func testASheetWithoutBadWeatherHasNoTileForIt() {
        let table = sheet([onDay(3)])
        XCTAssertFalse(table.tiles.contains { $0.label == "Bad-weather days" })
    }

    func testTheSheetSaysWhichDaysWereRainedOff() {
        var stopped = onDay(4) { $0.stoppedForBadWeather(at: Fixture.time(11)) }
        stopped.note = "Storm"
        let table = sheet([onDay(3), stopped], language: .german)
        let notes = table.rows.filter { $0.role == .day }.map { $0.values.last ?? "" }
        XCTAssertEqual(notes, ["", "Schlechtwetter · Storm"])
    }
}
