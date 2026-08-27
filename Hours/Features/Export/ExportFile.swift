import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Hashable {
    case csv
    case xlsx
    case pdf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .csv: return "CSV"
        case .xlsx: return "Excel"
        case .pdf: return "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .xlsx: return "xlsx"
        case .pdf: return "pdf"
        }
    }

    var systemImage: String {
        switch self {
        case .csv: return "tablecells"
        case .xlsx: return "tablecells.badge.ellipsis"
        case .pdf: return "doc.richtext"
        }
    }

    var explanation: String {
        switch self {
        case .csv: return "Opens in Excel, Numbers, Google Sheets and LibreOffice."
        case .xlsx: return "A workbook with a bold header row. Decimal durations are written as real numbers."
        case .pdf: return "A ruled table with a summary, ready to print or send on."
        }
    }
}

/// Writes a report to a file in the app's temporary directory, ready for the
/// share sheet. Nothing is uploaded anywhere; the file exists only until the
/// system reclaims it.
enum ExportFileFactory {
    static func write(
        table: ReportTable,
        format: ExportFormat,
        preferences: ExportPreferences,
        baseName: String
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory
            .appendingPathComponent(sanitise(baseName))
            .appendingPathExtension(format.fileExtension)

        let data: Data
        switch format {
        case .csv:
            data = CSVExporter.data(for: table, preferences: preferences)
        case .xlsx:
            data = XLSXWriter.data(for: table, preferences: preferences, generatedOn: Date())
        case .pdf:
            data = PDFReportRenderer.data(for: table)
        }

        try data.write(to: url, options: .atomic)
        return url
    }

    /// Removes files left behind by earlier exports in this session.
    static func clearPreviousExports() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in contents { try? FileManager.default.removeItem(at: url) }
    }

    static func sanitise(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_."))
        let cleaned = String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Hours" : trimmed
    }
}
