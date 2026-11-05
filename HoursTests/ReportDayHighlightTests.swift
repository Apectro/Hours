import XCTest
@testable import Hours

/// Sick leave, holidays and days nobody worked stand out on the printed
/// sheets (2026-11): which days, in which colour, and where.
final class ReportDayHighlightTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let site = Site(name: "Jarunski Dvori")
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))

    private func type(_ id: DayTypeID) -> DayTypeDefinition {
        DayTypeCatalog().definition(for: id)
    }

    // MARK: - Which days, in which colour

    func testEveryDayAwayIsHighlightedInItsOwnTypesColour() {
        XCTAssertEqual(ReportDayHighlight.tint(for: type(.sick)), .red)
        XCTAssertEqual(ReportDayHighlight.tint(for: type(.vacation)), .teal)
        XCTAssertEqual(ReportDayHighlight.tint(for: type(.holiday)), .purple)
        XCTAssertEqual(ReportDayHighlight.tint(for: type(.personal)), .indigo)
        XCTAssertEqual(ReportDayHighlight.tint(for: type(.timeOffInLieu)), .orange)
        XCTAssertEqual(ReportDayHighlight.tint(for: type(.dayOff)), .brown)
        XCTAssertEqual(ReportDayHighlight.tint(for: type(.badWeather)), .yellow)
        XCTAssertEqual(ReportDayHighlight.tint(for: type(.other)), .gray)
    }

    /// Work is the ordinary day, and a weekend is already greyed.
    func testWorkAndWeekendsAreNotHighlighted() {
        XCTAssertNil(ReportDayHighlight.tint(for: type(.work)))
        XCTAssertNil(ReportDayHighlight.tint(for: type(.weekend)))
    }

    /// A holiday somebody worked shows times, so it is an ordinary row.
    func testADayWithHoursWorkedIsNotHighlighted() {
        XCTAssertNil(ReportDayHighlight.tint(for: type(.holiday), workedMinutes: 240))
        XCTAssertEqual(ReportDayHighlight.tint(for: type(.holiday), workedMinutes: 0), .purple)
    }

    /// A type of the user's own follows its own colour; one made for work
    /// reads as work.
    func testCustomTypesUseTheirOwnColourUnlessTheyAreWork() {
        let training = DayTypeDefinition(id: DayTypeID("training"), name: "Training", symbolName: "book",
                                         tint: .pink, expectation: .creditedAbsence, showsTimesByDefault: false)
        let nightShift = DayTypeDefinition(id: DayTypeID("night"), name: "Night shift", symbolName: "moon",
                                           tint: .indigo, expectation: .scheduled, showsTimesByDefault: true)
        XCTAssertEqual(ReportDayHighlight.tint(for: training), .pink)
        XCTAssertNil(ReportDayHighlight.tint(for: nightShift))

        var sick = type(.sick)
        sick.tint = .green
        XCTAssertEqual(ReportDayHighlight.tint(for: sick), .green, "a recoloured type prints in its new colour")
    }

    func testANoWorkDayTakesItsReasonsColour() {
        let catalog = DayTypeCatalog()
        XCTAssertEqual(ReportDayHighlight.tint(for: .dayOff, catalog: catalog), .brown)
        XCTAssertEqual(ReportDayHighlight.tint(for: .badWeather, catalog: catalog), .yellow)
        XCTAssertEqual(ReportDayHighlight.tint(for: .noWork, catalog: catalog), .gray)
        XCTAssertNil(ReportDayHighlight.tint(for: .crewElsewhere, catalog: catalog), "the crew was working elsewhere")
    }

    // MARK: - Legible on paper, in colour and in black and white

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ value: UInt32) -> Double {
            let c = Double(value & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(hex >> 16) + 0.7152 * channel(hex >> 8) + 0.0722 * channel(hex)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (light, dark) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (light + 0.05) / (dark + 0.05)
    }

    func testTheWordReadsOnItsWashAndTheWashStaysLight() {
        for tint in TypeTint.allCases {
            XCTAssertGreaterThanOrEqual(contrast(tint.printInk, tint.printWash), 4.5, "\(tint): the word is too faint on its wash")
            XCTAssertGreaterThanOrEqual(contrast(tint.printInk, 0xFFFFFF), 4.5, "\(tint): the word is too faint on white")
            // Printed in grey, a wash this light is a faint tone, not a block.
            XCTAssertGreaterThanOrEqual(luminance(tint.printWash), 0.8, "\(tint): the wash is too dark for paper")
        }
    }

    // MARK: - On the sheets

    func testATimesheetHighlightsTheDayAwayAndNotTheWorkingDays() {
        let settings = Fixture.settings(export: ExportPreferences(language: .english))
        let range = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 7))
        let records: [Int: DayRecord] = [
            Fixture.workingMonday.key: DayRecord(date: Fixture.workingMonday, start: Fixture.time(8), end: Fixture.time(16)),
            Fixture.workingTuesday.key: DayRecord(date: Fixture.workingTuesday, dayTypeID: .sick)
        ]
        let days = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: Fixture.longAgo)
            .days(in: range, records: records, holidays: [])
        let table = ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "")
            .makeTable(days: days, range: range, title: "Hours", countingThrough: range.end)
        let row = { (date: CalendarDate) in table.rows.first { $0.id == date.key } }
        XCTAssertEqual(row(Fixture.workingTuesday)?.dayTint, .red)
        XCTAssertNil(row(Fixture.workingMonday)?.dayTint)
        XCTAssertNil(row(Fixture.saturday)?.dayTint, "a weekend keeps its grey")
    }

    private func siteSheet(_ days: [SiteDay], crew: [CrewMember], language: ExportLanguage = .english) -> ReportTable {
        let settings = Fixture.settings(export: ExportPreferences(language: language, ownerName: "Marijo"))
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—")
            .makeTable(site: site, crew: crew, results: days.map(calculator.compute), range: august)
    }

    private func workday(_ day: Int, present: [UUID], absences: [CrewAbsence] = []) -> SiteDay {
        SiteDay(siteID: site.id, date: Fixture.date(2026, 8, day), start: Fixture.time(7), end: Fixture.time(16),
                breakMinutes: 30, present: present.map { Attendance(memberID: $0) }, absences: absences)
    }

    /// Marijo sick while Dusko worked: only Marijo's cell stands out.
    func testOnASiteSheetOnlyThePersonAwayIsHighlighted() {
        let dusko = CrewMember(siteID: site.id, name: "Dusko", sortOrder: 0)
        let table = siteSheet([
            workday(3, present: [CrewMember.youID, dusko.id]),
            workday(4, present: [dusko.id], absences: [CrewAbsence(memberID: CrewMember.youID, dayTypeID: .sick)])
        ], crew: [dusko])
        let sick = table.rows[1]
        // Groups: date, day, Marijo, Dusko, notes.
        XCTAssertEqual(sick.groupTints, [2: .red])
        XCTAssertNil(sick.dayTint)
        XCTAssertTrue(table.rows[0].groupTints.isEmpty)
        XCTAssertTrue(table.legend.hasSuffix(ExportLanguage.english(.dayHighlightLegend)), table.legend)
    }

    func testASheetWithNothingHighlightedSaysNothingAboutShading() {
        let table = siteSheet([workday(3, present: [CrewMember.youID])], crew: [])
        XCTAssertFalse(table.hasDayHighlights)
        XCTAssertEqual(table.legend, ExportLanguage.english(.siteLegend))
    }

    /// A day off for the whole site: the whole row.
    func testADayOffForEveryoneHighlightsTheRow() {
        let table = siteSheet([
            workday(3, present: [CrewMember.youID]),
            SiteDay.noWork(.dayOff, siteID: site.id, date: Fixture.date(2026, 8, 4), jobID: nil)
        ], crew: [])
        XCTAssertNil(table.rows[0].dayTint)
        XCTAssertEqual(table.rows[1].dayTint, .brown)
    }

    func testTheLegendLineIsInTheExportLanguage() {
        let dusko = CrewMember(siteID: site.id, name: "Dusko", sortOrder: 0)
        let table = siteSheet([
            workday(4, present: [dusko.id], absences: [CrewAbsence(memberID: CrewMember.youID, dayTypeID: .sick)])
        ], crew: [dusko], language: .croatian)
        XCTAssertTrue(table.legend.hasSuffix(ExportLanguage.croatian(.dayHighlightLegend)), table.legend)
        XCTAssertTrue(table.legend.contains("Osjenčano"))
    }

    /// A combined sheet for two sites marks the person away on each of
    /// their rows that day.
    func testACombinedSheetHighlightsThePersonAway() {
        let other = Site(name: "Trg Pravde Zagreb")
        let settings = Fixture.settings(export: ExportPreferences(language: .english, ownerName: "Marijo"))
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let dusko = CrewMember(siteID: site.id, name: "Dusko", sortOrder: 0)
        let days = [
            workday(4, present: [dusko.id], absences: [CrewAbsence(memberID: CrewMember.youID, dayTypeID: .vacation)]),
            SiteDay(siteID: other.id, date: Fixture.date(2026, 8, 5), start: Fixture.time(7), end: Fixture.time(16),
                    breakMinutes: 30, present: [Attendance(memberID: CrewMember.youID)])
        ]
        let table = SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—")
            .makeTable(sites: [site, other], crew: [dusko], results: days.map(calculator.compute), range: august)
        // Groups: date, day, site, Marijo, Dusko, notes.
        XCTAssertEqual(table.rows[0].groupTints, [3: .teal])
        XCTAssertTrue(table.rows[1].groupTints.isEmpty)
        XCTAssertTrue(table.hasDayHighlights)
    }

    /// A sheet split across pages keeps each mark on its own person.
    func testASplitSheetMovesTheMarkWithItsPerson() {
        let crew = (0..<6).map { CrewMember(siteID: site.id, name: "Person \($0)", sortOrder: $0) }
        let table = siteSheet([
            workday(4, present: [CrewMember.youID] + crew.dropLast().map(\.id),
                    absences: [CrewAbsence(memberID: crew[5].id, dayTypeID: .sick)])
        ], crew: crew)
        let parts = SiteSheetBuilder.split(table, peoplePerPage: 4)
        XCTAssertEqual(parts.count, 2)
        let second = parts[1].rows[0]
        // Second part: date, day, people 5–7 (Person 3, 4, 5), notes; Person 5 is group 4.
        XCTAssertEqual(second.groupTints, [4: .red])
        XCTAssertTrue(parts[0].rows[0].groupTints.isEmpty)
    }

    // MARK: - The workbook

    func testTheWorkbookFillsTheCellsOfTheDayAway() {
        let dusko = CrewMember(siteID: site.id, name: "Dusko", sortOrder: 0)
        let table = siteSheet([
            workday(4, present: [dusko.id], absences: [CrewAbsence(memberID: CrewMember.youID, dayTypeID: .sick)])
        ], crew: [dusko])
        let package = String(decoding: XLSXWriter.data(for: table, preferences: ExportPreferences()), as: UTF8.self)
        let red = TypeTint.red
        XCTAssertTrue(package.contains(String(format: "FF%06X", red.printWash)), "the red wash is not a fill")
        XCTAssertTrue(package.contains("<cellXfs count=\"\(27 + TypeTint.allCases.count)\">"))
        let style = 27 + (TypeTint.allCases.firstIndex(of: red) ?? 0)
        XCTAssertTrue(package.contains("s=\"\(style)\"><is><t xml:space=\"preserve\">Sick leave</t>"), "the sick cell is not filled red")
    }
}
