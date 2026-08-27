import Foundation

/// Writes a report as a real `.xlsx` workbook.
///
/// The file is an OOXML package built by hand: strings are inline, so there is
/// no shared-string table to keep in sync, and durations chosen as decimal
/// hours are written as genuine numbers so a spreadsheet can total them without
/// anyone having to re-type a column.
enum XLSXWriter {
    /// One sheet: the title, the summary, the days, and their totals.
    ///
    /// It was two sheets for a while, on the reasoning that someone opening a
    /// timesheet wants the balance rather than thirty-one rows. Then the days
    /// got a totals row of their own, which is the same figures in the place
    /// you can check them against the column they came from — so the second
    /// sheet became a page of white space carrying a copy.
    static func data(
        for table: ReportTable,
        preferences: ExportPreferences,
        sheetName: String = "Hours",
        generatedOn: Date? = nil
    ) -> Data {
        var archive = ZIPArchive()
        archive.addFile(name: "[Content_Types].xml", contents: Data(contentTypes.utf8))
        archive.addFile(name: "_rels/.rels", contents: Data(rootRelationships.utf8))
        // The sheet reports back which row its column titles landed on: the
        // summary above them is a variable number of lines, and the workbook
        // has to name that row for the print repeat.
        let worksheet = sheet(for: table, preferences: preferences, generatedOn: generatedOn)
        archive.addFile(
            name: "xl/workbook.xml",
            contents: Data(workbook(sheetName: sheetName, headerRow: worksheet.headerRow).utf8)
        )
        archive.addFile(name: "xl/_rels/workbook.xml.rels", contents: Data(workbookRelationships.utf8))
        archive.addFile(name: "xl/styles.xml", contents: Data(styles(in: table.language).utf8))
        archive.addFile(name: "xl/worksheets/sheet1.xml", contents: Data(worksheet.xml.utf8))
        return archive.finalized()
    }

    private static func subtitleLine(for table: ReportTable, generatedOn: Date?) -> String {
        guard let generatedOn else { return table.subtitle }
        let formatter = DateFormatter()
        formatter.locale = table.language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(table.subtitle)   ·   \(table.language(.generated)) \(formatter.string(from: generatedOn))"
    }

    // MARK: - Worksheet

    private static func sheet(
        for table: ReportTable,
        preferences: ExportPreferences,
        generatedOn: Date?
    ) -> (xml: String, headerRow: Int) {
        var rows: [String] = []
        var grid: [[Cell]] = []
        var merges: [String] = []
        var rowNumber = 1

        /// `sizing` is the row as the column widths should see it. A merged
        /// label passes a gap in its own place and the figure beside it, so a
        /// twenty-two character label does not set the width of the date
        /// column while the figure it belongs to still gets room.
        func emit(_ cells: [Cell], sizing: [Cell]? = nil, height: Double? = nil) {
            rows.append(row(number: rowNumber, cells: cells, height: height))
            grid.append(sizing ?? cells)
            rowNumber += 1
        }
        func blank() { rowNumber += 1 }
        func merge(_ first: Int, _ last: Int, row: Int) {
            guard last > first else { return }
            merges.append("\(columnName(first))\(row):\(columnName(last))\(row)")
        }

        let columns = max(1, table.columns.count)

        // The title block, as the PDF opens.
        merge(0, columns - 1, row: rowNumber)
        emit([Cell.text(table.title, style: .title)], sizing: [], height: 26)
        if !table.ownerName.isEmpty {
            merge(0, columns - 1, row: rowNumber)
            emit([Cell.text(table.ownerName, style: .bold)], sizing: [])
        }
        merge(0, columns - 1, row: rowNumber)
        emit([Cell.text(subtitleLine(for: table, generatedOn: generatedOn), style: .subtitle)], sizing: [])
        blank()

        // The summary sits above the table, not below it.
        //
        // Below, two things went wrong at once: the repeated column titles —
        // which a printed table needs on every sheet of paper — landed over
        // the summary as well, so a page of totals carried a header reading
        // Date, Day, Type; and the page break fell in the middle of the block.
        // The PDF avoids both by drawing the header only when there are rows
        // under it, which is a choice a spreadsheet does not get to make.
        // Above the table there is nothing to repeat over and nothing to
        // split.
        if preferences.includeSummaryRows && !table.totals.isEmpty {
            merge(0, columns - 1, row: rowNumber)
            emit([Cell.text(table.language(.summary), style: .section)], sizing: [], height: 20)

            // Durations down the left, day counts down the right, as the PDF
            // pairs them — but only where there are columns enough to hold two
            // pairs without them running together.
            //
            // Written out rather than as a ternary over two maps, which the
            // type checker gave up on: an optional tuple inside a conditional
            // inside a map is more inference than one expression is worth.
            let paired = columns >= 9
            let left = table.totals.filter { $0.minutes != nil }
            let right = table.totals.filter { $0.minutes == nil }

            var entries: [(first: ReportTotal?, second: ReportTotal?)] = []
            if paired {
                for index in 0..<max(left.count, right.count) {
                    let first: ReportTotal? = index < left.count ? left[index] : nil
                    let second: ReportTotal? = index < right.count ? right[index] : nil
                    entries.append((first, second))
                }
            } else {
                for total in table.totals {
                    entries.append((total, nil))
                }
            }

            // Labels are merged rather than left to overflow, because the cell
            // beside them holds the figure and a blocked overflow clips.
            //
            // Unpaired, the figure goes in the last column and the label takes
            // everything before it — so a report of two columns still has
            // somewhere to put the balance. It used to stop three columns from
            // the right, which on a narrow report was past the end of the row
            // and the figures were dropped in silence.
            let labelEnd = paired ? 2 : columns - 2
            let valueColumn = labelEnd + 1
            let secondLabelEnd = 7

            for (first, second) in entries {
                var cells = Array(repeating: Cell.gap, count: columns)
                var sizing = cells
                if let first {
                    merge(0, labelEnd, row: rowNumber)
                    cells[0] = .text(first.label, style: .summaryLabel)
                    if valueColumn > 0 && valueColumn < columns {
                        cells[valueColumn] = figure(for: first)
                        sizing[valueColumn] = cells[valueColumn]
                    }
                }
                if paired, let second, secondLabelEnd + 1 < columns {
                    merge(5, secondLabelEnd, row: rowNumber)
                    cells[5] = .text(second.label, style: .summaryLabel)
                    cells[secondLabelEnd + 1] = figure(for: second)
                    sizing[secondLabelEnd + 1] = cells[secondLabelEnd + 1]
                }
                emit(cells, sizing: sizing)
            }
            blank()
        }

        let headerRow = rowNumber
        emit(table.headerTitles().map { Cell.text($0, style: .header) }, height: 22)

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

        // A ruled total under each column of figures, as a timesheet on paper
        // has always had. Written as SUM over the days rather than as the
        // number they happen to add up to, so correcting a Tuesday corrects
        // the total too.
        if lastDataRow > headerRow {
            let durationColumns = Set(table.rows.flatMap { reportRow in
                reportRow.minutes.enumerated().compactMap { $0.element == nil ? nil : $0.offset }
            })
            var totals: [Cell] = []
            for index in 0..<columns {
                if index == 0 {
                    totals.append(.text(table.language(.total), style: .totalLabel))
                } else if durationColumns.contains(index) {
                    let letter = columnName(index)
                    let summed = table.rows.reduce(0) { running, reportRow in
                        running + (index < reportRow.minutes.count ? (reportRow.minutes[index] ?? 0) : 0)
                    }
                    totals.append(.formula(
                        "SUM(\(letter)\(headerRow + 1):\(letter)\(lastDataRow))",
                        cached: dayFraction(minutes: summed),
                        style: .totalDuration
                    ))
                } else {
                    totals.append(.text("", style: .totalLabel))
                }
            }
            emit(totals, height: 20)
        }


        let lastColumn = columnName(columns - 1)
        let mergeBlock = merges.isEmpty
            ? ""
            : "<mergeCells count=\"\(merges.count)\">"
                + merges.map { "<mergeCell ref=\"\($0)\"/>" }.joined()
                + "</mergeCells>"

        // The order of these elements is fixed by the file format — extent,
        // views, formatting defaults, columns, the data, the filter, the
        // merges, then the page — and out of order the workbook is refused
        // rather than degraded.
        //
        // `dimension` and `sheetFormatPr` are both optional by the letter of
        // the spec and both were left out, which cost an afternoon: Excel and
        // openpyxl honoured the column widths without them and the previewer
        // on a phone quietly discarded the whole <cols> block, so the file was
        // correct everywhere except the place someone actually opens it.
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>\
        <dimension ref="A1:\(lastColumn)\(rowNumber - 1)"/>\
        <sheetViews><sheetView workbookViewId="0"><pane ySplit="\(headerRow)" topLeftCell="A\(headerRow + 1)" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>\
        <sheetFormatPr defaultRowHeight="15" baseColWidth="10"/>\
        \(columnWidths(for: grid))\
        <sheetData>\(rows.joined())</sheetData>\
        \(autoFilter(headerRow: headerRow, lastDataRow: lastDataRow, columns: columns))\
        \(mergeBlock)\
        \(printSetup)\
        \(footer(title: table.title, language: table.language))\
        </worksheet>
        """
        return (xml, headerRow)
    }

    private static func figure(for total: ReportTotal) -> Cell {
        if let minutes = total.minutes {
            return .number(dayFraction(minutes: minutes), style: .summaryValue)
        }
        if let count = total.count {
            return .number(Double(count), style: .summaryCount)
        }
        return .text(total.value, style: .bold)
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

    /// "Hours — August 2026   ·   page 3", centred and small, as the PDF
    /// prints it.
    ///
    /// The codes are the format's own: `&C` centres, `&8` sets eight point,
    /// `&K` takes a colour, `&P` is the page number. They travel as literal
    /// ampersands in the XML, so they are written escaped and the title —
    /// which is the user's — is escaped separately.
    private static func footer(title: String, language: ExportLanguage) -> String {
        "<headerFooter><oddFooter>&amp;C&amp;8&amp;K8E8E96\(escape(title))   ·   \(escape(language(.page))) &amp;P</oddFooter></headerFooter>"
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
        case totalLabel = 14
        case totalDuration = 15

        static func text(rest: Bool) -> Style { rest ? .restText : .normal }
        static func duration(rest: Bool) -> Style { rest ? .restDuration : .duration }
    }

    /// Sorting and filtering the days, without touching the totals below them.
    private static func autoFilter(headerRow: Int, lastDataRow: Int, columns: Int) -> String {
        guard lastDataRow > headerRow, columns > 0 else { return "" }
        return "<autoFilter ref=\"A\(headerRow):\(columnName(columns - 1))\(lastDataRow)\"/>"
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
        /// A real formula, with the answer cached beside it.
        ///
        /// The cache is what a reader that does not calculate shows — a phone
        /// previewer, mostly — and the formula is what makes the total follow
        /// the column when somebody corrects a Tuesday. A literal would have
        /// been simpler and would have started lying the moment the sheet was
        /// edited, which is the whole reason it is a spreadsheet.
        case formula(String, cached: Double, style: Style)
        /// Holds a position in the row without writing a cell, so a merged
        /// span or an overflow is not blocked by an empty one.
        case gap

        /// The characters this cell will try to show, for sizing the column.
        var width: Int {
            switch self {
            case let .text(value, _): return value.count
            case let .formula(_, cached, style): return Cell.number(cached, style: style).width
            case .gap: return 0
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
            case .gap:
                continue
            case let .text(value, style):
                xml += "<c r=\"\(reference)\" t=\"inlineStr\" s=\"\(style.rawValue)\"><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
            case let .number(value, style):
                xml += "<c r=\"\(reference)\" s=\"\(style.rawValue)\"><v>\(format(value))</v></c>"
            case let .formula(expression, cached, style):
                xml += "<c r=\"\(reference)\" s=\"\(style.rawValue)\"><f>\(escape(expression))</f><v>\(format(cached))</v></c>"
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

    private static func workbook(sheetName: String, headerRow: Int) -> String {
        let name = escape(String(sheetName.prefix(31)))
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><workbookPr date1904="1"/><sheets><sheet name="\(name)" sheetId="1" r:id="rId1"/></sheets><definedNames><definedName name="_xlnm.Print_Titles" localSheetId="0">\'\(name)\'!$\(headerRow):$\(headerRow)</definedName></definedNames></workbook>
        """
    }

    /// Sixteen cell formats, in the order `Style` indexes them.
    ///
    /// Durations are stored as a fraction of a day and shown through a mask,
    /// which is the only way a cell can read "9h 45m" and still be added up:
    /// the value is a number and the hours-and-minutes is a mask over it.
    /// Decimal hours summed just as well and looked like a database export.
    ///
    /// `[h]` — square brackets — counts hours past twenty-four instead of
    /// wrapping, so a hundred and sixty-five hours is not shown as twenty-one.
    ///
    /// The mask has three arms, and the order matters because the first one
    /// that matches wins:
    ///
    /// - `[<0]` — negative, which only a balance is. It keeps the hours, and
    ///   needs the 1904 date base to render at all rather than as hashes.
    /// - `[<0.0416666]` — under an hour, so a half-hour break reads "30m".
    ///   `[m]` in brackets is elapsed minutes; a bare `m` is the *month*, and
    ///   writing it that way rendered every break in the file as "1m".
    ///   rather than "0h 30m" down twenty-one rows of a month. Zero lands here
    ///   too and reads "0m", which is the price of the arm above: four cases
    ///   and a format has room for three.
    /// - everything else — "8h 00m". The minutes cannot be dropped on a whole
    ///   hour, because that is a fourth case.
    ///
    /// The look follows the PDF rather than inventing a second one: a header
    /// in light grey with dark grey type, a hairline under every row, and days
    /// the schedule expects nothing of greyed out entirely — which carries
    /// more than banding every other row did, because it means something.
    private static func styles(in language: ExportLanguage) -> String {
        // The mask spells the units out, so a German workbook reads 8 Std 30
        // Min in the cell as well as in the text the PDF prints. The spacer
        // rides inside the quoted literal because the format has its own
        // space between the two halves, and doubling it would show.
        let hour = escape(language.unitSpacer + language.hourUnit)
        let minute = escape(language.unitSpacer + language.minuteUnit)
        let duration = "[&lt;0][h]&quot;\(hour)&quot; mm&quot;\(minute)&quot;;"
            + "[&lt;0.0416666][m]&quot;\(minute)&quot;;"
            + "[h]&quot;\(hour)&quot; mm&quot;\(minute)&quot;"
        return """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="2"><numFmt numFmtId="164" formatCode="\(duration)"/><numFmt numFmtId="165" formatCode="0"/></numFmts><fonts count="8"><font><sz val="11"/><color rgb="FF1A1A1C"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FF1A1A1C"/><name val="Calibri"/></font><font><sz val="11"/><color rgb="FF5A5A64"/><name val="Calibri"/></font><font><b/><sz val="18"/><color rgb="FF1A1A1C"/><name val="Calibri"/></font><font><sz val="10"/><color rgb="FF8E8E96"/><name val="Calibri"/></font><font><sz val="11"/><color rgb="FF9A9AA2"/><name val="Calibri"/></font><font><sz val="11"/><color rgb="FF7A7A84"/><name val="Calibri"/></font><font><b/><sz val="13"/><color rgb="FF1A1A1C"/><name val="Calibri"/></font></fonts><fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFF2F2F5"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFAFAFB"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="4"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FFD8D8DE"/></bottom><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FFEDEDF1"/></bottom><diagonal/></border><border><left/><right/><top style="thin"><color rgb="FF9A9AA2"/></top><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="16"><xf numFmtId="0" fontId="0" fillId="0" borderId="2" xfId="0" applyBorder="1" applyAlignment="1"><alignment indent="1"/></xf><xf numFmtId="164" fontId="0" fillId="0" borderId="2" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" indent="1"/></xf><xf numFmtId="165" fontId="0" fillId="0" borderId="2" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" indent="1"/></xf><xf numFmtId="0" fontId="5" fillId="3" borderId="2" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment indent="1"/></xf><xf numFmtId="164" fontId="5" fillId="3" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" indent="1"/></xf><xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" indent="1"/></xf><xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="7" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="6" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="right" indent="1"/></xf><xf numFmtId="165" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyAlignment="1"><alignment horizontal="right" indent="1"/></xf><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="3" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" indent="1"/></xf><xf numFmtId="164" fontId="1" fillId="0" borderId="3" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right" vertical="center" indent="1"/></xf></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
    """
    }
}
