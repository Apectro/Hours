import Foundation

/// An item used before, offered again as a chip: its name and the unit it
/// was last counted in. One list for the user, not one per site — the same
/// lamp is fitted on every site.
///
/// Since scanning (1.3) an item can have barcodes: a code named once is known
/// on every site, so nobody names the same box twice. Which sites it was used
/// on is remembered too, so a site's own items are offered first there.
struct ExtraWorkCatalogItem: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var unit: ExtraWorkUnit
    var useCount: Int
    var lastUsed: Date
    /// The codes on its box, as scanned or typed (`ExtraWorkCatalog.code`).
    /// One code is one item (`ExtraWorkCatalog.addingCode`).
    var barcodes: [String]
    /// The sites it was used on, in the order it was first used there.
    var siteIDs: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        unit: ExtraWorkUnit,
        useCount: Int = 0,
        lastUsed: Date = Date(),
        barcodes: [String] = [],
        siteIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.useCount = useCount
        self.lastUsed = lastUsed
        self.barcodes = barcodes
        self.siteIDs = siteIDs
    }

    var hasBarcode: Bool { !barcodes.isEmpty }

    private enum CodingKeys: String, CodingKey { case id, name, unit, useCount, lastUsed, barcodes, siteIDs }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            name: container.lenient(.name, ""),
            unit: container.lenient(.unit, .pieces),
            useCount: max(0, container.lenient(.useCount, 0)),
            lastUsed: container.lenient(.lastUsed, Date(timeIntervalSince1970: 0)),
            barcodes: container.lenient(.barcodes, [String]()).compactMap(ExtraWorkCatalog.code),
            siteIDs: container.lenient(.siteIDs, [UUID]())
        )
    }

    /// The codes and sites only when there are some, so a backup of an item
    /// without them reads as it always did.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(unit, forKey: .unit)
        try container.encode(useCount, forKey: .useCount)
        try container.encode(lastUsed, forKey: .lastUsed)
        if !barcodes.isEmpty { try container.encode(barcodes, forKey: .barcodes) }
        if !siteIDs.isEmpty { try container.encode(siteIDs, forKey: .siteIDs) }
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

    /// The first barcode of the remembered item with this name (by `key`),
    /// for a report's material summary: the one remembered in the same unit
    /// first, else any with that name that has a code; `nil` when none has.
    static func firstCode(forName name: String, unit: ExtraWorkUnit, in catalog: [ExtraWorkCatalogItem]) -> String? {
        let nameKey = key(name)
        guard !nameKey.isEmpty else { return nil }
        let named = catalog.filter { $0.hasBarcode && key($0.name) == nameKey }
        let match = named.first { $0.unit.groupingKey == unit.groupingKey } ?? named.first
        return match?.barcodes.first
    }

    /// The catalogue after a job with these items was saved: each item
    /// remembered once, with the spelling and unit it was last used with.
    /// With a site, the site is remembered on each item, so it is offered
    /// first there next time.
    static func recording(
        _ items: [ExtraWorkItem],
        into catalog: [ExtraWorkCatalogItem],
        at moment: Date,
        siteID: UUID? = nil
    ) -> [ExtraWorkCatalogItem] {
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
                if let siteID, !result[index].siteIDs.contains(siteID) { result[index].siteIDs.append(siteID) }
            } else {
                result.append(ExtraWorkCatalogItem(
                    name: name, unit: item.unit, useCount: 1, lastUsed: moment, siteIDs: siteID.map { [$0] } ?? []
                ))
            }
        }
        return result
    }

    /// The chips under a job's material: the items used on this site first
    /// (when there is one), then the most recently used, the most used among
    /// those used the same day, and nothing already on it.
    static func suggestions(
        from catalog: [ExtraWorkCatalogItem],
        excluding names: [String],
        siteID: UUID? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [ExtraWorkCatalogItem] {
        let taken = Set(names.map(key))
        var seen = Set<String>()
        return catalog
            .filter { !key($0.name).isEmpty && !taken.contains(key($0.name)) && seen.insert(key($0.name)).inserted }
            .sorted { lhs, rhs in
                if let siteID {
                    let leftHere = lhs.siteIDs.contains(siteID)
                    let rightHere = rhs.siteIDs.contains(siteID)
                    if leftHere != rightHere { return leftHere }
                }
                let left = calendar.startOfDay(for: lhs.lastUsed)
                let right = calendar.startOfDay(for: rhs.lastUsed)
                if left != right { return left > right }
                if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: - Searching

    /// The items whose name holds what was typed (case, accents and spacing
    /// aside) or whose code starts with it: this site's first, then the most
    /// used, then the most recently used. Nothing typed is every item.
    static func search(_ query: String, in catalog: [ExtraWorkCatalogItem], siteID: UUID?) -> [ExtraWorkCatalogItem] {
        let needle = key(query)
        let compact = query.filter { !$0.isWhitespace }
        return catalog
            .filter { item in
                guard !key(item.name).isEmpty else { return false }
                if needle.isEmpty { return true }
                if key(item.name).contains(needle) { return true }
                return !compact.isEmpty && item.barcodes.contains { $0.hasPrefix(compact) }
            }
            .sorted { lhs, rhs in
                if let siteID {
                    let leftHere = lhs.siteIDs.contains(siteID)
                    let rightHere = rhs.siteIDs.contains(siteID)
                    if leftHere != rightHere { return leftHere }
                }
                if lhs.useCount != rhs.useCount { return lhs.useCount > rhs.useCount }
                if lhs.lastUsed != rhs.lastUsed { return lhs.lastUsed > rhs.lastUsed }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: - Barcodes

    /// A code as it is kept: what the scanner read or was typed, without
    /// spaces or line ends around it. Nothing is no code.
    static func code(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The item with this code on it, if it has been named.
    static func item(forCode raw: String, in catalog: [ExtraWorkCatalogItem]) -> ExtraWorkCatalogItem? {
        guard let code = code(raw) else { return nil }
        return catalog.first { $0.barcodes.contains(code) }
    }

    /// A code seen for the first time, named: the item of that name gets the
    /// code (and the unit chosen), or a new item is made with it. The item is
    /// not counted as used here; adding it to a job does that.
    static func naming(
        code raw: String,
        name: String,
        unit: ExtraWorkUnit,
        in catalog: [ExtraWorkCatalogItem],
        at moment: Date
    ) -> (catalog: [ExtraWorkCatalogItem], item: ExtraWorkCatalogItem) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = catalog
        let target: UUID
        if let index = result.firstIndex(where: { key($0.name) == key(trimmed) && !key(trimmed).isEmpty }) {
            result[index].unit = unit
            target = result[index].id
        } else {
            let item = ExtraWorkCatalogItem(name: trimmed, unit: unit, useCount: 0, lastUsed: moment)
            result.append(item)
            target = item.id
        }
        result = addingCode(raw, to: target, in: result)
        let item = result.first { $0.id == target } ?? ExtraWorkCatalogItem(name: trimmed, unit: unit)
        return (result, item)
    }

    /// Gives an item a code, taking it off any other item: one code is one
    /// item.
    static func addingCode(_ raw: String, to itemID: UUID, in catalog: [ExtraWorkCatalogItem]) -> [ExtraWorkCatalogItem] {
        guard let code = code(raw) else { return catalog }
        return catalog.map { item in
            var next = item
            if item.id == itemID {
                if !next.barcodes.contains(code) { next.barcodes.append(code) }
            } else {
                next.barcodes.removeAll { $0 == code }
            }
            return next
        }
    }

    static func removingCode(_ raw: String, from itemID: UUID, in catalog: [ExtraWorkCatalogItem]) -> [ExtraWorkCatalogItem] {
        guard let code = code(raw) else { return catalog }
        return catalog.map { item in
            var next = item
            if item.id == itemID { next.barcodes.removeAll { $0 == code } }
            return next
        }
    }
}

/// Scanning material into a job (1.3): each code recognised adds one of its
/// item; what the scanner offers when a code is new.
enum ExtraWorkScan {
    /// "Counted in" on the New item sheet: the extra-work units a box of
    /// material comes in.
    static let units: [ExtraWorkUnit] = [.pieces, .metres, .kilograms, .boxes]

    /// The job's lines with one more (or, with −1, one fewer) of the item:
    /// its line counted up, or a new line at the end. Never below zero; a
    /// line at zero is the editor's to remove.
    static func adding(_ item: ExtraWorkCatalogItem, by step: Int, to items: [ExtraWorkItem]) -> [ExtraWorkItem] {
        var result = items
        if let index = lineIndex(of: item, in: result) {
            result[index].quantity = ExtraWorkQuantity.stepped(result[index].quantity, by: step)
        } else if step > 0 {
            result.append(ExtraWorkItem(name: item.name, quantity: Decimal(step), unit: item.unit))
        }
        return result
    }

    /// How many of the item the job has now: "now 2 pcs".
    static func quantity(of item: ExtraWorkCatalogItem, in items: [ExtraWorkItem]) -> Decimal {
        lineIndex(of: item, in: items).map { items[$0].quantity } ?? 0
    }

    private static func lineIndex(of item: ExtraWorkCatalogItem, in items: [ExtraWorkItem]) -> Int? {
        let itemKey = ExtraWorkCatalog.key(item.name)
        return items.firstIndex { ExtraWorkCatalog.key($0.name) == itemKey && $0.unit.groupingKey == item.unit.groupingKey }
    }
}

/// One box held in front of the camera is seen many times a second. A code
/// seen again within a second and a half of the last time it was seen is the
/// same box, and is ignored — for as long as it stays in view.
struct ScanRepeatFilter: Sendable {
    static let window: TimeInterval = 1.5

    private var lastSeen: [String: Date] = [:]

    init() {}

    /// Whether this sighting counts.
    mutating func accepts(_ raw: String, at moment: Date) -> Bool {
        guard let code = ExtraWorkCatalog.code(raw) else { return false }
        defer { lastSeen[code] = moment }
        guard let previous = lastSeen[code] else { return true }
        return moment.timeIntervalSince(previous) >= Self.window
    }
}

/// What one scanning session did: the items scanned, in the order first
/// scanned, and how many it added in all ("Done · 6 items").
struct ScanSession: Sendable {
    struct Line: Hashable, Sendable {
        let itemID: UUID
        let name: String
        let unit: ExtraWorkUnit
    }

    private(set) var lines: [Line] = []
    private(set) var last: Line?
    private(set) var added = 0

    init() {}

    mutating func record(_ item: ExtraWorkCatalogItem, by step: Int) {
        let line = Line(itemID: item.id, name: item.name, unit: item.unit)
        if !lines.contains(where: { $0.itemID == item.id }) { lines.append(line) }
        last = line
        added = max(0, added + step)
    }
}
