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
        var rowNumber = 1

        rows.append(row(number: rowNumber, cells: table.headerTitles().map { Cell.text($0, bold: true) }))
        rowNumber += 1

        // Numbers are only emitted for the decimal style; the other styles are
        // text by nature ("8h 30m") and would import as a broken number.
        let numeric = preferences.durationStyle == .decimal

        for reportRow in table.rows {
            let cells = reportRow.values.enumerated().map { index, value -> Cell in
                if numeric, index < reportRow.numbers.count, let number = reportRow.numbers[index] {
                    return Cell.number(number)
                }
                return Cell.text(value, bold: false)
            }
            rows.append(row(number: rowNumber, cells: cells))
            rowNumber += 1
        }

        if preferences.includeSummaryRows && !table.totals.isEmpty {
            rowNumber += 1
            rows.append(row(number: rowNumber, cells: [Cell.text("Summary", bold: true), Cell.text(table.subtitle, bold: false)]))
            rowNumber += 1
            for total in table.totals {
                rows.append(row(number: rowNumber, cells: [
                    Cell.text(total.label, bold: total.isEmphasised),
                    Cell.text(total.value, bold: total.isEmphasised)
                ]))
                rowNumber += 1
            }
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>\(rows.joined())</sheetData></worksheet>
        """
    }

    private enum Cell {
        case text(String, bold: Bool)
        case number(Double)
    }

    private static func row(number: Int, cells: [Cell]) -> String {
        var xml = "<row r=\"\(number)\">"
        for (index, cell) in cells.enumerated() {
            let reference = "\(columnName(index))\(number)"
            switch cell {
            case let .text(value, bold):
                let style = bold ? " s=\"1\"" : ""
                xml += "<c r=\"\(reference)\" t=\"inlineStr\"\(style)><is><t xml:space=\"preserve\">\(escape(value))</t></is></c>"
            case let .number(value):
                xml += "<c r=\"\(reference)\"><v>\(format(value))</v></c>"
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

    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
    """
}
