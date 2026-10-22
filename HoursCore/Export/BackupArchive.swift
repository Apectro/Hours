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

    /// Job sites, their crews and the days recorded on them.
    ///
    /// Optional because nil and empty mean different things on restore: nil is
    /// a file written before Sites existed, which must leave the sites already
    /// on the device alone, while an empty list is a backup of someone who has
    /// none, which replaces them.
    var sites: [Site]?
    var crew: [CrewMember]?
    var siteDays: [SiteDay]?

    /// The site diary, its photos and the crew's signatures (1.1).
    ///
    /// Optional for the reason sites are: nil is a file from before they
    /// existed. The format version stays 1 because these are additions an
    /// older app can skip — it reads its hours and ignores keys it does not
    /// know — while raising it would make 1.0 refuse the whole file.
    ///
    /// Photos go in as base64, inside this one JSON file, so a backup stays a
    /// single file that restores through the same door as ever. The cost is
    /// size: a stored photo is roughly 200–500 KB, a third more as base64, so
    /// a month with three photos on twenty days adds about 15–30 MB.
    var diaries: [SiteDiary]?
    var diaryPhotos: [DiaryPhoto]?
    var signatures: [CrewSignature]?

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
        sites: [Site]? = nil,
        crew: [CrewMember]? = nil,
        siteDays: [SiteDay]? = nil,
        diaries: [SiteDiary]? = nil,
        diaryPhotos: [DiaryPhoto]? = nil,
        signatures: [CrewSignature]? = nil,
        damagedDays: [DamagedDay] = []
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.settings = settings
        self.days = days.sorted { $0.date < $1.date }
        self.holidays = holidays
        self.sites = sites
        self.crew = crew
        self.siteDays = siteDays
        self.diaries = diaries
        self.diaryPhotos = diaryPhotos
        self.signatures = signatures
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
        case formatVersion, exportedAt, settings, days, holidays, sites, crew, siteDays
        case diaries, diaryPhotos, signatures
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
        // Only when present, so a nil stays distinguishable from empty.
        try container.encodeIfPresent(sites, forKey: .sites)
        try container.encodeIfPresent(crew, forKey: .crew)
        try container.encodeIfPresent(siteDays, forKey: .siteDays)
        try container.encodeIfPresent(diaries, forKey: .diaries)
        try container.encodeIfPresent(diaryPhotos, forKey: .diaryPhotos)
        try container.encodeIfPresent(signatures, forKey: .signatures)
    }

    /// What a restore leaves of a kind of site record the file may not know
    /// about — diaries, photos, signatures.
    ///
    /// A file that carries the list replaces what is on the device. A file
    /// from before the list existed keeps the device's, but only for sites the
    /// file restores: a diary whose site the restore removed would belong to
    /// nothing. A file with no site data at all (`restoredSiteIDs == nil`)
    /// leaves the sites alone, and so leaves these alone too.
    static func restoredItems<Item>(
        fromFile: [Item]?,
        onDevice: [Item],
        restoredSiteIDs: Set<UUID>?,
        siteID: KeyPath<Item, UUID>
    ) -> [Item] {
        if let fromFile { return fromFile }
        guard let restoredSiteIDs else { return onDevice }
        return onDevice.filter { restoredSiteIDs.contains($0[keyPath: siteID]) }
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
            // Lenient: a missing key is an older file, and a damaged list
            // reads as absent rather than as "no sites", so it cannot wipe
            // the sites on the device.
            sites: container.lenientOptional(.sites),
            crew: container.lenientOptional(.crew),
            siteDays: container.lenientOptional(.siteDays),
            diaries: container.lenientOptional(.diaries),
            diaryPhotos: container.lenientOptional(.diaryPhotos),
            signatures: container.lenientOptional(.signatures),
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
