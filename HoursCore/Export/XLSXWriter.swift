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
    static func data(
        for table: ReportTable,
        preferences: ExportPreferences,
        sheetName: String = "Hours",
        generatedOn: Date? = nil
    ) -> Data {
        let showsSummary = preferences.includeSummaryRows && !table.totals.isEmpty
        var archive = ZIPArchive()
        archive.addFile(name: "[Content_Types].xml", contents: Data(contentTypes(includesSummary: showsSummary).utf8))
        archive.addFile(name: "_rels/.rels", contents: Data(rootRelationships.utf8))
        archive.addFile(name: "xl/workbook.xml", contents: Data(workbook(sheetName: sheetName, includesSummary: showsSummary).utf8))
        archive.addFile(name: "xl/_rels/workbook.xml.rels", contents: Data(workbookRelationships(includesSummary: showsSummary).utf8))
        archive.addFile(name: "xl/styles.xml", contents: Data(styles.utf8))

        if showsSummary {
            archive.addFile(name: "xl/worksheets/sheet1.xml", contents: Data(summarySheet(for: table, generatedOn: generatedOn).utf8))
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
    private static func summarySheet(for table: ReportTable, generatedOn: Date?) -> String {
        var rows: [String] = []
        var grid: [[Cell]] = []
        var rowNumber = 1

        func emit(_ cells: [Cell], height: Double? = nil) {
            rows.append(row(number: rowNumber, cells: cells, height: height))
            grid.append(cells)
            rowNumber += 1
        }

        emit([Cell.text(table.title, style: .title)], height: 26)
        emit([Cell.text(subtitleLine(for: table, generatedOn: generatedOn), style: .subtitle)])
        rowNumber += 1
        emit([Cell.text("Summary", style: .section)], height: 20)

        // Two columns, as the PDF sets them: the amounts of time on the left
        // and the counts of days on the right, rather than one list of nine
        // that runs down the page and says nothing about which is which.
        let durations = table.totals.filter { $0.minutes != nil }
        let counts = table.totals.filter { $0.minutes == nil }

        func figure(_ total: ReportTotal) -> Cell {
            if let minutes = total.minutes {
                return .number(dayFraction(minutes: minutes), style: .summaryValue)
            }
            if let count = total.count {
                return .number(Double(count), style: .summaryCount)
            }
            return .text(total.value, style: .bold)
        }

        for index in 0..<max(durations.count, counts.count) {
            var cells: [Cell] = []
            if index < durations.count {
                cells.append(Cell.text(durations[index].label, style: .summaryLabel))
                cells.append(figure(durations[index]))
            } else {
                cells.append(Cell.text("", style: .plain))
                cells.append(Cell.text("", style: .plain))
            }
            cells.append(Cell.text("", style: .plain))
            if index < counts.count {
                cells.append(Cell.text(counts[index].label, style: .summaryLabel))
                cells.append(figure(counts[index]))
            }
            emit(cells)
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>\
        <dimension ref="A1:E\(max(1, rowNumber - 1))"/>\
        <sheetViews><sheetView tabSelected="1" workbookViewId="0"/></sheetViews>\
        <sheetFormatPr defaultRowHeight="15" baseColWidth="10"/>\
        \(columnWidths(for: grid))\
        <sheetData>\(rows.joined())</sheetData>\
        \(summaryPrintSetup)\
        \(footer(title: table.title))\
        </worksheet>
        """
    }

    /// "2026-08-01 – 2026-08-31   ·   generated Aug 26, 2026 at 11:43" — the
    /// PDF's second line. The timestamp is optional so a test can produce a
    /// file that is the same every time it runs.
    private static func subtitleLine(for table: ReportTable, generatedOn: Date?) -> String {
        guard let generatedOn else { return table.subtitle }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(table.subtitle)   ·   generated \(formatter.string(from: generatedOn))"
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
        for reportRow in table.rows {
            // The PDF greys a day the schedule expects nothing of, and that
            // carries more than a wash on every other row did: a weekend and a
            // Wednesday stop looking alike, which is the mistake the banding
            // was there to prevent in the first place.
            let rest = !reportRow.isWorkingDay
            let cells = reportRow.values.enumerated().map { index, value -> Cell in
                if index < reportRow.minutes.count, let minutes = reportRow.minutes[index] {
                    return Cell.number(dayFraction(minutes: minutes), style: .duration(rest: rest))
                }
                return Cell.text(value, style: .text(rest: rest))
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
        <sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>\
        <dimension ref="A1:\(lastColumn)\(rowNumber - 1)"/>\
        \(frozenHeader)\
        <sheetFormatPr defaultRowHeight="15" baseColWidth="10"/>\
        \(columnWidths(for: grid))\
        <sheetData>\(rows.joined())</sheetData>\
        \(autoFilter(lastDataRow: lastDataRow, columns: table.columns.count))\
        \(printSetup)\
        \(footer(title: table.title))\
        </worksheet>
        """
    }

    /// What a printed timesheet needs, which is most of what the PDF does for
    /// free: landscape, squeezed to one page wide, and the column titles
    /// repeated at the top of every sheet of paper.
    ///
    /// `fitToWidth` alone does nothing. It is inert until `pageSetUpPr` says
    /// the sheet is fitted to the page at all, which is declared up in
    /// `sheetPr` — and without it the Notes column printed on a third sheet of
    /// paper, on its own, with a header and thirty-one dashes.
    ///
    /// The repeat is a workbook-level defined name rather than a worksheet
    /// setting, which is why it lives in `workbook` and not here.
    private static let printSetup = """
    <printOptions horizontalCentered="0"/><pageMargins left="0.4" right="0.4" top="0.6" bottom="0.6" header="0.3" footer="0.4"/><pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>
    """

    /// Landscape, like the days and like the PDF. Portrait could not hold the
    /// two columns of totals and pushed the right-hand one onto a second sheet
    /// of paper, which is the same failure the Notes column had.
    private static let summaryPrintSetup = """
    <pageMargins left="0.5" right="0.5" top="0.7" bottom="0.7" header="0.3" footer="0.4"/><pageSetup paperSize="9" orientation="landscape" fitToWidth="1" fitToHeight="0"/>
    """

    /// "Hours — August 2026   ·   page 3", centred and small, as the PDF
    /// prints it.
    ///
    /// The codes are the format's own: `&C` centres, `&8` sets eight point,
    /// `&K` takes a colour, `&P` is the page number. They travel as literal
    /// ampersands in the XML, so they are written escaped and the title —
    /// which is the user's — is escaped separately.
    private static func footer(title: String) -> String {
        "<headerFooter><oddFooter>&amp;C&amp;8&amp;K8E8E96\(escape(title))   ·   page &amp;P</oddFooter></headerFooter>"
    }

    /// Indexes into `cellXfs` in `styles`, in the order they are declared
    /// there. A wrong index here is not an error the file reports — the cell
    /// simply renders with somebody else's formatting.
    private enum Style: Int {
        case normal = 0
        case duration = 1
        case count = 2
        /// A day the schedule expects nothing of, greyed the way the PDF greys
        /// it: the row is there to be counted, not to be read.
        case restText = 3
        case restDuration = 4
        case header = 5
        case title = 6
        case subtitle = 7
        case section = 8
        case summaryLabel = 9
        case summaryValue = 10
        case summaryCount = 11
        case bold = 12
        case plain = 13

        static func text(rest: Bool) -> Style { rest ? .restText : .normal }
        static func duration(rest: Bool) -> Style { rest ? .restDuration : .duration }
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
                switch style {
                case .count, .summaryCount:
                    return String(Int(value.magnitude)).count
                default:
                    // Shown through the [h]"h" mm"m" mask, so the width is the
                    // hours it resolves to plus "h 00m" — not the digits of the
                    // fraction of a day actually in the cell.
                    let hours = Int((value.magnitude * 24).rounded(.down))
                    return String(hours).count + 5 + (value < 0 ? 1 : 0)
                }
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

    /// A duration as the workbook stores it: a fraction of a day, which is
    /// what the `[h]"h" mm"m"` mask expects. Four decimal places is a third of
    /// a second, so nothing a timesheet records is lost.
    static func dayFraction(minutes: Int) -> Double {
        Double(minutes) / 1440.0
    }

    /// Always a point as the decimal mark: the file format demands it,
    /// regardless of what the user chose for CSV.
    private static func format(_ value: Double) -> String {
        String(format: "%.6f", value)
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
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><workbookPr date1904="1"/><sheets>\(sheets)</sheets><definedNames><definedName name="_xlnm.Print_Titles" localSheetId="\(includesSummary ? 1 : 0)">\'\(name)\'!$1:$1</definedName></definedNames></workbook>
        """
    }

    /// Fourteen cell formats, in the order `Style` indexes them.
    ///
    /// Durations are stored as a fraction of a day and shown by `[h]"h" mm"m"`,
    /// which is the only way a cell can read "9h 45m" and still be added up:
    /// the value is a number, the hours-and-minutes is a mask over it. Decimal
    /// hours summed just as well and looked like a database export, which is
    /// what the PDF beside it does not look like.
    ///
    /// `[h]` — square brackets — counts hours past twenty-four instead of
    /// wrapping, so a hundred and sixty-five hours is not shown as twenty-one.
    ///
    /// The look follows the PDF rather than inventing a second one: a header
    /// in light grey with dark grey type, a hairline under every row, and days
    /// the schedule expects nothing of greyed out entirely — which carries
    /// more than banding every other row did, because it means something.
    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="2"><numFmt numFmtId="164" formatCode="[h]&quot;h&quot; mm&quot;m&quot;;-[h]&quot;h&quot; mm&quot;m&quot;;&quot;0h&quot;"/><numFmt numFmtId="165" formatCode="0"/></numFmts><fonts count="8"><font><sz val="11"/><color rgb="FF1A1A1C"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FF1A1A1C"/><name val="Calibri"/></font><font><sz val="11"/><color rgb="FF5A5A64"/><name val="Calibri"/></font><font><b/><sz val="18"/><color rgb="FF1A1A1C"/><name val="Calibri"/></font><font><sz val="10"/><color rgb="FF8E8E96"/><name val="Calibri"/></font><font><sz val="11"/><color rgb="FF9A9AA2"/><name val="Calibri"/></font><font><sz val="11"/><color rgb="FF7A7A84"/><name val="Calibri"/></font><font><b/><sz val="13"/><color rgb="FF1A1A1C"/><name val="Calibri"/></font></fonts><fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF2F2F5"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFAFAFB"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="3"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FFD8D8DE"/></bottom><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FFEDEDF1"/></bottom><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="14"><xf numFmtId="0" fontId="0" fillId="0" borderId="2" xfId="0" applyBorder="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="2" xfId="0" applyNumberFormat="1" applyBorder="1"/><xf numFmtId="165" fontId="0" fillId="0" borderId="2" xfId="0" applyNumberFormat="1" applyBorder="1"/><xf numFmtId="0" fontId="5" fillId="3" borderId="2" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/><xf numFmtId="164" fontId="5" fillId="3" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" indent="1"/></xf><xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf><xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="7" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="6" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="right" indent="1"/></xf><xf numFmtId="165" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="right" indent="1"/></xf><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
    """
}
