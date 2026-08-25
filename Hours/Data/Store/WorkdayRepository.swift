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

    func entry(on date: CalendarDate) -> DayEntry? {
        let key = date.key
        var descriptor = FetchDescriptor<DayEntry>(predicate: #Predicate<DayEntry> { $0.dateKey == key })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func entries(in range: CalendarDateRange) -> [DayEntry] {
        let lower = range.start.key
        let upper = range.end.key
        let descriptor = FetchDescriptor<DayEntry>(
            predicate: #Predicate<DayEntry> { $0.dateKey >= lower && $0.dateKey <= upper },
            sortBy: [SortDescriptor(\DayEntry.dateKey)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func allEntries() -> [DayEntry] {
        let descriptor = FetchDescriptor<DayEntry>(sortBy: [SortDescriptor(\DayEntry.dateKey)])
        return (try? context.fetch(descriptor)) ?? []
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
        return (try? context.fetch(descriptor)) ?? []
    }

    func holidayRules() -> [HolidayRule] {
        holidayRecords().map(\.rule)
    }

    func upsert(_ rule: HolidayRule) {
        let identifier = rule.id
        var descriptor = FetchDescriptor<HolidayRecord>(predicate: #Predicate<HolidayRecord> { $0.identifier == identifier })
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.apply(rule)
        } else {
            context.insert(HolidayRecord(rule: rule))
        }
        persist()
    }

    func deleteHoliday(id: UUID) {
        var descriptor = FetchDescriptor<HolidayRecord>(predicate: #Predicate<HolidayRecord> { $0.identifier == id })
        descriptor.fetchLimit = 1
        guard let existing = (try? context.fetch(descriptor))?.first else { return }
        context.delete(existing)
        persist()
    }

    func deleteAllHolidays() {
        for record in holidayRecords() { context.delete(record) }
        persist()
    }

    // MARK: - Saving

    /// SwiftData autosaves, but an explicit save after each edit means a crash
    /// can never lose a day the user just entered.
    private func persist() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
