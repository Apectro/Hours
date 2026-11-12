import Foundation

/// What the phone holds that a sync can change: its sites, every crew row
/// (hidden ones too), the sites' setups and the dates each site has days on.
struct ConnectLocal: Sendable {
    var sites: [Site]
    var crew: [CrewMember]
    var setups: [UUID: SiteSetup]
    var writtenDates: [UUID: Set<CalendarDate>]

    init(sites: [Site], crew: [CrewMember], setups: [UUID: SiteSetup] = [:], writtenDates: [UUID: Set<CalendarDate>] = [:]) {
        self.sites = sites
        self.crew = crew
        self.setups = setups
        self.writtenDates = writtenDates
    }
}

/// Something a sync did not do, or did only in part, because a month on
/// the phone is closed. Written days are never changed by a sync; these
/// are what the office should hear about.
struct ConnectMergeConflict: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// The office returned a record of a closed month: the month must be
        /// reopened on the phone to correct it.
        case returnedInClosedMonth
        /// The office removed a site with days in a closed month: archived,
        /// its days kept.
        case siteRemovedWithClosedMonth
        /// The office removed a person with days in a closed month: hidden,
        /// their days kept.
        case personRemovedWithClosedMonth
    }

    var kind: Kind
    var recordKind: ConnectV1.RecordKind
    var id: String
    var month: String
}

/// What to write after a sync page: the sites, setups and crew rows that
/// change, and the state to keep once they are written.
struct ConnectMergePlan: Sendable {
    var sites: [Site] = []
    var setups: [UUID: SiteSetup] = [:]
    var crew: [CrewMember] = []
    var state: ConnectState
    var conflicts: [ConnectMergeConflict] = []

    var changesStore: Bool { !sites.isEmpty || !setups.isEmpty || !crew.isEmpty }
}

/// Receiving (web → phone): one page of `GET /v1/device/sync`, merged into
/// what the phone has.
///
/// - Sites, people and assignments are upserts by id. A web site becomes a
///   site here with the web's id, name, address, work days, usual day and
///   pause; its name and address are the web's again at every sync, so a
///   local rename lasts until then. Everything else about it (sort order,
///   the arrival reminder, the job) stays the phone's.
/// - Each assignment becomes a crew row on its site, linked to the person:
///   an existing row of the same name is linked rather than doubled, else a
///   row is made with a name-based id. The paired person is "You" and gets
///   no row.
/// - Tombstones archive a site and hide a person's rows; nothing written is
///   ever deleted. A full snapshot does the same to whatever it no longer
///   holds, once its last page is in.
/// - Comments and reviews are kept for the screens; a review's version
///   becomes the record's base version.
/// - Days are never touched. What a closed month stops is listed in
///   `conflicts`.
enum ConnectMerge {
    static func plan(
        _ page: ConnectV1.SyncResponse,
        state: ConnectState,
        local: ConnectLocal,
        lock: MonthLock,
        today: CalendarDate,
        now: Date
    ) -> ConnectMergePlan {
        var state = state
        var conflicts: [ConnectMergeConflict] = []
        var sites = Dictionary(local.sites.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var setups = local.setups
        var crew = Dictionary(local.crew.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changedSites = Set<UUID>()
        var changedSetups = Set<UUID>()
        var changedCrew = Set<UUID>()

        // A snapshot replaces: what it holds is everything the web has.
        if page.full {
            state.snapshot = ConnectSnapshotSeen()
        }
        if var seen = state.snapshot {
            seen.sites.formUnion(page.sites.compactMap { ConnectID.uuid($0.id) })
            seen.people.formUnion(page.crew.compactMap { ConnectID.uuid($0.id) })
            seen.assignments.formUnion(page.assignments.map { $0.id.lowercased() })
            state.snapshot = seen
        }

        // MARK: People

        for person in page.crew {
            guard let id = ConnectID.uuid(person.id) else { continue }
            state.people.company[id] = ConnectPeople.ConnectPerson(name: person.name, hidden: person.hidden)
        }

        // MARK: Sites

        var nextSortOrder = (local.sites.map(\.sortOrder).max() ?? -1) + 1
        for remote in page.sites {
            guard let id = ConnectID.uuid(remote.id) else { continue }
            state.companySites.insert(id)
            state.siteCopies[id] = remote
            if sites[id] == nil {
                sites[id] = Site(id: id, name: remote.name, sortOrder: nextSortOrder)
                nextSortOrder += 1
                changedSites.insert(id)
            }
            let setup = setups[id] ?? SiteSetup()
            let updated = applying(remote, to: setup)
            if updated != setup {
                setups[id] = updated
                changedSetups.insert(id)
            }
        }
        // The web's name and address again for every web site, and its
        // archived flag: a local edit lasts until the next sync.
        for (id, remote) in state.siteCopies {
            guard var site = sites[id] else { continue }
            let before = site
            site.name = remote.name.isEmpty ? site.name : remote.name
            site.address = remote.address
            site.allowanceByDefault = remote.allowanceByDefault
            site.isArchived = remote.archived
            if site != before {
                sites[id] = site
                changedSites.insert(id)
            }
        }

        // MARK: Assignments

        let you = state.people.you
        for assignment in page.assignments {
            guard let siteID = ConnectID.uuid(assignment.siteId),
                  let personID = ConnectID.uuid(assignment.memberId) else { continue }
            var mark = ConnectAssignmentMark(siteID: siteID, personID: personID, rowID: nil)
            defer { state.assignments[assignment.id.lowercased()] = mark }
            guard personID != you, sites[siteID] != nil else { continue }
            let person = state.people.company[personID]
            let name = person?.name ?? ""
            let ended = ConnectFormat.parseDate(assignment.to).map { $0 < today } ?? false
            let hidden = (person?.hidden ?? false) || ended

            let onSite = crew.values.filter { $0.siteID == siteID }
            var row = onSite.first { state.people.rows[$0.id] == personID }
            if row == nil, !name.isEmpty {
                let key = CrewCandidates.key(for: name)
                row = onSite
                    .filter { CrewCandidates.key(for: $0.name) == key }
                    .filter { member in
                        guard let linked = state.people.rows[member.id] else { return true }
                        return linked == member.id || !state.people.isCompanyPerson(linked)
                    }
                    .sorted { $0.id.uuidString < $1.id.uuidString }
                    .first
            }
            if var existing = row {
                let before = existing
                state.people.rows[existing.id] = personID
                if !name.isEmpty { existing.name = name }
                existing.isHidden = hidden
                if existing != before {
                    crew[existing.id] = existing
                    changedCrew.insert(existing.id)
                }
                mark.rowID = existing.id
            } else if !name.isEmpty {
                let order = (onSite.map(\.sortOrder).max() ?? -1) + 1
                let made = CrewMember(
                    id: ConnectUUID.crewRowID(siteID: siteID, personID: personID),
                    siteID: siteID,
                    name: name,
                    isHidden: hidden,
                    sortOrder: order
                )
                crew[made.id] = made
                changedCrew.insert(made.id)
                state.people.rows[made.id] = personID
                mark.rowID = made.id
            }
        }

        // A person renamed or hidden on the web: every row of theirs.
        for person in page.crew {
            guard let personID = ConnectID.uuid(person.id) else { continue }
            for (rowID, linked) in state.people.rows where linked == personID {
                guard var row = crew[rowID] else { continue }
                let before = row
                row.name = person.name
                if person.hidden { row.isHidden = true }
                if row != before {
                    crew[rowID] = row
                    changedCrew.insert(rowID)
                }
            }
        }

        // MARK: Removals

        var removedSites: [UUID] = []
        var removedPeople: [UUID] = []
        var removedAssignments: [String] = []
        for tombstone in page.tombstones {
            switch tombstone.kind {
            case .site: ConnectID.uuid(tombstone.id).map { removedSites.append($0) }
            case .crewMember: ConnectID.uuid(tombstone.id).map { removedPeople.append($0) }
            case .assignment: removedAssignments.append(tombstone.id.lowercased())
            case .comment: state.comments[tombstone.id.lowercased()] = nil
            default: break
            }
        }
        if let seen = state.snapshot, !page.hasMore {
            removedSites += state.companySites.subtracting(seen.sites).sorted { $0.uuidString < $1.uuidString }
            removedPeople += Set(state.people.company.keys).subtracting(seen.people).sorted { $0.uuidString < $1.uuidString }
            removedAssignments += Set(state.assignments.keys).subtracting(seen.assignments).sorted()
            state.snapshot = nil
        }

        for siteID in removedSites {
            state.siteCopies[siteID] = nil
            if var site = sites[siteID], !site.isArchived {
                site.isArchived = true
                sites[siteID] = site
                changedSites.insert(siteID)
            }
            if let month = closedMonth(in: local.writtenDates[siteID] ?? [], lock: lock) {
                conflicts.append(ConnectMergeConflict(kind: .siteRemovedWithClosedMonth, recordKind: .site, id: ConnectID.string(siteID), month: month))
            }
        }
        for personID in removedPeople {
            state.people.company[personID] = nil
            for (rowID, linked) in state.people.rows where linked == personID {
                guard var row = crew[rowID] else { continue }
                if !row.isHidden {
                    row.isHidden = true
                    crew[rowID] = row
                    changedCrew.insert(rowID)
                }
                let dates = local.writtenDates[row.siteID] ?? []
                if let month = closedMonth(in: dates, lock: lock) {
                    conflicts.append(ConnectMergeConflict(kind: .personRemovedWithClosedMonth, recordKind: .crewMember, id: ConnectID.string(personID), month: month))
                }
            }
        }
        for assignmentID in removedAssignments {
            guard let mark = state.assignments.removeValue(forKey: assignmentID), let rowID = mark.rowID else { continue }
            // Still on the site through another assignment: stays.
            let stillThere = state.assignments.values.contains { $0.rowID == rowID }
            guard !stillThere, var row = crew[rowID], !row.isHidden else { continue }
            row.isHidden = true
            crew[rowID] = row
            changedCrew.insert(rowID)
        }

        // MARK: Comments and reviews

        for comment in page.comments {
            state.comments[comment.id.lowercased()] = comment
        }
        for review in page.reviews {
            let key = ConnectRecordKey.make(review.kind, review.id)
            state.reviews[key] = ConnectReview(
                kind: review.kind,
                id: review.id.lowercased(),
                version: review.version,
                state: review.state,
                changedAt: review.changedAt,
                commentIDs: review.commentIds.map { $0.lowercased() }
            )
            if var mark = state.marks[key] {
                mark.baseVersion = max(mark.baseVersion, review.version)
                state.marks[key] = mark
            }
            if review.state == "returned", let month = month(ofReturned: review, state: state), lock.isLocked(month) {
                conflicts.append(ConnectMergeConflict(kind: .returnedInClosedMonth, recordKind: review.kind, id: review.id.lowercased(), month: ConnectFormat.month(month)))
            }
        }

        // MARK: Who is who, and the rest

        let allCrew = Array(crew.values)
        state.people = state.people.linking(allCrew)
        state.cursor = page.cursor
        state.lastSyncedAt = now
        state.lockedConflicts = Array((state.lockedConflicts + conflicts).suffix(50))

        return ConnectMergePlan(
            sites: changedSites.sorted { $0.uuidString < $1.uuidString }.compactMap { sites[$0] },
            setups: Dictionary(uniqueKeysWithValues: changedSetups.compactMap { id in setups[id].map { (id, $0) } }),
            crew: changedCrew.sorted { $0.uuidString < $1.uuidString }.compactMap { crew[$0] },
            state: state,
            conflicts: conflicts
        )
    }

    /// A web site's work days, usual day and pause in the site's setup.
    /// What the web leaves out (no usual day, no work days) stays the
    /// phone's.
    static func applying(_ remote: ConnectV1.Site, to setup: SiteSetup) -> SiteSetup {
        var setup = setup
        if let usual = remote.usualDay,
           let start = ConnectFormat.parseTime(usual.start),
           let end = ConnectFormat.parseTime(usual.end) {
            setup.start = start
            setup.end = end
            setup.breakMinutes = max(0, usual.breakMinutes)
        }
        let days = Set(remote.workDays.filter { (1...7).contains($0) })
        if !days.isEmpty { setup.workDays = days }
        if let pause = remote.pause, let start = ConnectFormat.parseDate(pause.start) {
            setup.pause = SitePause(start: start, end: ConnectFormat.parseDate(pause.end))
        } else {
            setup.pause = nil
        }
        return setup
    }

    /// The month of a returned record, from what was sent: a site day's
    /// date, a sheet's or sign-off's month.
    private static func month(ofReturned review: ConnectV1.Review, state: ConnectState) -> YearMonth? {
        let key = ConnectRecordKey.make(review.kind, review.id)
        let data = state.queue.first { $0.key == key }?.data ?? state.conflicts[key]?.server
        if let month = data?["month"]?.stringValue { return ConnectFormat.parseMonth(month) }
        if let date = data?["date"]?.stringValue { return ConnectFormat.parseDate(date)?.yearMonth }
        return state.marks[key]?.month
    }

    private static func closedMonth(in dates: Set<CalendarDate>, lock: MonthLock) -> String? {
        dates.map(\.yearMonth).filter { lock.isLocked($0) }.min().map(ConnectFormat.month)
    }
}
