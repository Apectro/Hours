import Foundation

/// Someone on a site's crew, other than the person using the app.
struct CrewMember: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var siteID: UUID
    var name: String
    /// Hidden members stay in past days but are no longer offered when
    /// recording a new one.
    var isHidden: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        siteID: UUID,
        name: String,
        isHidden: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.siteID = siteID
        self.name = name
        self.isHidden = isHidden
        self.sortOrder = sortOrder
    }

    /// Stands in for the user in a day's attendance list. "You" is never a
    /// stored `CrewMember`, so the identifier is fixed rather than random:
    /// every site, every device and every stored day agree on who it means.
    static let youID = UUID(uuidString: "00000000-0000-4000-8000-0000000000B1")!

    private enum CodingKeys: String, CodingKey {
        case id, siteID, name, isHidden, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            siteID: container.lenient(.siteID, UUID()),
            name: container.lenient(.name, ""),
            isHidden: container.lenient(.isHidden, false),
            sortOrder: container.lenient(.sortOrder, 0)
        )
    }
}
