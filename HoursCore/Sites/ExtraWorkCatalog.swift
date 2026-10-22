import Foundation

/// An item used before, offered again as a chip: its name and the unit it
/// was last counted in. One list for the user, not one per site — the same
/// lamp is fitted on every site.
struct ExtraWorkCatalogItem: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var unit: ExtraWorkUnit
    var useCount: Int
    var lastUsed: Date

    init(id: UUID = UUID(), name: String, unit: ExtraWorkUnit, useCount: Int = 0, lastUsed: Date = Date()) {
        self.id = id
        self.name = name
        self.unit = unit
        self.useCount = useCount
        self.lastUsed = lastUsed
    }

    private enum CodingKeys: String, CodingKey { case id, name, unit, useCount, lastUsed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            name: container.lenient(.name, ""),
            unit: container.lenient(.unit, .pieces),
            useCount: max(0, container.lenient(.useCount, 0)),
            lastUsed: container.lenient(.lastUsed, Date(timeIntervalSince1970: 0))
        )
    }
}

enum ExtraWorkCatalog {
    /// What makes two spellings one item: case, accents and spacing do not
    /// count. "Kabel" and "kabel " are the same cable; "Kabelkanal" is not.
    static func key(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// The catalogue after a job with these items was saved: each item
    /// remembered once, with the spelling and unit it was last used with.
    static func recording(_ items: [ExtraWorkItem], into catalog: [ExtraWorkCatalogItem], at moment: Date) -> [ExtraWorkCatalogItem] {
        var result = catalog
        var seen = Set<String>()
        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let itemKey = key(name)
            guard !itemKey.isEmpty, seen.insert(itemKey).inserted else { continue }
            if let index = result.firstIndex(where: { key($0.name) == itemKey }) {
                result[index].name = name
                result[index].unit = item.unit
                result[index].useCount += 1
                result[index].lastUsed = max(result[index].lastUsed, moment)
            } else {
                result.append(ExtraWorkCatalogItem(name: name, unit: item.unit, useCount: 1, lastUsed: moment))
            }
        }
        return result
    }

    /// The chips under a job's material: the most recently used first, the
    /// most used among those used the same day, and nothing already on it.
    static func suggestions(
        from catalog: [ExtraWorkCatalogItem],
        excluding names: [String],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [ExtraWorkCatalogItem] {
        let taken = Set(names.map(key))
        var seen = Set<String>()
        return catalog
            .filter { !key($0.name).isEmpty && !taken.contains(key($0.name)) && seen.insert(key($0.name)).inserted }
            .sorted { lhs, rhs in
                let left = calendar.startOfDay(for: lhs.lastUsed)
                let right = calendar.startOfDay(for: rhs.lastUsed)
                if left != right { return left > right }
                if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}
