import Foundation
import SwiftData

/// A checked delivery (schema V11): when, its lines as JSON
/// (`[DeliveryLine]`), and the delivery note's photo outside the database
/// file, as the diary's photos are. `hasPhoto` says whether there is one
/// without reading it. Defaults or optional on every attribute, no
/// relationships, nothing `.unique`: one row per id is
/// `DeliveryRepository`'s rule.
@Model
final class DeliveryEntry {
    /// `Delivery.id`, as `uuidString`. Unique by rule.
    var deliveryID: String = ""
    var siteID: String = ""
    var receivedAt: Date = Date()
    var linesData: Data?
    var hasPhoto: Bool = false
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(delivery: Delivery) {
        self.deliveryID = delivery.id.uuidString
        self.siteID = delivery.siteID.uuidString
        self.receivedAt = delivery.receivedAt
        self.linesData = try? JSONEncoder().encode(delivery.lines)
        self.photoData = delivery.photoData
        self.hasPhoto = delivery.photoData != nil
        self.createdAt = Date()
        self.updatedAt = delivery.updatedAt
    }
}

extension DeliveryEntry {
    var lines: [DeliveryLine] {
        guard let linesData else { return [] }
        return (try? JSONDecoder().decode([DeliveryLine].self, from: linesData)) ?? []
    }

    /// The delivery; with `includingPhoto`, its photo's bytes too, which
    /// reads the file.
    func delivery(includingPhoto: Bool) -> Delivery {
        Delivery(
            id: UUID(uuidString: deliveryID) ?? UUID(),
            siteID: UUID(uuidString: siteID) ?? UUID(),
            receivedAt: receivedAt,
            lines: lines,
            hasPhoto: hasPhoto,
            photoData: includingPhoto ? photoData : nil,
            updatedAt: updatedAt
        )
    }
}
