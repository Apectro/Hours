import XCTest
@testable import Hours

/// The exported file is the thing that leaves the app, so its shape matters
/// more than almost anything else here.
final class ExportTests: XCTestCase {
    private let calendar = Fixture.calendar()

    private func sampleTable(
        settings: AppSettings = Fixture.settings(),
        placeholder: String = ""
    ) -> ReportTable {
        let range = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 8))
        let records: [Int: DayRecord] = [
            Fixture.workingMonday.key: DayRecord(
                date: Fixture.workingMonday,
                start: Fixture.time(8),
                end: Fixture.time(16, 30),
                breaks: [.duration(30)]
            ),
            Fixture.workingTuesday.key: DayRecord(
                date: Fixture.workingTuesday,
                start: Fixture.time(8),
                end: Fixture.time(18),
                breaks: [.duration(30)],
                note: "Release, said \"finally\""
            )
        ]
        let days = PeriodEngine(settings: settings, calendar: calendar)
            .days(in: range, records: records, holidays: [])
        return ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: placeholder)
            .makeTable(
                days: days,
                range: range,
                title: "Hours — August 2026",
                // Totals stop on the 4th, so this fixture behaves like a month
                // still in progress — the case the summary has to get right.
                countingThrough: Fixture.workingTuesday
            )
    }

    // MARK: - The table

    func testEveryDayInTheRangeGetsARow() {
        let table = sampleTable()
        XCTAssertEqual(table.rows.count, 8)
        XCTAssertEqual(table.columns, ReportColumn.defaultSelection)
    }

    func testTheRowsCarryTheRightFigures() {
        let table = sampleTable()
        guard let monday = table.rows.first(where: { $0.id == Fixture.workingMonday.key }) else {
            return XCTFail("Monday is missing from the report")
        }
        let index = { (column: ReportColumn) -> Int in table.columns.firstIndex(of: column) ?? 0 }

        XCTAssertEqual(monday.values[index(.date)], "2026-08-03")
        XCTAssertEqual(monday.values[index(.weekday)], "Mon")
        XCTAssertEqual(monday.values[index(.dayType)], "Work")
        XCTAssertEqual(monday.values[index(.start)], "08:00")
        XCTAssertEqual(monday.values[index(.end)], "16:30")
        XCTAssertEqual(monday.values[index(.breakTime)], "30m")
        XCTAssertEqual(monday.values[index(.worked)], "8h")
        XCTAssertEqual(monday.values[index(.expected)], "8h")
        XCTAssertEqual(monday.values[index(.overtime)], "0h")
    }

    func testAWeekendRowIsPresentButEmpty() {
        let table = sampleTable(placeholder: "—")
        guard let saturday = table.rows.first(where: { $0.id == Fixture.date(2026, 8, 1).key }) else {
            return XCTFail("Saturday is missing from the report")
        }
        let index = { (column: ReportColumn) -> Int in table.columns.firstIndex(of: column) ?? 0 }

        XCTAssertEqual(saturday.values[index(.dayType)], "Weekend")
        XCTAssertEqual(saturday.values[index(.start)], "—")
        XCTAssertEqual(saturday.values[index(.worked)], "0h")
        XCTAssertFalse(saturday.isWorkingDay)
    }

    func testSwitchingOffAFeatureRemovesItsColumnFromTheReport() {
        var features = FeatureToggles()
        features.trackBreaks = false
        features.trackNotes = false
        let table = sampleTable(settings: Fixture.settings(features: features))

        XCTAssertFalse(table.columns.contains(.breakTime))
        XCTAssertFalse(table.columns.contains(.note))
        XCTAssertTrue(table.columns.contains(.worked))
    }

    func testTheSummaryAddsUp() {
        let table = sampleTable()
        let totals = Dictionary(uniqueKeysWithValues: table.totals.map { ($0.label, $0.value) })

        XCTAssertEqual(totals["Total worked"], "17h 30m")
        XCTAssertEqual(totals["Total expected"], "16h")
        XCTAssertEqual(totals["Balance"], "+1h 30m")
        XCTAssertEqual(totals["Days worked"], "2")
    }

    func testEmptyDaysCanBeLeftOut() {
        var settings = Fixture.settings()
        settings.export.includeEmptyDays = false
        let table = sampleTable(settings: settings)

        XCTAssertEqual(table.rows.count, 2)
        XCTAssertTrue(table.rows.allSatisfy(\.hasEntry))
    }

    // MARK: - CSV

    func testCSVQuotesOnlyWhatNeedsQuoting() {
        XCTAssertEqual(CSVExporter.escape("plain", separator: ","), "plain")
        XCTAssertEqual(CSVExporter.escape("a,b", separator: ","), "\"a,b\"")
        XCTAssertEqual(CSVExporter.escape("a,b", separator: ";"), "a,b")
        XCTAssertEqual(CSVExporter.escape("a;b", separator: ";"), "\"a;b\"")
        XCTAssertEqual(CSVExporter.escape("say \"hi\"", separator: ","), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVExporter.escape("line\nbreak", separator: ","), "\"line\nbreak\"")
        XCTAssertEqual(CSVExporter.escape(" padded ", separator: ","), "\" padded \"")
    }

    /// The Start and End columns of a split shift entered out of order.
    ///
    /// This is where the ordering bug actually reached a person: not on a
    /// screen they could squint at, but in a file sent to whoever pays them,
    /// reading Start 13:00 and End 12:00 for a perfectly ordinary day.
    func testASplitShiftExportsItsStartAndEndTheRightWayRound() {
        let settings = Fixture.settings()
        let date = Fixture.workingTuesday
        let records = [
            date.key: DayRecord(
                date: date,
                shifts: [
                    Shift(start: Fixture.time(13), end: Fixture.time(17)),
                    Shift(start: Fixture.time(8), end: Fixture.time(12))
                ]
            )
        ]
        let range = CalendarDateRange(single: date)
        let days = PeriodEngine(settings: settings, calendar: calendar)
            .days(in: range, records: records, holidays: [])
        let table = ReportBuilder(settings: settings, calendar: calendar)
            .makeTable(days: days, range: range, title: "Split", countingThrough: date)

        let row = table.rows.first
        let startColumn = table.columns.firstIndex(of: .start)
        let endColumn = table.columns.firstIndex(of: .end)
        guard let row, let startColumn, let endColumn else {
            return XCTFail("the report has no start and end columns to check")
        }

        XCTAssertEqual(row.values[startColumn], "08:00")
        XCTAssertEqual(row.values[endColumn], "17:00")
    }

    // MARK: - What the file does on someone else's machine

    /// A note is free text, and free text beginning `=` is a formula to every
    /// spreadsheet that opens it. The export exists to be sent to a payroll
    /// department, so the machine that runs it is not this one.
    func testANoteIsNeverAFormula() {
        XCTAssertEqual(
            CSVExporter.escape("=HYPERLINK(\"http://elsewhere\",\"payslip\")", separator: ","),
            "\"'=HYPERLINK(\"\"http://elsewhere\"\",\"\"payslip\"\")\""
        )
        XCTAssertEqual(CSVExporter.defused("=1+1"), "'=1+1")
        XCTAssertEqual(CSVExporter.defused("+1"), "'+1")
        XCTAssertEqual(CSVExporter.defused("@SUM(A1)"), "'@SUM(A1)")
        XCTAssertEqual(CSVExporter.defused("\tstarts with a tab"), "'\tstarts with a tab")
    }

    /// The other half of that trade: ordinary notes are left alone.
    func testOrdinaryNotesAreNotMangled() {
        for note in ["-2h owed", "- see email", "Release day", "8:00 start", "100% done", ""] {
            XCTAssertEqual(CSVExporter.defused(note), note, "\(note) was altered")
        }
    }

    /// The workbook needs no such guard, and this is why: its cells declare
    /// themselves text. If that ever changes to a shared-string or general
    /// cell type, this fails and says so.
    func testTheWorkbookWritesNotesAsDeclaredText() {
        let table = sampleTable()
        // Readable straight out of the archive because ZIPArchive stores its
        // entries uncompressed, so the sheet XML is in there as plain bytes.
        let package = String(decoding: XLSXWriter.data(for: table, preferences: ExportPreferences()), as: UTF8.self)
        XCTAssertTrue(package.contains("t=\"inlineStr\""), "text cells are no longer declared as inline strings")
    }

    /// The hours in a workbook have to be numbers.
    ///
    /// They were text, in every display style but one. A column of hours you
    /// cannot total is the one thing a workbook offers over the CSV sitting
    /// next to it, and this is a paid feature — so this asserts the property
    /// for all three styles rather than only the one that used to work.
    func testEveryDurationIsWrittenAsANumberInEveryDisplayStyle() {
        for style in DurationStyle.allCases {
            var preferences = ExportPreferences()
            preferences.durationStyle = style
            let settings = Fixture.settings(export: preferences)
            let package = String(
                decoding: XLSXWriter.data(for: sampleTable(settings: settings), preferences: preferences),
                as: UTF8.self
            )

            // 8h worked on the Monday, less the half-hour break, is 8.00; the
            // Tuesday runs to 18:00, which is 9.50.
            XCTAssertTrue(
                package.contains("<v>8.0000</v>"),
                "\(style) wrote the worked hours as text rather than a number"
            )
            XCTAssertTrue(
                package.contains("<v>9.5000</v>"),
                "\(style) wrote the longer day as text rather than a number"
            )
        }
    }

    /// And they have to carry a format, or the sheet shows 8 where it means
    /// 8.00 and 8.25 where it means a quarter past.
    func testDurationCellsCarryTheTwoDecimalFormat() {
        let package = String(
            decoding: XLSXWriter.data(for: sampleTable(), preferences: ExportPreferences()),
            as: UTF8.self
        )

        XCTAssertTrue(package.contains("s=\"2\""), "no cell uses the hours format")
        XCTAssertTrue(package.contains("numFmtId=\"164\" formatCode=\"0.00\""))
        XCTAssertTrue(package.contains("numFmtId=\"165\" formatCode=\"0\""))
        // Seven formats are declared and Style indexes them 0...6; a cell
        // asking for an eighth renders with nobody's formatting.
        XCTAssertTrue(package.contains("<cellXfs count=\"7\">"))
        XCTAssertFalse(package.contains("s=\"7\""), "a cell points past the end of cellXfs")
    }

    /// The summary block is where someone looks first, so its figures are
    /// numbers too — the durations as hours, the day counts as whole numbers.
    func testTheSummaryBlockIsNumericAsWell() {
        let package = String(
            decoding: XLSXWriter.data(for: sampleTable(), preferences: ExportPreferences()),
            as: UTF8.self
        )

        XCTAssertTrue(package.contains("s=\"3\""), "the emphasised totals are not formatted as hours")
        XCTAssertTrue(package.contains("s=\"4\""), "the day counts are not formatted as whole numbers")
    }

    /// The sheet has to be laid out, not just filled in.
    ///
    /// Opened on a phone, the first export read "2026-08-0" down the date
    /// column and "Total worl" and "Days work" in the summary, because no
    /// column had ever been given a width. Every column now takes its width
    /// from the widest thing in it, so nothing is truncated.
    func testColumnsAreWideEnoughForWhatIsInThem() {
        let package = String(
            decoding: XLSXWriter.data(for: sampleTable(), preferences: ExportPreferences()),
            as: UTF8.self
        )

        XCTAssertTrue(package.contains("<cols>"), "no column widths at all")
        XCTAssertTrue(package.contains("customWidth=\"1\""))

        // "Scheduled working days" is 22 characters and sits in column A, so
        // column A cannot come out at the width of a date.
        guard let range = package.range(of: "<col min=\"1\" max=\"1\" width=\"") else {
            return XCTFail("column A has no width")
        }
        let width = Int(package[range.upperBound...].prefix { $0.isNumber }) ?? 0
        XCTAssertGreaterThanOrEqual(width, 25, "column A truncates the longest summary label")
        XCTAssertLessThanOrEqual(width, 44, "one long note should not push the sheet off the screen")
    }

    /// Scrolling a year of days must not lose the column titles, and the days
    /// should be sortable without the totals being dragged into the sort.
    func testTheHeaderIsFrozenAndFiltersOnlyTheDays() {
        let table = sampleTable()
        let package = String(
            decoding: XLSXWriter.data(for: table, preferences: ExportPreferences()),
            as: UTF8.self
        )

        XCTAssertTrue(package.contains("state=\"frozen\""), "the header scrolls away")
        XCTAssertTrue(package.contains("ySplit=\"1\""))

        // The filter covers the header and the days, and stops before the
        // blank row and the summary block underneath.
        let lastDayRow = table.rows.count + 1
        XCTAssertTrue(
            package.contains("<autoFilter ref=\"A1:\(XLSXWriter.columnName(table.columns.count - 1))\(lastDayRow)\"/>"),
            "the filter range does not stop at the last day"
        )
    }

    /// The header is the one part of the sheet that has to read as a heading
    /// on paper, where bold alone does not carry.
    func testTheHeaderRowIsStyledRatherThanMerelyBold() {
        let package = String(
            decoding: XLSXWriter.data(for: sampleTable(), preferences: ExportPreferences()),
            as: UTF8.self
        )

        XCTAssertTrue(package.contains("s=\"6\""), "the header row uses no header style")
        XCTAssertTrue(package.contains("<fgColor rgb=\"FF2B4A93\"/>"), "the header has no fill")
        XCTAssertTrue(package.contains("<color rgb=\"FFFFFFFF\"/>"), "the header text is not reversed out")
        XCTAssertTrue(package.contains("<bottom style=\"thin\">"), "no rule under the header")
    }

    /// Two elements the spec calls optional and a phone does not.
    ///
    /// Without `sheetFormatPr` and `dimension`, Excel and openpyxl honoured
    /// the column widths and the previewer on iOS discarded the whole `cols`
    /// block — so the file was correct everywhere except where someone opens
    /// it before sending it on. Optional in the format is not optional in
    /// practice.
    func testTheSheetDeclaresItsExtentAndItsFormattingDefaults() {
        let package = String(
            decoding: XLSXWriter.data(for: sampleTable(), preferences: ExportPreferences()),
            as: UTF8.self
        )

        XCTAssertTrue(package.contains("<dimension ref=\"A1:"), "the sheet does not declare its extent")
        XCTAssertTrue(package.contains("<sheetFormatPr"), "no formatting defaults, so cols may be ignored")

        // Order is fixed by the format, and a reader that finds them out of
        // order refuses the file rather than skipping the element.
        guard let dimension = package.range(of: "<dimension"),
              let views = package.range(of: "<sheetViews>"),
              let format = package.range(of: "<sheetFormatPr"),
              let cols = package.range(of: "<cols>"),
              let data = package.range(of: "<sheetData>") else {
            return XCTFail("the worksheet is missing one of its structural elements")
        }
        XCTAssertTrue(dimension.lowerBound < views.lowerBound)
        XCTAssertTrue(views.lowerBound < format.lowerBound)
        XCTAssertTrue(format.lowerBound < cols.lowerBound)
        XCTAssertTrue(cols.lowerBound < data.lowerBound)
    }

    func testCSVUsesCarriageReturnLineFeedAndStartsWithTheHeader() {
        let table = sampleTable()
        let csv = CSVExporter.string(for: table, preferences: ExportPreferences())
        let lines = csv.components(separatedBy: "\r\n")

        XCTAssertEqual(lines.first, "Date,Day,Type,Start,End,Break,Worked,Expected,Overtime,Notes")
        XCTAssertTrue(csv.hasSuffix("\r\n"))
    }

    func testACommaInsideANoteDoesNotBreakTheColumns() {
        let table = sampleTable()
        let csv = CSVExporter.string(for: table, preferences: ExportPreferences())
        XCTAssertTrue(
            csv.contains("\"Release, said \"\"finally\"\"\""),
            "the note must be quoted and its quotes doubled"
        )
    }

    func testASemicolonFileUsesSemicolons() {
        var preferences = ExportPreferences()
        preferences.fieldSeparator = .semicolon
        let csv = CSVExporter.string(for: sampleTable(), preferences: preferences)

        XCTAssertTrue(csv.hasPrefix("Date;Day;Type"))
    }

    func testDecimalDurationsFollowTheChosenDecimalSeparator() {
        var settings = Fixture.settings()
        settings.export.durationStyle = .decimal
        settings.export.decimalSeparator = .comma
        settings.export.fieldSeparator = .semicolon

        let table = sampleTable(settings: settings)
        guard let monday = table.rows.first(where: { $0.id == Fixture.workingMonday.key }),
              let index = table.columns.firstIndex(of: .worked) else {
            return XCTFail("Monday is missing from the report")
        }
        XCTAssertEqual(monday.values[index], "8,00")
    }

    func testTheByteOrderMarkIsWrittenOnlyWhenAskedFor() {
        let table = sampleTable()
        var preferences = ExportPreferences()

        preferences.includeByteOrderMark = true
        let withMark = CSVExporter.data(for: table, preferences: preferences)
        XCTAssertEqual(Array(withMark.prefix(3)), [0xEF, 0xBB, 0xBF])

        preferences.includeByteOrderMark = false
        let withoutMark = CSVExporter.data(for: table, preferences: preferences)
        XCTAssertNotEqual(Array(withoutMark.prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    func testTheSummaryFollowsABlankLineSoTheColumnsStayClean() {
        var preferences = ExportPreferences()
        preferences.includeSummaryRows = true
        let csv = CSVExporter.string(for: sampleTable(), preferences: preferences)
        let lines = csv.components(separatedBy: "\r\n")

        guard let blank = lines.firstIndex(of: "") else {
            return XCTFail("expected a blank line before the summary")
        }
        XCTAssertEqual(lines[blank - 1].hasPrefix("2026-08-08"), true, "data rows come first")
        XCTAssertTrue(lines[blank + 1].hasPrefix("Summary"))
    }

    // MARK: - XLSX

    func testSpreadsheetColumnNames() {
        XCTAssertEqual(XLSXWriter.columnName(0), "A")
        XCTAssertEqual(XLSXWriter.columnName(25), "Z")
        XCTAssertEqual(XLSXWriter.columnName(26), "AA")
        XCTAssertEqual(XLSXWriter.columnName(51), "AZ")
        XCTAssertEqual(XLSXWriter.columnName(52), "BA")
        XCTAssertEqual(XLSXWriter.columnName(701), "ZZ")
        XCTAssertEqual(XLSXWriter.columnName(702), "AAA")
    }

    func testXMLEscaping() {
        XCTAssertEqual(XLSXWriter.escape("a < b & c > d"), "a &lt; b &amp; c &gt; d")
        XCTAssertEqual(XLSXWriter.escape("say \"hi\""), "say &quot;hi&quot;")
        XCTAssertEqual(XLSXWriter.escape("tab\tkept"), "tab\tkept")
        XCTAssertEqual(XLSXWriter.escape("bell\u{07}gone"), "bellgone", "control characters would break the file")
    }

    func testTheWorkbookIsAValidZipContainer() {
        let data = XLSXWriter.data(for: sampleTable(), preferences: ExportPreferences())

        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "local file header signature")

        let tail = Array(data.suffix(22))
        XCTAssertEqual(Array(tail.prefix(4)), [0x50, 0x4B, 0x05, 0x06], "end of central directory")

        let entryCount = Int(tail[10]) | (Int(tail[11]) << 8)
        XCTAssertEqual(entryCount, 6, "six parts make up the package")
    }

    func testCRC32MatchesTheStandardCheckValue() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
    }

    // MARK: - Durations

    func testDurationFormatting() {
        let hoursMinutes = DurationFormatting(style: .hoursAndMinutes, minusSign: "-")
        XCTAssertEqual(hoursMinutes.string(0), "0h")
        XCTAssertEqual(hoursMinutes.string(480), "8h")
        XCTAssertEqual(hoursMinutes.string(570), "9h 30m")
        XCTAssertEqual(hoursMinutes.string(45), "45m")
        XCTAssertEqual(hoursMinutes.signedString(90), "+1h 30m")
        XCTAssertEqual(hoursMinutes.signedString(-90), "-1h 30m")

        let clock = DurationFormatting(style: .clock, minusSign: "-")
        XCTAssertEqual(clock.string(570), "9:30")
        XCTAssertEqual(clock.string(605), "10:05")

        let decimal = DurationFormatting(style: .decimal, minusSign: "-")
        XCTAssertEqual(decimal.string(570), "9.50")
        XCTAssertEqual(decimal.signedString(-90), "-1.50")
    }

    func testExportsUseAPlainHyphenSoSpreadsheetsSeeANegative() {
        let display = DurationFormatting.display
        let export = DurationFormatting.export(style: .hoursAndMinutes, decimalSeparator: ".")

        XCTAssertTrue(display.signedString(-60).hasPrefix("\u{2212}"), "on screen: a typographic minus")
        XCTAssertTrue(export.signedString(-60).hasPrefix("-"), "in a file: a plain hyphen")
    }

    func testDecimalHours() {
        XCTAssertEqual(DurationFormatting.decimalHours(90), 1.5)
        XCTAssertEqual(DurationFormatting.decimalHours(485), 8.08)
    }

    // MARK: - Dates and times in files

    func testExportDateStyles() {
        let date = Fixture.date(2026, 8, 4)
        XCTAssertEqual(ExportDateStyle.iso.string(for: date), "2026-08-04")
        XCTAssertEqual(ExportDateStyle.dotted.string(for: date), "04.08.2026")
        XCTAssertEqual(ExportDateStyle.slashed.string(for: date), "04/08/2026")
        XCTAssertEqual(ExportDateStyle.slashedUS.string(for: date), "08/04/2026")
    }

    func testExportTimeStyles() {
        XCTAssertEqual(ExportTimeStyle.twentyFourHour.string(for: Fixture.time(16, 30)), "16:30")
        XCTAssertEqual(ExportTimeStyle.twelveHour.string(for: Fixture.time(16, 30)), "4:30 PM")
        XCTAssertEqual(ExportTimeStyle.twelveHour.string(for: Fixture.time(0, 5)), "12:05 AM")
        XCTAssertEqual(ExportTimeStyle.twelveHour.string(for: Fixture.time(12, 0)), "12:00 PM")
    }

    func testAnOvernightEndTimeIsMarkedInTheFile() {
        let date = Fixture.workingMonday
        let records = [date.key: DayRecord(date: date, start: Fixture.time(22), end: Fixture.time(6))]
        let settings = Fixture.settings()
        let days = PeriodEngine(settings: settings, calendar: calendar)
            .days(in: CalendarDateRange(single: date), records: records, holidays: [])
        let table = ReportBuilder(settings: settings, calendar: calendar)
            .makeTable(days: days, range: CalendarDateRange(single: date), title: "One day")

        guard let index = table.columns.firstIndex(of: .end) else { return XCTFail("no end column") }
        XCTAssertEqual(table.rows[0].values[index], "06:00 (+1)")
    }

}
