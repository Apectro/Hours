import Foundation

/// Where the break of someone who moved to another site is counted.
enum BreakPlacement: String, Codable, CaseIterable, Hashable, Sendable {
    /// On the site they left.
    case here
    /// On the site they went to.
    case there
    /// Half on each, the odd minute on the site they left.
    case split
}

/// Some of the crew left one site in the middle of the day and finished it on
/// another (1.2): "4 went to Trg Pravde at 11:30".
///
/// Kept on the day they left (`SiteDay.moves`) with what each person's
/// attendance was on both days before, so Undo puts both days back exactly
/// and the crew rows can say "7:00 – 11:30 → Trg Pravde".
struct SiteMove: Identifiable, Hashable, Codable, Sendable {
    /// One person who went, and what the move changed for them.
    struct Person: Hashable, Codable, Sendable {
        /// On the site they left.
        var memberID: UUID
        /// On the site they went to: each site keeps its own crew, so the
        /// same person is matched by name, or added (`CrewCandidates.key`).
        var targetMemberID: UUID
        /// Their attendance here before they left.
        var before: Attendance
        /// Their attendance there before, if they were already ticked.
        var targetBefore: Attendance?
        /// A reason given there for them not being there, which arriving
        /// cleared ("At Hauptstraße 12").
        var targetReasonBefore: AbsenceReason?
        /// Whether they had the field allowance there before.
        var targetAllowanceBefore: Bool

        private enum CodingKeys: String, CodingKey {
            case memberID, targetMemberID, before, targetBefore, targetReason, targetAllowanceBefore
        }

        init(
            memberID: UUID,
            targetMemberID: UUID,
            before: Attendance,
            targetBefore: Attendance? = nil,
            targetReasonBefore: AbsenceReason? = nil,
            targetAllowanceBefore: Bool = false
        ) {
            self.memberID = memberID
            self.targetMemberID = targetMemberID
            self.before = before
            self.targetBefore = targetBefore
            self.targetReasonBefore = targetReasonBefore
            self.targetAllowanceBefore = targetAllowanceBefore
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let memberID = try container.decode(UUID.self, forKey: .memberID)
            let reason = container.lenientOptional(.targetReason, CrewAbsence.self)
            self.init(
                memberID: memberID,
                targetMemberID: container.lenient(.targetMemberID, memberID),
                before: container.lenient(.before, Attendance(memberID: memberID)),
                targetBefore: container.lenientOptional(.targetBefore),
                targetReasonBefore: reason?.reason,
                targetAllowanceBefore: container.lenient(.targetAllowanceBefore, false)
            )
        }

        /// The reason is written the way a day's own reasons are, as a
        /// `CrewAbsence`, so one coding serves both.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(memberID, forKey: .memberID)
            try container.encode(targetMemberID, forKey: .targetMemberID)
            try container.encode(before, forKey: .before)
            try container.encodeIfPresent(targetBefore, forKey: .targetBefore)
            if let targetReasonBefore {
                try container.encode(CrewAbsence(memberID: targetMemberID, reason: targetReasonBefore), forKey: .targetReason)
            }
            if targetAllowanceBefore { try container.encode(true, forKey: .targetAllowanceBefore) }
        }
    }

    var id: UUID
    var toSiteID: UUID
    var left: TimeOfDay
    var started: TimeOfDay
    var breakPlacement: BreakPlacement
    var people: [Person]
    /// The other site had no day on that date until this move made one, so
    /// Undo takes it away again when nothing else was written on it since.
    var createdTargetDay: Bool

    /// Who went, as members of the site they left.
    var memberIDs: [UUID] { people.map(\.memberID) }

    init(
        id: UUID = UUID(),
        toSiteID: UUID,
        left: TimeOfDay,
        started: TimeOfDay,
        breakPlacement: BreakPlacement,
        people: [Person],
        createdTargetDay: Bool
    ) {
        self.id = id
        self.toSiteID = toSiteID
        self.left = left
        self.started = started
        self.breakPlacement = breakPlacement
        self.people = people
        self.createdTargetDay = createdTargetDay
    }

    private enum CodingKeys: String, CodingKey {
        case id, toSiteID, left, started, breakPlacement, people, createdTargetDay
    }

    /// The move's identity and destination are required; a move without them
    /// cannot be shown or undone, so it is left out rather than guessed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            toSiteID: try container.decode(UUID.self, forKey: .toSiteID),
            left: try container.decode(TimeOfDay.self, forKey: .left),
            started: try container.decode(TimeOfDay.self, forKey: .started),
            breakPlacement: container.lenient(.breakPlacement, .there),
            people: container.lenient(.people, [Lossy<Person>]()).compactMap(\.value),
            createdTargetDay: container.lenient(.createdTargetDay, false)
        )
    }

    /// One entry of a list, nil where it cannot be read.
    struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }
}

/// Why a move cannot be made as asked.
enum SiteMoveError: Error, Equatable, Sendable {
    /// The site they would go to is the site they are on.
    case sameSite
    /// Nobody was chosen.
    case nobody
    /// Someone chosen is not ticked here: someone away is never moved.
    case notHere
    /// Someone chosen already went to another site from this day.
    case alreadyMoved
    /// Someone chosen has no start or end here to split.
    case noTimes
    /// They would leave before they started or after they finished here.
    case leftOutsideShift
    /// They would start on the other site before leaving this one.
    case startedBeforeLeft
    /// They would start on the other site after their day ends.
    case startedAfterEnd
}

/// What applying a move is given: the two days and crews, who went, when, and
/// where the break goes.
struct SiteMoveRequest: Sendable {
    var source: SiteDay
    /// The other site's day on the same date, if it has one.
    var target: SiteDay?
    var targetSite: Site
    var sourceCrew: [CrewMember]
    var targetCrew: [CrewMember]
    /// Who went, as members of the site they left (`CrewMember.youID` for you).
    var memberIDs: [UUID]
    var left: TimeOfDay
    var started: TimeOfDay
    var breakPlacement: BreakPlacement
    var lock: MonthLock
    /// Whether the field allowance is tracked at all.
    var tracksAllowance: Bool
}

/// Both days after a move, and the members the other site's crew gains.
struct SiteMoveOutcome: Hashable, Sendable {
    var source: SiteDay
    var target: SiteDay
    /// Crew members to store on the other site: someone not on its crew yet,
    /// or someone hidden there who is back.
    var crewChanges: [CrewMember]
    var move: SiteMove
}

/// Moving people from one site to another in the middle of a day, and taking
/// it back. Pure: the repository stores both days and your calendar day in
/// one save.
enum SiteMoving {
    /// Applies a move.
    ///
    /// Each person who went gets their end here set to the time they left;
    /// on the other site's day — made for the date when there is none,
    /// freezing that site's job as any new day does — they are ticked from
    /// the time they started until their original end here, with the break
    /// where `breakPlacement` puts it. Nobody else on either day changes, a
    /// reason someone is away is never moved, and a closed month refuses.
    static func apply(
        _ request: SiteMoveRequest,
        moveID: UUID = UUID(),
        newMemberID: () -> UUID = UUID.init
    ) throws -> SiteMoveOutcome {
        let source = request.source
        try request.lock.check(source.date)
        guard request.targetSite.id != source.siteID else { throw SiteMoveError.sameSite }
        var seen = Set<UUID>()
        let movers = request.memberIDs.filter { seen.insert($0).inserted }
        guard !movers.isEmpty else { throw SiteMoveError.nobody }

        let left = request.left
        let started = request.started
        var originals: [(id: UUID, attendance: Attendance, start: TimeOfDay, end: TimeOfDay, breakMinutes: Int)] = []
        for id in movers {
            guard let attendance = source.attendance(for: id), let mine = source.resolved(for: id) else {
                throw SiteMoveError.notHere
            }
            guard source.move(of: id) == nil else { throw SiteMoveError.alreadyMoved }
            guard let start = mine.start, let end = mine.end, start < end else { throw SiteMoveError.noTimes }
            guard left > start, left < end else { throw SiteMoveError.leftOutsideShift }
            guard started >= left else { throw SiteMoveError.startedBeforeLeft }
            guard started < end else { throw SiteMoveError.startedAfterEnd }
            originals.append((id, attendance, start, end, mine.breakMinutes))
        }

        // The other site's day, or a new one beginning when they arrived.
        let created = request.target == nil
        var target = request.target ?? SiteDay(
            siteID: request.targetSite.id,
            date: source.date,
            start: started,
            end: source.end ?? originals[0].end,
            breakMinutes: split(breakMinutes: source.breakMinutes, placement: request.breakPlacement).there,
            jobID: request.targetSite.jobID
        )

        var crewChanges: [CrewMember] = []
        var nextSortOrder = (request.targetCrew.map(\.sortOrder).max() ?? -1) + 1
        func targetMember(for id: UUID) -> UUID {
            if id == CrewMember.youID { return id }
            let name = request.sourceCrew.first { $0.id == id }?.name ?? ""
            let key = CrewCandidates.key(for: name)
            let known = request.targetCrew + crewChanges
            if !key.isEmpty {
                let matches = known.filter { $0.siteID == request.targetSite.id && CrewCandidates.key(for: $0.name) == key }
                if let shown = matches.first(where: { !$0.isHidden }) { return shown.id }
                if var hidden = matches.first {
                    hidden.isHidden = false
                    crewChanges.removeAll { $0.id == hidden.id }
                    crewChanges.append(hidden)
                    return hidden.id
                }
            }
            let member = CrewMember(
                id: newMemberID(),
                siteID: request.targetSite.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: nextSortOrder
            )
            nextSortOrder += 1
            crewChanges.append(member)
            return member.id
        }

        var next = source
        var people: [SiteMove.Person] = []
        for original in originals {
            let parts = split(breakMinutes: original.breakMinutes, placement: request.breakPlacement)

            var here = original.attendance
            here.end = left
            here.breakMinutes = parts.here
            if let index = next.present.firstIndex(where: { $0.memberID == original.id }) {
                next.present[index] = normalized(here, in: next)
            }

            let otherID = targetMember(for: original.id)
            let arriving = normalized(
                Attendance(memberID: otherID, start: started, end: original.end, breakMinutes: parts.there),
                in: target
            )
            let person = SiteMove.Person(
                memberID: original.id,
                targetMemberID: otherID,
                before: original.attendance,
                targetBefore: target.attendance(for: otherID),
                targetReasonBefore: target.absences.first { $0.memberID == otherID }?.reason,
                targetAllowanceBefore: target.allowanceMemberIDs.contains(otherID)
            )
            people.append(person)

            target.absences.removeAll { $0.memberID == otherID }
            if let index = target.present.firstIndex(where: { $0.memberID == otherID }) {
                target.present[index] = arriving
            } else {
                target.present.append(arriving)
            }
            // The allowance is for the day, not per site: someone who has it
            // here already is not given it a second time there.
            if request.tracksAllowance, request.targetSite.allowanceByDefault,
               !source.hasAllowance(for: original.id), !target.allowanceMemberIDs.contains(otherID) {
                target.allowanceMemberIDs.append(otherID)
            }
        }

        let move = SiteMove(
            id: moveID,
            toSiteID: request.targetSite.id,
            left: left,
            started: started,
            breakPlacement: request.breakPlacement,
            people: people,
            createdTargetDay: created
        )
        next.moves.append(move)
        return SiteMoveOutcome(source: next, target: target, crewChanges: crewChanges, move: move)
    }

    /// Both days as they were before `move`, as far as the move changed them:
    /// each person's attendance here, and there their attendance, the reason
    /// they were away and their allowance. A day the move made is gone again
    /// (nil) unless something else was written on it since.
    static func undo(_ move: SiteMove, source: SiteDay, target: SiteDay?) -> (source: SiteDay, target: SiteDay?) {
        var restored = source
        for person in move.people {
            if let index = restored.present.firstIndex(where: { $0.memberID == person.memberID }) {
                restored.present[index] = person.before
            } else {
                restored.present.append(person.before)
                restored.absences.removeAll { $0.memberID == person.memberID }
            }
        }
        restored.moves.removeAll { $0.id == move.id }

        guard var other = target else { return (restored, nil) }
        for person in move.people {
            let id = person.targetMemberID
            if let before = person.targetBefore {
                if let index = other.present.firstIndex(where: { $0.memberID == id }) {
                    other.present[index] = before
                } else {
                    other.present.append(before)
                }
            } else {
                other.present.removeAll { $0.memberID == id }
            }
            other.absences.removeAll { $0.memberID == id }
            if let reason = person.targetReasonBefore {
                other.absences.append(CrewAbsence(memberID: id, reason: reason))
            }
            other.allowanceMemberIDs.removeAll { $0 == id }
            if person.targetAllowanceBefore { other.allowanceMemberIDs.append(id) }
        }
        let untouchedSince = other.present.isEmpty
            && other.absences.isEmpty
            && other.moves.isEmpty
            && other.kilometres == 0
            && !other.isBadWeatherStop
            && other.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if move.createdTargetDay, untouchedSince { return (restored, nil) }
        return (restored, other)
    }

    /// How a break of `breakMinutes` divides between the two sites.
    static func split(breakMinutes: Int, placement: BreakPlacement) -> (here: Int, there: Int) {
        let minutes = max(0, breakMinutes)
        switch placement {
        case .here: return (minutes, 0)
        case .there: return (0, minutes)
        case .split: return (minutes - minutes / 2, minutes / 2)
        }
    }

    /// Where the break goes unless chosen: where it falls in time. A break
    /// with no time of its own sits in the middle of the shift, as earnings
    /// place it; taken before they left, it stays here, otherwise — after,
    /// or cut by the move — it goes to the other site.
    static func defaultBreakPlacement(start: TimeOfDay?, end: TimeOfDay?, breakMinutes: Int, left: TimeOfDay) -> BreakPlacement {
        guard breakMinutes > 0, let start, let end, start < end else { return .there }
        let breakStart = start.minutes + max(0, end.minutes - start.minutes - breakMinutes) / 2
        return breakStart + breakMinutes <= left.minutes ? .here : .there
    }

    /// When they left, unless told: now, on today, while the day is under
    /// way, to the user's rounding (at least five minutes, so a picker opens
    /// on a round time); otherwise the middle of the day, half-hour rounded.
    /// The end of the day would leave nothing to move.
    static func suggestedLeftTime(for day: SiteDay, now: TimeOfDay, isToday: Bool, rounding: RoundingRule) -> TimeOfDay {
        let step = max(5, rounding.step)
        guard let start = day.start, let end = day.end, start < end else {
            return now.rounded(toNearest: step)
        }
        let rounded = now.rounded(toNearest: step)
        if isToday, rounded > start, rounded < end { return rounded }
        let middle = TimeOfDay(minutes: (start.minutes + end.minutes) / 2).rounded(toNearest: 30)
        return middle > start && middle < end ? middle : TimeOfDay(minutes: (start.minutes + end.minutes) / 2)
    }

    /// The attendance with nothing of its own where it says what the day
    /// says, so nobody is shown as having their own times for no reason.
    private static func normalized(_ attendance: Attendance, in day: SiteDay) -> Attendance {
        var result = attendance
        if result.start == day.start { result.start = nil }
        if result.end == day.end { result.end = nil }
        if result.breakMinutes == day.breakMinutes { result.breakMinutes = nil }
        return result
    }
}

/// How a site day's moves are stored without a new column (1.2).
///
/// They ride in the `absenceData` column next to the reasons people were
/// away, as entries of their own kind (`"kind": "move"`). Every build since
/// 1.1 reads that list entry by entry and leaves out an entry whose kind it
/// does not know (`CrewAbsence.decodeList`), so a TestFlight build of 1.2
/// from before this simply does not see them: no schema version, no CloudKit
/// schema to deploy again, and nothing an older build can misread as a person
/// present or away. The worst an older build does is write the day again
/// without them, which takes away the Undo and the "→ Trg Pravde" and leaves
/// the hours as they are.
enum SiteDayStorage {
    private static let moveKind = "move"

    private struct MoveEntry: Codable {
        /// An entry's person, which an older reader decodes before it looks
        /// at the kind: the move's own id, never a crew member's.
        var memberID: UUID
        var kind: String
        var move: SiteMove
    }

    /// The column's value: the reasons, then the moves; nil for neither.
    static func absenceData(absences: [CrewAbsence], moves: [SiteMove]) -> Data? {
        guard !absences.isEmpty || !moves.isEmpty else { return nil }
        let encoder = JSONEncoder()
        var items: [Data] = []
        for absence in absences {
            if let data = try? encoder.encode(absence) { items.append(data) }
        }
        for move in moves {
            if let data = try? encoder.encode(MoveEntry(memberID: move.id, kind: moveKind, move: move)) { items.append(data) }
        }
        var joined = Data("[".utf8)
        for (index, item) in items.enumerated() {
            if index > 0 { joined.append(Data(",".utf8)) }
            joined.append(item)
        }
        joined.append(Data("]".utf8))
        return joined
    }

    /// The moves in the column, every readable one; none for nothing or junk.
    static func moves(fromAbsenceData data: Data?) -> [SiteMove] {
        guard let data, !data.isEmpty,
              let list = try? JSONDecoder().decode([SiteMove.Lossy<MoveEntry>].self, from: data)
        else { return [] }
        return list.compactMap(\.value).filter { $0.kind == moveKind }.map(\.move)
    }
}

extension SiteDay {
    /// The move `memberID` left this site's day with, if they did.
    func move(of memberID: UUID) -> SiteMove? {
        moves.last { $0.memberIDs.contains(memberID) }
    }
}
