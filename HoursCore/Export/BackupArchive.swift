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

    /// Why a file was refused as a backup.
    ///
    /// These exist because restoring is destructive: it erases everything on
    /// the device before writing what it read. Decoding used to be lenient
    /// about every field, `try?` included, so *any* JSON object decoded
    /// successfully — as an archive holding no days, no holidays and default
    /// settings. Restoring from a file that was not a backup, or from a backup
    /// truncated by a bad copy, therefore deleted everything and put nothing
    /// back. The importer's catch block could not fire, because nothing ever
    /// threw.
    enum BackupError: LocalizedError, Equatable {
        case notABackup
        case fromANewerVersion(Int)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notABackup:
                return "This file is not a Hours backup."
            case let .fromANewerVersion(version):
                return "This backup was made by a newer version of Hours (format \(version)). Update Hours and try again."
            case let .unreadable(part):
                return "This backup is damaged: its \(part) could not be read."
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Identity before content. A backup always carries a format version, so
        // a file without one is something else — and something else must never
        // reach a restore, which erases before it writes.
        guard let version = try? container.decode(Int.self, forKey: .formatVersion) else {
            throw BackupError.notABackup
        }
        // Reading a newer file with older rules would drop whatever it holds
        // that this version does not understand, and the loss becomes
        // permanent the moment the restore finishes.
        guard version <= BackupArchive.currentFormatVersion else {
            throw BackupError.fromANewerVersion(version)
        }

        // The records are strict. A malformed list is damage, and reading
        // damage as "no days" is how a restore empties a device.
        let days: [DayRecord]
        do {
            days = try container.decodeIfPresent([DayRecord].self, forKey: .days) ?? []
        } catch {
            throw BackupError.unreadable("list of days")
        }

        let holidays: [HolidayRule]
        do {
            holidays = try container.decodeIfPresent([HolidayRule].self, forKey: .holidays) ?? []
        } catch {
            throw BackupError.unreadable("list of holidays")
        }

        self.init(
            formatVersion: version,
            exportedAt: container.lenient(.exportedAt, Date()),
            // Settings stay lenient, field by field, on purpose: a preference
            // this version does not recognise should cost that preference and
            // nothing else. Losing a theme is not losing a year of work.
            settings: container.lenient(.settings, AppSettings()),
            days: days,
            holidays: holidays
        )
    }
}
