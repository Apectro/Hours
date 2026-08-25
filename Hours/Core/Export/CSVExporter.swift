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
            lines.append(row(["Summary", table.subtitle], separator: separator))
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
}
