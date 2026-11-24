import Foundation

/// A site day, by its site and date.
struct ConnectSiteDayRef: Hashable, Sendable {
    var siteID: UUID
    var date: CalendarDate

    /// The id both sides know the day by.
    var id: String { ConnectID.string(ConnectUUID.siteDayID(siteID: siteID, date: date)) }
}

/// What the small line on a site day says.
enum ConnectOfficeMark: Hashable, Sendable {
    /// "Written by the office": the office wrote the day.
    case written
    /// "Changed by the office": a phone's day the office edited.
    case changed
}

/// The phone's own unsent edit of a day the office changed, set aside
/// while the day shows the office's: the day as it was, or nil when the
/// edit was deleting it.
struct ConnectMine: Codable, Hashable, Sendable {
    var day: SiteDay?
}

/// A day the office wrote or changed, as taken into the phone.
struct ConnectOfficeDay: Codable, Hashable, Sendable {
    var siteID: UUID
    var date: CalendarDate
    /// The office wrote it (`origin: director`).
    var writtenByOffice: Bool
    /// The office changed it last (`editedBy: director`), and the phone has
    /// not edited it since.
    var changedByOffice: Bool
    /// The server's version that was taken.
    var version: Int
    /// The phone's unsent edit the office's copy replaced, until the user
    /// chooses "Use the office's" or "Keep mine".
    var mine: ConnectMine?

    var mark: ConnectOfficeMark? {
        if writtenByOffice { return .written }
        return changedByOffice ? .changed : nil
    }
}

/// An office day waiting for its month to be reopened: the day, or nil for
/// one the office deleted.
struct ConnectHeldOfficeDay: Codable, Hashable, Sendable {
    var version: Int
    /// Nil while it waits for its site rather than for a month.
    var month: YearMonth?
    var day: ConnectV1.SiteDay?
}

/// Web → phone, one day: the protocol's site day as the app's.
enum ConnectIncoming {
    /// The office's day as the local site day of its site and date.
    ///
    /// - `existing`: the local day it replaces. Its job stays, and its moves
    ///   keep what Undo needs where the office's copy still names them.
    /// - `member`: the local id of a person by the company's id: "You" for
    ///   the paired person, a crew row of the site for anyone else, nil for
    ///   someone unknown, who is left out.
    ///
    /// The diary is not touched: it is a record of its own on the phone.
    static func siteDay(
        _ wire: ConnectV1.SiteDay,
        siteID: UUID,
        date: CalendarDate,
        existing: SiteDay?,
        jobID: UUID?,
        member: (String) -> UUID?
    ) -> SiteDay {
        var seen = Set<UUID>()
        let present = wire.attendance.compactMap { entry -> Attendance? in
            guard let id = member(entry.memberId), seen.insert(id).inserted else { return nil }
            return Attendance(
                memberID: id,
                start: ConnectFormat.parseTime(entry.start),
                end: ConnectFormat.parseTime(entry.end),
                breakMinutes: entry.breakMinutes.map { max(0, $0) }
            )
        }
        var away = Set<UUID>()
        let absences = wire.absences.compactMap { absence -> CrewAbsence? in
            guard let id = member(absence.memberId), !seen.contains(id) else { return nil }
            let reason: AbsenceReason
            switch absence.reason.type {
            case "dayType":
                guard let type = absence.reason.dayType, !type.isEmpty else { return nil }
                reason = .dayType(DayTypeID(type))
            case "otherSite":
                reason = .otherSite(ConnectID.uuid(absence.reason.siteId))
            default:
                // A reason this version does not know: left out, not guessed.
                return nil
            }
            guard away.insert(id).inserted else { return nil }
            return CrewAbsence(memberID: id, reason: reason)
        }
        var allowed = Set<UUID>()
        let allowance = wire.allowanceMemberIds.compactMap { text -> UUID? in
            guard let id = member(text), seen.contains(id), allowed.insert(id).inserted else { return nil }
            return id
        }
        let known = Dictionary((existing?.moves ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let moves = wire.moves.compactMap { move -> SiteMove? in
            guard let id = ConnectID.uuid(move.id) else { return nil }
            let members = move.memberIds.compactMap(member)
            // The phone's own move, as long as the same people went: with
            // what its Undo needs.
            if let mine = known[id], Set(mine.memberIDs) == Set(members) { return mine }
            guard let toSite = ConnectID.uuid(move.toSiteId),
                  let left = ConnectFormat.parseTime(move.left),
                  let started = ConnectFormat.parseTime(move.started),
                  !members.isEmpty else { return nil }
            return SiteMove(
                id: id,
                toSiteID: toSite,
                left: left,
                started: started,
                breakPlacement: BreakPlacement(rawValue: move.breakPlacement) ?? .here,
                people: members.map { SiteMove.Person(memberID: $0, targetMemberID: $0, before: Attendance(memberID: $0)) },
                createdTargetDay: false
            )
        }
        return SiteDay(
            siteID: siteID,
            date: date,
            start: ConnectFormat.parseTime(wire.start),
            end: ConnectFormat.parseTime(wire.end),
            breakMinutes: max(0, wire.breakMinutes),
            present: present,
            note: wire.note,
            jobID: existing?.jobID ?? jobID,
            isBadWeatherStop: wire.badWeatherStop,
            absences: absences,
            allowanceMemberIDs: allowance,
            kilometres: max(0, wire.kilometres),
            moves: moves,
            noWork: wire.noWork.flatMap(SiteNoWorkReason.init(rawValue:))
        )
    }
}

/// What taking office days changes in the store.
struct ConnectOfficeDayChanges: Sendable {
    var save: [ConnectSiteDayRef: SiteDay] = [:]
    var remove: Set<ConnectSiteDayRef> = []
}

extension ConnectMerge {
    static let editedOnWeb = "editedOnWeb"

    /// An office day worth looking at: its site, date and version, when its
    /// id is the one its site and date give.
    static func officeDayParts(_ wire: ConnectV1.SiteDay) -> (siteID: UUID, date: CalendarDate, version: Int)? {
        guard let siteID = ConnectID.uuid(wire.siteId),
              let date = ConnectFormat.parseDate(wire.date),
              let version = wire.version, version > 0,
              ConnectID.same(ConnectID.string(ConnectUUID.siteDayID(siteID: siteID, date: date)), wire.id) else { return nil }
        return (siteID, date, version)
    }

    /// The office's copy in an upload's `conflict, editedOnWeb` result: the
    /// office view's `data`, or the day itself.
    static func officeDay(in conflict: ConnectConflict) -> ConnectV1.SiteDay? {
        guard conflict.kind == .siteDay, conflict.reason == editedOnWeb, let server = conflict.server else { return nil }
        let json = server["data"] ?? server
        guard let data = try? ConnectJSON.encode(json),
              var day = try? ConnectJSON.decode(ConnectV1.SiteDay.self, from: data) else { return nil }
        if day.version == nil { day.version = conflict.serverVersion }
        return day
    }

    /// Office days (`docs/app.md`, Office days), from a sync page, from an
    /// upload answered `conflict, editedOnWeb`, and those held back earlier.
    ///
    /// - Each becomes the local day of its site and date, and its version
    ///   the record's base version, unless the phone already has that
    ///   version or its own newer one.
    /// - A closed month is never changed: the day is held until the month
    ///   is reopened, and listed in `conflicts` once.
    /// - With an unsent local edit (still queued, or just refused by the
    ///   server as `editedOnWeb`) the office's copy is taken all the same
    ///   and the phone's is set aside as "mine" for the user to choose,
    ///   unless both say the same.
    /// - People the day names who have no row on the site get one from the
    ///   company's people: hidden, because being named on one day does not
    ///   put someone on the site's usual crew (an assignment does).
    /// - A deleted office day (`tombstones`) deletes the local day when the
    ///   office wrote it and the phone has no unsent edit of it; with one
    ///   set aside, that edit is the day again.
    static func takeOfficeDays(
        _ incoming: [ConnectV1.SiteDay],
        tombstones: [String],
        state: inout ConnectState,
        sites: [UUID: Site],
        crew: inout [UUID: CrewMember],
        changedCrew: inout Set<UUID>,
        localDays: [SiteDay],
        lock: MonthLock,
        conflicts: inout [ConnectMergeConflict]
    ) -> ConnectOfficeDayChanges {
        var changes = ConnectOfficeDayChanges()

        // The newest copy of each day on offer.
        var offered: [String: ConnectV1.SiteDay] = [:]
        func offer(_ day: ConnectV1.SiteDay) {
            let id = day.id.lowercased()
            if let has = offered[id], (has.version ?? 0) >= (day.version ?? 0) { return }
            offered[id] = day
        }
        for held in state.heldOfficeDays.values {
            if let day = held.day { offer(day) }
        }
        for conflict in state.conflicts.values where state.officeDays[conflict.id]?.mine == nil {
            if let day = officeDay(in: conflict) { offer(day) }
        }
        incoming.forEach(offer)
        let gone = Set(tombstones.map { $0.lowercased() })
            .union(state.heldOfficeDays.filter { $0.value.day == nil }.keys)
        guard !offered.isEmpty || !gone.isEmpty else { return changes }

        let local = Dictionary(
            localDays.map { (ConnectSiteDayRef(siteID: $0.siteID, date: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for id in offered.keys.sorted() {
            guard let wire = offered[id] else { continue }
            let key = ConnectRecordKey.make(.siteDay, id)
            let unsentConflict = state.conflicts[key]?.reason == editedOnWeb && state.officeDays[id]?.mine == nil
            guard let parts = officeDayParts(wire) else {
                state.heldOfficeDays[id] = nil
                if unsentConflict { state.conflicts[key] = nil }
                continue
            }
            let version = parts.version
            let applied = state.officeDays[id]?.version ?? 0
            let base = state.marks[key]?.baseVersion ?? 0
            // Already taken, or the phone's own newer version come back.
            if version <= applied || (!wire.isOfficeEdited && version <= base) {
                state.heldOfficeDays[id] = nil
                if unsentConflict { state.conflicts[key] = nil }
                continue
            }
            let month = parts.date.yearMonth
            guard let site = sites[parts.siteID] else {
                state.heldOfficeDays[id] = ConnectHeldOfficeDay(version: version, month: nil, day: wire)
                continue
            }
            if lock.isLocked(month) {
                let held = state.heldOfficeDays[id]
                if held?.version != version || held?.month == nil || held?.day == nil {
                    conflicts.append(ConnectMergeConflict(kind: .officeDayInClosedMonth, recordKind: .siteDay, id: id, month: ConnectFormat.month(month)))
                }
                state.heldOfficeDays[id] = ConnectHeldOfficeDay(version: version, month: month, day: wire)
                continue
            }
            state.heldOfficeDays[id] = nil

            let ref = ConnectSiteDayRef(siteID: parts.siteID, date: parts.date)
            let existing = local[ref]
            let mapped = ConnectIncoming.siteDay(wire, siteID: parts.siteID, date: parts.date, existing: existing, jobID: site.jobID) { text in
                localMember(text, on: parts.siteID, state: &state, crew: &crew, changedCrew: &changedCrew)
            }

            // The phone's own unsent edit, if it says something else.
            let queued = state.queue.contains { $0.key == key }
            var mine = state.officeDays[id]?.mine
            if queued || unsentConflict {
                mine = says(existing, theSameAs: mapped) ? nil : ConnectMine(day: existing)
            }
            state.queue.removeAll { $0.key == key }

            var mark = state.marks[key] ?? ConnectRecordMark(version: 0, baseVersion: 0, hash: "")
            mark.version = max(mark.version, version)
            mark.baseVersion = max(mark.baseVersion, version)
            mark.adopts = true
            mark.deleted = false
            mark.siteIDs = [parts.siteID]
            mark.month = month
            state.marks[key] = mark

            state.officeDays[id] = ConnectOfficeDay(
                siteID: parts.siteID,
                date: parts.date,
                writtenByOffice: wire.isOfficeWritten,
                changedByOffice: wire.isOfficeEdited,
                version: version,
                mine: mine
            )
            if mine != nil {
                state.conflicts[key] = ConnectConflict(
                    kind: .siteDay,
                    id: id,
                    reason: editedOnWeb,
                    serverVersion: version,
                    server: (try? ConnectJSON.encode(wire)).flatMap { try? ConnectJSON.decode(JSONValue.self, from: $0) },
                    commentIDs: state.conflicts[key]?.commentIDs ?? []
                )
            } else {
                state.conflicts[key] = nil
            }
            if !says(existing, theSameAs: mapped) { changes.save[ref] = mapped }
        }

        for id in gone.sorted() {
            let key = ConnectRecordKey.make(.siteDay, id)
            // Only a day the office wrote is ever deleted this way.
            guard let office = state.officeDays[id], office.writtenByOffice else {
                state.heldOfficeDays[id] = nil
                continue
            }
            let month = office.date.yearMonth
            if lock.isLocked(month) {
                if let held = state.heldOfficeDays[id], held.day == nil {
                    // Listed when it was first held.
                } else {
                    conflicts.append(ConnectMergeConflict(kind: .officeDayInClosedMonth, recordKind: .siteDay, id: id, month: ConnectFormat.month(month)))
                }
                state.heldOfficeDays[id] = ConnectHeldOfficeDay(version: office.version, month: month, day: nil)
                continue
            }
            state.heldOfficeDays[id] = nil
            let ref = ConnectSiteDayRef(siteID: office.siteID, date: office.date)
            let present = changes.save[ref] != nil || local[ref] != nil
            func delete() {
                changes.save[ref] = nil
                if present { changes.remove.insert(ref) }
                state.marks[key] = nil
            }
            if let mine = office.mine {
                if let day = mine.day {
                    // The phone's own day again, to be sent as a new one.
                    changes.save[ref] = day
                    if var mark = state.marks[key] {
                        mark.hash = ""
                        mark.adopts = nil
                        state.marks[key] = mark
                    }
                } else {
                    delete()
                }
            } else if !state.queue.contains(where: { $0.key == key }) {
                delete()
            }
            state.officeDays[id] = nil
            state.conflicts[key] = nil
        }
        return changes
    }

    /// Whether the local day already says what the office's does: the same
    /// people, hours and everything else, in whatever order they are named.
    static func says(_ local: SiteDay?, theSameAs office: SiteDay) -> Bool {
        guard let local else { return false }
        func ordered(_ day: SiteDay) -> SiteDay {
            var day = day
            day.present.sort { $0.memberID.uuidString < $1.memberID.uuidString }
            day.absences.sort { $0.memberID.uuidString < $1.memberID.uuidString }
            day.allowanceMemberIDs = Set(day.allowanceMemberIDs).sorted { $0.uuidString < $1.uuidString }
            return day
        }
        return ordered(local) == ordered(office)
    }

    /// The local id of a company person on a site: "You" for the paired
    /// person, else their row there, made (hidden) from the company's
    /// people when the site has none. Nil for someone the phone has never
    /// heard of.
    private static func localMember(
        _ text: String,
        on siteID: UUID,
        state: inout ConnectState,
        crew: inout [UUID: CrewMember],
        changedCrew: inout Set<UUID>
    ) -> UUID? {
        guard let personID = ConnectID.uuid(text) else { return nil }
        if personID == state.people.you { return CrewMember.youID }
        let name = state.people.company[personID]?.name ?? ""
        if let row = row(of: personID, named: name, on: siteID, crew: crew, people: state.people) {
            state.people.rows[row.id] = personID
            return row.id
        }
        guard !name.isEmpty else { return nil }
        let order = (crew.values.filter { $0.siteID == siteID }.map(\.sortOrder).max() ?? -1) + 1
        let made = CrewMember(
            id: ConnectUUID.crewRowID(siteID: siteID, personID: personID),
            siteID: siteID,
            name: name,
            isHidden: true,
            sortOrder: order
        )
        crew[made.id] = made
        changedCrew.insert(made.id)
        state.people.rows[made.id] = personID
        return made.id
    }

    /// The row that stands for a company person on a site: the one linked
    /// to them, else one of the same name that is nobody else's.
    static func row(of personID: UUID, named name: String, on siteID: UUID, crew: [UUID: CrewMember], people: ConnectPeople) -> CrewMember? {
        let onSite = crew.values.filter { $0.siteID == siteID }.sorted { $0.id.uuidString < $1.id.uuidString }
        if let linked = onSite.first(where: { people.rows[$0.id] == personID }) { return linked }
        guard !name.isEmpty else { return nil }
        let key = CrewCandidates.key(for: name)
        return onSite
            .filter { CrewCandidates.key(for: $0.name) == key }
            .first { member in
                guard let linked = people.rows[member.id] else { return true }
                return linked == member.id || !people.isCompanyPerson(linked)
            }
    }

    /// What is waiting to be taken outside a sync: the office's copy from
    /// an upload answered `conflict, editedOnWeb`, and days held for a month
    /// that has been reopened since.
    static func planPending(state: ConnectState, local: ConnectLocal, lock: MonthLock) -> ConnectMergePlan {
        var state = state
        var conflicts: [ConnectMergeConflict] = []
        var crew = Dictionary(local.crew.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changedCrew = Set<UUID>()
        let changes = takeOfficeDays(
            [],
            tombstones: [],
            state: &state,
            sites: Dictionary(local.sites.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }),
            crew: &crew,
            changedCrew: &changedCrew,
            localDays: local.siteDays,
            lock: lock,
            conflicts: &conflicts
        )
        state.lockedConflicts = Array((state.lockedConflicts + conflicts).suffix(50))
        return ConnectMergePlan(
            crew: changedCrew.sorted { $0.uuidString < $1.uuidString }.compactMap { crew[$0] },
            siteDays: changes.save.values.sorted { ($0.date, $0.siteID.uuidString) < ($1.date, $1.siteID.uuidString) },
            removedSiteDays: changes.remove.sorted { ($0.date, $0.siteID.uuidString) < ($1.date, $1.siteID.uuidString) },
            state: state,
            conflicts: conflicts
        )
    }
}

extension ConnectState {
    // MARK: - Office days

    /// What the office did with a day, if anything.
    func officeDay(siteID: UUID, date: CalendarDate) -> ConnectOfficeDay? {
        guard !officeDays.isEmpty else { return nil }
        return officeDays[ConnectSiteDayRef(siteID: siteID, date: date).id]
    }

    /// The days of a site that say "Written by the office" or "Changed by
    /// the office", for its month.
    func officeMarks(siteID: UUID) -> [CalendarDate: ConnectOfficeMark] {
        var marks: [CalendarDate: ConnectOfficeMark] = [:]
        for day in officeDays.values where day.siteID == siteID {
            if day.mine != nil {
                marks[day.date] = .changed
            } else if let mark = day.mark {
                marks[day.date] = mark
            }
        }
        return marks
    }

    /// Whether `planPending` has something to do: an office copy from a
    /// refused upload not taken yet, or a held day whose month is open.
    func hasOfficeDaysToTake(lock: MonthLock) -> Bool {
        for (id, conflict) in conflicts where officeDays[conflict.id]?.mine == nil && heldOfficeDays[conflict.id] == nil {
            if id.hasPrefix(ConnectV1.RecordKind.siteDay.rawValue + ":"), ConnectMerge.officeDay(in: conflict) != nil { return true }
        }
        return heldOfficeDays.values.contains { held in
            held.month.map { !lock.isLocked($0) } ?? false
        }
    }

    /// "Use the office's": the day already shows it; the phone's own edit
    /// is dropped.
    mutating func useOfficeDay(siteID: UUID, date: CalendarDate) {
        let id = ConnectSiteDayRef(siteID: siteID, date: date).id
        guard var office = officeDays[id], office.mine != nil else { return }
        office.mine = nil
        officeDays[id] = office
        conflicts[ConnectRecordKey.make(.siteDay, id)] = nil
    }

    /// "Keep mine": gives back the phone's own edit to be written again
    /// (a day, or nil inside for a day to delete). The next scan queues it
    /// as a new version on top of the office's: `baseVersion` is the
    /// office's version, so it wins.
    mutating func keepMine(siteID: UUID, date: CalendarDate) -> ConnectMine? {
        let id = ConnectSiteDayRef(siteID: siteID, date: date).id
        let key = ConnectRecordKey.make(.siteDay, id)
        guard var office = officeDays[id], let mine = office.mine else { return nil }
        office.mine = nil
        office.changedByOffice = false
        officeDays[id] = office.writtenByOffice && mine.day != nil ? office : nil
        conflicts[key] = nil
        if var mark = marks[key] {
            // Whatever the day is now, it is not what the server has.
            mark.hash = ""
            mark.adopts = nil
            mark.deleted = false
            marks[key] = mark
        }
        return mine
    }

    /// A site day the phone changed is being queued: it is the phone's
    /// again, built on the office's version.
    mutating func noteLocalEdit(ofSiteDay id: String, deleted: Bool) {
        guard var office = officeDays[id] else { return }
        let key = ConnectRecordKey.make(.siteDay, id)
        if conflicts[key]?.reason == ConnectMerge.editedOnWeb { conflicts[key] = nil }
        office.mine = nil
        office.changedByOffice = false
        officeDays[id] = office.writtenByOffice && !deleted ? office : nil
    }
}
