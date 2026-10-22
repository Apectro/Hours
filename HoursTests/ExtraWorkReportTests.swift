import XCTest
@testable import Hours

/// The report for the boss: which jobs it carries, the material in total,
/// and who confirmed what.
final class ExtraWorkReportTests: XCTestCase {
    private let site = UUID()
    private let otherSite = UUID()
    private let calendar = Fixture.calendar()
    private let base = Date(timeIntervalSince1970: 1_792_000_000)
    private let signature = ExtraWorkSignature(
        signerName: "Ing. M. Horvat",
        signedAt: Date(timeIntervalSince1970: 1_792_000_000),
        strokes: [[SignaturePoint(x: 0, y: 0.5), SignaturePoint(x: 2, y: 0.4)]]
    )

    private func job(
        _ day: Int,
        _ description: String,
        _ items: [ExtraWorkItem] = [],
        site: UUID? = nil,
        status: ExtraWorkStatus = .open,
        createdOffset: TimeInterval = 0
    ) -> ExtraWorkJob {
        let moment = base.addingTimeInterval(TimeInterval(day) * 86_400 + createdOffset)
        return ExtraWorkJob(
            siteID: site ?? self.site,
            date: Fixture.date(2026, 10, day),
            description: description,
            items: items,
            status: status,
            createdAt: moment,
            updatedAt: moment
        )
    }

    private func item(_ name: String, _ quantity: String, _ unit: ExtraWorkUnit = .pieces) -> ExtraWorkItem {
        ExtraWorkItem(name: name, quantity: Decimal(string: quantity)!, unit: unit)
    }

    /// The week of the mockup: Monday 19 to Thursday 22 October 2026.
    private var week: [ExtraWorkJob] {
        [
            job(19, "Ceiling lamps, staff kitchen", [item("Ceiling lamp LED", "12")]),
            job(20, "Emergency lights, basement garage", [item("Emergency light", "6"), item("Cable NYM 3×1.5", "30", .metres)]),
            job(21, "Extra sockets, office 1.04", [item("Junction box", "8"), item("Cable NYM 3×1.5", "40", .metres)]),
            job(22, "Emergency lighting, stairwell 2nd floor", [item("Emergency light", "8"), item("Cable NYM 3×1.5", "25", .metres)]),
            job(22, "Ceiling lamps, corridor B", [item("Ceiling lamp LED", "10"), item("Junction box", "10")], createdOffset: 60)
        ]
    }

    // MARK: - Totals

    func testTotalsAddUpEachItemInItsUnit() {
        let report = ExtraWorkReport(siteID: site, jobs: week)
        let lines = report.totals.map { "\($0.name) \(ExtraWorkQuantity.string($0.quantity, decimalSeparator: ".")) \($0.unit.code)" }
        XCTAssertEqual(lines, [
            "Emergency light 14 pcs",
            "Ceiling lamp LED 22 pcs",
            "Junction box 18 pcs",
            "Cable NYM 3×1.5 95 m"
        ])
    }

    func testSpellingsDifferingInCaseOrAccentsAreOneItemNamedAsMostRecentlyWritten() {
        let report = ExtraWorkReport(siteID: site, jobs: [
            job(19, "a", [item("Kabelkanal Ä", "2")]),
            job(21, "b", [item("kabelkanal a", "3")]),
            job(20, "c", [item("KABELKANAL  Ä", "1")])
        ])
        XCTAssertEqual(report.totals.count, 1)
        XCTAssertEqual(report.totals[0].name, "kabelkanal a")
        XCTAssertEqual(report.totals[0].quantity, 6)
    }

    func testTheSameItemInTwoUnitsIsTwoLines() {
        let report = ExtraWorkReport(siteID: site, jobs: [
            job(19, "a", [item("Cable", "10", .metres)]),
            job(20, "b", [item("Cable", "2", .pieces)])
        ])
        XCTAssertEqual(report.totals.map(\.unit), [.pieces, .metres])
    }

    func testTypedUnitsTotalTogetherWhateverTheirCase() {
        let report = ExtraWorkReport(siteID: site, jobs: [
            job(19, "a", [item("Tape", "1", .custom("Rolle"))]),
            job(20, "b", [item("Tape", "2", .custom("rolle"))])
        ])
        XCTAssertEqual(report.totals.count, 1)
        XCTAssertEqual(report.totals[0].quantity, 3)
        XCTAssertEqual(report.totals[0].unit, .custom("rolle"), "the newest spelling")
    }

    func testDecimalQuantitiesAddExactly() {
        let report = ExtraWorkReport(siteID: site, jobs: [
            job(19, "a", [item("Cable", "12.5", .metres)]),
            job(20, "b", [item("Cable", "0.1", .metres)]),
            job(21, "c", [item("Cable", "0.2", .metres)])
        ])
        XCTAssertEqual(report.totals[0].quantity, Decimal(string: "12.8"))
    }

    // MARK: - Jobs

    func testJobsAreNewestDayFirstAndInTheOrderWrittenWithinADay() {
        let report = ExtraWorkReport(siteID: site, jobs: week)
        XCTAssertEqual(report.jobs.map(\.description).prefix(3), [
            "Emergency lighting, stairwell 2nd floor",
            "Ceiling lamps, corridor B",
            "Extra sockets, office 1.04"
        ])
        XCTAssertEqual(report.period, CalendarDateRange(start: Fixture.date(2026, 10, 19), end: Fixture.date(2026, 10, 22)))
    }

    func testAnEmptyReportHasNoPeriod() {
        let report = ExtraWorkReport(siteID: site, jobs: [])
        XCTAssertTrue(report.isEmpty)
        XCTAssertNil(report.period)
    }

    func testOtherSitesNeverReachTheReport() {
        let report = ExtraWorkReport(siteID: site, jobs: week + [job(22, "Elsewhere", site: otherSite)])
        XCTAssertEqual(report.jobs.count, 5)
    }

    // MARK: - Hours

    func testHoursAreAbsentUnlessAJobHasThem() {
        XCTAssertFalse(ExtraWorkReport(siteID: site, jobs: week).hasHours)

        var jobs = week
        jobs[3].hours = [ExtraWorkHours(name: "Ivan", minutes: 180), ExtraWorkHours(name: "Marko", minutes: 180)]
        jobs[1].hours = [ExtraWorkHours(name: "Luka", minutes: 150)]
        let report = ExtraWorkReport(siteID: site, jobs: jobs)
        XCTAssertTrue(report.hasHours)
        XCTAssertEqual(report.totalMinutes, 510)
    }

    // MARK: - Confirmation

    func testConfirmedCountsJobsTheClientSigned() {
        var jobs = week
        jobs[4].clientSignature = signature
        jobs[2].clientSignature = signature
        let report = ExtraWorkReport(siteID: site, jobs: jobs)
        XCTAssertEqual(report.confirmedCount, 2)
        XCTAssertTrue(report.isConfirmed(jobs[4]))
        XCTAssertFalse(report.isConfirmed(jobs[0]))
    }

    /// A signature under the report confirms every job in it.
    func testASignatureOnTheReportConfirmsEveryJob() {
        let report = ExtraWorkReport(siteID: site, jobs: week, clientSignature: signature)
        XCTAssertEqual(report.confirmedCount, 5)
    }

    // MARK: - Choosing the jobs

    private let today = Fixture.date(2026, 10, 22)

    func testNotSentYetIsEveryOpenJobWhateverItsDate() {
        var jobs = week
        jobs[0].status = .sent
        jobs[1].status = .invoiced
        jobs.append(job(2, "Last month, forgotten"))
        let chosen = ExtraWorkRange.notSentYet.select(jobs, siteID: site, today: today, calendar: calendar)
        XCTAssertEqual(Set(chosen.map(\.description)), [
            "Extra sockets, office 1.04",
            "Emergency lighting, stairwell 2nd floor",
            "Ceiling lamps, corridor B",
            "Last month, forgotten"
        ])
    }

    func testThisWeekIsTheCalendarWeekWhateverWasSent() {
        var jobs = week
        jobs[0].status = .sent
        jobs.append(job(18, "Sunday before"))
        let chosen = ExtraWorkRange.thisWeek.select(jobs, siteID: site, today: today, calendar: calendar)
        XCTAssertEqual(chosen.count, 5, "Monday 19 to Sunday 25; the 18th is the week before")
    }

    func testPickedDatesIncludeBothEnds() {
        let range = CalendarDateRange(start: Fixture.date(2026, 10, 20), end: Fixture.date(2026, 10, 21))
        let chosen = ExtraWorkRange.dates(range).select(week, siteID: site, today: today, calendar: calendar)
        XCTAssertEqual(chosen.map(\.date.day).sorted(), [20, 21])
    }

    func testChoosingNeverTakesAnotherSitesJobs() {
        let chosen = ExtraWorkRange.notSentYet.select([job(22, "x", site: otherSite)], siteID: site, today: today, calendar: calendar)
        XCTAssertTrue(chosen.isEmpty)
    }

    func testCountsForTheDayScreen() {
        var jobs = week
        jobs[0].status = .sent
        let counts = ExtraWorkReport.counts(jobs, on: today)
        XCTAssertEqual(counts.onDay, 2)
        XCTAssertEqual(counts.notSent, 4)
    }

    func testDaysWithJobsForTheMonthGrid() {
        XCTAssertEqual(ExtraWorkReport.dateKeys(week), [20_261_019, 20_261_020, 20_261_021, 20_261_022])
    }
}
