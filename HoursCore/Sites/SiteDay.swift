import Foundation

/// One person's presence on a site day. Any `nil` field means "use the
/// site's", so the common case, everyone working the same hours, stores
/// nothing per person.
struct Attendance: Hashable, Codable, Sendable {
    var memberID: UUID
    var start: TimeOfDay?
    var end: TimeOfDay?
    var breakMinutes: Int?

    init(memberID: UUID, start: TimeOfDay? = nil, end: TimeOfDay? = nil, breakMinutes: Int? = nil) {
        self.memberID = memberID
        self.start = start
        self.end = end
        self.breakMinutes = breakMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case memberID, start, end, breakMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            memberID: container.lenient(.memberID, UUID()),
            start: container.lenientOptional(.start),
            end: container.lenientOptional(.end),
            breakMinutes: container.lenientOptional(.breakMinutes)
        )
    }
}

/// Why someone on the crew was not on this site that day.
enum AbsenceReason: Hashable, Sendable {
    /// A day type that means absent — Sick, Vacation, a day off
    /// (`DayTypeCatalog.absenceReasons`).
    case dayType(DayTypeID)
    /// Working on another site: which one when it was picked, nil for
    /// "another site" with no name. Not a day type, so it never reaches your
    /// calendar (your hours there come from that site) and counts as neither
    /// sick nor leave.
    case otherSite(UUID?)
}

/// One person's reason for not being here. Per day, because people are sick
/// a day at a time; never copied to the next day.
///
/// Stored as `memberID` with either `dayTypeID` (what the first version
/// wrote, and still writes for a day type) or `kind: "otherSite"` and an
/// optional `siteID`. An other-site entry has no `dayTypeID` on purpose: a
/// reader that only knows day types fails on it rather than guessing one,
/// and every such reader treats a list it cannot read as no reasons.
struct CrewAbsence: Hashable, Codable, Sendable {
    var memberID: UUID
    var reason: AbsenceReason

    init(memberID: UUID, reason: AbsenceReason) {
        self.memberID = memberID
        self.reason = reason
    }

    init(memberID: UUID, dayTypeID: DayTypeID) {
        self.init(memberID: memberID, reason: .dayType(dayTypeID))
    }

    /// The day type, when the reason is one.
    var dayTypeID: DayTypeID? {
        if case let .dayType(id) = reason { return id }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case memberID, dayTypeID, kind, siteID
    }

    private static let otherSiteKind = "otherSite"

    /// Unreadable means left out, not guessed: an entry with no person, or
    /// with no reason this version knows, throws, and `decodeList` and
    /// `SiteDay`'s decoder skip it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let memberID = try container.decode(UUID.self, forKey: .memberID)
        if let kind = container.lenientOptional(.kind, String.self) {
            guard kind == Self.otherSiteKind else {
                throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "unknown kind")
            }
            self.init(memberID: memberID, reason: .otherSite(container.lenientOptional(.siteID, UUID.self)))
        } else {
            self.init(memberID: memberID, dayTypeID: try container.decode(DayTypeID.self, forKey: .dayTypeID))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(memberID, forKey: .memberID)
        switch reason {
        case let .dayType(id):
            try container.encode(id, forKey: .dayTypeID)
        case let .otherSite(siteID):
            try container.encode(Self.otherSiteKind, forKey: .kind)
            try container.encodeIfPresent(siteID, forKey: .siteID)
        }
    }

    /// A stored list, every readable entry of it; none for nothing or junk.
    static func decodeList(_ data: Data?) -> [CrewAbsence] {
        guard let data, !data.isEmpty,
              let list = try? JSONDecoder().decode([Lossy].self, from: data)
        else { return [] }
        return list.compactMap(\.value)
    }

    /// One entry of a list, nil where it cannot be read.
    struct Lossy: Decodable {
        let value: CrewAbsence?

        init(from decoder: Decoder) throws {
            value = try? CrewAbsence(from: decoder)
        }
    }
}

/// The hours a crew worked on one site on one date.
struct SiteDay: Hashable, Codable, Sendable {
    var siteID: UUID
    var date: CalendarDate
    var start: TimeOfDay?
    var end: TimeOfDay?
    /// The site's break; attendances may override it.
    var breakMinutes: Int
    var present: [Attendance]
    var note: String
    /// The job these hours count towards, frozen when the day is written so
    /// that later changes to the site never move recorded hours between jobs.
    var jobID: UUID?
    /// The crew was rained off: a bad-weather stop (Schlechtwetter). Either
    /// no hours at all, or the hours up to the stop; see
    /// `stoppedForBadWeather(at:)`.
    var isBadWeatherStop: Bool
    /// Why people who are not ticked were not there, for those it was given
    /// for (1.1). Nobody is both here and absent: `settingAbsence` unticks,
    /// `togglingPresence` clears the reason, and `absence(for:)` ignores a
    /// stray reason for someone ticked.
    var absences: [CrewAbsence]
    /// Who on the crew gets the field allowance for this day (1.2), frozen
    /// when the day is written: ticking someone in on a site with
    /// `Site.allowanceByDefault` adds them, and it can be taken off one
    /// person at a time. Only someone ticked present has it
    /// (`hasAllowance(for:)`).
    var allowanceMemberIDs: [UUID]
    /// Kilometres the crew's vehicle drove for this day: one number for the
    /// day, not per person (1.2).
    var kilometres: Int
    /// People who left this day for another of your sites (1.2), each with
    /// what Undo needs: see `SiteMove` and `SiteMoving`. Never copied to the
    /// next day.
    var moves: [SiteMove]

    init(
        siteID: UUID,
        date: CalendarDate,
        start: TimeOfDay? = nil,
        end: TimeOfDay? = nil,
        breakMinutes: Int = 0,
        present: [Attendance] = [],
        note: String = "",
        jobID: UUID? = nil,
        isBadWeatherStop: Bool = false,
        absences: [CrewAbsence] = [],
        allowanceMemberIDs: [UUID] = [],
        kilometres: Int = 0,
        moves: [SiteMove] = []
    ) {
        self.siteID = siteID
        self.date = date
        self.start = start
        self.end = end
        self.breakMinutes = breakMinutes
        self.present = present
        self.note = note
        self.jobID = jobID
        self.isBadWeatherStop = isBadWeatherStop
        self.absences = absences
        self.allowanceMemberIDs = allowanceMemberIDs
        self.kilometres = max(0, kilometres)
        self.moves = moves
    }

    func attendance(for memberID: UUID) -> Attendance? {
        present.first { $0.memberID == memberID }
    }

    /// One person's hours on this day: their own override where they have one,
    /// the site's value otherwise. `nil` when they are not present. The single
    /// place this is decided, so the site screen and the calendar cannot
    /// disagree about it.
    func resolved(for memberID: UUID) -> (start: TimeOfDay?, end: TimeOfDay?, breakMinutes: Int)? {
        guard let attendance = attendance(for: memberID) else { return nil }
        return (
            attendance.start ?? start,
            attendance.end ?? end,
            attendance.breakMinutes ?? breakMinutes
        )
    }

    // MARK: - Absences

    /// Why `memberID` was not here, when a reason was given and they are not
    /// ticked present.
    func absenceReason(for memberID: UUID) -> AbsenceReason? {
        guard attendance(for: memberID) == nil else { return nil }
        return absences.first { $0.memberID == memberID }?.reason
    }

    /// The day type `memberID` was away for, when the reason is one. Nil for
    /// "on another site", which is not a day type.
    func absence(for memberID: UUID) -> DayTypeID? {
        guard case let .dayType(id)? = absenceReason(for: memberID) else { return nil }
        return id
    }

    /// The reasons given for people who were not here, one per person, stray
    /// reasons for someone ticked left out. Someone neither ticked nor given a
    /// reason is not counted: they may not be on this crew yet.
    private var awayReasons: [AbsenceReason] {
        absences.compactMap { absenceReason(for: $0.memberID) }
    }

    /// How many people were away for a reason, which the site's month marks.
    var awayCount: Int { awayReasons.count }

    /// The reason the month's mark is coloured by: Sick before any other day
    /// type, a day type before "on another site", which is the least news.
    var leadingAwayReason: AbsenceReason? {
        let reasons = awayReasons
        if reasons.contains(.dayType(.sick)) { return .dayType(.sick) }
        return reasons.first { if case .dayType = $0 { return true } else { return false } } ?? reasons.first
    }

    /// The day with `reason` as why `memberID` was not here; nil clears it.
    /// Absent means not here, so giving a reason unticks them.
    func settingReason(_ reason: AbsenceReason?, for memberID: UUID) -> SiteDay {
        var day = self
        day.absences.removeAll { $0.memberID == memberID }
        if let reason {
            day.present.removeAll { $0.memberID == memberID }
            day.allowanceMemberIDs.removeAll { $0 == memberID }
            day.absences.append(CrewAbsence(memberID: memberID, reason: reason))
        }
        return day
    }

    /// `settingReason` with a day type.
    func settingAbsence(_ dayType: DayTypeID?, for memberID: UUID) -> SiteDay {
        settingReason(dayType.map(AbsenceReason.dayType), for: memberID)
    }

    /// Ticks `memberID` in, or out. Ticking in clears any reason they were
    /// away, and gives them the field allowance when the site gives it by
    /// default; ticking out gives no reason and takes the allowance.
    func togglingPresence(of memberID: UUID, allowanceByDefault: Bool = false) -> SiteDay {
        var day = self
        day.allowanceMemberIDs.removeAll { $0 == memberID }
        if let index = day.present.firstIndex(where: { $0.memberID == memberID }) {
            day.present.remove(at: index)
        } else {
            day.present.append(Attendance(memberID: memberID))
            day.absences.removeAll { $0.memberID == memberID }
            if allowanceByDefault { day.allowanceMemberIDs.append(memberID) }
        }
        return day
    }

    // MARK: - Field allowance

    /// Whether `memberID` gets the field allowance for this day: ticked
    /// present and given it. A stray entry for someone not there counts for
    /// nothing.
    func hasAllowance(for memberID: UUID) -> Bool {
        attendance(for: memberID) != nil && allowanceMemberIDs.contains(memberID)
    }

    /// How many of the people present get the allowance.
    var allowanceCount: Int {
        Set(allowanceMemberIDs).filter { attendance(for: $0) != nil }.count
    }

    /// The day with the allowance given to, or taken off, one person. Only
    /// someone present can have it, so giving it to anyone else does nothing.
    func settingAllowance(_ hasAllowance: Bool, for memberID: UUID) -> SiteDay {
        var day = self
        day.allowanceMemberIDs.removeAll { $0 == memberID }
        if hasAllowance, attendance(for: memberID) != nil {
            day.allowanceMemberIDs.append(memberID)
        }
        return day
    }

    /// True when there is nothing worth storing: nobody ticked, no site times
    /// and no note. The day screen deletes such a day rather than keeping an
    /// empty row, as the calendar does with a blank `DayRecord`. A break on
    /// its own does not count, because it means nothing without times; a
    /// note does, because "rain, nobody came" is worth keeping and dropping
    /// typed text would be a save that silently did nothing.
    var isBlank: Bool {
        !isBadWeatherStop
            && kilometres == 0
            && present.isEmpty
            && absences.isEmpty
            && start == nil
            && end == nil
            && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when the member was present but worked different hours from the
    /// site's, which is what the day editor flags.
    func hasException(_ memberID: UUID) -> Bool {
        guard let attendance = attendance(for: memberID) else { return false }
        return attendance.start != nil || attendance.end != nil || attendance.breakMinutes != nil
    }

    // MARK: - Bad weather

    /// The day as a bad-weather stop for the whole crew.
    ///
    /// With no time, nobody worked: the site's times, its break and
    /// everyone's own times go, and who was there stays, because "the crew turned up and was
    /// sent home" is the fact the director needs. With a time — "stopped at
    /// 11:00" — the hours until then stand: the site's end becomes the stop,
    /// and anyone whose own end was later stops with everyone else, while
    /// someone who had already left keeps the time they left.
    ///
    /// A stop before the day's start, or on a day running past midnight, is
    /// taken at its word only for the site's end; nobody's start is moved.
    func stoppedForBadWeather(at stop: TimeOfDay?) -> SiteDay {
        var day = self
        day.isBadWeatherStop = true
        guard let stop else {
            day.start = nil
            day.end = nil
            day.breakMinutes = 0
            day.present = present.map { Attendance(memberID: $0.memberID) }
            return day
        }
        day.end = stop
        day.present = present.map { attendance in
            var stopped = attendance
            if let own = attendance.end, own.minutes > stop.minutes {
                stopped.end = stop
            }
            return stopped
        }
        return day
    }

    /// The stop taken back. The times stay as they are, to be corrected by hand.
    func liftingBadWeatherStop() -> SiteDay {
        var day = self
        day.isBadWeatherStop = false
        return day
    }

    /// Whether this day was a full stop for `memberID`: rained off, present,
    /// and no hours to show for it.
    func isFullStop(for memberID: UUID) -> Bool {
        guard isBadWeatherStop, let mine = resolved(for: memberID) else { return false }
        return mine.start == nil || mine.end == nil
    }

    private enum CodingKeys: String, CodingKey {
        case siteID, date, start, end, breakMinutes, present, note, jobID, isBadWeatherStop, absences
        case allowanceMemberIDs, kilometres, moves
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            siteID: container.lenient(.siteID, UUID()),
            date: container.lenient(.date, CalendarDate(year: 1970, month: 1, day: 1)),
            start: container.lenientOptional(.start),
            end: container.lenientOptional(.end),
            breakMinutes: container.lenient(.breakMinutes, 0),
            present: container.lenient(.present, []),
            note: container.lenient(.note, ""),
            jobID: container.lenientOptional(.jobID),
            isBadWeatherStop: container.lenient(.isBadWeatherStop, false),
            // Entry by entry: one that cannot be read is left out, not the day's list.
            absences: container.lenient(.absences, [CrewAbsence.Lossy]()).compactMap(\.value),
            allowanceMemberIDs: container.lenient(.allowanceMemberIDs, []),
            kilometres: container.lenient(.kilometres, 0),
            moves: container.lenient(.moves, [SiteMove.Lossy<SiteMove>]()).compactMap(\.value)
        )
    }

    /// Written by hand so the allowance and the kilometres go in only when
    /// set, and a day without them is written exactly as before.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(siteID, forKey: .siteID)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(start, forKey: .start)
        try container.encodeIfPresent(end, forKey: .end)
        try container.encode(breakMinutes, forKey: .breakMinutes)
        try container.encode(present, forKey: .present)
        try container.encode(note, forKey: .note)
        try container.encodeIfPresent(jobID, forKey: .jobID)
        try container.encode(isBadWeatherStop, forKey: .isBadWeatherStop)
        try container.encode(absences, forKey: .absences)
        if !allowanceMemberIDs.isEmpty { try container.encode(allowanceMemberIDs, forKey: .allowanceMemberIDs) }
        if kilometres != 0 { try container.encode(kilometres, forKey: .kilometres) }
        // 1.0 and 1.1 decode a site day by its keys and skip this one.
        if !moves.isEmpty { try container.encode(moves, forKey: .moves) }
    }
}
