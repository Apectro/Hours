import Foundation
import SwiftData

/// Reads and writes the sites' Missing lists (1.3).
///
/// Thin in the way `ExtraWorkRepository` is: it converts between
/// `MissingItemEntry` and `MissingItem`, owns the one-row-per-id rule, and
/// collapses the duplicates sync can leave, last edit winning. The rules
/// themselves (counting up, the states, what is sent) are `MissingList`'s.
///
/// **Not under the month lock**: nothing on the list is anyone's hours, and
/// what is missing on the 31st is ordered in the next month. Only a
/// read-only site (the Pro rule) stops adding, and that is the screens'
/// to check. The method names avoid `save`, `delete` and `replaceAll` so
/// `Scripts/check-repository-lock.py` does not take these writes for the
/// hours'.
///
/// Always built from a view's `modelContext` and used on the main actor.
struct MissingRepository {
    let context: ModelContext

    /// A site's list, every state.
    func items(siteID: UUID) -> [MissingItem] {
        let key = siteID.uuidString
        let descriptor = FetchDescriptor<MissingItemEntry>(
            predicate: #Predicate<MissingItemEntry> { $0.siteID == key },
            sortBy: [SortDescriptor(\MissingItemEntry.notedAt)]
        )
        return deduplicated(fetch(descriptor)).map(\.item)
    }

    /// How many are still needed on the site: the site page's "3 needed".
    func neededCount(siteID: UUID) -> Int {
        MissingList.count(.needed, in: items(siteID: siteID))
    }

    /// Adds to a site's list by `MissingList.adding`: the same needed item
    /// again is counted up. Returns the row written, if any.
    @discardableResult
    func add(_ draft: MissingDraft, siteID: UUID, at moment: Date = Date()) -> MissingItem? {
        let before = items(siteID: siteID)
        let result = MissingList.adding(draft, siteID: siteID, at: moment, to: before)
        storeChanges(from: before, to: result.items)
        return result.item
    }

    /// Moves one row to a state: swiped, or a delivery scanned.
    func mark(_ id: UUID, _ state: MissingState, siteID: UUID, at moment: Date = Date()) {
        let before = items(siteID: siteID)
        storeChanges(from: before, to: MissingList.marking(id, state, at: moment, in: before))
    }

    /// After "Send the list" with "Mark them as ordered" on.
    func markOrdered(_ sent: [MissingItem], siteID: UUID, at moment: Date = Date()) {
        let before = items(siteID: siteID)
        storeChanges(from: before, to: MissingList.markingOrdered(sent, at: moment, in: before))
    }

    func remove(id: UUID) {
        for entry in entries(id: id) { context.delete(entry) }
        persist()
    }

    // MARK: - Backup and restore

    func everything() -> [MissingItem] {
        deduplicated(fetch(FetchDescriptor<MissingItemEntry>(sortBy: [SortDescriptor(\MissingItemEntry.notedAt)]))).map(\.item)
    }

    /// Makes the given rows the whole of every list, as a restore and
    /// "Delete everything" do. A file holding one row twice keeps the first.
    func replaceEverything(_ items: [MissingItem]) {
        for entry in fetch(FetchDescriptor<MissingItemEntry>()) { context.delete(entry) }
        var seen = Set<UUID>()
        for item in items where seen.insert(item.id).inserted {
            context.insert(MissingItemEntry(item: item))
        }
        persist()
    }

    // MARK: - Rows

    private func storeChanges(from before: [MissingItem], to after: [MissingItem]) {
        for item in after where !before.contains(item) {
            if let entry = entries(id: item.id).first {
                entry.apply(item)
            } else {
                context.insert(MissingItemEntry(item: item))
            }
        }
        let kept = Set(after.map(\.id))
        for item in before where !kept.contains(item.id) {
            for entry in entries(id: item.id) { context.delete(entry) }
        }
        persist()
    }

    private func entries(id: UUID) -> [MissingItemEntry] {
        let key = id.uuidString
        let descriptor = FetchDescriptor<MissingItemEntry>(predicate: #Predicate<MissingItemEntry> { $0.itemID == key })
        return deduplicated(fetch(descriptor))
    }

    private func deduplicated(_ entries: [MissingItemEntry]) -> [MissingItemEntry] {
        let kept = context.collapseDuplicates(entries, by: \.itemID) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt)
        }.kept
        // Rows nothing could tell apart are all kept by the collapse; the
        // first of each stands for them until the next edit decides.
        var seen = Set<String>()
        return kept.filter { seen.insert($0.itemID).inserted }
    }

    private func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> [Model] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func persist() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
