import Foundation
import SwiftData

/// Reads and writes the deliveries checked on a site (1.3), and what saving
/// one does to its Missing list.
///
/// Not under the month lock, for Missing's reason; the method names avoid
/// `save`, `delete` and `replaceAll` (see `MissingRepository`). Always built
/// from a view's `modelContext` and used on the main actor.
struct DeliveryRepository {
    let context: ModelContext

    /// A site's deliveries, the latest first, without their photos.
    func deliveries(siteID: UUID) -> [Delivery] {
        let key = siteID.uuidString
        let descriptor = FetchDescriptor<DeliveryEntry>(
            predicate: #Predicate<DeliveryEntry> { $0.siteID == key },
            sortBy: [SortDescriptor(\DeliveryEntry.receivedAt, order: .reverse)]
        )
        return deduplicated(fetch(descriptor)).map { $0.delivery(includingPhoto: false) }
    }

    /// One delivery with its photo, for the read-only sheet.
    func delivery(id: UUID) -> Delivery? {
        entries(id: id).first?.delivery(includingPhoto: true)
    }

    /// "Save the delivery": the delivery kept, and the Missing list moved
    /// by `DeliveryCheck.applying` — what all came arrived, what partly came
    /// split, the rest still ordered. Returns what was stored.
    @discardableResult
    func record(
        lines: [DeliveryLine],
        photo: Data?,
        siteID: UUID,
        at moment: Date = Date()
    ) -> Delivery {
        let delivery = Delivery(siteID: siteID, receivedAt: moment, lines: lines, photoData: photo, updatedAt: moment)
        context.insert(DeliveryEntry(delivery: delivery))
        persist()
        MissingRepository(context: context).applyDelivery(lines, siteID: siteID, at: moment)
        return delivery
    }

    func remove(id: UUID) {
        for entry in entries(id: id) { context.delete(entry) }
        persist()
    }

    // MARK: - Backup and restore

    /// Every delivery with its photo.
    func everything() -> [Delivery] {
        deduplicated(fetch(FetchDescriptor<DeliveryEntry>(sortBy: [SortDescriptor(\DeliveryEntry.receivedAt)])))
            .map { $0.delivery(includingPhoto: true) }
    }

    func replaceEverything(_ deliveries: [Delivery]) {
        for entry in fetch(FetchDescriptor<DeliveryEntry>()) { context.delete(entry) }
        var seen = Set<UUID>()
        for delivery in deliveries where seen.insert(delivery.id).inserted {
            context.insert(DeliveryEntry(delivery: delivery))
        }
        persist()
    }

    // MARK: - Rows

    private func entries(id: UUID) -> [DeliveryEntry] {
        let key = id.uuidString
        return deduplicated(fetch(FetchDescriptor<DeliveryEntry>(predicate: #Predicate<DeliveryEntry> { $0.deliveryID == key })))
    }

    private func deduplicated(_ entries: [DeliveryEntry]) -> [DeliveryEntry] {
        let kept = context.collapseDuplicates(entries, by: \.deliveryID) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt)
        }.kept
        var seen = Set<String>()
        return kept.filter { seen.insert($0.deliveryID).inserted }
    }

    private func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> [Model] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func persist() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
