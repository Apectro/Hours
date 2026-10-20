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

    init(
        siteID: UUID,
        date: CalendarDate,
        start: TimeOfDay? = nil,
        end: TimeOfDay? = nil,
        breakMinutes: Int = 0,
        present: [Attendance] = [],
        note: String = "",
        jobID: UUID? = nil
    ) {
        self.siteID = siteID
        self.date = date
        self.start = start
        self.end = end
        self.breakMinutes = breakMinutes
        self.present = present
        self.note = note
        self.jobID = jobID
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

    /// True when the member was present but worked different hours from the
    /// site's, which is what the day editor flags.
    func hasException(_ memberID: UUID) -> Bool {
        guard let attendance = attendance(for: memberID) else { return false }
        return attendance.start != nil || attendance.end != nil || attendance.breakMinutes != nil
    }

    private enum CodingKeys: String, CodingKey {
        case siteID, date, start, end, breakMinutes, present, note, jobID
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
            jobID: container.lenientOptional(.jobID)
        )
    }
}
