import Foundation

/// Writes a report as a real `.xlsx` workbook.
///
/// The file is an OOXML package built by hand: strings are inline, so there is
/// no shared-string table to keep in sync, and durations chosen as decimal
/// hours are written as genuine numbers so a spreadsheet can total them without
/// anyone having to re-type a column.
enum XLSXWriter {
    /// Two sheets, summary first.
    ///
    /// A timesheet is opened by someone who wants one number — the balance —
    /// and only sometimes by someone who wants to audit thirty-one rows to
    /// find it. The PDF puts its totals on a page of their own for that
    /// reason; the workbook now opens on them, and the days are a tab away.
    static func data(for table: ReportTable, preferences: ExportPreferences, sheetName: String = "Hours") -> Data {
        let showsSummary = preferences.includeSummaryRows && !table.totals.isEmpty
        var archive = ZIPArchive()
        archive.addFile(name: "[Content_Types].xml", contents: Data(contentTypes(includesSummary: showsSummary).utf8))
        archive.addFile(name: "_rels/.rels", contents: Data(rootRelationships.utf8))
        archive.addFile(name: "xl/workbook.xml", contents: Data(workbook(sheetName: sheetName, includesSummary: showsSummary).utf8))
        archive.addFile(name: "xl/_rels/workbook.xml.rels", contents: Data(workbookRelationships(includesSummary: showsSummary).utf8))
        archive.addFile(name: "xl/styles.xml", contents: Data(styles.utf8))

        if showsSummary {
            archive.addFile(name: "xl/worksheets/sheet1.xml", contents: Data(summarySheet(for: table).utf8))
            archive.addFile(name: "xl/worksheets/sheet2.xml", contents: Data(daysSheet(for: table).utf8))
        } else {
            archive.addFile(name: "xl/worksheets/sheet1.xml", contents: Data(daysSheet(for: table).utf8))
        }
        return archive.finalized()
    }

    // MARK: - The summary sheet

    /// The page the workbook opens on.
    ///
    /// Built like the PDF's title block and totals: the report's name, the
    /// range it covers, then the figures in two labelled groups — the amounts
    /// of time, and the counts of days. Two columns wide, so nothing needs a
    /// horizontal scroll on a phone, which is where these get looked at first.
    private static func summarySheet(for table: ReportTable) -> String {
        var rows: [String] = []
        var grid: [[Cell]] = []
        var rowNumber = 1

        func emit(_ cells: [Cell], height: Double? = nil) {
            rows.append(row(number: rowNumber, cells: cells, height: height))
            grid.append(cells)
            rowNumber += 1
        }
        func blank() { rowNumber += 1 }

        emit([Cell.text(table.title, style: .title)], height: 28)
        emit([Cell.text(table.subtitle, style: .subtitle)])
        blank()

        let durations = table.totals.filter { $0.minutes != nil }
        let counts = table.totals.filter { $0.count != nil }
        let other = table.totals.filter { $0.minutes == nil && $0.count == nil }

        func group(_ heading: String, _ totals: [ReportTotal]) {
            guard !totals.isEmpty else { return }
            emit([Cell.text(heading, style: .section)], height: 20)
            for total in totals {
                let figure: Cell
                if let minutes = total.minutes {
                    figure = .number(
                        DurationFormatting.decimalHours(minutes),
                        style: total.isEmphasised ? .boldHours : .hours
                    )
                } else if let count = total.count {
                    figure = .number(Double(count), style: total.isEmphasised ? .boldCount : .count)
                } else {
                    figure = .text(total.value, style: total.isEmphasised ? .boldText : .normal)
                }
                emit([
                    Cell.text(total.label, style: total.isEmphasised ? .boldText : .normal),
                    figure
                ])
            }
            blank()
        }

        group("Hours", durations)
        group("Days", counts)
        group("Other", other)

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <dimension ref="A1:B\(max(1, rowNumber - 1))"/>\
        <sheetViews><sheetView tabSelected="1" workbookViewId="0"/></sheetViews>\
        <sheetFormatPr defaultRowHeight="15" baseColWidth="10"/>\
        \(columnWidths(for: grid))\
        <sheetData>\(rows.joined())</sheetData>\
        </worksheet>
        """
    }

    // MARK: - Worksheet

    private static func daysSheet(for table: ReportTable) -> String {
        var rows: [String] = []
        // Every cell, kept alongside the XML so the columns can be sized from
        // what is actually in them. A timesheet whose first column reads
        // "2026-08-0" and whose summary reads "Total worl" is not a document
        // anyone would hand to a payroll office.
        var grid: [[Cell]] = []
        var rowNumber = 1

        /// `sizing` is how many of the row's cells get a say in how wide their
        /// columns are. The summary block passes 1: its labels sit in the
        /// first column and must fit, but its second column holds the date
        /// range of the report, and sizing the *weekday* column to
        /// "2026-08-01 – 2026-08-31" made a column of "Mon" and "Tue" three
        /// times wider than the table needs. Text with empty cells to its
        /// right overflows into them on screen and on paper, so that heading
        /// is readable either way.
        func emit(_ cells: [Cell], sizing: Int? = nil, height: Double? = nil) {
            rows.append(row(number: rowNumber, cells: cells, height: height))
            grid.append(Array(cells.prefix(sizing ?? cells.count)))
            rowNumber += 1
        }

        emit(table.headerTitles().map { Cell.text($0, style: .header) }, height: 22)

        // Every duration is written as a number, whatever the display style.
        //
        // It used to write numbers only when the style was already decimal, on
        // the reasoning that "8h 30m" is text by nature. That is true of a CSV
        // and false of a spreadsheet: a cell holds a value and a display format
        // as two separate things, so it can hold 8.5 and show it however you
        // like. Writing the text instead threw away the only thing a workbook
        // does that a CSV does not — a column of hours you cannot sum is a
        // screenshot with extra steps, and this is a paid feature.
        //
        // Decimal hours rather than Excel's time serial. A serial with the
        // pretty [h]"h" mm"m" format reads better, but a negative one renders
        // as ######## in the 1900 date system, and a balance is negative
        // exactly when someone most wants to look at it.
        for (position, reportRow) in table.rows.enumerated() {
            // Alternate rows carry a wash, as the PDF's do. Reading across ten
            // columns of a thirty-one row table without one is how a Tuesday
            // gets mistaken for a Wednesday.
            let banded = !position.isMultiple(of: 2)
            let cells = reportRow.values.enumerated().map { index, value -> Cell in
                if index < reportRow.minutes.count, let minutes = reportRow.minutes[index] {
                    return Cell.number(DurationFormatting.decimalHours(minutes), style: .hours(banded: banded))
                }
                return Cell.text(value, style: .text(banded: banded))
            }
            emit(cells)
        }
        let lastDataRow = rowNumber - 1


        // The order of these elements is fixed by the file format — extent,
        // views, formatting defaults, columns, the data, then the filter — and
        // out of order the workbook is refused rather than degraded.
        //
        // `dimension` and `sheetFormatPr` are both optional by the letter of
        // the spec and both were left out, which cost an afternoon: Excel and
        // openpyxl honoured the column widths without them and the previewer
        // on a phone quietly discarded the whole <cols> block, so the file was
        // correct everywhere except the place someone actually opens it.
        let lastColumn = columnName(max(0, (grid.map(\.count).max() ?? 1) - 1))
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <dimension ref="A1:\(lastColumn)\(rowNumber - 1)"/>\
        \(frozenHeader)\
        <sheetFormatPr defaultRowHeight="15" baseColWidth="10"/>\
        \(columnWidths(for: grid))\
        <sheetData>\(rows.joined())</sheetData>\
        \(autoFilter(lastDataRow: lastDataRow, columns: table.columns.count))\
        </worksheet>
        """
    }

    /// Indexes into `cellXfs` in `styles`, in the order they are declared
    /// there. A wrong index here is not an error the file reports — the cell
    /// simply renders with somebody else's formatting.

    /// Scrolling a year of days must not lose the column titles.
    private static let frozenHeader = """
    <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
    """

    /// Sorting and filtering the days, without touching the totals below them.
    private static func autoFilter(lastDataRow: Int, columns: Int) -> String {
        guard lastDataRow > 1, columns > 0 else { return "" }
        return "<autoFilter ref=\"A1:\(columnName(columns - 1))\(lastDataRow)\"/>"
    }

    /// Column widths, from the widest thing each column has to show.
    ///
    /// The unit is roughly one character of the default font, so this is the
    /// longest value plus a little air. Bounded at both ends: a column narrower
    /// than its own heading is unreadable, and one note three hundred
    /// characters long should not push the rest of the sheet off the screen —
    /// a wrapped cell is better than a column nobody can scroll past.
    private static func columnWidths(for grid: [[Cell]]) -> String {
        let columnCount = grid.map(\.count).max() ?? 0
        guard columnCount > 0 else { return "" }

        var widest = Array(repeating: 0, count: columnCount)
        for row in grid {
            for (index, cell) in row.enumerated() where index < columnCount {
                widest[index] = max(widest[index], cell.width)
            }
        }

        let entries = widest.enumerated().map { index, characters -> String in
            let width = min(max(characters + 3, 9), 44)
            return "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width).0\" customWidth=\"1\" bestFit=\"1\"/>"
        }
        return "<cols>\(entries.joined())</cols>"
    }

    private enum Style: Int {
        case normal = 0
        case boldText = 1
        case hours = 2
        case boldHours = 3
        case count = 4
        case boldCount = 5
        case header = 6
        case title = 7
        case subtitle = 8
        case section = 9
        /// Ruled data rows, and the same three banded, so the table reads the
        /// way the PDF's does rather than as an undifferentiated grid.
        case ruledText = 10
        case ruledHours = 11
        case ruledCount = 12
        case bandedText = 13
        case bandedHours = 14
        case bandedCount = 15

        static func text(banded: Bool) -> Style { banded ? .bandedText : .ruledText }
        static func hours(banded: Bool) -> Style { banded ? .bandedHours : .ruledHours }
    }

    private enum Cell {
        case text(String, style: Style)
        case number(Double, style: Style)

        /// The characters this cell will try to show, for sizing the column.
        var width: Int {
            switch self {
            case let .text(value, _): return value.count
            // "165.00" and the like: the format is fixed, so the widest a
            // number gets is its digits plus the point and two decimals.
            case let .number(value, style):
                let whole = String(Int(value.magnitude)).count + (value < 0 ? 1 : 0)
                return style == .count || style == .boldCount ? whole : whole + 3
            }
        }
    }

    private static func row(number: Int, cells: [Cell], height: Double? = nil) -> String {
        // A taller header reads as a heading even where a renderer drops the
        // fill — Quick Look on a phone being the one that matters, since that
        // is where a timesheet gets looked at before it gets sent on.
        let heightAttribute = height.map { " ht=\"\($0)\" customHeight=\"1\"" } ?? ""
        var xml = "<row r=\"\(number)\"\(heightAttribute)>"
        for (index, cell) in cells.enumerated() {
            let reference = "\(columnName(index))\(number)"
            switch cell {
            case let .text(value, style):
                xml += "<c r=\"\(reference)\" t=\"inlineStr\" s=\"\(style.rawValue)\"><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
            case let .number(value, style):
                xml += "<c r=\"\(reference)\" s=\"\(style.rawValue)\"><v>\(format(value))</v></c>"
            }
        }
        xml += "</row>"
        return xml
    }

    /// 0 -> A, 25 -> Z, 26 -> AA.
    static func columnName(_ index: Int) -> String {
        var remaining = max(0, index)
        var name = ""
        repeat {
            let letter = Character(UnicodeScalar(UInt8(65 + remaining % 26)))
            name = String(letter) + name
            remaining = remaining / 26 - 1
        } while remaining >= 0
        return name
    }

    /// Always a point as the decimal mark: the file format demands it,
    /// regardless of what the user chose for CSV.
    private static func format(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    static func escape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value.unicodeScalars {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default:
                // Control characters are illegal in XML 1.0 and would make the
                // whole workbook unreadable.
                if character.value < 0x20 && character != "\t" && character != "\n" {
                    continue
                }
                result.unicodeScalars.append(character)
            }
        }
        return result
    }

    // MARK: - Fixed parts

    private static func contentTypes(includesSummary: Bool) -> String {
        let second = includesSummary
            ? "<Override PartName=\"/xl/worksheets/sheet2.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            : ""
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\(second)<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
        """
    }

    private static let rootRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static func workbookRelationships(includesSummary: Bool) -> String {
        // Styles take the last id, so the sheets keep rId1 and rId2 in the
        // order the workbook lists them.
        let sheets = includesSummary
            ? "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet2.xml\"/>"
            : "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/>"
        let styles = includesSummary
            ? "<Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
            : "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(sheets)\(styles)</Relationships>
        """
    }

    private static func workbook(sheetName: String, includesSummary: Bool) -> String {
        let name = escape(String(sheetName.prefix(31)))
        let sheets = includesSummary
            ? "<sheet name=\"Summary\" sheetId=\"1\" r:id=\"rId1\"/><sheet name=\"\(name)\" sheetId=\"2\" r:id=\"rId2\"/>"
            : "<sheet name=\"\(name)\" sheetId=\"1\" r:id=\"rId1\"/>"
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(sheets)</sheets></workbook>
        """
    }

    /// Sixteen cell formats, in the order `Style` indexes them.
    ///
    /// `numFmtId` 164 is the first id the format reserves for custom entries;
    /// anything below 164 is a built-in and cannot be redefined. `0.00` for
    /// hours so a quarter of an hour reads 0.25 rather than 0.3, and `0` for
    /// day counts so twenty-one days is not written 21.00.
    ///
    /// The look follows the PDF: a heading in the app's blue reversed out
    /// white, a hairline under every row, and a wash on alternate rows so the
    /// eye can carry across ten columns without losing the line.
    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="2"><numFmt numFmtId="164" formatCode="0.00"/><numFmt numFmtId="165" formatCode="0"/></numFmts><fonts count="6"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font><font><b/><sz val="18"/><color rgb="FF141A2E"/><name val="Calibri"/></font><font><sz val="10"/><color rgb="FF6B7280"/><name val="Calibri"/></font><font><b/><sz val="12"/><color rgb="FF2B4A93"/><name val="Calibri"/></font></fonts><fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF2B4A93"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF4F6FA"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="3"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FF1E3568"/></bottom><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FFE2E6EF"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="16"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="165" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf><xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="5" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="0" fillId="0" borderId="2" xfId="0" applyBorder="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="2" xfId="0" applyNumberFormat="1" applyBorder="1"/><xf numFmtId="165" fontId="0" fillId="0" borderId="2" xfId="0" applyNumberFormat="1" applyBorder="1"/><xf numFmtId="0" fontId="0" fillId="3" borderId="2" xfId="0" applyFill="1" applyBorder="1"/><xf numFmtId="164" fontId="0" fillId="3" borderId="2" xfId="0" applyNumberFormat="1" applyFill="1" applyBorder="1"/><xf numFmtId="165" fontId="0" fillId="3" borderId="2" xfId="0" applyNumberFormat="1" applyFill="1" applyBorder="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
    """
}
