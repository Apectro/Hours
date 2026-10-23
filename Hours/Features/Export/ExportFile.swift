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

    /// What each format is for, under its name on the format cards.
    var purpose: String {
        switch self {
        case .csv: return String(localized: "Plain data", comment: "Export format card: what a CSV file is for")
        case .xlsx: return String(localized: "For payroll", comment: "Export format card: what an Excel file is for")
        case .pdf: return String(localized: "To print or send", comment: "Export format card: what a PDF is for")
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
        let data: Data
        switch format {
        case .csv:
            data = CSVExporter.data(for: table, preferences: preferences)
        case .xlsx:
            data = XLSXWriter.data(for: table, preferences: preferences, generatedOn: Date())
        case .pdf:
            data = PDFReportRenderer.data(for: table)
        }
        return try write(data: data, format: format, baseName: baseName)
    }

    /// Writes bytes already produced — the PDF the preview was drawn from,
    /// so the page on screen and the page shared are one rendering, not two.
    static func write(data: Data, format: ExportFormat, baseName: String) throws -> URL {
        try write(data: data, fileExtension: format.fileExtension, baseName: baseName)
    }

    /// The same, for a file that is not one of the export formats — the
    /// extra-work report as a picture, `png` or `jpg`.
    static func write(data: Data, fileExtension: String, baseName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory
            .appendingPathComponent(sanitise(baseName))
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Gives an already-written export a new name.
    ///
    /// Renaming beats rewriting: the bytes do not change when the file is
    /// called something else, and re-rendering a year of PDF on every
    /// keystroke would be a lot of work to arrive back at the same document.
    static func rename(_ url: URL, to baseName: String) throws -> URL {
        let destination = url
            .deletingLastPathComponent()
            .appendingPathComponent(sanitise(baseName))
            .appendingPathExtension(url.pathExtension)
        guard destination != url else { return url }

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
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
