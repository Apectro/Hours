import XCTest
@testable import Hours

/// The extra-work report as the boss receives it: every word the app writes
/// in the export language, the user's own words untouched, and the same
/// content in the PDF's blocks, the workbook's two sheets and the CSV.
final class ExtraWorkExportTests: XCTestCase {
    private let site = Site(name: "Trg Pravde Zagreb")
    private let calendar = Fixture.calendar()
    private let base = Date(timeIntervalSince1970: 1_792_000_000)
    private let ivan = UUID()

    private func settings(_ language: ExportLanguage = .english, decimal: DecimalSeparator = .point) -> AppSettings {
        Fixture.settings(export: ExportPreferences(decimalSeparator: decimal, language: language, ownerName: "Marijo Mikša"))
    }

    private func job(_ day: Int, _ description: String, _ items: [ExtraWorkItem], offset: TimeInterval = 0) -> ExtraWorkJob {
        let moment = base.addingTimeInterval(TimeInterval(day) * 86_400 + offset)
        return ExtraWorkJob(
            siteID: site.id, date: Fixture.date(2026, 10, day), description: description, items: items,
            createdAt: moment, updatedAt: moment
        )
    }

    private func item(_ name: String, _ quantity: String, _ unit: ExtraWorkUnit = .pieces) -> ExtraWorkItem {
        ExtraWorkItem(name: name, quantity: Decimal(string: quantity)!, unit: unit)
    }

    private var signature: ExtraWorkSignature {
        ExtraWorkSignature(signerName: "Ing. M. Horvat", signedAt: base, strokes: [[SignaturePoint(x: 0, y: 0.5), SignaturePoint(x: 2, y: 0.3)]])
    }

    private func report(withHours: Bool = true, reportSigned: Bool = false) -> ExtraWorkReport {
        var stairwell = job(22, "Emergency lighting, stairwell 2nd floor", [item("Emergency light", "8"), item("Cable NYM 3×1.5", "25.5", .metres)])
        if withHours {
            stairwell.hours = [ExtraWorkHours(memberID: ivan, name: "Ivan", minutes: 180), ExtraWorkHours(name: "Marko", minutes: 180)]
        }
        var corridor = job(22, "Ceiling lamps, corridor B", [item("Ceiling lamp LED", "10"), item("Junction box", "10")], offset: 60)
        corridor.clientSignature = signature
        let kitchen = job(19, "Ceiling lamps, staff kitchen", [item("Ceiling lamp LED", "12")])
        return ExtraWorkReport(siteID: site.id, jobs: [kitchen, stairwell, corridor], clientSignature: reportSigned ? signature : nil)
    }

    private func document(
        _ language: ExportLanguage = .english,
        decimal: DecimalSeparator = .point,
        withHours: Bool = true,
        reportSigned: Bool = false,
        photos: [UUID: [UUID]] = [:]
    ) -> ExtraWorkDocument {
        ExtraWorkDocumentBuilder(settings: settings(language, decimal: decimal), calendar: calendar)
            .make(report: report(withHours: withHours, reportSigned: reportSigned), siteName: site.name, photoIDs: photos)
    }

    // MARK: - The page

    func testTheHeaderReadsAsTheMockup() {
        let page = document()
        XCTAssertEqual(page.eyebrow, "Extra work · 19 – 22 October 2026")
        XCTAssertEqual(page.title, "Trg Pravde Zagreb")
        XCTAssertEqual(page.byline, "Recorded by Marijo Mikša · Extra work report")
        XCTAssertEqual(page.tiles.map(\.label), ["Jobs", "Items", "Client signed", "Hours"])
        XCTAssertEqual(page.tiles.map(\.value), ["3", "4", "1 of 3", "6h"])
    }

    func testTheHoursTileAppearsOnlyWhenHoursWereNoted() {
        let page = document(withHours: false)
        XCTAssertEqual(page.tiles.map(\.label), ["Jobs", "Items", "Client signed"])
        XCTAssertTrue(page.jobs.allSatisfy { $0.hours.isEmpty })
        XCTAssertFalse(page.jobsTable().columnHeadings().contains("Hours"))
        XCTAssertFalse(page.legend.contains("Hours"))
    }

    func testMaterialInTotal() {
        let page = document()
        XCTAssertEqual(page.materialHeading, "Material in total")
        XCTAssertEqual(page.materialHeadings, ["Item", "Quantity", "Unit"])
        XCTAssertEqual(page.material.map { [$0.name, $0.quantity, $0.unit] }, [
            ["Emergency light", "8", "pcs"],
            ["Ceiling lamp LED", "22", "pcs"],
            ["Junction box", "10", "pcs"],
            ["Cable NYM 3×1.5", "25.5", "m"]
        ])
    }

    func testJobsDayByDay() {
        let report = report()
        let page = ExtraWorkDocumentBuilder(settings: settings(), calendar: calendar)
            .make(report: report, siteName: site.name, photoIDs: [report.jobs[0].id: [UUID(), UUID()]])
        XCTAssertEqual(page.jobsHeading, "Jobs, day by day")
        XCTAssertEqual(page.jobHeadings, ["Day", "Work and material", "Photos", "Client"])
        let first = page.jobs[0]
        XCTAssertEqual(first.day, "Thu 22")
        XCTAssertEqual(first.description, "Emergency lighting, stairwell 2nd floor")
        XCTAssertEqual(first.material, "8 × Emergency light · 25.5 m Cable NYM 3×1.5")
        XCTAssertEqual(first.hours, "Ivan 3h · Marko 3h")
        XCTAssertEqual(first.photoIDs.count, 2)
        XCTAssertEqual(first.client, "open")
        XCTAssertFalse(first.isConfirmed)
        XCTAssertEqual(page.jobs[1].client, "signed")
        XCTAssertTrue(page.jobs[1].isConfirmed)
        XCTAssertEqual(page.jobs.map(\.day), ["Thu 22", "Thu 22", "Mon 19"])
    }

    func testTheFooterSignsForTheClientWhenTheReportIsSigned() {
        let unsigned = document()
        XCTAssertNil(unsigned.clientSignature)
        XCTAssertEqual(unsigned.signatureLines, ["Client · date, signature", "Supervisor · date, signature"])

        let signed = document(reportSigned: true)
        XCTAssertEqual(signed.clientSignature?.signerName, "Ing. M. Horvat")
        XCTAssertEqual(signed.clientSignatureLabel, "Client · Ing. M. Horvat · 14 Oct 2026")
        XCTAssertEqual(signed.signatureLines, ["Supervisor · date, signature"])
        XCTAssertTrue(signed.jobs.allSatisfy(\.isConfirmed))
        XCTAssertEqual(signed.tiles[2].value, "3 of 3")
    }

    // MARK: - Languages

    func testGermanWritesEveryLabelInGermanAndLeavesTheUsersWordsAlone() {
        let page = document(.german, decimal: .comma)
        XCTAssertEqual(page.eyebrow, "Regiearbeiten · 19. – 22. Oktober 2026")
        XCTAssertEqual(page.byline, "Erfasst von Marijo Mikša · Regiebericht")
        XCTAssertEqual(page.tiles.map(\.label), ["Arbeiten", "Positionen", "Unterschrieben", "Stunden"])
        XCTAssertEqual(page.tiles[2].value, "1 von 3")
        XCTAssertEqual(page.materialHeadings, ["Artikel", "Menge", "Einheit"])
        XCTAssertEqual(page.material[0].unit, "Stk")
        XCTAssertEqual(page.material[3].quantity, "25,5")
        XCTAssertEqual(page.material[0].name, "Emergency light", "an item's name is the user's own")
        XCTAssertEqual(page.jobs[0].description, "Emergency lighting, stairwell 2nd floor")
        XCTAssertEqual(page.jobs[0].material, "8 × Emergency light · 25,5 m Cable NYM 3×1.5")
        XCTAssertEqual(page.jobs[0].client, "offen")
        XCTAssertTrue(page.jobs[0].day.hasPrefix("Do") && page.jobs[0].day.contains("22"), page.jobs[0].day)
        XCTAssertTrue(page.legend.hasPrefix("Mengen wie auf der Baustelle eingebaut."))
        XCTAssertEqual(page.signatureLines.last, "Bauleiter · Datum, Unterschrift")
    }

    func testCroatianWritesEveryLabelInCroatian() {
        let page = document(.croatian)
        XCTAssertTrue(page.eyebrow.hasPrefix("Izvanugovorni radovi · "), page.eyebrow)
        XCTAssertEqual(page.byline, "Evidenciju vodi Marijo Mikša · Izvješće o izvanugovornim radovima")
        XCTAssertEqual(page.materialHeading, "Ukupno materijala")
        XCTAssertEqual(page.material[0].unit, "kom")
        XCTAssertEqual(page.jobs[1].client, "potpisano")
        XCTAssertEqual(page.jobsHeading, "Radovi po danima")
        XCTAssertEqual(page.material[0].name, "Emergency light")
    }

    func testATypedUnitIsPrintedAsTyped() {
        let custom = ExtraWorkReport(siteID: site.id, jobs: [job(20, "Tape", [item("Tape", "2", .custom("Rolle"))])])
        let page = ExtraWorkDocumentBuilder(settings: settings(.croatian), calendar: calendar).make(report: custom, siteName: site.name)
        XCTAssertEqual(page.material[0].unit, "Rolle")
        XCTAssertEqual(page.jobs[0].material, "2 Rolle Tape")
    }

    func testNoMoneyAnywhere() {
        let page = document()
        let text = ([page.eyebrow, page.byline, page.legend] + page.tiles.map(\.label)
            + page.materialHeadings + page.jobHeadings).joined(separator: " ")
        for word in ["€", "EUR", "price", "Price", "rate"] {
            XCTAssertFalse(text.contains(word), word)
        }
    }

    func testTheFileIsNamedForTheSiteAndTheDates() {
        XCTAssertEqual(document().fileName, "Trg Pravde Zagreb - Extra work 2026-10-19 to 2026-10-22")
        XCTAssertEqual(document(.german).fileName, "Trg Pravde Zagreb - Regiearbeiten 2026-10-19 to 2026-10-22")
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
        XCTAssertEqual(table.columnHeadings(), ["Date", "Job", "Work and material", "Hours", "Client"])
        XCTAssertEqual(table.rows.count, 3)
        XCTAssertEqual(table.rows[0].values[1], "Emergency lighting, stairwell 2nd floor")
        XCTAssertEqual(table.rows[0].minutes[3], 360)
        XCTAssertNil(table.rows[1].minutes[3])
    }

    func testTheWorkbookHasAMaterialAndAJobsSheet() {
        let page = document(.german)
        let parts = String(decoding: page.workbook(preferences: settings(.german).export), as: UTF8.self)
        XCTAssertTrue(parts.contains(#"<sheet name="Material gesamt" sheetId="1""#))
        XCTAssertTrue(parts.contains(#"<sheet name="Arbeiten" sheetId="2""#))
        XCTAssertTrue(parts.contains("xl/worksheets/sheet2.xml"))
        XCTAssertFalse(parts.contains("sheet3.xml"))
        XCTAssertTrue(parts.contains("Emergency lighting, stairwell 2nd floor"))
        XCTAssertTrue(parts.contains("<v>25.500000</v>"), "a quantity is a number in the workbook")
    }

    func testTheCSVIsOneTableOfJobLines() {
        let page = document()
        let csv = String(decoding: CSVExporter.data(for: page.linesTable(), preferences: ExportPreferences(includeByteOrderMark: false)), as: UTF8.self)
        let lines = csv.split(separator: "\r\n").map(String.init)
        XCTAssertEqual(lines.first, "Date,Job,Item,Quantity,Unit,Hours,Client")
        XCTAssertEqual(lines.count, 1 + 5, "a line per item")
        XCTAssertTrue(lines[1].contains("Emergency light,8,pcs"), lines[1])
        XCTAssertTrue(lines[2].contains("Cable NYM 3×1.5,25.5,m"), lines[2])
        XCTAssertTrue(lines[1].contains("6h"), "the job's hours on its first line")
        XCTAssertFalse(lines[2].contains("6h"), "and only there, so a sum does not count them twice")
    }

    func testTheCSVLeavesOutHoursWhenNoneWereNoted() {
        let header = document(withHours: false).linesTable().headerTitles()
        XCTAssertEqual(header, ["Date", "Job", "Item", "Quantity", "Unit", "Client"])
    }
}
