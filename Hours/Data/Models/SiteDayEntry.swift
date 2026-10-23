import Foundation
import SwiftData

/// The stored hours of one site on one date. Mirrors `SiteDay`, decomposed
/// into primitives.
///
/// One row per (`siteID`, `dateKey`) is a rule the repository enforces rather
/// than the schema, for the same reasons as `DayEntry.dateKey`.
@Model
final class SiteDayEntry {
    /// `SiteDay.siteID`, as `uuidString`.
    var siteID: String = ""
    /// `yyyyMMdd`, as `DayEntry.dateKey`.
    var dateKey: Int = 0

    /// Minutes since local midnight; `nil` when not yet entered.
    var startMinutes: Int?
    var endMinutes: Int?
    var breakMinutes: Int = 0

    /// JSON-encoded `[Attendance]`. Encoded rather than modelled as rows for
    /// the reason `DayEntry.shiftsData` is: who was present has no identity
    /// outside the day, and must be written, read and deleted with it, all at
    /// once. `nil` means nobody was ticked present.
    var presentData: Data?

    var note: String = ""
    /// `SiteDay.jobID`, as `uuidString`: the job frozen on the day when it was
    /// written. `nil` means the default job.
    var jobID: String?
    /// `SiteDay.isBadWeatherStop`. Added in schema V4 with a default, so a
    /// row written before it reads as an ordinary day.
    var isBadWeatherStop: Bool = false
    /// JSON-encoded `[CrewAbsence]`: why people not ticked were away, as
    /// `presentData` holds who was there. Added in schema V7, optional, so a
    /// row written before it reads as a day with no absences; `nil` also
    /// means none.
    var absenceData: Data?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(day: SiteDay) {
        self.siteID = day.siteID.uuidString
        self.dateKey = day.date.key
        self.createdAt = Date()
        self.updatedAt = Date()
        apply(day)
    }
}

extension SiteDayEntry {
    /// The value-type view of this entry, as handed to the engine.
    ///
    /// Damage degrades rather than crashes, as the engine's lenient decoding
    /// does: an unreadable date becomes 1 January 1970 like `DayEntry`'s, an
    /// unreadable job id means the default job, an unreadable attendance
    /// list means nobody present, and an unreadable absence list means no
    /// reasons given.
    var siteDay: SiteDay {
        SiteDay(
            siteID: UUID(uuidString: siteID) ?? UUID(),
            date: CalendarDate(key: dateKey) ?? CalendarDate(year: 1970, month: 1, day: 1),
            start: startMinutes.map { TimeOfDay(minutes: $0) },
            end: endMinutes.map { TimeOfDay(minutes: $0) },
            breakMinutes: breakMinutes,
            present: SiteDayEntry.decodePresent(presentData),
            note: note,
            jobID: jobID.flatMap(UUID.init(uuidString:)),
            isBadWeatherStop: isBadWeatherStop,
            absences: SiteDayEntry.decodeAbsences(absenceData)
        )
    }

    /// Copies a site day onto this entry. `siteID` and `dateKey` are never
    /// changed: moving a day means deleting and re-creating it, as it does for
    /// `DayEntry`.
    func apply(_ day: SiteDay) {
        startMinutes = day.start?.minutes
        endMinutes = day.end?.minutes
        breakMinutes = day.breakMinutes
        presentData = SiteDayEntry.encodePresent(day.present)
        note = day.note
        jobID = day.jobID?.uuidString
        isBadWeatherStop = day.isBadWeatherStop
        absenceData = SiteDayEntry.encodeAbsences(day.absences)
        updatedAt = Date()
    }

    static func encodePresent(_ present: [Attendance]) -> Data? {
        guard !present.isEmpty else { return nil }
        return try? JSONEncoder().encode(present)
    }

    static func decodePresent(_ data: Data?) -> [Attendance] {
        guard let data, !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([Attendance].self, from: data)) ?? []
    }

    static func encodeAbsences(_ absences: [CrewAbsence]) -> Data? {
        guard !absences.isEmpty else { return nil }
        return try? JSONEncoder().encode(absences)
    }

    static func decodeAbsences(_ data: Data?) -> [CrewAbsence] {
        CrewAbsence.decodeList(data)
    }
}
