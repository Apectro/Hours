import Foundation
import SwiftData

/// Reads and writes days and holidays.
///
/// Deliberately thin: it converts between SwiftData entities and the value
/// types the calculation engine speaks, and owns the upsert rule. It contains
/// no arithmetic of its own.
///
/// Always constructed from a view's `modelContext` and therefore always used
/// on the main actor; it holds a `ModelContext`, which must not be shared
/// across threads.
struct WorkdayRepository {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Reading days

    /// The entry for a day, and only one.
    ///
    /// No fetch limit, deliberately: with sync on, two devices can each create
    /// the day while offline and both rows arrive. Taking the first would mean
    /// the app showed one of them and silently edited the other on the next
    /// save. Instead the newest wins and the rest are removed on the spot, so a
    /// duplicate lives exactly until the day is next looked at.
    func entry(on date: CalendarDate) -> DayEntry? {
        let key = date.key
        let descriptor = FetchDescriptor<DayEntry>(predicate: #Predicate<DayEntry> { $0.dateKey == key })
        guard let matches = try? context.fetch(descriptor), !matches.isEmpty else { return nil }
        guard matches.count > 1 else { return matches[0] }
        return resolve(matches)
    }

    func entries(in range: CalendarDateRange) -> [DayEntry] {
        let lower = range.start.key
        let upper = range.end.key
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate<DayEntry> { $0.dateKey >= lower && $0.dateKey <= upper },
            sortBy: [SortDescriptor(\DayEntry.dateKey)]
        )
        return deduplicated((try? context.fetch(descriptor)) ?? [])
    }

    func allEntries() -> [DayEntry] {
        let descriptor = FetchDescriptor<DayEntry>(sortBy: [SortDescriptor(\DayEntry.dateKey)])
        return deduplicated((try? context.fetch(descriptor)) ?? [])
    }

    func record(on date: CalendarDate) -> DayRecord? {
        entry(on: date)?.record
    }

    /// Records for a range, keyed by date key for O(1) lookup while building a
    /// month of cells.
    func records(in range: CalendarDateRange) -> [Int: DayRecord] {
        var result: [Int: DayRecord] = [:]
        for entry in entries(in: range) {
            result[entry.dateKey] = entry.record
        }
        return result
    }

    /// The earliest and latest day that carry data, used to bound "all time".
    func recordedDateBounds() -> (first: CalendarDate, last: CalendarDate)? {
        var ascending = FetchDescriptor<DayEntry>(sortBy: [SortDescriptor(\DayEntry.dateKey, order: .forward)])
        ascending.fetchLimit = 1
        var descending = FetchDescriptor<DayEntry>(sortBy: [SortDescriptor(\DayEntry.dateKey, order: .reverse)])
        descending.fetchLimit = 1
        guard
            let first = (try? context.fetch(ascending))?.first,
            let last = (try? context.fetch(descending))?.first,
            let firstDate = CalendarDate(key: first.dateKey),
            let lastDate = CalendarDate(key: last.dateKey)
        else { return nil }
        return (firstDate, lastDate)
    }

    // MARK: - Writing days

    /// Creates, updates, or deletes the day so that storage always reflects the
    /// record exactly. A record with nothing in it is deleted rather than
    /// stored, which is what keeps the calendar's "has data" marks honest.
    @discardableResult
    func save(_ record: DayRecord) -> DayEntry? {
        let existing = entry(on: record.date)

        if record.isBlank {
            if let existing { context.delete(existing) }
            persist()
            return nil
        }

        let entry = existing ?? DayEntry(dateKey: record.date.key)
        if existing == nil { context.insert(entry) }
        entry.apply(record)
        persist()
        return entry
    }

    func delete(on date: CalendarDate) {
        guard let existing = entry(on: date) else { return }
        context.delete(existing)
        persist()
    }

    func deleteAllDays() {
        for entry in allEntries() { context.delete(entry) }
        persist()
    }

    // MARK: - Holidays

    func holidayRecords() -> [HolidayRecord] {
        let descriptor = FetchDescriptor<HolidayRecord>(sortBy: [SortDescriptor(\HolidayRecord.name)])
        return deduplicatedHolidays((try? context.fetch(descriptor)) ?? [])
    }

    func holidayRules() -> [HolidayRule] {
        holidayRecords().map(\.rule)
    }

    func upsert(_ rule: HolidayRule) {
        let identifier = rule.id
        let descriptor = FetchDescriptor<HolidayRecord>(predicate: #Predicate<HolidayRecord> { $0.identifier == identifier })
        let matches = deduplicatedHolidays((try? context.fetch(descriptor)) ?? [])
        if let existing = matches.first {
            existing.apply(rule)
        } else {
            context.insert(HolidayRecord(rule: rule))
        }
        persist()
    }

    func deleteHoliday(id: UUID) {
        let descriptor = FetchDescriptor<HolidayRecord>(predicate: #Predicate<HolidayRecord> { $0.identifier == id })
        let matches = (try? context.fetch(descriptor)) ?? []
        guard !matches.isEmpty else { return }
        for existing in matches { context.delete(existing) }
        persist()
    }

    func deleteAllHolidays() {
        for record in holidayRecords() { context.delete(record) }
        persist()
    }

    // MARK: - Duplicates

    /// Removes duplicate days, keeping the one edited most recently.
    ///
    /// Only sync can create these. Without it the app is one process on one
    /// device writing on the main actor, and the repository never inserts a day
    /// it has not just failed to find. With it, two devices offline on the same
    /// Tuesday each create one and CloudKit merges both in — it has no idea
    /// they mean the same thing.
    ///
    /// Last edit wins rather than any attempt to merge the two: hours are not
    /// meaningfully mergeable — a start time from one device and an end time
    /// from another would invent a shift neither person worked — and the losing
    /// row's contents are what the older device already showed as replaced.
    @discardableResult
    func reconcileDuplicates() -> Int {
        let before = (try? context.fetchCount(FetchDescriptor<DayEntry>())) ?? 0
        _ = allEntries()
        _ = holidayRecords()
        let after = (try? context.fetchCount(FetchDescriptor<DayEntry>())) ?? 0
        return max(0, before - after)
    }

    private func deduplicated(_ entries: [DayEntry]) -> [DayEntry] {
        var byKey: [Int: [DayEntry]] = [:]
        for entry in entries { byKey[entry.dateKey, default: []].append(entry) }
        guard byKey.contains(where: { $0.value.count > 1 }) else { return entries }

        var survivors: Set<PersistentIdentifier> = []
        for (_, group) in byKey where group.count > 1 {
            survivors.insert(resolve(group).persistentModelID)
        }
        persist()
        return entries.filter { entry in
            byKey[entry.dateKey]?.count == 1 || survivors.contains(entry.persistentModelID)
        }
    }

    /// Keeps the newest of a group and deletes the rest.
    private func resolve(_ group: [DayEntry]) -> DayEntry {
        // `updatedAt` first, then creation, then the identifier — so that two
        // rows saved in the same second still resolve the same way on every
        // device rather than each keeping a different one.
        let ordered = group.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.persistentModelID.hashValue > $1.persistentModelID.hashValue
        }
        for loser in ordered.dropFirst() { context.delete(loser) }
        return ordered[0]
    }

    private func deduplicatedHolidays(_ records: [HolidayRecord]) -> [HolidayRecord] {
        var byID: [UUID: [HolidayRecord]] = [:]
        for record in records { byID[record.identifier, default: []].append(record) }
        guard byID.contains(where: { $0.value.count > 1 }) else { return records }

        var survivors: Set<PersistentIdentifier> = []
        for (_, group) in byID where group.count > 1 {
            let ordered = group.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.persistentModelID.hashValue > $1.persistentModelID.hashValue
            }
            for loser in ordered.dropFirst() { context.delete(loser) }
            survivors.insert(ordered[0].persistentModelID)
        }
        persist()
        return records.filter { record in
            byID[record.identifier]?.count == 1 || survivors.contains(record.persistentModelID)
        }
    }

    // MARK: - Saving

    /// SwiftData autosaves, but an explicit save after each edit means a crash
    /// can never lose a day the user just entered.
    private func persist() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
