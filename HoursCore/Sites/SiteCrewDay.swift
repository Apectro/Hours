import Foundation

/// How one person stands on a site day (1.2 redesign, mockup 06 "Who's
/// different today?"): one of four buttons is lit for them — Usual,
/// Late/early, Away, Moved — or none, for someone simply not ticked.
///
/// Decided here, from the stored day, so the crew screen, the written day's
/// lines and their colours cannot disagree about who was late or away.
enum SiteCrewState: Hashable, Sendable {
    /// Ticked, at the site's times.
    case usual
    /// Ticked, with their own start, end or break.
    case ownTimes
    /// Ticked here and left for another site (`SiteMove`): the site they
    /// went to.
    case moved(UUID)
    /// Not ticked, with a reason.
    case away(AbsenceReason)
    /// Not ticked, no reason given.
    case notHere

    static func of(_ memberID: UUID, in day: SiteDay) -> SiteCrewState {
        if day.attendance(for: memberID) != nil {
            if let move = day.move(of: memberID) { return .moved(move.toSiteID) }
            return day.hasException(memberID) ? .ownTimes : .usual
        }
        if let reason = day.absenceReason(for: memberID) { return .away(reason) }
        return .notHere
    }

    /// Ticked present on this site.
    var isHere: Bool {
        switch self {
        case .usual, .ownTimes, .moved: return true
        case .away, .notHere: return false
        }
    }

    /// Orange under the colour rule: came late, left early, away. A move is
    /// not: it is said in the accent, as where they went.
    var needsAttention: Bool {
        switch self {
        case .ownTimes, .away: return true
        case .usual, .moved, .notHere: return false
        }
    }
}

extension SiteDay {
    /// `memberID` ticked in at the site's times: their own times go, any
    /// reason they were away goes. Someone already here keeps the field
    /// allowance they had; someone new gets it when the site gives it by
    /// default, as a tick does.
    func settingUsual(for memberID: UUID, allowanceByDefault: Bool) -> SiteDay {
        settingAttendance(Attendance(memberID: memberID), allowanceByDefault: allowanceByDefault)
    }

    /// `memberID` here with `attendance`'s times, ticked in first when they
    /// were not: "Late/early" on someone away is them turning up after all.
    func settingAttendance(_ attendance: Attendance, allowanceByDefault: Bool) -> SiteDay {
        var day = self
        if let index = day.present.firstIndex(where: { $0.memberID == attendance.memberID }) {
            day.present[index] = attendance
            return day
        }
        day = day.settingReason(nil, for: attendance.memberID)
        day.present.append(attendance)
        day.allowanceMemberIDs.removeAll { $0 == attendance.memberID }
        if allowanceByDefault { day.allowanceMemberIDs.append(attendance.memberID) }
        return day
    }

    /// `memberID` not here and no reason given ("Unpaid / no reason").
    func settingNotHere(for memberID: UUID) -> SiteDay {
        var day = settingReason(nil, for: memberID)
        day.present.removeAll { $0.memberID == memberID }
        day.allowanceMemberIDs.removeAll { $0 == memberID }
        return day
    }
}

// MARK: - The usual day

/// The times a site's usual day has: its own (`SiteSetup`) when both are
/// set, the working week's otherwise — what the site's times sheet already
/// opens on for a day with none.
struct SiteUsualTimes: Hashable, Sendable {
    var start: TimeOfDay
    var end: TimeOfDay
    var breakMinutes: Int

    init(start: TimeOfDay, end: TimeOfDay, breakMinutes: Int) {
        self.start = start
        self.end = end
        self.breakMinutes = max(0, breakMinutes)
    }

    init(setup: SiteSetup, schedule: WorkSchedule) {
        if setup.hasUsualTimes, let start = setup.start, let end = setup.end {
            self.init(start: start, end: end, breakMinutes: setup.breakMinutes)
        } else {
            self.init(start: schedule.defaultStart, end: schedule.defaultEnd, breakMinutes: schedule.defaultBreakMinutes)
        }
    }
}

extension SiteDay {
    /// "Same as usual" (mockup 06): a new day with the site's usual times
    /// for everyone in `crew` (you and the visible crew, in the screen's
    /// order), nobody with own times, and the field allowance for everyone
    /// when the site gives it by default.
    static func usual(
        siteID: UUID,
        date: CalendarDate,
        jobID: UUID?,
        times: SiteUsualTimes,
        crew: [UUID],
        allowanceByDefault: Bool
    ) -> SiteDay {
        var seen = Set<UUID>()
        let people = crew.filter { seen.insert($0).inserted }
        return SiteDay(
            siteID: siteID,
            date: date,
            start: times.start,
            end: times.end,
            breakMinutes: times.breakMinutes,
            present: people.map { Attendance(memberID: $0) },
            jobID: jobID,
            allowanceMemberIDs: allowanceByDefault ? people : []
        )
    }

    /// "Same as the day before" (and the site widget's "Same as yesterday"):
    /// this day copied onto `date`, not saved.
    ///
    /// The site's times, its break and who was there carry over; each
    /// person's exceptions do not, because someone leaving early is a fact
    /// about that day rather than about the crew. Reasons, moves, the note
    /// and a bad-weather stop stay behind for the same reason. Who got the
    /// field allowance carries over with them, and so do the vehicle's
    /// kilometres: the same crew driving to the same site.
    ///
    /// `hidden` are crew members hidden since: no longer offered for a new
    /// day, so not copied in. `jobID` is the site's job now, since a new day
    /// freezes the job as it stands when it is written.
    func copied(to date: CalendarDate, leavingOut hidden: Set<UUID>, jobID: UUID?) -> SiteDay {
        let people = present
            .filter { !hidden.contains($0.memberID) }
            .map { Attendance(memberID: $0.memberID) }
        return SiteDay(
            siteID: siteID,
            date: date,
            start: start,
            end: end,
            breakMinutes: breakMinutes,
            present: people,
            jobID: jobID,
            allowanceMemberIDs: people.map(\.memberID).filter(hasAllowance(for:)),
            kilometres: kilometres
        )
    }
}

// MARK: - Late or early

/// How far one person's own times are from the site's (mockup 06, phone 3):
/// "left 3 hours before the site's usual end". Signed minutes, measured the
/// short way round the clock so a night shift reads right: a positive
/// start came later, a negative end left earlier.
struct SiteTimeDifference: Hashable, Sendable {
    /// Their start less the site's: positive came late.
    var startMinutes: Int
    /// Their end less the site's: negative left early.
    var endMinutes: Int
    /// Their break less the site's.
    var breakMinutes: Int

    var isNone: Bool { startMinutes == 0 && endMinutes == 0 && breakMinutes == 0 }

    static func of(_ attendance: Attendance, in day: SiteDay) -> SiteTimeDifference {
        guard let siteStart = day.start, let siteEnd = day.end else {
            return SiteTimeDifference(startMinutes: 0, endMinutes: 0, breakMinutes: 0)
        }
        return SiteTimeDifference(
            startMinutes: attendance.start.map { shortWay($0, from: siteStart) } ?? 0,
            endMinutes: attendance.end.map { shortWay($0, from: siteEnd) } ?? 0,
            breakMinutes: attendance.breakMinutes.map { $0 - day.breakMinutes } ?? 0
        )
    }

    private static func shortWay(_ time: TimeOfDay, from reference: TimeOfDay) -> Int {
        let day = TimeOfDay.minutesPerDay
        let forward = ((time.minutes - reference.minutes) % day + day) % day
        return forward > day / 2 ? forward - day : forward
    }
}

// MARK: - Figures

/// How many people a site day has and their hours, for the lines under the
/// crew's sheets: "4 people · 32h 30m", "5 people · 4h each".
struct SiteCrewFigures: Hashable, Sendable {
    var people: Int
    var totalMinutes: Int
    /// Everyone's hours when they are all the same; nil when they differ or
    /// nobody is here.
    var eachMinutes: Int?

    init(_ days: [PersonDay]) {
        people = days.count
        totalMinutes = days.reduce(0) { $0 + $1.workedMinutes }
        let distinct = Set(days.map(\.workedMinutes))
        eachMinutes = distinct.count == 1 ? distinct.first : nil
    }

    /// The crew if the weather stopped them (mockup 07 "Bad weather"): at
    /// `stop`, or no work at all for nil. A day with no start yet starts at
    /// `start`, as the stop itself does.
    static func ifStopped(
        _ day: SiteDay,
        at stop: TimeOfDay?,
        startingAt start: TimeOfDay,
        calculator: SiteDayCalculator
    ) -> SiteCrewFigures {
        var next = day
        if stop != nil, next.start == nil { next.start = start }
        return SiteCrewFigures(calculator.compute(next.stoppedForBadWeather(at: stop)).people)
    }

    /// The movers' hours on each side of a move (mockup 07 "Moved to another
    /// site"): "Here: 5h 40m each. There: 3h 20m each."
    static func ofMove(_ outcome: SiteMoveOutcome, calculator: SiteDayCalculator) -> (here: SiteCrewFigures, there: SiteCrewFigures) {
        let movers = Set(outcome.move.people.map(\.memberID))
        let arrivals = Set(outcome.move.people.map(\.targetMemberID))
        let here = calculator.compute(outcome.source).people.filter { movers.contains($0.memberID) }
        let there = calculator.compute(outcome.target).people.filter { arrivals.contains($0.memberID) }
        return (SiteCrewFigures(here), SiteCrewFigures(there))
    }
}
