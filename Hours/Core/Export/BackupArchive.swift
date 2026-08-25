import Foundation

/// A complete, human-readable copy of everything the app holds.
///
/// Because nothing is synced, this file is the only copy that survives losing
/// the device — so it is plain JSON rather than an opaque blob: readable,
/// diffable, and recoverable by hand if it ever comes to that.
struct BackupArchive: Codable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var exportedAt: Date
    var settings: AppSettings
    var days: [DayRecord]
    var holidays: [HolidayRule]

    init(
        formatVersion: Int = BackupArchive.currentFormatVersion,
        exportedAt: Date = Date(),
        settings: AppSettings,
        days: [DayRecord],
        holidays: [HolidayRule]
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.days = days.sorted { $0.date < $1.date }
        self.holidays = holidays
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decoded(from data: Data) throws -> BackupArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupArchive.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, settings, days, holidays
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            formatVersion: container.lenient(.formatVersion, BackupArchive.currentFormatVersion),
            exportedAt: container.lenient(.exportedAt, Date()),
            settings: container.lenient(.settings, AppSettings()),
            days: container.lenient(.days, []),
            holidays: container.lenient(.holidays, [])
        )
    }
}
