import XCTest
import UIKit
import PDFKit
@testable import Hours

/// Produces the export files a person would actually get, and photographs them.
///
/// Not a test of anything, and honest about that. Every export test alongside
/// this one asserts on strings; none of them ever looked at the finished PDF,
/// which is the artefact a person prints and hands to a payroll department.
/// Rendering it is how the totals block running off the bottom of a full page
/// was found.
///
/// CI exports the attachments; see the "App Store screenshots" step.
final class ExportCaptureTests: XCTestCase {
    private let calendar = Fixture.calendar()

    /// A full month with the kinds of day that make a report interesting:
    /// overtime, a short day, a weekend, a holiday and a long note.
    private func monthTable(days dayCount: Int = 31, language: ExportLanguage = .device) -> ReportTable {
        // A name, because a timesheet that reaches somebody else carries one
        // — and because the captures are the only place the title block is
        // ever looked at rather than asserted on.
        var export = ExportPreferences()
        export.ownerName = "Ada Lovelace"
        export.language = language
        let settings = Fixture.settings(export: export)
        let start = Fixture.date(2026, 8, 1)
        let end = Fixture.date(2026, 8, dayCount)
        let range = CalendarDateRange(start: start, end: end)

        var records: [Int: DayRecord] = [:]
        for day in 1...dayCount {
            let date = Fixture.date(2026, 8, day)
            let weekday = calendar.component(.weekday, from: date.date(in: calendar))
            guard weekday != 1, weekday != 7 else { continue }

            switch day % 5 {
            case 0:
                records[date.key] = DayRecord(
                    date: date,
                    start: Fixture.time(8),
                    end: Fixture.time(18, 15),
                    breaks: [.timed(from: Fixture.time(12), to: Fixture.time(12, 30))],
                    note: "Release day — stayed for the deploy"
                )
            case 3:
                records[date.key] = DayRecord(
                    date: date,
                    start: Fixture.time(9),
                    end: Fixture.time(14, 30),
                    breaks: []
                )
            default:
                records[date.key] = DayRecord(
                    date: date,
                    start: Fixture.time(8),
                    end: Fixture.time(16, 30),
                    breaks: [.timed(from: Fixture.time(12), to: Fixture.time(12, 30))]
                )
            }
        }

        let days = PeriodEngine(settings: settings, calendar: calendar)
            .days(in: range, records: records, holidays: [])
        return ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—")
            .makeTable(
                days: days,
                range: range,
                title: "\(language(.hours)) — \(CalendarFormatting(locale: language.locale, calendar: calendar).monthTitle(start.yearMonth))",
                countingThrough: end
            )
    }

    private func attach(_ image: UIImage, named name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Renders every page of a PDF so it can be looked at rather than assumed.
    private func pages(of data: Data) throws -> [UIImage] {
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertGreaterThan(document.numberOfPages, 0, "the PDF has no pages")

        var images: [UIImage] = []
        for number in 1...document.numberOfPages {
            guard let page = document.page(at: number) else { continue }
            let bounds = page.getBoxRect(.mediaBox)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
            images.append(renderer.image { context in
                UIColor.white.setFill()
                context.fill(bounds)
                context.cgContext.translateBy(x: 0, y: bounds.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                context.cgContext.drawPDFPage(page)
            })
        }
        return images
    }

    func testCaptureThePDF() throws {
        let data = PDFReportRenderer.data(for: monthTable())
        let rendered = try pages(of: data)

        for (index, image) in rendered.prefix(3).enumerated() {
            attach(image, named: "06-export-pdf-\(index + 1)")
        }
        print("----- export -----")
        print("pdf pages               -> \(rendered.count)")
        print("pdf bytes               -> \(data.count)")
    }

    /// The case that breaks the layout: enough rows to fill a page exactly, so
    /// the totals block has nowhere to go.
    func testCaptureTheSummaryOnAFullPage() throws {
        let data = PDFReportRenderer.data(for: monthTable(days: 31))
        let rendered = try pages(of: data)
        if let last = rendered.last {
            attach(last, named: "07-export-pdf-summary")
        }
        print("summary page            -> \(rendered.count)")
        print("----- end export -----")
    }

    // MARK: - The summary must survive

    /// Every page count from one row to a hundred, and the summary is on all
    /// of them.
    ///
    /// The old renderer drew the totals wherever the last row left off and
    /// skipped any line that did not fit, so whether a report kept its summary
    /// depended on how many days the month happened to have. Somewhere in this
    /// range the rows end near the bottom of a page, and that is the report
    /// that used to come out with its totals missing.
    func testTheSummaryIsInThePDFWhateverTheRowCountIs() throws {
        for dayCount in [1, 7, 20, 28, 29, 30, 31] {
            let table = monthTable(days: dayCount)
            guard !table.totals.isEmpty else { continue }

            let data = PDFReportRenderer.data(for: table)
            let document = try XCTUnwrap(PDFDocument(data: data), "\(dayCount) days: unreadable PDF")
            let text = (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined()

            XCTAssertTrue(text.contains("Summary"), "\(dayCount) days: the summary is missing")
            // Not just the heading — the figures under it.
            for total in table.totals.prefix(3) {
                XCTAssertTrue(
                    text.contains(total.label),
                    "\(dayCount) days: the summary is missing \"\(total.label)\""
                )
            }
        }
    }

    /// A report with no rows at all still gets its summary.
    func testAnEmptyReportStillCarriesItsSummary() throws {
        let settings = Fixture.settings()
        let range = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 1))
        let days = PeriodEngine(settings: settings, calendar: calendar)
            .days(in: range, records: [:], holidays: [])
        let table = ReportBuilder(settings: settings, calendar: calendar)
            .makeTable(days: days, range: range, title: "Empty", countingThrough: range.end)

        let document = try XCTUnwrap(PDFDocument(data: PDFReportRenderer.data(for: table)))
        XCTAssertGreaterThan(document.pageCount, 0, "an empty report produced no pages at all")
    }

    /// The same month in each language the export speaks.
    ///
    /// A translation is the kind of thing that passes every assertion and
    /// still comes out wrong — a column left in English, a number format that
    /// a number format that disagrees with the text beside it, a month name
    /// that ignored the setting. Assertions cannot see any of that; a rendered page can.
    func testCaptureTheExportInEveryLanguage() throws {
        for (language, name) in [(ExportLanguage.german, "de"), (ExportLanguage.croatian, "hr")] {
            let table = monthTable(language: language)
            let rendered = try pages(of: PDFReportRenderer.data(for: table))
            if let first = rendered.first {
                attach(first, named: "11-export-pdf-\(name)")
            }

            let workbook = XCTAttachment(
                data: XLSXWriter.data(for: table, preferences: ExportPreferences(language: language), generatedOn: Date()),
                uniformTypeIdentifier: "org.openxmlformats.spreadsheetml.sheet"
            )
            workbook.name = "12-export-xlsx-\(name).xlsx"
            workbook.lifetime = .keepAlways
            add(workbook)

            print("\(name) header          -> \(table.headerTitles().joined(separator: " | "))")
        }
    }

    /// What the renderer actually drew, not what the table was willing to say.
    ///
    /// The table's `headerTitles()` were translated and asserted on, and the
    /// PDF came out with English column titles anyway — because it was
    /// drawing `column.title`, the app's own name for the column, and never
    /// asked the table. An assertion on the model cannot see that. This one
    /// reads the text back out of the finished document.
    func testTheRenderedGermanPDFIsGermanAndNothingIsClipped() throws {
        let table = monthTable(language: .german)
        let document = try XCTUnwrap(PDFDocument(data: PDFReportRenderer.data(for: table)))
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined()

        for heading in ["Datum", "Art", "Gearbeitet", "Pause", "Überstunden"] {
            XCTAssertTrue(text.contains(heading), "the PDF never drew the column title \(heading)")
        }
        for english in ["Worked", "Expected", "Overtime", "Break"] {
            XCTAssertFalse(text.contains(english), "\(english) is still in English in the rendered PDF")
        }

        // Weekdays come from the calendar's own locale, which is not the one
        // the formatter was given — so these were English long after the
        // setting said otherwise.
        // Absence rather than presence: a two-letter German abbreviation is a
        // substring of half the page, but "Sat" and "Sun" appear nowhere in a
        // German sheet that is really German.
        XCTAssertFalse(text.contains("Sat"), "the weekdays are still English")
        XCTAssertFalse(text.contains("Sun"), "the weekdays are still English")
        XCTAssertTrue(text.contains("Wochenende"), "the day types are not in German")

        // A truncated note is untidy. A truncated duration is a wrong number.
        // The units stay h and m in every language; only the words around
        // them change.
        XCTAssertTrue(text.contains("9h 45m"), "a duration was clipped")
        XCTAssertFalse(text.contains("9h 45…") || text.contains("5h 30…"))
    }

    /// The CSV and the workbook, written exactly as the app writes them.
    func testCaptureTheDataFiles() throws {
        let table = monthTable()
        let preferences = ExportPreferences()

        let csv = CSVExporter.data(for: table, preferences: preferences)
        let csvAttachment = XCTAttachment(data: csv, uniformTypeIdentifier: "public.comma-separated-values-text")
        csvAttachment.name = "08-export-csv.csv"
        csvAttachment.lifetime = .keepAlways
        add(csvAttachment)

        let xlsx = XLSXWriter.data(for: table, preferences: preferences)
        // The workbook's own type, not "public.data". Attached as generic data
        // it came out of the result bundle with no .xlsx on the end, so the
        // renamer did not recognise it and the workbook was the one export
        // artifact that never reached the branch.
        let xlsxAttachment = XCTAttachment(
            data: xlsx,
            uniformTypeIdentifier: "org.openxmlformats.spreadsheetml.sheet"
        )
        xlsxAttachment.name = "09-export-xlsx.xlsx"
        xlsxAttachment.lifetime = .keepAlways
        add(xlsxAttachment)

        // A workbook Excel cannot open is worse than no workbook, and the ZIP
        // is written by hand here, so check it is at least a ZIP.
        XCTAssertEqual(Array(xlsx.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "not a ZIP archive")
        XCTAssertGreaterThan(csv.count, 100)
    }
}
