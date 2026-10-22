import Foundation

/// How a recurrence is written down, in a backup and in the store.
///
/// 1.0 knows three kinds and reads them strictly. In a backup, a `kind` it has
/// never heard of fails the list of holidays, and with it the whole restore;
/// in the store, it reads an unknown kind string as `annual` on the stored
/// month and day. So a movable rule (Easter, weekday-on-or-after, off-Sunday)
/// is written as what 1.0 can read and will never place: an annual
/// 31 February, which no year has. Its real shape travels beside it — a
/// `movable` object in JSON, and the kind string in the store — where 1.0
/// does not look. The worst an older app does with one is list it without a
/// date; it never puts a holiday on a wrong day.
extension HolidayRecurrence {
    private enum CodingKeys: String, CodingKey {
        case kind, year, month, day, weekday, ordinal, startYear, endYear, movable
    }

    private struct Movable: Codable {
        var kind: String
        var month: Int
        var day: Int
        var weekday: Int
        var offset: Int
    }

    /// The 31 February that 1.0 is shown in place of a movable rule.
    private static let neverMonth = 2
    private static let neverDay = 31

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let startYear = try container.decodeIfPresent(Int.self, forKey: .startYear)
        let endYear = try container.decodeIfPresent(Int.self, forKey: .endYear)

        if let movable = try? container.decodeIfPresent(Movable.self, forKey: .movable),
           let kind = Kind(rawValue: movable.kind), kind.isMovable {
            self.init(
                kind: kind, month: movable.month, day: movable.day, weekday: movable.weekday,
                startYear: startYear, endYear: endYear, offset: movable.offset
            )
            return
        }

        let rawKind = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: rawKind), !kind.isMovable else {
            // A kind from a later version, or a movable one that lost its
            // shape: keep the rule, and let it never occur, rather than fail
            // every holiday in the file or guess a date.
            self.init(
                kind: .annual, month: Self.neverMonth, day: Self.neverDay,
                startYear: startYear, endYear: endYear
            )
            return
        }
        self.init(
            kind: kind,
            year: try container.decode(Int.self, forKey: .year),
            month: try container.decode(Int.self, forKey: .month),
            day: try container.decode(Int.self, forKey: .day),
            weekday: try container.decode(Int.self, forKey: .weekday),
            ordinal: try container.decode(Int.self, forKey: .ordinal),
            startYear: startYear,
            endYear: endYear
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(startYear, forKey: .startYear)
        try container.encodeIfPresent(endYear, forKey: .endYear)
        guard kind.isMovable else {
            // Exactly the shape 1.0 wrote.
            try container.encode(kind.rawValue, forKey: .kind)
            try container.encode(year, forKey: .year)
            try container.encode(month, forKey: .month)
            try container.encode(day, forKey: .day)
            try container.encode(weekday, forKey: .weekday)
            try container.encode(ordinal, forKey: .ordinal)
            return
        }
        try container.encode(Kind.annual.rawValue, forKey: .kind)
        try container.encode(2000, forKey: .year)
        try container.encode(Self.neverMonth, forKey: .month)
        try container.encode(Self.neverDay, forKey: .day)
        try container.encode(2, forKey: .weekday)
        try container.encode(1, forKey: .ordinal)
        try container.encode(
            Movable(kind: kind.rawValue, month: month, day: day, weekday: weekday, offset: offset),
            forKey: .movable
        )
    }
}

/// A recurrence as the store's primitive columns hold it (`HolidayRecord`).
struct StoredHolidayRecurrence: Hashable, Sendable {
    var kindRawValue: String
    var year: Int
    var month: Int
    var day: Int
    var weekday: Int
    var ordinal: Int
    var startYear: Int?
    var endYear: Int?
}

extension HolidayRecurrence {
    /// A movable rule keeps its whole shape in the kind string —
    /// `easter:2:31:2:39`, i.e. kind, month, day, weekday, offset — and an
    /// annual 31 February in the columns 1.0 reads. No new column, so no new
    /// schema version for a rule that fits in the ones there are.
    var storedColumns: StoredHolidayRecurrence {
        guard kind.isMovable else {
            return StoredHolidayRecurrence(
                kindRawValue: kind.rawValue, year: year, month: month, day: day,
                weekday: weekday, ordinal: ordinal, startYear: startYear, endYear: endYear
            )
        }
        let packed = [kind.rawValue, String(month), String(day), String(weekday), String(offset)]
            .joined(separator: ":")
        return StoredHolidayRecurrence(
            kindRawValue: packed, year: 2000, month: Self.neverMonth, day: Self.neverDay,
            weekday: 2, ordinal: 1, startYear: startYear, endYear: endYear
        )
    }

    init(stored: StoredHolidayRecurrence) {
        let parts = stored.kindRawValue.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count == 5, let kind = Kind(rawValue: parts[0]), kind.isMovable,
           let month = Int(parts[1]), let day = Int(parts[2]),
           let weekday = Int(parts[3]), let offset = Int(parts[4]) {
            self.init(
                kind: kind, month: month, day: day, weekday: weekday,
                startYear: stored.startYear, endYear: stored.endYear, offset: offset
            )
            return
        }
        // As 1.0 always did: a kind it does not know reads as annual.
        let kind = Kind(rawValue: stored.kindRawValue).flatMap { $0.isMovable ? nil : $0 } ?? .annual
        self.init(
            kind: kind, year: stored.year, month: stored.month, day: stored.day,
            weekday: stored.weekday, ordinal: stored.ordinal,
            startYear: stored.startYear, endYear: stored.endYear
        )
    }
}
