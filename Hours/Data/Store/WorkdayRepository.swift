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
        return deduplicated((try? context.fetch(descriptor)) ?? []).first
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

    /// How many recorded days are marked with a given day type.
    ///
    /// Asked before deleting a custom type. A day whose type no longer exists
    /// resolves to "Unknown", which expects nothing and credits nothing — so
    /// deleting a type that ten days of paid leave point at moves the balance
    /// by eighty hours, from a settings screen, with no warning and nothing
    /// undone. Knowing the count is what lets the app say so first.
    func dayCount(using type: DayTypeID) -> Int {
        let raw = type.rawValue
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate<DayEntry> { $0.dayTypeRawValue == raw }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
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
    ///
    /// The one exception is rows nothing can tell apart, which are all kept.
    /// See `collapse` for why that is the safe answer rather than the lazy one.
    @discardableResult
    func reconcileDuplicates() -> Int {
        let before = (try? context.fetchCount(FetchDescriptor<DayEntry>())) ?? 0
        _ = allEntries()
        _ = holidayRecords()
        let after = (try? context.fetchCount(FetchDescriptor<DayEntry>())) ?? 0
        return max(0, before - after)
    }

    private func deduplicated(_ entries: [DayEntry]) -> [DayEntry] {
        collapse(entries, by: \.dateKey) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt)
        }
    }

    private func deduplicatedHolidays(_ records: [HolidayRecord]) -> [HolidayRecord] {
        // Holiday rules carry no updatedAt, so creation is all there is.
        collapse(records, by: \.identifier) {
            Freshness(updatedAt: $0.createdAt, createdAt: $0.createdAt)
        }
    }

    /// How recent a row is, for choosing between duplicates.
    ///
    /// Two rows of equal freshness are ones nothing can tell apart, which is
    /// deliberately not a tie to be broken — see `collapse`.
    private struct Freshness: Comparable {
        let updatedAt: Date
        let createdAt: Date

        static func < (a: Self, b: Self) -> Bool {
            a.updatedAt == b.updatedAt ? a.createdAt < b.createdAt : a.updatedAt < b.updatedAt
        }
    }

    /// Groups rows by what makes them the same thing, keeps the freshest, and
    /// deletes the rest.
    ///
    /// Two properties this has to have, and neither is incidental.
    ///
    /// **Every survivor is chosen before anything is deleted.** Reading a
    /// property off a model that has been deleted and saved is undefined, so
    /// the grouping cannot happen afterwards — it would be doing exactly that
    /// to every row it just removed.
    ///
    /// **Rows nothing can tell apart are all kept.** Breaking that tie
    /// arbitrarily is the one genuinely dangerous thing this function could
    /// do: two devices picking differently would each delete what the other
    /// kept, both deletions would sync, and the day would be gone. Keeping
    /// both leaves a duplicate, which is untidy and self-healing — the next
    /// edit stamps one of them and it wins outright from then on. In practice
    /// the tie needs two devices to agree to sub-millisecond precision on both
    /// timestamps, so it is the unreachable branch that matters rather than
    /// the reachable one.
    private func collapse<Model: PersistentModel, Key: Hashable, Rank: Comparable>(
        _ models: [Model],
        by key: KeyPath<Model, Key>,
        freshness: (Model) -> Rank
    ) -> [Model] {
        var groups: [Key: [Model]] = [:]
        var order: [Key] = []
        for model in models {
            let identity = model[keyPath: key]
            if groups[identity] == nil { order.append(identity) }
            groups[identity, default: []].append(model)
        }
        guard groups.contains(where: { $0.value.count > 1 }) else { return models }

        var kept: [Model] = []
        var doomed: [Model] = []
        for identity in order {
            let group = groups[identity] ?? []
            guard group.count > 1 else {
                kept.append(contentsOf: group)
                continue
            }
            let best = group.map(freshness).max()
            for model in group {
                if freshness(model) == best { kept.append(model) } else { doomed.append(model) }
            }
        }

        for loser in doomed { context.delete(loser) }
        persist()
        // Returned in the order they arrived, which is the order the fetch
        // sorted them into.
        return kept
    }

    // MARK: - Saving

    /// SwiftData autosaves, but an explicit save after each edit means a crash
    /// can never lose a day the user just entered.
    private func persist() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
