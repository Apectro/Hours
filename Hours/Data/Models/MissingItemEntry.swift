import Foundation
import SwiftData

/// One row of a site's Missing list in the store (schema V10). Mirrors
/// `MissingItem`. The rules a CloudKit-mirrored store sets hold: a default
/// or optional on every attribute, nothing `.unique`, no relationships — the
/// site and the remembered item are id strings, and one row per id is
/// `MissingRepository`'s rule, kept by the same last-edit-wins collapse as
/// every other entity.
@Model
final class MissingItemEntry {
    /// `MissingItem.id`, as `uuidString`. Unique by rule.
    var itemID: String = ""
    var siteID: String = ""
    var name: String = ""
    /// `ExtraWorkCatalogItem.id`, as `uuidString`, when picked from the list.
    var catalogItemID: String?
    /// The quantity as text ("12.5"), exact on every platform.
    var quantityText: String = "1"
    /// `ExtraWorkUnit.code`.
    var unitCode: String = "pcs"
    var note: String = ""
    /// Who noticed it; empty for you.
    var notedBy: String = ""
    var notedAt: Date = Date()
    /// `MissingState` raw value. One this version does not know reads as
    /// needed.
    var stateRawValue: String = "needed"
    var orderedAt: Date?
    var arrivedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(item: MissingItem) {
        self.itemID = item.id.uuidString
        self.siteID = item.siteID.uuidString
        self.createdAt = Date()
        apply(item)
        self.updatedAt = item.updatedAt
    }
}

extension MissingItemEntry {
    var item: MissingItem {
        MissingItem(
            id: UUID(uuidString: itemID) ?? UUID(),
            siteID: UUID(uuidString: siteID) ?? UUID(),
            name: name,
            catalogItemID: catalogItemID.flatMap(UUID.init(uuidString:)),
            quantity: ExtraWorkQuantity.parse(quantityText) ?? 1,
            unit: ExtraWorkUnit(code: unitCode),
            note: note,
            notedBy: notedBy,
            notedAt: notedAt,
            state: MissingState(storedValue: stateRawValue),
            orderedAt: orderedAt,
            arrivedAt: arrivedAt,
            updatedAt: updatedAt
        )
    }

    /// Everything but which row it is and on which site.
    func apply(_ item: MissingItem) {
        name = item.name
        catalogItemID = item.catalogItemID?.uuidString
        quantityText = ExtraWorkQuantity.string(item.quantity, decimalSeparator: ".")
        unitCode = item.unit.code
        note = item.note
        notedBy = item.notedBy
        notedAt = item.notedAt
        stateRawValue = item.state.rawValue
        orderedAt = item.orderedAt
        arrivedAt = item.arrivedAt
        updatedAt = Date()
    }
}
