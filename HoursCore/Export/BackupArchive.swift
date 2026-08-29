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

    /// Days that were in the file and could not be read.
    ///
    /// Damage is rarely total. One day mangled by a bad edit, a truncated
    /// copy-paste, a sync that half-wrote a record — the other nine hundred are
    /// perfectly good, and refusing the whole file would throw them away to
    /// punish one. So the good days restore and the bad ones are counted and
    /// named, which is the only version of this where the person can go and
    /// re-enter what was lost.
    ///
    /// Not encoded: it describes one attempt at reading a file, not anything
    /// the file contains. Absent from `CodingKeys` for exactly that reason.
    var damagedDays: [DamagedDay]

    var hasDamage: Bool { !damagedDays.isEmpty }

    init(
        formatVersion: Int = BackupArchive.currentFormatVersion,
        exportedAt: Date = Date(),
        settings: AppSettings,
        days: [DayRecord],
        holidays: [HolidayRule],
        damagedDays: [DamagedDay] = []
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.days = days.sorted { $0.date < $1.date }
        self.holidays = holidays
        self.damagedDays = damagedDays
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

    /// Written out rather than synthesised, so that `damagedDays` being absent
    /// from the file is a decision on the page instead of a consequence of how
    /// Swift happens to treat a property missing from `CodingKeys`.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(settings, forKey: .settings)
        try container.encode(days, forKey: .days)
        try container.encode(holidays, forKey: .holidays)
    }

    /// A day that was in the file and could not be read.
    ///
    /// Carries the date rather than a sentence, because dates shown to people
    /// are formatted for their locale and this type has no business deciding
    /// that. Sometimes even the date is gone, which is worth saying out loud
    /// rather than dropping the day from the count.
    enum DamagedDay: Hashable, Sendable {
        case dated(CalendarDate)
        case unidentified
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

        /// Read by whoever tried to restore, which is a person having a bad
        /// day already — so it follows the phone like the rest of the app.
        ///
        /// `String(format:)` rather than interpolation, because the word table
        /// has to hold a whole sentence per language and the value belongs in
        /// a different place in some of them: French puts it at the end,
        /// German at the front.
        var errorDescription: String? {
            let language = ExportLanguage.device
            switch self {
            case .notABackup:
                return language(.backupNotABackup)
            case let .fromANewerVersion(version):
                return String(format: language(.backupFromNewerVersion), version)
            case let .unreadable(part):
                return String(format: language(.backupUnreadable), part)
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

        // The list itself is strict — a `days` key that is not an array of
        // objects is damage, and reading damage as "no days" is how a restore
        // empties a device. Within the list, each day is decoded on its own so
        // that one bad record does not cost the person the other nine hundred.
        let days: [DayRecord]
        var damaged: [DamagedDay] = []
        do {
            let attempts = try container.decodeIfPresent([DayOrDamage].self, forKey: .days) ?? []
            days = attempts.compactMap(\.record)
            damaged = attempts.compactMap(\.damage)
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
            holidays: holidays,
            damagedDays: damaged
        )
    }
}

/// One entry in the list of days: either a record, or a note that it could not
/// be read.
///
/// Its `init(from:)` never throws, and that is the whole design. Recovering
/// element by element from an unkeyed container is the obvious alternative and
/// a trap: a `decode` that throws is not guaranteed to advance the container's
/// index, so the loop that tries to skip a bad element can spin on it forever.
/// Decoding an array of these has no such problem, because nothing fails.
private struct DayOrDamage: Decodable {
    let record: DayRecord?
    let damage: BackupArchive.DamagedDay?

    /// Just enough of a day to name it in a report, when the rest is unreadable.
    private enum Naming: String, CodingKey { case date }

    init(from decoder: Decoder) throws {
        if let decoded = try? DayRecord(from: decoder) {
            record = decoded
            damage = nil
            return
        }
        record = nil

        // Salvage the date if it survived, so the report can say which days to
        // go and re-enter. "A day with no readable date" is a poor thing to
        // have to tell someone, but it beats a silent gap in their year.
        var salvaged: CalendarDate?
        if let container = try? decoder.container(keyedBy: Naming.self) {
            salvaged = try? container.decode(CalendarDate.self, forKey: .date)
        }
        damage = salvaged.map(BackupArchive.DamagedDay.dated) ?? .unidentified
    }
}
