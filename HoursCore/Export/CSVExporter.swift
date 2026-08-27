import Foundation

/// Writes a report as CSV.
///
/// RFC 4180 quoting, CRLF line endings and an optional byte-order mark, which
/// together are what make the same file open correctly in Excel on Windows,
/// Numbers, Google Sheets and LibreOffice. The data block stays strictly
/// tabular — the totals follow after a blank line so an importer that reads the
/// first row as a header still gets clean columns.
enum CSVExporter {
    static func string(for table: ReportTable, preferences: ExportPreferences) -> String {
        let separator = preferences.fieldSeparator.character
        var lines: [String] = []

        lines.append(row(table.headerTitles(), separator: separator))
        for row in table.rows {
            lines.append(self.row(row.values, separator: separator))
        }

        if preferences.includeSummaryRows && !table.totals.isEmpty {
            lines.append("")
            lines.append(row([table.language(.summary), table.subtitle], separator: separator))
            // The name goes here rather than above the header row: the data
            // block is strictly tabular on purpose, so that an importer
            // reading line one as the column titles gets clean columns.
            if !table.ownerName.isEmpty {
                lines.append(row([table.language(.name), table.ownerName], separator: separator))
            }
            for total in table.totals {
                lines.append(row([total.label, total.value], separator: separator))
            }
        }

        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func data(for table: ReportTable, preferences: ExportPreferences) -> Data {
        var data = Data()
        if preferences.includeByteOrderMark {
            // Excel on Windows reads UTF-8 as the system code page without it,
            // which mangles every accented character.
            data.append(contentsOf: [0xEF, 0xBB, 0xBF])
        }
        data.append(Data(string(for: table, preferences: preferences).utf8))
        return data
    }

    private static func row(_ fields: [String], separator: String) -> String {
        fields.map { escape($0, separator: separator) }.joined(separator: separator)
    }

    /// Quotes a field only when it needs it, and doubles any quotes inside.
    static func escape(_ field: String, separator: String) -> String {
        let field = defused(field)
        let needsQuoting = field.contains(separator)
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
            // A leading or trailing space is silently eaten by some importers.
            || field.hasPrefix(" ")
            || field.hasSuffix(" ")
        guard needsQuoting else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Stops a note from being run as a formula by whoever opens the file.
    ///
    /// A cell beginning `=`, `+` or `@` is a formula to Excel, Sheets and
    /// LibreOffice, and formulas can reach outside the document — the
    /// `HYPERLINK` and DDE families do. Nothing in this app executes anything,
    /// but this app is not where the file ends up: the point of an export is to
    /// send it to someone else, and it is their machine that runs whatever a
    /// note happened to start with.
    ///
    /// A leading apostrophe is what a spreadsheet reads as "this is text". It
    /// is not shown in the cell.
    ///
    /// `-` is deliberately not in the set. It can begin a formula, but it far
    /// more often begins an ordinary note — "-2h owed", "- see email" — and
    /// mangling those to defend against a formula someone typed into their own
    /// timesheet is the worse trade. XLSX needs none of this: its cells are
    /// `inlineStr`, which is text by declaration.
    static func defused(_ field: String) -> String {
        guard let first = field.first, "=+@\t\r".contains(first) else { return field }
        return "'" + field
    }
}
