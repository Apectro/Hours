import XCTest
@testable import Hours

/// The extra-work report as the boss receives it — what is done, then what
/// is still in progress if included, then the material used: every word the
/// app writes in the export language, the user's own words untouched, and
/// the same content in the PDF's blocks, the workbook's two sheets and the
/// CSV.
final class ExtraWorkExportTests: XCTestCase {
    private let site = Site(name: "Trg Pravde Zagreb")
    private let calendar = Fixture.calendar()
    private let base = Date(timeIntervalSince1970: 1_792_000_000)
    private let ivan = UUID()

    private func settings(_ language: ExportLanguage = .english, decimal: DecimalSeparator = .point) -> AppSettings {
        Fixture.settings(export: ExportPreferences(decimalSeparator: decimal, language: language, ownerName: "Marijo Mikša"))
    }

    private func job(_ day: Int, _ description: String, _ items: [ExtraWorkItem], offset: TimeInterval = 0, done: Bool = true) -> ExtraWorkJob {
        let moment = base.addingTimeInterval(TimeInterval(day) * 86_400 + offset)
        return ExtraWorkJob(
            siteID: site.id, date: Fixture.date(2026, 10, day), description: description, items: items,
            isDone: done, doneAt: done ? moment : nil, createdAt: moment, updatedAt: moment
        )
    }

    private func item(_ name: String, _ quantity: String, _ unit: ExtraWorkUnit = .pieces) -> ExtraWorkItem {
        ExtraWorkItem(name: name, quantity: Decimal(string: quantity)!, unit: unit)
    }

    private var signature: ExtraWorkSignature {
        ExtraWorkSignature(signerName: "Ing. M. Horvat", signedAt: base, strokes: [[SignaturePoint(x: 0, y: 0.5), SignaturePoint(x: 2, y: 0.3)]])
    }

    private func report(withHours: Bool = true, reportSigned: Bool = false, inProgress: Bool = false) -> ExtraWorkReport {
        var stairwell = job(22, "Emergency lighting, stairwell 2nd floor", [item("Emergency light", "8"), item("Cable NYM 3×1.5", "25.5", .metres)])
        if withHours {
            stairwell.hours = [ExtraWorkHours(memberID: ivan, name: "Ivan", minutes: 180), ExtraWorkHours(name: "Marko", minutes: 180)]
        }
        var corridor = job(22, "Ceiling lamps, corridor B", [item("Ceiling lamp LED", "10"), item("Junction box", "10")], offset: 60)
        corridor.clientSignature = signature
        let kitchen = job(19, "Ceiling lamps, staff kitchen", [item("Ceiling lamp LED", "12")])
        var jobs = [kitchen, stairwell, corridor]
        if inProgress {
            jobs.append(job(21, "Cable trays, plant room", [item("Cable tray", "6", .metres)], done: false))
        }
        return ExtraWorkReport(siteID: site.id, jobs: jobs, clientSignature: reportSigned ? signature : nil)
    }

    private func document(
        _ language: ExportLanguage = .english,
        decimal: DecimalSeparator = .point,
        withHours: Bool = true,
        reportSigned: Bool = false,
        inProgress: Bool = false,
        photos: [UUID: [UUID]] = [:]
    ) -> ExtraWorkDocument {
        ExtraWorkDocumentBuilder(settings: settings(language, decimal: decimal), calendar: calendar)
            .make(report: report(withHours: withHours, reportSigned: reportSigned, inProgress: inProgress), siteName: site.name, photoIDs: photos)
    }

    // MARK: - The page

    func testTheHeaderSaysWhatIsDone() {
        let page = document()
        XCTAssertEqual(page.eyebrow, "Extra work done · 19 – 22 October 2026")
        XCTAssertEqual(page.title, "Trg Pravde Zagreb")
        XCTAssertEqual(page.byline, "Recorded by Marijo Mikša")
        XCTAssertEqual(page.tiles.map(\.label), ["Jobs done", "Hours"])
        XCTAssertEqual(page.tiles.map(\.value), ["3", "6h"])
    }

    func testTilesCountPhotosAndJobsInProgressOnlyWhenThere() {
        let report = report(inProgress: true)
        let page = ExtraWorkDocumentBuilder(settings: settings(), calendar: calendar)
            .make(report: report, siteName: site.name, photoIDs: [report.jobs[0].id: [UUID(), UUID()], report.jobs[2].id: [UUID()]])
        XCTAssertEqual(page.tiles.map(\.label), ["Jobs done", "In progress", "Photos", "Hours"])
        XCTAssertEqual(page.tiles.map(\.value), ["3", "1", "3", "6h"])
    }

    func testTheHoursTileAppearsOnlyWhenHoursWereNoted() {
        let page = document(withHours: false)
        XCTAssertEqual(page.tiles.map(\.label), ["Jobs done"])
        XCTAssertTrue(page.jobs.allSatisfy { $0.hours.isEmpty })
        XCTAssertFalse(page.jobsTable().columnHeadings().contains("Hours"))
        XCTAssertEqual(page.legend, "Quantities as fitted on site.")
    }

    func testTheWorkDoneComesDayByDay() {
        let report = report()
        let page = ExtraWorkDocumentBuilder(settings: settings(), calendar: calendar)
            .make(report: report, siteName: site.name, photoIDs: [report.jobs[0].id: [UUID(), UUID()]])
        XCTAssertEqual(page.jobsHeading, "Work done, day by day")
        XCTAssertEqual(page.jobHeadings, ["Day", "Work and material", "Photos"])
        let first = page.jobs[0]
        XCTAssertEqual(first.day, "Thu 22")
        XCTAssertEqual(first.description, "Emergency lighting, stairwell 2nd floor")
        XCTAssertEqual(first.material, "8 × Emergency light · 25.5 m Cable NYM 3×1.5")
        XCTAssertEqual(first.hours, "Ivan 3h · Marko 3h")
        XCTAssertEqual(first.photoIDs.count, 2)
        XCTAssertEqual(first.confirmation, "", "nothing said about a signature nobody gave")
        XCTAssertNil(first.signature)
        XCTAssertEqual(page.jobs[1].confirmation, "Confirmed on site by Ing. M. Horvat, 14 Oct 2026")
        XCTAssertNotNil(page.jobs[1].signature)
        XCTAssertEqual(page.jobs.map(\.day), ["Thu 22", "Thu 22", "Mon 19"])
        XCTAssertTrue(page.inProgressJobs.isEmpty)
    }

    func testTheMaterialUsedSupportsTheWork() {
        let page = document()
        XCTAssertEqual(page.materialHeading, "Material used")
        XCTAssertEqual(page.materialHeadings, ["Item", "Quantity", "Unit"])
        XCTAssertEqual(page.material.map { [$0.name, $0.quantity, $0.unit] }, [
            ["Emergency light", "8", "pcs"],
            ["Ceiling lamp LED", "22", "pcs"],
            ["Junction box", "10", "pcs"],
            ["Cable NYM 3×1.5", "25.5", "m"]
        ])
    }

    func testJobsStillInProgressHaveASectionOfTheirOwnAfterTheDoneOnes() {
        let page = document(inProgress: true)
        XCTAssertEqual(page.jobs.map(\.description), [
            "Emergency lighting, stairwell 2nd floor", "Ceiling lamps, corridor B", "Ceiling lamps, staff kitchen"
        ])
        XCTAssertEqual(page.inProgressHeading, "Still in progress")
        XCTAssertEqual(page.inProgressJobs.map(\.description), ["Cable trays, plant room"])
        XCTAssertEqual(page.material.last?.name, "Cable tray", "material used so far counts")
    }

    /// No lines to fill in: the boss is told what is done, not handed a
    /// form. A signature the client gave is shown, and nothing otherwise.
    func testOnlyASignatureThatWasGivenIsShown() {
        let unsigned = document()
        XCTAssertNil(unsigned.clientSignature)
        XCTAssertEqual(unsigned.clientSignatureLabel, "")

        let signed = document(reportSigned: true)
        XCTAssertEqual(signed.clientSignature?.signerName, "Ing. M. Horvat")
        XCTAssertEqual(signed.clientSignatureLabel, "Confirmed on site by Ing. M. Horvat, 14 Oct 2026")
    }

    // MARK: - Languages

    func testGermanWritesEveryLabelInGermanAndLeavesTheUsersWordsAlone() {
        let page = document(.german, decimal: .comma, inProgress: true)
        XCTAssertEqual(page.eyebrow, "Erledigte Zusatzarbeiten · 19. – 22. Oktober 2026")
        XCTAssertEqual(page.byline, "Erfasst von Marijo Mikša")
        XCTAssertEqual(page.tiles.map(\.label), ["Erledigt", "In Arbeit", "Stunden"])
        XCTAssertEqual(page.jobsHeading, "Erledigte Arbeiten, Tag für Tag")
        XCTAssertEqual(page.inProgressHeading, "Noch in Arbeit")
        XCTAssertEqual(page.materialHeading, "Verwendetes Material")
        XCTAssertEqual(page.materialHeadings, ["Artikel", "Menge", "Einheit"])
        XCTAssertEqual(page.material[0].unit, "Stk")
        XCTAssertEqual(page.material[3].quantity, "25,5")
        XCTAssertEqual(page.material[0].name, "Emergency light", "an item's name is the user's own")
        XCTAssertEqual(page.jobs[0].description, "Emergency lighting, stairwell 2nd floor")
        XCTAssertEqual(page.jobs[0].material, "8 × Emergency light · 25,5 m Cable NYM 3×1.5")
        XCTAssertTrue(page.jobs[1].confirmation.hasPrefix("Vor Ort bestätigt von Ing. M. Horvat, "), page.jobs[1].confirmation)
        XCTAssertTrue(page.jobs[0].day.hasPrefix("Do") && page.jobs[0].day.contains("22"), page.jobs[0].day)
        XCTAssertTrue(page.legend.hasPrefix("Mengen wie auf der Baustelle eingebaut."))
        XCTAssertEqual(page.jobsTable().rows.map { $0.values[4] }, ["erledigt", "erledigt", "erledigt", "in Arbeit"])
    }

    func testCroatianWritesEveryLabelInCroatian() {
        let page = document(.croatian, inProgress: true)
        XCTAssertTrue(page.eyebrow.hasPrefix("Izvršeni dodatni radovi · "), page.eyebrow)
        XCTAssertEqual(page.byline, "Evidenciju vodi Marijo Mikša")
        XCTAssertEqual(page.materialHeading, "Utrošeni materijal")
        XCTAssertEqual(page.material[0].unit, "kom")
        XCTAssertEqual(page.jobsHeading, "Izvršeni radovi po danima")
        XCTAssertEqual(page.inProgressHeading, "Još u tijeku")
        XCTAssertTrue(page.jobs[1].confirmation.hasPrefix("Potvrđeno na gradilištu: Ing. M. Horvat, "), page.jobs[1].confirmation)
        XCTAssertEqual(page.jobsTable().rows.last?.values[4], "u tijeku")
        XCTAssertEqual(page.material[0].name, "Emergency light")
    }

    func testATypedUnitIsPrintedAsTyped() {
        let custom = ExtraWorkReport(siteID: site.id, jobs: [job(20, "Tape", [item("Tape", "2", .custom("Rolle"))])])
        let page = ExtraWorkDocumentBuilder(settings: settings(.croatian), calendar: calendar).make(report: custom, siteName: site.name)
        XCTAssertEqual(page.material[0].unit, "Rolle")
        XCTAssertEqual(page.jobs[0].material, "2 Rolle Tape")
    }

    /// A report of what is done, not a bill: no money, and none of the
    /// words of invoicing, in any language.
    func testNoMoneyAndNoInvoiceAnywhere() {
        for language in ExportLanguage.allCases {
            let page = document(language, inProgress: true)
            let text = ([page.eyebrow, page.byline, page.legend, page.documentTitle, page.fileName, page.jobsHeading,
                         page.inProgressHeading, page.materialHeading, page.clientSignatureLabel] + page.tiles.map(\.label)
                + page.materialHeadings + page.jobHeadings + page.jobsTable().columnHeadings()
                + page.linesTable().columnHeadings()).joined(separator: " ").lowercased()
            for word in ["€", "eur ", "price", "rate", "invoice", "bill", "rechnung", "regie", "račun", "faktur", "fattur",
                         "factur", "fatur", "signature"] {
                XCTAssertFalse(text.contains(word), "\(language): \(word) in \(text)")
            }
        }
    }

    func testTheFileIsNamedForTheSiteAndTheDates() {
        XCTAssertEqual(document().fileName, "Trg Pravde Zagreb - Extra work done 2026-10-19 to 2026-10-22")
        XCTAssertEqual(document(.german).fileName, "Trg Pravde Zagreb - Erledigte Zusatzarbeiten 2026-10-19 to 2026-10-22")
        XCTAssertEqual(document().documentTitle, "Extra work done — Trg Pravde Zagreb")
    }

    // MARK: - Workbook and CSV

    func testTheMaterialSheetHoldsQuantitiesAsNumbers() {
        let table = document(decimal: .comma).materialTable()
        XCTAssertEqual(table.columnHeadings(), ["Item", "Quantity", "Unit"])
        XCTAssertEqual(table.rows.count, 4)
        XCTAssertEqual(table.rows[3].values, ["Cable NYM 3×1.5", "25,5", "m"])
        XCTAssertEqual(table.rows[3].numbers, [nil, 25.5, nil])
    }

    func testTheJobsSheetHasARowPerJobWithHoursAsDurations() {
        let table = document().jobsTable()
        XCTAssertEqual(table.columnHeadings(), ["Date", "Job", "Work and material", "Hours", "Confirmed on site"])
        XCTAssertEqual(table.rows.count, 3)
        XCTAssertEqual(table.rows[0].values[1], "Emergency lighting, stairwell 2nd floor")
        XCTAssertEqual(table.rows[0].minutes[3], 360)
        XCTAssertNil(table.rows[1].minutes[3])
        XCTAssertEqual(table.rows[1].values[4], "Ing. M. Horvat, 14 Oct 2026")
        XCTAssertEqual(table.rows[0].values[4], "")
    }

    func testTheJobsSheetMarksJobsStillInProgressAfterTheDoneOnes() {
        let table = document(inProgress: true).jobsTable()
        XCTAssertEqual(table.columnHeadings(), ["Date", "Job", "Work and material", "Hours", "Status", "Confirmed on site"])
        XCTAssertEqual(table.rows.map { $0.values[4] }, ["done", "done", "done", "in progress"])
        XCTAssertEqual(table.rows.last?.values[1], "Cable trays, plant room")
    }

    func testNeitherStatusNorConfirmationColumnsWhenThereIsNothingToSay() {
        let plain = ExtraWorkReport(siteID: site.id, jobs: [job(20, "Tape", [item("Tape", "2")])])
        let page = ExtraWorkDocumentBuilder(settings: settings(), calendar: calendar).make(report: plain, siteName: site.name)
        XCTAssertEqual(page.jobsTable().columnHeadings(), ["Date", "Job", "Work and material"])
        XCTAssertEqual(page.linesTable().columnHeadings(), ["Date", "Job", "Item", "Quantity", "Unit"])
    }

    func testTheWorkbookPutsTheJobsFirst() {
        let page = document(.german)
        let parts = String(decoding: page.workbook(preferences: settings(.german).export), as: UTF8.self)
        XCTAssertTrue(parts.contains(#"<sheet name="Arbeiten" sheetId="1""#))
        XCTAssertTrue(parts.contains(#"<sheet name="Verwendetes Material" sheetId="2""#))
        XCTAssertTrue(parts.contains("xl/worksheets/sheet2.xml"))
        XCTAssertFalse(parts.contains("sheet3.xml"))
        XCTAssertTrue(parts.contains("Emergency lighting, stairwell 2nd floor"))
        XCTAssertTrue(parts.contains("<v>25.500000</v>"), "a quantity is a number in the workbook")
    }

    func testTheCSVIsOneTableOfJobLines() {
        let page = document()
        let csv = String(decoding: CSVExporter.data(for: page.linesTable(), preferences: ExportPreferences(includeByteOrderMark: false)), as: UTF8.self)
        let lines = csv.split(separator: "\r\n").map(String.init)
        XCTAssertEqual(lines.first, "Date,Job,Item,Quantity,Unit,Hours,Confirmed on site")
        XCTAssertEqual(lines.count, 1 + 5, "a line per item")
        XCTAssertTrue(lines[1].contains("Emergency light,8,pcs"), lines[1])
        XCTAssertTrue(lines[2].contains("Cable NYM 3×1.5,25.5,m"), lines[2])
        XCTAssertTrue(lines[1].contains("6h"), "the job's hours on its first line")
        XCTAssertFalse(lines[2].contains("6h"), "and only there, so a sum does not count them twice")
    }

    func testTheCSVMarksJobsStillInProgress() {
        let page = document(inProgress: true)
        XCTAssertEqual(page.linesTable().columnHeadings(), ["Date", "Job", "Item", "Quantity", "Unit", "Hours", "Status", "Confirmed on site"])
        XCTAssertEqual(page.linesTable().rows.last?.values[6], "in progress")
    }

    func testTheCSVLeavesOutHoursWhenNoneWereNoted() {
        let header = document(withHours: false).linesTable().headerTitles()
        XCTAssertEqual(header, ["Date", "Job", "Item", "Quantity", "Unit", "Confirmed on site"])
    }
}
