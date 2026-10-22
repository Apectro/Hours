import XCTest
import UIKit
import PDFKit
@testable import Hours

/// The extra-work PDF read back as text, the way the director's sheet is
/// tested: what the boss reads is on the page — the work done first — in the
/// export language, with the user's own words untouched, and a long report
/// runs on over pages.
final class ExtraWorkPDFTests: XCTestCase {
    private let site = Site(name: "Trg Pravde Zagreb")
    private let calendar = Fixture.calendar()

    private func document(_ language: ExportLanguage, jobs count: Int = 3, signed: Bool = false, inProgress: Bool = false) -> ExtraWorkDocument {
        let settings = Fixture.settings(export: ExportPreferences(language: language, ownerName: "Marijo Mikša"))
        let jobs = (0..<count).map { index in
            ExtraWorkJob(
                siteID: site.id,
                date: Fixture.date(2026, 10, 1 + index % 28),
                description: "Emergency lighting \(index)",
                items: [
                    ExtraWorkItem(name: "Emergency light", quantity: 8, unit: .pieces),
                    ExtraWorkItem(name: "Cable NYM 3×1.5", quantity: Decimal(string: "12.5")!, unit: .metres)
                ],
                hours: index == 0 ? [ExtraWorkHours(name: "Ivan", minutes: 180)] : [],
                isDone: !(inProgress && index == count - 1)
            )
        }
        let signature = signed
            ? ExtraWorkSignature(signerName: "Ing. M. Horvat", signedAt: Date(timeIntervalSince1970: 1_792_000_000),
                                 strokes: [[SignaturePoint(x: 0.1, y: 0.5), SignaturePoint(x: 2.5, y: 0.3)]])
            : nil
        return ExtraWorkDocumentBuilder(settings: settings, calendar: calendar)
            .make(report: ExtraWorkReport(siteID: site.id, jobs: jobs, clientSignature: signature), siteName: site.name)
    }

    private func pages(_ document: ExtraWorkDocument) throws -> [String] {
        let pdf = try XCTUnwrap(PDFDocument(data: ExtraWorkPDFRenderer.data(for: document)))
        // PDFKit may hand back "š" as "s" and a combining caron; compare the
        // composed form, which is the same text.
        return (0..<pdf.pageCount).map { (pdf.page(at: $0)?.string ?? "").precomposedStringWithCanonicalMapping }
    }

    func testTheGermanPageSaysItInGerman() throws {
        let text = try pages(document(.german, inProgress: true)).joined(separator: "\n")
        XCTAssertTrue(text.contains("ERLEDIGTE ZUSATZARBEITEN"), text)
        XCTAssertFalse(text.contains("REGIE"), "not a bill: \(text)")
        XCTAssertTrue(text.contains("Trg Pravde Zagreb"), "the site name was cut short: \(text)")
        XCTAssertTrue(text.contains("Erfasst von Marijo Mikša"), text)
        XCTAssertTrue(text.contains("ERLEDIGTE ARBEITEN, TAG FÜR TAG"), text)
        XCTAssertTrue(text.contains("NOCH IN ARBEIT"), text)
        XCTAssertTrue(text.contains("VERWENDETES MATERIAL"), text)
        XCTAssertTrue(text.contains("Stk"))
        XCTAssertTrue(text.contains("Emergency light"), "the user's own words")
        XCTAssertFalse(text.contains("Unterschrift"), "no empty lines to sign on")
        XCTAssertTrue(text.contains("Seite 1 von 1"))
    }

    /// The work is what the boss reads first; the material supports it.
    func testTheWorkComesBeforeTheMaterial() throws {
        let text = try pages(document(.english, inProgress: true)).joined(separator: "\n")
        let work = try XCTUnwrap(text.range(of: "WORK DONE, DAY BY DAY"))
        let progress = try XCTUnwrap(text.range(of: "STILL IN PROGRESS"))
        let material = try XCTUnwrap(text.range(of: "MATERIAL USED"))
        XCTAssertLessThan(work.lowerBound, progress.lowerBound)
        XCTAssertLessThan(progress.lowerBound, material.lowerBound)
    }

    func testTheCroatianPageSaysItInCroatian() throws {
        let text = try pages(document(.croatian)).joined(separator: "\n")
        XCTAssertTrue(text.contains("IZVRŠENI DODATNI RADOVI"), text)
        XCTAssertTrue(text.contains("UTROŠENI MATERIJAL"), text)
        XCTAssertTrue(text.contains("kom"))
        XCTAssertTrue(text.contains("Emergency lighting 0"))
        XCTAssertFalse(text.contains("IZVANUGOVORNI"), text)
    }

    func testASignedReportSaysWhoConfirmedItAndAnUnsignedOneSaysNothing() throws {
        let signed = try pages(document(.english, signed: true)).joined(separator: "\n")
        XCTAssertTrue(signed.contains("Confirmed on site by Ing. M. Horvat"), signed)
        let unsigned = try pages(document(.english)).joined(separator: "\n")
        XCTAssertFalse(unsigned.contains("Confirmed"), unsigned)
        XCTAssertFalse(unsigned.contains("signature"), unsigned)
    }

    func testALongReportRunsOnAndCountsItsPages() throws {
        let rendered = try pages(document(.english, jobs: 60))
        XCTAssertGreaterThan(rendered.count, 1)
        XCTAssertTrue(rendered[1].contains("WORK DONE, DAY BY DAY"), "the heading goes over with the rows")
        XCTAssertTrue(rendered.last?.contains("Quantities as fitted on site.") == true, "the legend closes the last page")
        XCTAssertTrue(rendered.last?.contains("page \(rendered.count) of \(rendered.count)") == true)
    }
}
