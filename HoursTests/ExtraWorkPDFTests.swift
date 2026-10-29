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

    private func document(
        _ language: ExportLanguage,
        jobs count: Int = 3,
        signed: Bool = false,
        inProgress: Bool = false,
        address: String = ""
    ) -> ExtraWorkDocument {
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
            .make(report: ExtraWorkReport(siteID: site.id, jobs: jobs, clientSignature: signature), siteName: site.name, siteAddress: address)
    }

    /// The site's address (1.2): one line under the byline, the work still
    /// where it was.
    func testTheAddressIsALineUnderTheByline() throws {
        let text = try pages(document(.english, address: "Trg pravde 1\n10000 Zagreb")).joined(separator: "\n")
        let byline = try XCTUnwrap(text.range(of: "Recorded by Marijo Mikša"))
        let address = try XCTUnwrap(text.range(of: "Trg pravde 1, 10000 Zagreb"), text)
        let work = try XCTUnwrap(text.range(of: "WORK DONE, DAY BY DAY"))
        XCTAssertLessThan(byline.lowerBound, address.lowerBound)
        XCTAssertLessThan(address.lowerBound, work.lowerBound)
        XCTAssertFalse(try pages(document(.english)).joined().contains("10000 Zagreb"))
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
        // The heading is drawn letter-spaced, and PDFKit can read a space
        // into it after a letter with a háček ("IZVRŠ ENI"); compare it
        // without the spaces. The page itself is the problem only if the
        // words are missing.
        let squeezed = text.replacingOccurrences(of: " ", with: "")
        XCTAssertTrue(squeezed.contains("IZVRŠENIDODATNIRADOVI"), text)
        XCTAssertFalse(text.contains(".."), "a doubled full stop in the period: \(text)")
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

    /// Items one under another, as the owner asked: "4 × P7" and "2 × P6"
    /// on lines of their own, never joined with a dot, and a job of six
    /// items measured tall enough that a page of them still runs on and
    /// counts right.
    func testItemsStandOneUnderAnother() throws {
        let settings = Fixture.settings(export: ExportPreferences(language: .english, ownerName: "Marijo Mikša"))
        let items = (1...6).map { ExtraWorkItem(name: "P\($0)", quantity: Decimal($0), unit: .pieces) }
        let jobs = (0..<20).map { index in
            ExtraWorkJob(
                siteID: site.id, date: Fixture.date(2026, 10, 1 + index), description: "Panels \(index)", items: items,
                hours: [ExtraWorkHours(name: "Marijo Mikša", minutes: 60), ExtraWorkHours(name: "Dusko Bajlović", minutes: 60)],
                isDone: true
            )
        }
        let document = ExtraWorkDocumentBuilder(settings: settings, calendar: calendar)
            .make(report: ExtraWorkReport(siteID: site.id, jobs: jobs), siteName: site.name)
        let rendered = try pages(document)
        let text = rendered.joined(separator: "\n")
        XCTAssertFalse(text.contains("1 × P1 · 2 × P2"), "items are not joined on one line: \(text)")
        XCTAssertTrue(text.contains("1h · Marijo Mikša, Dusko Bajlović"), "how long, then who: \(text)")
        let first = try XCTUnwrap(rendered.first)
        let one = try XCTUnwrap(first.range(of: "1 × P1"))
        let two = try XCTUnwrap(first.range(of: "2 × P2"))
        XCTAssertLessThan(one.lowerBound, two.lowerBound)
        XCTAssertFalse(first[one.upperBound..<two.lowerBound].contains("·"), "a line each, not a dot between")
        XCTAssertGreaterThan(rendered.count, 2, "twenty jobs of six lines each do not fit on two pages")
        for (index, page) in rendered.enumerated() {
            XCTAssertTrue(page.contains("page \(index + 1) of \(rendered.count)"), "page \(index + 1): \(page)")
        }
        // Every job printed with all six of its items: nothing was drawn
        // past the foot of a page.
        XCTAssertEqual(text.components(separatedBy: "6 × P6").count - 1, 20, "every job's last item is on a page")
    }

    func testALongReportRunsOnAndCountsItsPages() throws {
        let rendered = try pages(document(.english, jobs: 60))
        XCTAssertGreaterThan(rendered.count, 1)
        XCTAssertTrue(rendered[1].contains("WORK DONE, DAY BY DAY"), "the heading goes over with the rows")
        XCTAssertTrue(rendered.last?.contains("Quantities as fitted on site.") == true, "the legend closes the last page")
        XCTAssertTrue(rendered.last?.contains("page \(rendered.count) of \(rendered.count)") == true)
    }
}
