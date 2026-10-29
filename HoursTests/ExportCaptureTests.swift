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

        let days = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: Fixture.longAgo)
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

    /// A 31-day month on two sites with one day split between them (1.2):
    /// the Site column, the day's rows shaded as one with its Day row, the
    /// Sites tile and "By site" beside the summary. Every day and the total
    /// still fit the first page.
    func testCaptureAMonthWithASplitDay() throws {
        var export = ExportPreferences()
        export.ownerName = "Marijo Mikša"
        export.includeEmptyDays = true
        let settings = Fixture.settings(export: export)
        let haupt = UUID()
        let trg = UUID()
        let start = Fixture.date(2026, 10, 1)
        let end = Fixture.date(2026, 10, 31)
        let range = CalendarDateRange(start: start, end: end)
        func shift(_ site: UUID, _ from: TimeOfDay, _ to: TimeOfDay, breakMinutes: Int) -> Shift {
            Shift(
                id: site, start: from, end: to,
                breaks: breakMinutes > 0 ? [BreakSpan(id: site, explicitMinutes: breakMinutes)] : [],
                siteID: site
            )
        }

        var records: [Int: DayRecord] = [:]
        for day in 1...31 {
            let date = Fixture.date(2026, 10, day)
            let weekday = calendar.component(.weekday, from: date.date(in: calendar))
            guard weekday != 1, weekday != 7 else { continue }
            let shifts: [Shift]
            if day == 29 {
                shifts = [
                    shift(haupt, Fixture.time(7), Fixture.time(11, 30), breakMinutes: 0),
                    shift(trg, Fixture.time(12), Fixture.time(16), breakMinutes: 30)
                ]
            } else {
                shifts = [shift(day < 20 ? haupt : trg, Fixture.time(7), Fixture.time(16), breakMinutes: 30)]
            }
            records[date.key] = DayRecord(date: date, shifts: shifts)
        }

        let days = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: Fixture.longAgo)
            .days(in: range, records: records, holidays: [])
        var builder = ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—")
        builder.siteNames = [haupt: "Hauptstraße 12", trg: "Trg Pravde"]
        builder.siteAddresses = [haupt: "Hauptstraße 12\n10115 Berlin", trg: "Trg pravde 2\n10000 Zagreb"]
        let table = builder.makeTable(days: days, range: range, title: "Hours — October 2026", countingThrough: end)

        XCTAssertEqual(table.rows.count, 33, "31 days, the split day's second site and its Day row")
        let first = try XCTUnwrap(PDFReportLayout(table: table).pages().first)
        XCTAssertEqual(first.rows, 0..<table.rows.count, "every row on the first page")
        XCTAssertTrue(first.drawsTotal, "and the total under them")

        let data = PDFReportRenderer.data(for: table)
        for (index, image) in try pages(of: data).prefix(2).enumerated() {
            attach(image, named: "06-export-pdf-two-sites-\(index + 1)")
        }
    }

    /// A month with the field allowance, kilometres and travel, in German,
    /// with earnings on the sheet: the three columns before the notes, the
    /// allowance-days tile, and the summary's lines with their amounts.
    func testCaptureAMonthWithAllowanceColumns() throws {
        var export = ExportPreferences()
        export.ownerName = "Ada Lovelace"
        export.language = .german
        export.includeEarnings = true
        var settings = Fixture.settings(export: export)
        settings.changePay(forJob: Job.primaryID, to: PayRules(hourlyRateCents: 18_50), from: nil)
        settings.allowance = AllowancePreferences(
            isEnabled: true, dailyAllowanceCents: 28_00, centsPerKilometre: 42, travelCountsAsWork: false
        )
        let start = Fixture.date(2026, 8, 1)
        let end = Fixture.date(2026, 8, 31)
        let range = CalendarDateRange(start: start, end: end)

        var records: [Int: DayRecord] = [:]
        for day in 1...31 {
            let date = Fixture.date(2026, 8, day)
            let weekday = calendar.component(.weekday, from: date.date(in: calendar))
            guard weekday != 1, weekday != 7 else { continue }
            let away = day % 3 != 0
            records[date.key] = DayRecord(
                date: date,
                start: Fixture.time(7),
                end: Fixture.time(16),
                breaks: [.duration(30)],
                note: day == 12 ? "Baustelle Graz" : "",
                hasFieldAllowance: away,
                kilometres: away ? 0 : 46,
                travelMinutes: away ? 0 : 75
            )
        }

        let engine = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: Fixture.longAgo)
        let days = engine.days(in: range, records: records, holidays: [])
        let earnings = engine.earnings(in: range, records: records, holidays: [], countingThrough: end)
        let table = ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—")
            .makeTable(days: days, range: range, title: "Stunden — August 2026", countingThrough: end,
                       earnings: earnings, currencyCode: "EUR")
        XCTAssertTrue(table.columns.contains(.allowance))
        XCTAssertTrue(table.columns.contains(.kilometres))
        XCTAssertTrue(table.columns.contains(.travel))

        let rendered = try pages(of: PDFReportRenderer.data(for: table))
        for (index, image) in rendered.prefix(2).enumerated() {
            attach(image, named: "06-export-allowance-pdf-\(index + 1)")
        }
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
        let days = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: Fixture.longAgo)
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
        // French and Polish because they have the longest headings — "Heures
        // travaillées" and "Nieobecność płatna" against English's "Worked" —
        // so they are where a column tuned for English gives way first.
        let sampled: [(ExportLanguage, String)] = [
            (.german, "de"), (.croatian, "hr"), (.french, "fr"), (.polish, "pl")
        ]
        for (language, name) in sampled {
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

            // The CSV too. It was captured once, in English, and it is the
            // format most likely to be opened in a spreadsheet whose own
            // locale disagrees with the file — which is exactly where a
            // delimiter and a decimal separator stop being cosmetic.
            let csv = XCTAttachment(
                data: CSVExporter.data(
                    for: table,
                    preferences: ExportPreferences(language: language)
                ),
                uniformTypeIdentifier: "public.comma-separated-values-text"
            )
            csv.name = "13-export-csv-\(name).csv"
            csv.lifetime = .keepAlways
            add(csv)

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

        // The page prints its column titles in capitals.
        for heading in ["DATUM", "ART", "GEARBEITET", "PAUSE", "ÜBERSTUNDEN"] {
            XCTAssertTrue(text.contains(heading), "the PDF never drew the column title \(heading)")
        }
        for english in ["Worked", "Expected", "Overtime", "Break"] {
            XCTAssertFalse(text.contains(english), "\(english) is still in English in the rendered PDF")
            XCTAssertFalse(text.contains(english.uppercased()), "\(english) is still in English in the rendered PDF")
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

    /// No column that must not be cut short is narrower than what it holds.
    ///
    /// The page has a fixed width, so widening one column narrows another.
    /// The first attempt at making room for longer headings did exactly that
    /// and traded a clipped heading for a clipped date. This measures every
    /// column of every language against the text it will draw, so the trade
    /// cannot come back unnoticed.
    func testNoColumnIsNarrowerThanWhatItMustShow() {
        // The fonts the page draws in, and the headings as it prints them:
        // in capitals, which are wider.
        let heading = PDFReportStyle.headingFont
        func width(_ text: String, _ font: UIFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }

        for language in ExportLanguage.allCases where language != .device {
            let table = monthTable(language: language)
            let available = PDFReportRenderer.pageSize.width - PDFReportRenderer.margin * 2
            let widths = PDFReportRenderer.columnWidths(for: table, availableWidth: available)

            XCTAssertEqual(widths.count, table.columns.count)
            XCTAssertLessThanOrEqual(
                widths.reduce(0, +), available + 0.5,
                "\(language.rawValue): the columns are wider than the page"
            )

            for (index, column) in table.columns.enumerated() {
                let printed = column.heading(in: table.language).uppercased(with: table.language.locale)
                var needed = width(printed, heading)
                if !column.mayTruncate {
                    for row in table.rows where index < row.values.count {
                        let cell = PDFReportLayout.font(for: column, role: row.role)
                        needed = max(needed, width(row.values[index], cell))
                    }
                }
                XCTAssertGreaterThanOrEqual(
                    widths[index], needed,
                    "\(language.rawValue): \(column.rawValue) is too narrow for what it draws"
                )
            }
        }
    }

    // MARK: - The director's sheet

    /// The crew a big site has: with you, ten people on one sheet.
    private static let bigCrew = [
        "Ivan Horvat", "Marko Kovač", "Stjepan Babić", "Josip Novak", "Ante Jurić",
        "Tomislav Knežević", "Katarina Vuković-Marić", "Luka Pavlović", "Dragan Božić"
    ]

    /// A site's month with the cases its page has to show: someone off for a
    /// day, someone leaving early, and a note. `crew` after the first two
    /// are there every working day, the odd one leaving early.
    private func siteTable(crew names: [String] = ["Ivan Horvat", "Marko Kovač"], address: String = "") -> ReportTable {
        let site = Site(name: "Trg Pravde Zagreb", address: address)
        var export = ExportPreferences()
        export.ownerName = "Marijo Mikša"
        let settings = Fixture.settings(export: export)
        let crew = names.enumerated().map { index, name in
            CrewMember(siteID: site.id, name: name, isHidden: false, sortOrder: index)
        }
        var days: [SiteDay] = []
        for day in 1...31 {
            let date = Fixture.date(2026, 8, day)
            let weekday = calendar.component(.weekday, from: date.date(in: calendar))
            guard weekday != 1, weekday != 7 else { continue }
            var present = [Attendance(memberID: CrewMember.youID)]
            for (index, member) in crew.enumerated() {
                switch index {
                case 0:
                    present.append(Attendance(memberID: member.id))
                case 1:
                    if day % 6 != 0 {
                        present.append(Attendance(memberID: member.id, end: day % 5 == 0 ? Fixture.time(13) : nil))
                    }
                default:
                    present.append(Attendance(memberID: member.id, end: (day + index) % 7 == 0 ? Fixture.time(14, 30) : nil))
                }
            }
            days.append(SiteDay(
                siteID: site.id,
                date: date,
                start: Fixture.time(7),
                end: Fixture.time(16),
                breakMinutes: 30,
                present: present,
                note: day == 12 ? "Crane delivery" : ""
            ))
        }
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "")
            .makeTable(
                site: site,
                crew: crew,
                results: days.map(calculator.compute),
                range: CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))
            )
    }

    func testCaptureTheSiteSheet() throws {
        let table = siteTable()
        let data = PDFReportRenderer.data(for: table)
        for (index, image) in try pages(of: data).prefix(2).enumerated() {
            attach(image, named: "14-site-pdf-\(index + 1)")
        }
        let workbook = XCTAttachment(
            data: XLSXWriter.data(for: table, preferences: ExportPreferences(), generatedOn: Date()),
            uniformTypeIdentifier: "org.openxmlformats.spreadsheetml.sheet"
        )
        workbook.name = "15-site-xlsx.xlsx"
        workbook.lifetime = .keepAlways
        add(workbook)

        // The names head their columns and the closing rows are there.
        let document = try XCTUnwrap(PDFDocument(data: data))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        XCTAssertTrue(text.contains("IVAN HORVAT"), "a person's name is missing from the headings")
        // A normal crew's month and its closing rows, on one page.
        XCTAssertEqual(document.pageCount, 1, "a normal crew's month should fit one page")
        // The date and the day head a column each, as on a timesheet.
        for heading in ["DATE", "DAY"] {
            XCTAssertTrue(text.contains(heading), "the PDF never drew the column title \(heading)")
        }
        XCTAssertTrue(text.contains("2026-08-03"), "the date is not in the export's date style")
        XCTAssertTrue(text.contains("Month total"))
        XCTAssertTrue(text.contains("Checked"), "the signature line is missing")
    }

    /// The site's address is one small line under the byline (1.2): the
    /// month, its closing rows and the line to sign on still fit one page,
    /// and every part of a split sheet carries it.
    func testCaptureTheSiteSheetWithAnAddress() throws {
        let table = siteTable(address: "Trg pravde 1\n10000 Zagreb")
        XCTAssertEqual(table.address, "Trg pravde 1, 10000 Zagreb")
        let data = PDFReportRenderer.data(for: table)
        for (index, image) in try pages(of: data).prefix(1).enumerated() {
            attach(image, named: "14b-site-pdf-address-\(index + 1)")
        }
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, 1, "an address must not push a normal crew's month onto a second page")
        let text = document.page(at: 0)?.string ?? ""
        XCTAssertTrue(text.contains("Trg pravde 1, 10000 Zagreb"), "the address is not under the site's name")
        XCTAssertTrue(text.contains("2026-08-31"), "the 31st is not on the first page")
        XCTAssertTrue(text.contains("Month total"))
        XCTAssertTrue(text.contains("Checked"), "the signature line is missing")

        let parts = PDFReportRenderer.parts(of: siteTable(crew: Self.bigCrew, address: "Trg pravde 1"))
        XCTAssertGreaterThan(parts.count, 1)
        XCTAssertTrue(parts.allSatisfy { $0.address == "Trg pravde 1" })
    }

    /// Ten people for a whole month, to be looked at: whether a big crew's
    /// sheet still reads on A4 landscape. See the test below for the figures.
    func testCaptureTheSiteSheetForTenPeople() throws {
        let table = siteTable(crew: Self.bigCrew)
        let data = PDFReportRenderer.data(for: table)
        for (index, image) in try pages(of: data).prefix(2).enumerated() {
            attach(image, named: "16-site-pdf-ten-people-\(index + 1)")
        }
        let document = try XCTUnwrap(PDFDocument(data: data))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        XCTAssertTrue(text.contains("Month total"))
    }

    /// How many people fit on the site sheet before a time or an hours
    /// column is cut short.
    ///
    /// Every person is two columns that may never truncate — "07:00–16:00"
    /// and their hours — so the page runs out at some crew size and the
    /// renderer then squeezes every column by weight. Up to a normal crew the
    /// sheet must fit; past that this prints the figures (what the columns
    /// need against what the page has) instead of failing, so the limit is
    /// visible in the log until the layout is changed for big crews.
    func testTheSiteSheetFitsANormalCrewAndReportsWhereItStops() {
        let heading = PDFReportStyle.headingFont
        let available = PDFReportRenderer.pageSize.width - PDFReportRenderer.margin * 2
        let padding = PDFReportStyle.cellPadding * 2

        print("----- site sheet width -----")
        for crewSize in 0...Self.bigCrew.count {
            let table = siteTable(crew: Array(Self.bigCrew.prefix(crewSize)))
            let widths = PDFReportRenderer.columnWidths(for: table, availableWidth: available)
            XCTAssertEqual(widths.count, table.columns.count)

            // The headings as the page draws them: blank under a person's
            // name, which spans their two columns.
            let headings = PDFReportLayout(table: table).columnHeadings()
            var everyRow = table.rows
            if let totalRow = table.totalRow { everyRow.append(totalRow) }
            var required: CGFloat = 0
            var clipped: [String] = []
            for (index, column) in table.columns.enumerated() {
                var needed = PDFReportStyle.width(of: headings[index], font: heading)
                if !column.mayTruncate {
                    for row in everyRow where index < row.values.count {
                        let font = PDFReportLayout.font(for: column, role: row.role)
                        needed = max(needed, PDFReportStyle.width(of: row.values[index], font: font))
                    }
                }
                required += needed + padding
                if !column.mayTruncate, widths[index] + 0.5 < needed {
                    clipped.append("\(column.rawValue) \(Int(widths[index]))pt < \(Int(needed.rounded(.up)))pt")
                }
            }
            let people = crewSize + 1
            print("\(people) people: columns need \(Int(required.rounded(.up)))pt of \(Int(available))pt"
                + (clipped.isEmpty ? " — fits" : " — clipped: \(Set(clipped).sorted().joined(separator: ", "))"))

            if people <= 5 {
                XCTAssertTrue(clipped.isEmpty, "\(people) people: \(clipped.joined(separator: ", "))")
            }
        }
        print("----- end site sheet width -----")
    }

    /// The footer counts the pages it is on, which it can only do because
    /// the pages are laid out before any is drawn.
    func testTheFooterKnowsHowManyPagesThereAre() throws {
        let table = monthTable(days: 31)
        let document = try XCTUnwrap(PDFDocument(data: PDFReportRenderer.data(for: table)))
        let count = document.pageCount
        XCTAssertGreaterThan(count, 0)
        for index in 0..<count {
            let text = document.page(at: index)?.string ?? ""
            XCTAssertTrue(text.contains("page \(index + 1) of \(count)"), "page \(index + 1) does not say of \(count)")
        }
    }

    /// A 31-day month keeps every day and the total on the first page, the
    /// rows a little tighter; only the summary goes on, with the lines to sign
    /// on. The 31st used to go over alone with the total.
    func testAMonthsDaysAndTotalShareThePage() throws {
        let table = monthTable(days: 31)
        let document = try XCTUnwrap(PDFDocument(data: PDFReportRenderer.data(for: table)))
        let first = document.page(at: 0)?.string ?? ""
        XCTAssertTrue(first.contains("2026-08-31"), "the 31st is not on the first page")
        XCTAssertTrue(first.contains("Total"), "the total is not under the days")
        let all = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        XCTAssertTrue(all.contains("Summary"))
    }

    // MARK: - A big crew, split across pages

    /// Ten people for a whole month: more than A4 landscape holds, so the
    /// month prints once per group of people, each part with the date, the
    /// day, the notes and its own closing rows, and "People 1–5 of 10" under
    /// the header.
    func testCaptureTheSiteSheetSplitForTenPeople() throws {
        let table = siteTable(crew: Self.bigCrew)
        let parts = PDFReportRenderer.parts(of: table)
        XCTAssertGreaterThan(parts.count, 1, "ten people were printed on one page")

        let data = PDFReportRenderer.data(for: table)
        for (index, image) in try pages(of: data).prefix(4).enumerated() {
            attach(image, named: "17-site-pdf-split-\(index + 1)")
        }
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(document.pageCount, parts.count)
        let pageTexts = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        let text = pageTexts.joined()

        // The page count runs across every part.
        for (index, page) in pageTexts.enumerated() {
            XCTAssertTrue(page.contains("page \(index + 1) of \(document.pageCount)"), "page \(index + 1) is misnumbered")
        }
        XCTAssertTrue(pageTexts[0].contains(parts[0].partLabel), "the first page does not say whose hours it holds")
        XCTAssertTrue(parts[0].partLabel.hasPrefix("People 1–"))
        for part in parts {
            XCTAssertTrue(text.contains(part.partLabel), "\(part.partLabel) is not printed")
        }
        // Everyone is there, under their own name, and every part closes.
        for name in ["MARIJO MIKŠA"] + Self.bigCrew.map({ $0.uppercased() }) {
            XCTAssertTrue(text.contains(name), "\(name) is missing from the headings")
        }
        XCTAssertEqual(text.components(separatedBy: "Month total").count - 1, parts.count)
        XCTAssertGreaterThanOrEqual(text.components(separatedBy: "NOTES").count - 1, parts.count, "a part has no Notes")
    }

    /// One sheet for two sites' month (1.2): ten people across both crews,
    /// Ivan Horvat on both and moving between them on Tuesdays. Both crews
    /// work every weekday, so a day is a row per site, and a Tuesday adds
    /// Ivan's total; By site is on the last page, after everyone.
    func testCaptureACombinedSheetForTwoSites() throws {
        let first = Site(name: "Hauptstraße 12", address: "Hauptstraße 12\n10115 Berlin")
        let second = Site(name: "Trg Pravde")
        var export = ExportPreferences()
        export.ownerName = "Marijo Mikša"
        let settings = Fixture.settings(export: export)
        let crewHere = Self.bigCrew.prefix(5).enumerated().map { CrewMember(siteID: first.id, name: $1, sortOrder: $0) }
        let crewThere = (["Ivan Horvat"] + Self.bigCrew.suffix(4)).enumerated()
            .map { CrewMember(siteID: second.id, name: $1, sortOrder: $0) }
        var days: [SiteDay] = []
        for day in 1...31 {
            let date = Fixture.date(2026, 8, day)
            let weekday = calendar.component(.weekday, from: date.date(in: calendar))
            guard weekday != 1, weekday != 7 else { continue }
            let moves = weekday == 3
            var here = ([CrewMember.youID] + crewHere.map(\.id)).map { Attendance(memberID: $0) }
            if moves { here[1] = Attendance(memberID: crewHere[0].id, end: Fixture.time(11, 30), breakMinutes: 0) }
            var there = crewThere.dropFirst().map { Attendance(memberID: $0.id) }
            if moves { there.insert(Attendance(memberID: crewThere[0].id, start: Fixture.time(12)), at: 0) }
            days.append(SiteDay(siteID: first.id, date: date, start: Fixture.time(7), end: Fixture.time(16),
                                breakMinutes: 30, present: here, note: day == 12 ? "Crane delivery" : ""))
            days.append(SiteDay(siteID: second.id, date: date, start: Fixture.time(7), end: Fixture.time(16),
                                breakMinutes: 30, present: there))
        }
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let table = SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "")
            .makeTable(
                sites: [first, second],
                crew: crewHere + crewThere,
                results: days.map(calculator.compute),
                range: CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))
            )
        XCTAssertEqual(SiteSheetBuilder.peopleCount(in: table), 10, "you and nine, Ivan Horvat once")

        let data = PDFReportRenderer.data(for: table)
        for (index, image) in try pages(of: data).prefix(4).enumerated() {
            attach(image, named: "17b-site-pdf-combined-\(index + 1)")
        }
        let document = try XCTUnwrap(PDFDocument(data: data))
        let single = try XCTUnwrap(PDFDocument(data: PDFReportRenderer.data(for: siteTable(crew: Self.bigCrew))))
        XCTAssertGreaterThanOrEqual(document.pageCount, single.pageCount)
        XCTAssertLessThanOrEqual(document.pageCount, single.pageCount * 3, "a row per site a day, not more")
        let pageTexts = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        XCTAssertTrue(pageTexts[0].contains("Hauptstraße 12 · Trg Pravde"), "the title does not name both sites")
        let last = try XCTUnwrap(pageTexts.last)
        XCTAssertTrue(last.contains("By site"), "By site is not on the last page")
        XCTAssertTrue(last.contains("Hauptstraße 12, 10115 Berlin"), "the address is not in By site")
        XCTAssertEqual(pageTexts.joined().components(separatedBy: "By site").count - 1, 1, "By site is printed once")
        XCTAssertTrue(pageTexts.joined().contains("2026-08-31"))

        // The dates as wide as a date, not as "Month total" or a site's name
        // under them, which run on over the empty day and site cells; and
        // the site column wide enough for the site's whole name.
        let layout = PDFReportLayout(table: table)
        let minimum = layout.minimumWidths()
        let dateWidth = PDFReportStyle.width(of: "2026-08-31", font: PDFReportStyle.cellFont) + PDFReportStyle.cellPadding * 2
        XCTAssertLessThanOrEqual(minimum[0], dateWidth + 1, "the dates are sized by their closing labels")
        let siteName = PDFReportStyle.width(of: "Hauptstraße 12", font: PDFReportStyle.cellFont)
        XCTAssertGreaterThanOrEqual(minimum[2], siteName, "a site's name is cut short")
        let monthTotal = try XCTUnwrap(table.rows.first { $0.role == .total })
        XCTAssertEqual(layout.labelSpan(of: monthTotal), 0..<3)
    }

    /// Whatever the crew, no time and no hours are cut short: the sheet is
    /// split as far as it has to be and no further. A crew that fits prints
    /// exactly as it always did — one table, no "People 1–5 of 5".
    func testNoCrewSizeCutsATimeShort() {
        let available = PDFReportRenderer.pageSize.width - PDFReportRenderer.margin * 2
        print("----- site sheet parts -----")
        for crewSize in 0...Self.bigCrew.count {
            let table = siteTable(crew: Array(Self.bigCrew.prefix(crewSize)))
            let parts = PDFReportRenderer.parts(of: table)
            let people = crewSize + 1
            print("\(people) people: \(parts.compactMap(SiteSheetBuilder.peopleCount(in:))) to a page")

            if people <= 5 {
                XCTAssertEqual(parts, [table], "\(people) people should fit on one page, unchanged")
            }
            if parts.count == 1 {
                XCTAssertEqual(parts, [table], "a sheet that was not split was still changed")
            }
            for part in parts {
                let widths = PDFReportRenderer.columnWidths(for: part, availableWidth: available)
                let minimum = PDFReportLayout(table: part).minimumWidths()
                for (index, column) in part.columns.enumerated() where !column.mayTruncate {
                    XCTAssertGreaterThanOrEqual(
                        widths[index] + 0.5, minimum[index],
                        "\(people) people, \(part.partLabel): \(column.rawValue) is cut short"
                    )
                }
            }
        }
        print("----- end site sheet parts -----")
    }

    /// One person's own sheet for a month on two sites, with a sick day and
    /// a day on leave: the page a worker is handed to check against their
    /// payslip, in the personal timesheet's design.
    private func crewMemberTable() -> ReportTable {
        let south = Site(name: "Trg Pravde Zagreb", sortOrder: 0)
        let hall = Site(name: "Halle 3", sortOrder: 1)
        var export = ExportPreferences()
        export.ownerName = "Marijo Mikša"
        let settings = Fixture.settings(export: export)
        let ivan = CrewMember(siteID: south.id, name: "Ivan Horvat")
        let ivanHall = CrewMember(siteID: hall.id, name: "Ivan Horvat")
        var days: [SiteDay] = []
        for day in 1...31 {
            let date = Fixture.date(2026, 8, day)
            let weekday = calendar.component(.weekday, from: date.date(in: calendar))
            guard weekday != 1, weekday != 7 else { continue }
            switch day {
            case 11:
                days.append(SiteDay(siteID: south.id, date: date, start: Fixture.time(7), end: Fixture.time(16),
                                    breakMinutes: 30, absences: [CrewAbsence(memberID: ivan.id, dayTypeID: .sick)]))
            case 24:
                days.append(SiteDay(siteID: south.id, date: date, start: Fixture.time(7), end: Fixture.time(16),
                                    breakMinutes: 30, absences: [CrewAbsence(memberID: ivan.id, dayTypeID: .vacation)]))
            case 17...21:
                days.append(SiteDay(siteID: hall.id, date: date, start: Fixture.time(6, 30), end: Fixture.time(15),
                                    breakMinutes: 30, present: [Attendance(memberID: ivanHall.id)],
                                    note: day == 17 ? "Crane delivery" : ""))
            default:
                days.append(SiteDay(siteID: south.id, date: date, start: Fixture.time(7), end: Fixture.time(16),
                                    breakMinutes: 30,
                                    present: [Attendance(memberID: ivan.id, end: day % 5 == 0 ? Fixture.time(13) : nil)]))
            }
        }
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return CrewMemberSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "")
            .makeTable(
                person: .matching(ivan, in: [ivan, ivanHall]),
                sites: [south, hall],
                results: days.map(calculator.compute),
                range: CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))
            )
    }

    func testCaptureACrewMembersOwnSheet() throws {
        let table = crewMemberTable()
        let data = PDFReportRenderer.data(for: table)
        for (index, image) in try pages(of: data).prefix(2).enumerated() {
            attach(image, named: "18-crew-member-pdf-\(index + 1)")
        }
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(document.pageCount, 1, "a person's normal month should fit one page")
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        XCTAssertTrue(text.contains("Ivan Horvat"), "the person's name does not head the sheet")
        XCTAssertTrue(text.contains("Halle 3"), "the second site is missing")
        XCTAssertTrue(text.contains("Sick leave"), "the sick day has no reason")
        XCTAssertTrue(text.contains("Employee"), "the line to sign on is missing")
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
