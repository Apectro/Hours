import Foundation

/// Writes a report as a real `.xlsx` workbook.
///
/// The file is an OOXML package built by hand: strings are inline, so there is
/// no shared-string table to keep in sync, and durations chosen as decimal
/// hours are written as genuine numbers so a spreadsheet can total them without
/// anyone having to re-type a column.
enum XLSXWriter {
    static func data(for table: ReportTable, preferences: ExportPreferences, sheetName: String = "Hours") -> Data {
        var archive = ZIPArchive()
        archive.addFile(name: "[Content_Types].xml", contents: Data(contentTypes.utf8))
        archive.addFile(name: "_rels/.rels", contents: Data(rootRelationships.utf8))
        archive.addFile(name: "xl/workbook.xml", contents: Data(workbook(sheetName: sheetName).utf8))
        archive.addFile(name: "xl/_rels/workbook.xml.rels", contents: Data(workbookRelationships.utf8))
        archive.addFile(name: "xl/styles.xml", contents: Data(styles.utf8))
        archive.addFile(name: "xl/worksheets/sheet1.xml", contents: Data(sheet(for: table, preferences: preferences).utf8))
        return archive.finalized()
    }

    // MARK: - Worksheet

    private static func sheet(for table: ReportTable, preferences: ExportPreferences) -> String {
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
        for reportRow in table.rows {
            let cells = reportRow.values.enumerated().map { index, value -> Cell in
                if index < reportRow.minutes.count, let minutes = reportRow.minutes[index] {
                    return Cell.number(DurationFormatting.decimalHours(minutes), style: .hours)
                }
                return Cell.text(value, style: .normal)
            }
            emit(cells)
        }
        let lastDataRow = rowNumber - 1

        if preferences.includeSummaryRows && !table.totals.isEmpty {
            // One blank row between the days and their totals.
            rowNumber += 1
            emit([Cell.text("Summary", style: .boldText), Cell.text(table.subtitle, style: .normal)], sizing: 1)
            for total in table.totals {
                let figure: Cell
                if let minutes = total.minutes {
                    figure = .number(DurationFormatting.decimalHours(minutes), style: total.isEmphasised ? .boldHours : .hours)
                } else if let count = total.count {
                    figure = .number(Double(count), style: total.isEmphasised ? .boldCount : .count)
                } else {
                    figure = .text(total.value, style: total.isEmphasised ? .boldText : .normal)
                }
                emit([
                    Cell.text(total.label, style: total.isEmphasised ? .boldText : .normal),
                    figure
                ], sizing: 2)
            }
        }

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

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
    """

    private static let rootRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
    """

    private static let workbookRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
    """

    private static func workbook(sheetName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="\(escape(String(sheetName.prefix(31))))" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
    }

    /// Seven cell formats, in the order `Style` indexes them.
    ///
    /// `numFmtId` 164 is the first id the format reserves for custom entries;
    /// anything below 164 is a built-in and cannot be redefined. `0.00` for
    /// hours so a quarter of an hour reads 0.25 rather than 0.3, and `0` for
    /// day counts so twenty-one days is not written 21.00.
    ///
    /// The header is white on the same blue the app uses, with a rule beneath
    /// it. Bold alone was doing the work of telling a reader where the data
    /// starts, which on a printed page it does not do.
    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="2"><numFmt numFmtId="164" formatCode="0.00"/><numFmt numFmtId="165" formatCode="0"/></numFmts><fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF2B4A93"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FF1E3568"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="7"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="165" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/><xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
    """
}
