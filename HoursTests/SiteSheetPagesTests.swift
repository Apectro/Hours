import XCTest
@testable import Hours

/// A big crew's sheet split into parts for the printed page: a few people at
/// a time, each part with the date, the day and the notes.
final class SiteSheetPagesTests: XCTestCase {
    private let site = Site(name: "Bau Süd")
    private let calendar = Fixture.calendar()
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))

    private func settings(language: ExportLanguage = .english) -> AppSettings {
        Fixture.settings(export: ExportPreferences(language: language, ownerName: "Marijo"))
    }

    /// You and `others` more, in that order.
    private func crew(_ others: Int) -> [CrewMember] {
        (0..<others).map { CrewMember(siteID: site.id, name: "P\($0 + 2)", isHidden: false, sortOrder: $0) }
    }

    private func day(
        _ d: Int,
        present: [UUID],
        own: [UUID: Attendance] = [:],
        absences: [CrewAbsence] = [],
        note: String = ""
    ) -> SiteDay {
        SiteDay(
            siteID: site.id,
            date: Fixture.date(2026, 8, d),
            start: Fixture.time(7),
            end: Fixture.time(16),
            breakMinutes: 30,
            present: present.map { own[$0] ?? Attendance(memberID: $0) },
            note: note,
            absences: absences
        )
    }

    private func table(crew: [CrewMember], days: [SiteDay], language: ExportLanguage = .english) -> ReportTable {
        let settings = settings(language: language)
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return SiteSheetBuilder(settings: settings, calendar: calendar)
            .makeTable(site: site, crew: crew, results: days.map(calculator.compute), range: august)
    }

    /// Seven people — you and P2…P7 — on two days, everyone there.
    private func sevenPeople() -> (crew: [CrewMember], table: ReportTable) {
        let crew = crew(6)
        let everyone = [CrewMember.youID] + crew.map(\.id)
        return (crew, table(crew: crew, days: [
            day(3, present: everyone, note: "Crane"),
            day(4, present: everyone)
        ]))
    }

    // MARK: - How many to a page

    func testGroupsAreBalancedRatherThanFilledInOrder() {
        XCTAssertEqual(SiteSheetBuilder.groupSizes(people: 7, perPage: 5), [4, 3])
        XCTAssertEqual(SiteSheetBuilder.groupSizes(people: 9, perPage: 5), [5, 4])
        XCTAssertEqual(SiteSheetBuilder.groupSizes(people: 10, perPage: 5), [5, 5])
        XCTAssertEqual(SiteSheetBuilder.groupSizes(people: 11, perPage: 5), [4, 4, 3])
        XCTAssertEqual(SiteSheetBuilder.groupSizes(people: 5, perPage: 5), [5])
        XCTAssertEqual(SiteSheetBuilder.groupSizes(people: 3, perPage: 5), [3])
        XCTAssertEqual(SiteSheetBuilder.groupSizes(people: 3, perPage: 1), [1, 1, 1])
        XCTAssertEqual(SiteSheetBuilder.groupSizes(people: 0, perPage: 5), [])
        // Nobody fits is treated as one at a time rather than as no pages.
        XCTAssertEqual(SiteSheetBuilder.groupSizes(people: 2, perPage: 0), [1, 1])
    }

    func testThePeopleOnASheetAreCounted() {
        XCTAssertEqual(SiteSheetBuilder.peopleCount(in: sevenPeople().table), 7)
        let timesheet = ReportTable(title: "", subtitle: "", columns: [.date, .worked], rows: [], totals: [])
        XCTAssertNil(SiteSheetBuilder.peopleCount(in: timesheet))
    }

    // MARK: - Nothing changes when everyone fits

    func testASheetEveryoneFitsOnIsLeftAlone() {
        let (_, t) = sevenPeople()
        XCTAssertEqual(SiteSheetBuilder.split(t, peoplePerPage: 7), [t])
        XCTAssertEqual(SiteSheetBuilder.split(t, peoplePerPage: 20), [t])
        XCTAssertTrue(t.partLabel.isEmpty)
    }

    func testATimesheetIsNeverSplit() {
        let timesheet = ReportTable(title: "", subtitle: "", columns: [.date, .worked], rows: [], totals: [])
        XCTAssertEqual(SiteSheetBuilder.split(timesheet, peoplePerPage: 1), [timesheet])
    }

    // MARK: - The parts

    func testEachPartHasTheDateTheDayItsPeopleAndTheNotes() {
        let (_, t) = sevenPeople()
        let parts = SiteSheetBuilder.split(t, peoplePerPage: 5)
        XCTAssertEqual(parts.count, 2)

        XCTAssertEqual(parts[0].columns, [.date, .weekday] + Array(repeating: [ReportColumn.times, .worked], count: 4).flatMap { $0 } + [.note])
        XCTAssertEqual(parts[1].columns, [.date, .weekday] + Array(repeating: [ReportColumn.times, .worked], count: 3).flatMap { $0 } + [.note])
        XCTAssertEqual(parts[0].columnGroups.map(\.title), ["Date", "Day", "Marijo", "P2", "P3", "P4", "Notes"])
        XCTAssertEqual(parts[1].columnGroups.map(\.title), ["Date", "Day", "P5", "P6", "P7", "Notes"])
        XCTAssertEqual(parts[1].columnGroups.map(\.span), [1, 1, 2, 2, 2, 1])
        XCTAssertEqual(parts[1].headingOverrides, ["Date", "Day", "From–to", "Hours", "From–to", "Hours", "From–to", "Hours", "Notes"])
        XCTAssertEqual(parts[1].validGroups.count, 6, "the groups no longer describe the columns")

        for part in parts {
            XCTAssertEqual(part.kind, .siteSheet)
            XCTAssertEqual(part.rows.count, t.rows.count)
            XCTAssertEqual(part.rows.map(\.id), t.rows.map(\.id))
            // The header block is the whole site's.
            XCTAssertEqual(part.title, t.title)
            XCTAssertEqual(part.eyebrow, t.eyebrow)
            XCTAssertEqual(part.detail, t.detail)
            XCTAssertEqual(part.tiles, t.tiles)
            for (row, original) in zip(part.rows, t.rows) {
                XCTAssertEqual(row.values.count, part.columns.count)
                XCTAssertEqual(row.minutes.count, part.columns.count)
                XCTAssertEqual(Array(row.values.prefix(2)), Array(original.values.prefix(2)))
                XCTAssertEqual(row.values.last, original.values.last)
            }
        }
        // The first day: date, day, then P5's times and hours on part two.
        XCTAssertEqual(parts[1].written[0].values[0], t.written[0].values[0])
        XCTAssertEqual(parts[1].written[0].values[2], t.written[0].values[2 + 2 * 4])
        XCTAssertEqual(parts[1].written[0].minutes[3], t.written[0].minutes[3 + 2 * 4])
        XCTAssertEqual(parts[0].written[0].values.last, "Crane")
    }

    func testEachPartClosesWithItsOwnPeoplesTotals() {
        let (_, t) = sevenPeople()
        let parts = SiteSheetBuilder.split(t, peoplePerPage: 5)
        for part in parts {
            XCTAssertEqual(part.trailingSummaryRows, 2)
            let total = part.rows[part.rows.count - 2]
            let count = part.rows[part.rows.count - 1]
            XCTAssertEqual(total.role, .total)
            XCTAssertEqual(total.values[0], "Month total")
            XCTAssertEqual(count.values[0], "Days worked")
            XCTAssertEqual(total.values.count, part.columns.count)
        }
        XCTAssertEqual(parts[1].rows[parts[1].rows.count - 2].values[3], "17h")
        XCTAssertEqual(parts[1].rows[parts[1].rows.count - 2].minutes[3], 1_020)
        XCTAssertEqual(parts[1].rows[parts[1].rows.count - 1].values[3], "2")
    }

    func testTheLineSaysWhichPeopleArePrinted() {
        let (_, t) = sevenPeople()
        let parts = SiteSheetBuilder.split(t, peoplePerPage: 5)
        XCTAssertEqual(parts.map(\.partLabel), ["People 1–4 of 7", "People 5–7 of 7"])

        let one = SiteSheetBuilder.split(t, peoplePerPage: 1)
        XCTAssertEqual(one.count, 7)
        XCTAssertEqual(one[2].partLabel, "People 3 of 7")
    }

    func testTheLineIsInTheExportLanguage() {
        XCTAssertEqual(ExportLanguage.croatian.peopleOnPage(1...5, of: 9), "Osobe 1–5 od 9")
        XCTAssertEqual(ExportLanguage.german.peopleOnPage(6...9, of: 9), "Personen 6–9 von 9")
        XCTAssertEqual(ExportLanguage.english.peopleOnPage(4...4, of: 9), "People 4 of 9")
        for language in ExportLanguage.allCases {
            let line = language.peopleOnPage(1...5, of: 9)
            XCTAssertTrue(line.contains("1–5") && line.contains("9"), "\(language.rawValue): \(line)")
            XCTAssertFalse(line.contains("{"), "\(language.rawValue) left a placeholder: \(line)")
        }
    }

    func testTheAppendixFollowsTheWholeSheetNotEachPart() {
        var (_, t) = sevenPeople()
        t.signOff = [ReportSignOff(memberID: CrewMember.youID, name: "Marijo", hours: "17h 0m", status: "",
                                   isChanged: false, strokes: [], aspectRatio: 3)]
        let parts = SiteSheetBuilder.split(t, peoplePerPage: 5)
        XCTAssertTrue(parts.allSatisfy { $0.signOff.isEmpty && $0.diary == nil })
        // Each part still closes with the line to sign on and the legend.
        XCTAssertTrue(parts.allSatisfy { $0.signatures == t.signatures && $0.legend == t.legend })
    }

    // MARK: - Marks follow their person

    func testAnAbsenceIsMarkedOnTheRightGroupOfItsPart() {
        let crew = crew(6)
        let p6 = crew[4]
        let everyone = [CrewMember.youID] + crew.map(\.id)
        let t = table(crew: crew, days: [
            day(3, present: everyone.filter { $0 != p6.id }, absences: [CrewAbsence(memberID: p6.id, dayTypeID: .sick)]),
            day(4, present: everyone)
        ])
        // P6 is person 6 of 7, group 2 + 5 on the whole sheet.
        XCTAssertEqual(t.written[0].mergedGroups, [7])
        let parts = SiteSheetBuilder.split(t, peoplePerPage: 5)
        XCTAssertEqual(parts[0].written[0].mergedGroups, [])
        // On part two (P5, P6, P7) P6 is the second person: group 2 + 1.
        XCTAssertEqual(parts[1].written[0].mergedGroups, [3])
        XCTAssertEqual(parts[1].written[0].values[4], t.written[0].values[2 + 2 * 5])
    }

    func testALateArrivalIsFlaggedInItsPart() {
        let crew = crew(6)
        let p3 = crew[1]
        let everyone = [CrewMember.youID] + crew.map(\.id)
        let late = Attendance(memberID: p3.id, start: Fixture.time(8, 15))
        let t = table(crew: crew, days: [day(3, present: everyone, own: [p3.id: late])])
        // P3 is the third person: columns 2 + 2·2 and the one after.
        XCTAssertEqual(t.written[0].flagged, [6, 7])
        let parts = SiteSheetBuilder.split(t, peoplePerPage: 2)
        XCTAssertEqual(parts.map(\.partLabel), ["People 1–2 of 7", "People 3–4 of 7", "People 5–6 of 7", "People 7 of 7"])
        XCTAssertEqual(parts[0].written[0].flagged, [])
        XCTAssertEqual(parts[1].written[0].flagged, [2, 3])
        XCTAssertEqual(parts[1].written[0].values[2], "08:15–16:00")
    }

    func testAnAbsenceRowIsLeftOffAPartWhereNobodyWasAway() {
        let crew = crew(6)
        let p7 = crew[5]
        let everyone = [CrewMember.youID] + crew.map(\.id)
        let t = table(crew: crew, days: [
            day(3, present: everyone.filter { $0 != p7.id }, absences: [CrewAbsence(memberID: p7.id, dayTypeID: .sick)])
        ])
        XCTAssertEqual(t.trailingSummaryRows, 3)
        let parts = SiteSheetBuilder.split(t, peoplePerPage: 5)
        XCTAssertEqual(parts[0].trailingSummaryRows, 2)
        XCTAssertEqual(parts[0].rows.count, t.rows.count - 1)
        XCTAssertFalse(parts[0].rows.contains { $0.values.first == "Sick days" })
        XCTAssertEqual(parts[1].trailingSummaryRows, 3)
        let sick = parts[1].rows[parts[1].rows.count - 1]
        XCTAssertEqual(sick.values[0], "Sick days")
        XCTAssertEqual(sick.values[7], "1")
    }
}
