import Foundation

/// One line of a delivery as it was checked (1.3): what came of an ordered
/// item, all of it or part, or something that came without being ordered.
struct DeliveryLine: Hashable, Sendable {
    enum Kind: String, CaseIterable, Hashable, Sendable {
        /// All that was ordered came (or more).
        case arrived
        /// Less came than was ordered; the rest stays ordered.
        case short
        /// Not on the list, came anyway. Recorded on the delivery and shown,
        /// never added to Missing.
        case extra
    }

    var kind: Kind
    var name: String
    var unit: ExtraWorkUnit
    /// How much came.
    var came: Decimal
    /// How much was ordered: the Missing item's quantity; for an extra, what
    /// came.
    var ordered: Decimal
    /// The Missing item it ticks off; none for an extra.
    var missingItemID: UUID?
    var catalogItemID: UUID?

    init(
        kind: Kind,
        name: String,
        unit: ExtraWorkUnit,
        came: Decimal,
        ordered: Decimal,
        missingItemID: UUID? = nil,
        catalogItemID: UUID? = nil
    ) {
        self.kind = kind
        self.name = name
        self.unit = unit
        self.came = came
        self.ordered = ordered
        self.missingItemID = missingItemID
        self.catalogItemID = catalogItemID
    }

    /// What is still to come: nothing, unless short.
    var remainder: Decimal {
        kind == .short ? max(ordered - came, 0) : 0
    }

    /// "6 pcs", "30 m": what came.
    func cameAmount(in language: ExportLanguage, decimalSeparator: String) -> String {
        "\(ExtraWorkQuantity.string(came, decimalSeparator: decimalSeparator)) \(unit.name(in: language))"
    }

    /// "20 m Cable NYM 3×1.5", "4 × LED panel 60×60": what is still to come.
    func remainderLine(in language: ExportLanguage, decimalSeparator: String) -> String {
        ExtraWorkItem(name: name, quantity: remainder, unit: unit).line(in: language, decimalSeparator: decimalSeparator)
    }

    /// "2 × Emergency light 3h": what came.
    func cameLine(in language: ExportLanguage, decimalSeparator: String) -> String {
        ExtraWorkItem(name: name, quantity: came, unit: unit).line(in: language, decimalSeparator: decimalSeparator)
    }
}

extension DeliveryLine: Codable {
    private enum CodingKeys: String, CodingKey { case kind, name, unit, came, ordered, missingItemID, catalogItemID }

    /// Quantities as text, "12.5", exact everywhere, as Missing's are.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(unit, forKey: .unit)
        try container.encode(ExtraWorkQuantity.string(came, decimalSeparator: "."), forKey: .came)
        try container.encode(ExtraWorkQuantity.string(ordered, decimalSeparator: "."), forKey: .ordered)
        try container.encodeIfPresent(missingItemID, forKey: .missingItemID)
        try container.encodeIfPresent(catalogItemID, forKey: .catalogItemID)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let came = ExtraWorkQuantity.parse(container.lenient(.came, "0")) ?? 0
        self.init(
            // A kind this version does not know reads as something that
            // came anyway: shown, and nothing on Missing is touched by it.
            kind: Kind(rawValue: container.lenient(.kind, "extra")) ?? .extra,
            name: container.lenient(.name, ""),
            unit: container.lenient(.unit, .pieces),
            came: came,
            ordered: container.lenientOptional(.ordered, String.self).flatMap(ExtraWorkQuantity.parse) ?? came,
            missingItemID: container.lenientOptional(.missingItemID),
            catalogItemID: container.lenientOptional(.catalogItemID)
        )
    }
}

/// A delivery that was checked and saved: when, what came of what, and the
/// delivery note's photo if one was taken. Shown under Missing › Arrived,
/// read-only. Not hours, so not under the month lock.
struct Delivery: Identifiable, Hashable, Sendable {
    var id: UUID
    var siteID: UUID
    var receivedAt: Date
    var lines: [DeliveryLine]
    /// Whether a photo of the delivery note was kept, without reading it.
    var hasPhoto: Bool
    /// The photo itself, as the diary's are: only when asked for (a backup,
    /// the viewer), so a list of deliveries never reads an image.
    var photoData: Data?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        siteID: UUID,
        receivedAt: Date,
        lines: [DeliveryLine],
        hasPhoto: Bool = false,
        photoData: Data? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.siteID = siteID
        self.receivedAt = receivedAt
        self.lines = lines
        self.hasPhoto = hasPhoto || photoData != nil
        self.photoData = photoData
        self.updatedAt = updatedAt
    }

    func lines(_ kind: DeliveryLine.Kind) -> [DeliveryLine] {
        lines.filter { $0.kind == kind }
    }
}

extension Delivery: Codable {
    private enum CodingKeys: String, CodingKey { case id, siteID, receivedAt, lines, photo, updatedAt }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(siteID, forKey: .siteID)
        try container.encode(receivedAt, forKey: .receivedAt)
        try container.encode(lines, forKey: .lines)
        // Base64, as the diary's photos are in a backup.
        try container.encodeIfPresent(photoData, forKey: .photo)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            siteID: container.lenient(.siteID, UUID()),
            receivedAt: container.lenient(.receivedAt, Date(timeIntervalSince1970: 0)),
            lines: container.lenient(.lines, [DeliveryLine]()),
            photoData: container.lenientOptional(.photo, Data.self),
            updatedAt: container.lenient(.updatedAt, Date(timeIntervalSince1970: 0))
        )
    }
}

/// How much of an expected item has come so far: the bottom card's ✓,
/// half circle and empty circle.
enum DeliveryProgress: Hashable, Sendable {
    case notYet, partly, full
}

/// Checking a delivery against what is ordered (Delivery board, phones 10
/// and 11): each box scanned counts one of its item; an item measured in
/// metres or kilograms is set to what was ordered by its first scan and
/// corrected with − and +. A known code that is not ordered, and a new code
/// once named, come anyway. Pure; the scanner screen keeps one of these and
/// the repository stores what `lines` and `applying` say.
struct DeliveryCheck: Sendable {
    /// The Ordered items, in the list's order.
    let expected: [MissingItem]
    /// How much of each expected item came, by its id.
    private(set) var came: [UUID: Decimal] = [:]
    /// What came that is not ordered, in the order first scanned.
    private(set) var extras: [DeliveryLine] = []
    /// The line the card speaks about: the last scanned.
    private(set) var focus: Focus?

    enum Focus: Hashable, Sendable {
        case expected(UUID)
        case extra(Int)
    }

    /// What a scan did.
    enum Outcome: Hashable, Sendable {
        /// One more of an expected item.
        case counted(UUID)
        /// An expected item measured by length or weight: set to what was
        /// ordered, the stepper to correct it.
        case measured(UUID)
        /// One more of something not ordered, by its index in `extras`.
        case extra(Int)
        /// A code nothing is named for: "New item", then `addingExtra`.
        case unknown(String)
        /// Not a code at all.
        case ignored
    }

    init(expected: [MissingItem]) {
        self.expected = MissingList.items(.ordered, in: expected)
    }

    /// Bought by length or weight: one box is not one of them.
    static func isMeasured(_ unit: ExtraWorkUnit) -> Bool {
        switch unit {
        case .metres, .squareMetres, .cubicMetres, .kilograms: return true
        default: return false
        }
    }

    /// A code read off a box, or typed.
    mutating func scan(_ raw: String, catalog: [ExtraWorkCatalogItem]) -> Outcome {
        guard let code = ExtraWorkCatalog.code(raw) else { return .ignored }
        guard let item = ExtraWorkCatalog.item(forCode: code, in: catalog) else { return .unknown(code) }
        if let match = expectedMatch(for: item) {
            if DeliveryCheck.isMeasured(match.unit) {
                // The first scan says the roll came; the amount is the
                // order's until corrected.
                if (came[match.id] ?? 0) == 0 { came[match.id] = match.quantity }
                focus = .expected(match.id)
                return .measured(match.id)
            }
            came[match.id] = ExtraWorkQuantity.stepped(came[match.id] ?? 0, by: 1)
            focus = .expected(match.id)
            return .counted(match.id)
        }
        return .extra(addingExtra(item))
    }

    /// Something not ordered: one more of it, or its first. Returns its
    /// index in `extras`.
    @discardableResult
    mutating func addingExtra(_ item: ExtraWorkCatalogItem) -> Int {
        let key = ExtraWorkCatalog.key(item.name)
        if let index = extras.firstIndex(where: {
            $0.catalogItemID == item.id || (ExtraWorkCatalog.key($0.name) == key && $0.unit.groupingKey == item.unit.groupingKey)
        }) {
            extras[index].came = ExtraWorkQuantity.stepped(extras[index].came, by: 1)
            extras[index].ordered = extras[index].came
            focus = .extra(index)
            return index
        }
        extras.append(DeliveryLine(kind: .extra, name: item.name, unit: item.unit, came: 1, ordered: 1, catalogItemID: item.id))
        focus = .extra(extras.count - 1)
        return extras.count - 1
    }

    /// − and + on an expected item: one unit less or more, never below none.
    mutating func step(_ id: UUID, by step: Int) {
        guard expected.contains(where: { $0.id == id }) else { return }
        came[id] = ExtraWorkQuantity.stepped(came[id] ?? 0, by: step)
        focus = .expected(id)
    }

    /// − and + on something not ordered; at none it is gone.
    mutating func stepExtra(_ index: Int, by step: Int) {
        guard extras.indices.contains(index) else { return }
        let next = ExtraWorkQuantity.stepped(extras[index].came, by: step)
        if next <= 0 {
            extras.remove(at: index)
            focus = nil
            return
        }
        extras[index].came = next
        extras[index].ordered = next
        focus = .extra(index)
    }

    func cameAmount(of id: UUID) -> Decimal {
        came[id] ?? 0
    }

    func progress(of item: MissingItem) -> DeliveryProgress {
        let amount = cameAmount(of: item.id)
        if amount <= 0 { return .notYet }
        return amount >= item.quantity ? .full : .partly
    }

    /// "2 of 3 here": the expected items with anything come.
    var hereCount: Int {
        expected.filter { cameAmount(of: $0.id) > 0 }.count
    }

    /// Anything to save: something came.
    var hasAnything: Bool {
        hereCount > 0 || !extras.isEmpty
    }

    /// The delivery as it will be saved: every expected item, arrived or
    /// short (short with none come too: it is still on order), then the
    /// extras.
    var lines: [DeliveryLine] {
        let ordered = expected.map { item -> DeliveryLine in
            let amount = cameAmount(of: item.id)
            return DeliveryLine(
                kind: amount >= item.quantity ? .arrived : .short,
                name: item.name,
                unit: item.unit,
                came: amount,
                ordered: item.quantity,
                missingItemID: item.id,
                catalogItemID: item.catalogItemID
            )
        }
        return ordered.filter { $0.kind == .arrived } + ordered.filter { $0.kind == .short } + extras
    }

    private func expectedMatch(for item: ExtraWorkCatalogItem) -> MissingItem? {
        let itemKey = ExtraWorkCatalog.key(item.name)
        let matches = expected.filter { $0.catalogItemID == item.id || ExtraWorkCatalog.key($0.name) == itemKey }
        // Two orders of one item: the first still waiting for some.
        return matches.first { progress(of: $0) != .full } ?? matches.first
    }

    // MARK: - Saving

    /// The Missing list after the delivery: an item that all came is
    /// arrived; one that partly came is split, the part that came arrived
    /// on a row of its own and the rest still ordered on the item's own
    /// row; one that did not come is untouched. Extras never touch the list.
    static func applying(_ lines: [DeliveryLine], to items: [MissingItem], at moment: Date) -> [MissingItem] {
        var result = items
        for line in lines {
            guard line.kind != .extra, let id = line.missingItemID,
                  let index = result.firstIndex(where: { $0.id == id && $0.state == .ordered })
            else { continue }
            switch line.kind {
            case .arrived:
                result[index] = MissingList.moved(result[index], to: .arrived, at: moment)
            case .short:
                guard line.came > 0 else { continue }
                let item = result[index]
                result[index].quantity = max(item.quantity - line.came, 0)
                result[index].updatedAt = moment
                var arrived = item
                arrived.id = UUID()
                arrived.quantity = line.came
                arrived = MissingList.moved(arrived, to: .arrived, at: moment)
                result.insert(arrived, at: index + 1)
            case .extra:
                continue
            }
        }
        return result
    }
}

/// What the warehouse is told after a delivery (Delivery board, phone 12),
/// in the export language:
///
///     Trg Pravde Zagreb · delivery, 4 Nov
///
///     Still missing:
///     20 m Cable NYM 3×1.5
///     4 × LED panel 60×60
///
///     Not ordered, came anyway:
///     2 × Emergency light 3h
///
///     Marijo Mikša
struct DeliveryMessage: Sendable {
    let siteName: String
    let date: CalendarDate
    let lines: [DeliveryLine]
    let ownerName: String
    let language: ExportLanguage
    let decimalSeparator: String
    let calendar: Calendar

    var heading: String {
        let formatting = CalendarFormatting(locale: language.locale, calendar: calendar)
        return "\(siteName) · \(language(.delivery)), \(formatting.shortDate(date))"
    }

    var text: String {
        var parts = [heading]
        let short = lines.filter { $0.kind == .short && $0.remainder > 0 }
        let extra = lines.filter { $0.kind == .extra }
        if short.isEmpty {
            parts += ["", language(.everythingCame)]
        } else {
            parts += ["", language(.stillMissing)]
            parts += short.map { $0.remainderLine(in: language, decimalSeparator: decimalSeparator) }
        }
        if !extra.isEmpty {
            parts += ["", language(.cameAnyway)]
            parts += extra.map { $0.cameLine(in: language, decimalSeparator: decimalSeparator) }
        }
        let owner = ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty {
            parts += ["", owner]
        }
        return parts.joined(separator: "\n")
    }
}
