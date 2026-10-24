import Foundation
import SwiftData

/// Reads and writes sites, their crews and site days, and keeps your own
/// calendar in step with the site days.
///
/// Thin in the way `WorkdayRepository` is: it converts between SwiftData
/// entities and the engine's value types and owns the upsert and uniqueness
/// rules. What goes into your calendar is decided by `SiteCalendarSync`, not
/// here — this only makes sure it is written every time a site day is.
///
/// Always constructed from a view's `modelContext` and therefore always used
/// on the main actor; it holds a `ModelContext`, which must not be shared
/// across threads.
struct SiteRepository {
    let context: ModelContext

    /// Which months refuse edits. One lock covers site days and personal days
    /// alike, and it is handed on to the `WorkdayRepository` that writes your
    /// calendar day, so the two can never disagree about whether a month is
    /// closed. `Scripts/check-repository-lock.py` stops a writing path from
    /// building this without one.
    let lock: MonthLock

    init(context: ModelContext, lock: MonthLock = .unlocked) {
        self.context = context
        self.lock = lock
    }

    // MARK: - Sites

    /// Sites in the order the user arranged them.
    func sites(includeArchived: Bool) -> [Site] {
        let descriptor = FetchDescriptor<SiteEntry>(
            sortBy: [SortDescriptor(\SiteEntry.sortOrder), SortDescriptor(\SiteEntry.name)]
        )
        let entries = firstOfEach(deduplicatedSites(fetch(descriptor)), by: \.siteID)
        let all = entries.map(\.site)
        return includeArchived ? all : all.filter { !$0.isArchived }
    }

    func site(id: UUID) -> Site? {
        siteEntries(id: id).first?.site
    }

    /// Creates or updates a site. Not checked against the month lock: a site
    /// is not dated, and the job a recorded day counts towards is frozen on the
    /// day itself, so editing a site never reaches into a closed month.
    func upsert(_ site: Site) {
        if let existing = siteEntries(id: site.id).first {
            existing.apply(site)
        } else {
            context.insert(SiteEntry(site: site))
        }
        persist()
    }

    private func siteEntries(id: UUID) -> [SiteEntry] {
        let key = id.uuidString
        let descriptor = FetchDescriptor<SiteEntry>(predicate: #Predicate<SiteEntry> { $0.siteID == key })
        return deduplicatedSites(fetch(descriptor))
    }

    // MARK: - Crew

    /// A site's crew in the order the user arranged them. Hidden members are
    /// left out of what is offered for a new day, but past days still name
    /// them, which is why they are hidden rather than deleted.
    func crew(for siteID: UUID, includeHidden: Bool) -> [CrewMember] {
        let key = siteID.uuidString
        let descriptor = FetchDescriptor<CrewMemberEntry>(
            predicate: #Predicate<CrewMemberEntry> { $0.siteID == key },
            sortBy: [SortDescriptor(\CrewMemberEntry.sortOrder), SortDescriptor(\CrewMemberEntry.name)]
        )
        let entries = firstOfEach(deduplicatedCrew(fetch(descriptor)), by: \.memberID)
        let all = entries.map(\.member)
        return includeHidden ? all : all.filter { !$0.isHidden }
    }

    /// Creates or updates a crew member. Unlocked for the reason `upsert(_:)`
    /// for a site is: a name is not an edit to anybody's hours.
    func upsert(_ member: CrewMember) {
        let key = member.id.uuidString
        let descriptor = FetchDescriptor<CrewMemberEntry>(predicate: #Predicate<CrewMemberEntry> { $0.memberID == key })
        if let existing = deduplicatedCrew(fetch(descriptor)).first {
            existing.apply(member)
        } else {
            context.insert(CrewMemberEntry(member: member))
        }
        persist()
    }

    // MARK: - Reading site days

    /// The site's day on a date, and only one.
    ///
    /// Collapses duplicates on the spot, as `WorkdayRepository.entry(on:)`
    /// does, and brings your calendar day back in step with whichever row won.
    func siteDay(siteID: UUID, on date: CalendarDate) -> SiteDay? {
        let id = siteID.uuidString
        let key = date.key
        let descriptor = FetchDescriptor<SiteDayEntry>(
            predicate: #Predicate<SiteDayEntry> { $0.siteID == id && $0.dateKey == key }
        )
        return deduplicatedDays(fetch(descriptor)).first?.siteDay
    }

    /// Site days in a range, by date and then site. `nil` means every site.
    func siteDays(siteID: UUID?, in range: CalendarDateRange) -> [SiteDay] {
        let lower = range.start.key
        let upper = range.end.key
        let predicate: Predicate<SiteDayEntry>
        if let siteID {
            let id = siteID.uuidString
            predicate = #Predicate<SiteDayEntry> { $0.siteID == id && $0.dateKey >= lower && $0.dateKey <= upper }
        } else {
            predicate = #Predicate<SiteDayEntry> { $0.dateKey >= lower && $0.dateKey <= upper }
        }
        let descriptor = FetchDescriptor<SiteDayEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\SiteDayEntry.dateKey), SortDescriptor(\SiteDayEntry.siteID)]
        )
        return firstOfEach(deduplicatedDays(fetch(descriptor)), by: \.identity).map(\.siteDay)
    }

    /// The most recent day recorded on the site before `date`.
    func lastSiteDay(siteID: UUID, before date: CalendarDate) -> SiteDay? {
        let id = siteID.uuidString
        let key = date.key
        var descriptor = FetchDescriptor<SiteDayEntry>(
            predicate: #Predicate<SiteDayEntry> { $0.siteID == id && $0.dateKey < key },
            sortBy: [SortDescriptor(\SiteDayEntry.dateKey, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        // Only the date is taken from this row: it may be a duplicate that the
        // read below removes, and that read is the one that picks the winner.
        guard
            let latest = fetch(descriptor).first,
            let latestDate = CalendarDate(key: latest.dateKey)
        else { return nil }
        return siteDay(siteID: siteID, on: latestDate)
    }

    /// "Same as last day": a new, unsaved day on `date` filled from the most
    /// recent earlier day on the site. `nil` when there is none.
    ///
    /// The site's times, its break and who was there carry over; each
    /// person's exceptions do not, because someone leaving early is a fact
    /// about that day rather than about the crew. The note stays behind for the
    /// same reason. The job is the site's job now, not the copied day's,
    /// because a new day freezes the job as it stands when it is written.
    ///
    /// Someone hidden from the crew since is left out: hidden means no longer
    /// offered for a new day, and copying them in would record a person who
    /// has left as present, on the director's sheet. "You" is never a stored
    /// member, so it is never hidden and always carries over.
    ///
    /// Who got the field allowance carries over with them, and so do the
    /// vehicle's kilometres: the same crew driving to the same site.
    ///
    /// Not saved here: the caller shows it in the editor and saving is the
    /// person's decision, which is also where the month lock gets its say.
    func sameAsLastDay(siteID: UUID, on date: CalendarDate) -> SiteDay? {
        guard let last = lastSiteDay(siteID: siteID, before: date) else { return nil }
        let hidden = Set(crew(for: siteID, includeHidden: true).filter(\.isHidden).map(\.id))
        let present = last.present
            .filter { !hidden.contains($0.memberID) }
            .map { Attendance(memberID: $0.memberID) }
        return SiteDay(
            siteID: siteID,
            date: date,
            start: last.start,
            end: last.end,
            breakMinutes: last.breakMinutes,
            present: present,
            jobID: site(id: siteID)?.jobID,
            allowanceMemberIDs: present.map(\.memberID).filter(last.hasAllowance(for:)),
            kilometres: last.kilometres
        )
    }

    // MARK: - Writing site days

    /// Writes a site day and, with it, your own calendar day for that date.
    /// Throws `MonthLock.Refusal` when the date falls in a closed month.
    ///
    /// The two writes are one operation, because the failure this exists to
    /// prevent is the site and your calendar disagreeing about your hours. So
    /// the lock is checked before anything is touched — a refusal leaves both
    /// stores exactly as they were, with nothing pending in the context
    /// either — and everything is read before anything is written, so no read
    /// that tidies up a duplicate can save the site day ahead of the calendar
    /// day. The calendar day is then written through `WorkdayRepository` with
    /// the same lock, and one `context.save()` carries both.
    ///
    /// Your calendar day is rebuilt from every site's day on that date, not
    /// only this one: you can work on two sites in a day, and saving one must
    /// not drop the other's shift.
    func save(_ day: SiteDay) throws {
        try lock.check(day.date)
        let workdays = WorkdayRepository(context: context, lock: lock)
        let personal = workdays.record(on: day.date)
        let onThatDate = siteDayEntries(on: day.date)
        let id = day.siteID.uuidString

        let others = firstOfEach(onThatDate.filter { $0.siteID != id }, by: \.identity).map(\.siteDay)
        try carryIntoCalendar(
            on: day.date,
            personal: personal,
            siteDays: inSiteOrder(others + [day]),
            previous: firstOfEach(onThatDate, by: \.identity).map(\.siteDay),
            through: workdays,
            afterWriting: {
                if let existing = onThatDate.first(where: { $0.siteID == id }) {
                    existing.apply(day)
                } else {
                    context.insert(SiteDayEntry(day: day))
                }
            }
        )
        persist()
    }

    /// Removes a site day and its shift from your calendar. Anything else on
    /// your calendar day — your own shifts, a note, another site — stays; a
    /// calendar day left with nothing in it goes. Throws `MonthLock.Refusal`
    /// when the date falls in a closed month.
    func delete(siteID: UUID, on date: CalendarDate) throws {
        try lock.check(date)
        let workdays = WorkdayRepository(context: context, lock: lock)
        let personal = workdays.record(on: date)
        let onThatDate = siteDayEntries(on: date)
        let id = siteID.uuidString

        let others = firstOfEach(onThatDate.filter { $0.siteID != id }, by: \.identity).map(\.siteDay)
        try carryIntoCalendar(
            on: date,
            personal: personal,
            siteDays: others,
            previous: firstOfEach(onThatDate, by: \.identity).map(\.siteDay),
            through: workdays,
            afterWriting: {
                // Every row for the site, including one tied with the
                // survivor: the person asked for the day to go, not for one
                // copy of it to.
                for entry in onThatDate where entry.siteID == id { context.delete(entry) }
            }
        )
        persist()
    }

    /// Every site day on a date, across all sites, duplicates collapsed but
    /// the calendar left alone — the caller is about to write it.
    private func siteDayEntries(on date: CalendarDate) -> [SiteDayEntry] {
        let key = date.key
        let descriptor = FetchDescriptor<SiteDayEntry>(
            predicate: #Predicate<SiteDayEntry> { $0.dateKey == key },
            sortBy: [SortDescriptor(\SiteDayEntry.siteID)]
        )
        return deduplicatedDays(fetch(descriptor), followingCalendar: false)
    }

    /// Applies `write` to the site days, then writes the personal day that
    /// `SiteCalendarSync` makes of them, or deletes it when nothing is left.
    ///
    /// The site write is passed in rather than done first so that it happens
    /// after every read and immediately before the calendar write. A personal
    /// day that comes out unchanged is not written at all, so saving a day you
    /// were not on does not stamp your calendar day as edited and send it
    /// round sync for nothing.
    ///
    /// `previous` is every site day on the date as it stood before this
    /// write, which is how a lifted bad-weather stop takes the Bad weather
    /// type it put on your day back off (see `SiteCalendarSync.merged`).
    private func carryIntoCalendar(
        on date: CalendarDate,
        personal: DayRecord?,
        siteDays: [SiteDay],
        previous: [SiteDay] = [],
        through workdays: WorkdayRepository,
        afterWriting write: () -> Void
    ) throws {
        let merged = SiteCalendarSync.merged(personal: personal, siteDays: siteDays, on: date, previousSiteDays: previous)
        write()
        guard merged != personal else { return }
        if let merged {
            try workdays.save(merged)
        } else {
            try workdays.delete(on: date)
        }
    }

    /// Sorted by site so the shifts land in your calendar day in the same
    /// order every time, and re-merging an unchanged day yields an equal
    /// record rather than a reshuffled one.
    private func inSiteOrder(_ days: [SiteDay]) -> [SiteDay] {
        days.sorted { $0.siteID.uuidString < $1.siteID.uuidString }
    }

    // MARK: - Restore

    /// Makes the given sites, crew and site days the whole of the site data,
    /// as a restore does.
    ///
    /// Not checked against the month lock, for the reason the existing
    /// restore is not: a restore is the file becoming the database, not an
    /// edit to a closed month. Your calendar's site shifts are not touched
    /// here; the restore rebuilds them from the result with
    /// `SiteCalendarSync.rebuilt` once the personal days are in too.
    ///
    /// A file holding the same thing twice keeps the first, as
    /// `SiteCalendarSync` does, so a restore never creates a duplicate.
    func replaceAll(sites: [Site], crew: [CrewMember], siteDays: [SiteDay]) {
        for entry in fetch(FetchDescriptor<SiteDayEntry>()) { context.delete(entry) }
        for entry in fetch(FetchDescriptor<CrewMemberEntry>()) { context.delete(entry) }
        for entry in fetch(FetchDescriptor<SiteEntry>()) { context.delete(entry) }

        var seenSites = Set<UUID>()
        for site in sites where seenSites.insert(site.id).inserted {
            context.insert(SiteEntry(site: site))
        }
        var seenMembers = Set<UUID>()
        for member in crew where seenMembers.insert(member.id).inserted {
            context.insert(CrewMemberEntry(member: member))
        }
        var seenDays = Set<SiteDayIdentity>()
        for day in siteDays where seenDays.insert(SiteDayIdentity(siteID: day.siteID.uuidString, dateKey: day.date.key)).inserted {
            context.insert(SiteDayEntry(day: day))
        }
        persist()
    }

    // MARK: - Duplicates

    /// Removes duplicate sites, crew members and site days, keeping the one
    /// edited most recently, and brings your calendar back in step with every
    /// site day that changed. Returns how many rows went.
    ///
    /// Only sync creates these, exactly as for `WorkdayRepository`, and the
    /// rule is the same: last edit wins, and rows nothing can tell apart are
    /// all kept (see `ModelContext.collapseDuplicates`).
    ///
    /// The calendar is rewritten without the month lock. This is not an edit
    /// — the site day that won is one somebody already wrote, and the lock
    /// does not stop the losing row going any more than it does for a
    /// personal day. Leaving the calendar on the loser's hours would be the
    /// one outcome worse than either: your calendar and the site disagreeing.
    @discardableResult
    func reconcileDuplicates() -> Int {
        let before = rowCount()
        _ = deduplicatedSites(fetch(FetchDescriptor<SiteEntry>()))
        _ = deduplicatedCrew(fetch(FetchDescriptor<CrewMemberEntry>()))
        _ = deduplicatedDays(fetch(FetchDescriptor<SiteDayEntry>()))
        return max(0, before - rowCount())
    }

    private func rowCount() -> Int {
        let sites = (try? context.fetchCount(FetchDescriptor<SiteEntry>())) ?? 0
        let crew = (try? context.fetchCount(FetchDescriptor<CrewMemberEntry>())) ?? 0
        let days = (try? context.fetchCount(FetchDescriptor<SiteDayEntry>())) ?? 0
        return sites + crew + days
    }

    private func deduplicatedSites(_ entries: [SiteEntry]) -> [SiteEntry] {
        // Sites carry no createdAt, so the last edit is all there is.
        context.collapseDuplicates(entries, by: \.siteID) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.updatedAt)
        }.kept
    }

    private func deduplicatedCrew(_ entries: [CrewMemberEntry]) -> [CrewMemberEntry] {
        context.collapseDuplicates(entries, by: \.memberID) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.updatedAt)
        }.kept
    }

    /// Collapses duplicate site days and, unless the caller is about to do it
    /// itself, rewrites your calendar day on every date that lost a row.
    ///
    /// Without that second step the calendar could keep the losing row's
    /// hours: each device wrote its own site day and its own calendar day,
    /// and the two sides reconcile separately, so nothing guarantees the same
    /// device wins both.
    private func deduplicatedDays(_ entries: [SiteDayEntry], followingCalendar: Bool = true) -> [SiteDayEntry] {
        let result = context.collapseDuplicates(entries, by: \.identity) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt)
        }
        if followingCalendar, !result.removed.isEmpty {
            bringCalendarInStep(onDateKeys: Set(result.removed.map(\.dateKey)))
        }
        return result.kept
    }

    private func bringCalendarInStep(onDateKeys keys: Set<Int>) {
        // Deliberately unlocked; see `reconcileDuplicates`.
        let workdays = WorkdayRepository(context: context, lock: .unlocked)
        for key in keys.sorted() {
            guard let date = CalendarDate(key: key) else { continue }
            let personal = workdays.record(on: date)
            let siteDays = firstOfEach(siteDayEntries(on: date), by: \.identity).map(\.siteDay)
            // An unlocked repository never refuses, so there is nothing to catch.
            try? carryIntoCalendar(on: date, personal: personal, siteDays: siteDays, through: workdays, afterWriting: {})
        }
        persist()
    }

    /// Drops later rows that share an identity with an earlier one, without
    /// deleting anything. Only ever does something when a tie was kept,
    /// and keeps the screens from showing one site or one day twice.
    private func firstOfEach<Model, Key: Hashable>(_ models: [Model], by key: KeyPath<Model, Key>) -> [Model] {
        var seen = Set<Key>()
        return models.filter { seen.insert($0[keyPath: key]).inserted }
    }

    // MARK: - Saving

    private func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> [Model] {
        (try? context.fetch(descriptor)) ?? []
    }

    /// As in `WorkdayRepository`: SwiftData autosaves, but an explicit save
    /// after each edit means a crash can never lose a day just entered.
    private func persist() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}

/// What makes two site-day rows the same day: one site, one date.
struct SiteDayIdentity: Hashable {
    let siteID: String
    let dateKey: Int
}

extension SiteDayEntry {
    var identity: SiteDayIdentity {
        SiteDayIdentity(siteID: siteID, dateKey: dateKey)
    }
}
