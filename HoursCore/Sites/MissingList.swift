import Foundation

/// Where a missing item stands: noted as needed, ordered, and arrived.
enum MissingState: String, CaseIterable, Hashable, Sendable {
    case needed, ordered, arrived

    /// A stored value this version does not know reads as needed: shown,
    /// rather than lost.
    init(storedValue: String) {
        self = MissingState(rawValue: storedValue) ?? .needed
    }
}

/// Something a site needs and has not got (1.3): "6 × Junction box IP65,
/// 2nd floor corridor", noted by you or someone on the crew, then ordered,
/// then arrived. The list belongs to its site. Not hours, so not under the
/// month lock.
struct MissingItem: Identifiable, Hashable, Sendable {
    var id: UUID
    var siteID: UUID
    var name: String
    /// The remembered item it was picked from, when it was (its codes find
    /// it when a delivery is scanned).
    var catalogItemID: UUID?
    var quantity: Decimal
    var unit: ExtraWorkUnit
    /// Where or why, optional: "2nd floor corridor".
    var note: String
    /// Who noticed: a crew member's name, or empty for you.
    var notedBy: String
    var notedAt: Date
    var state: MissingState
    var orderedAt: Date?
    var arrivedAt: Date?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        siteID: UUID,
        name: String,
        catalogItemID: UUID? = nil,
        quantity: Decimal = 1,
        unit: ExtraWorkUnit = .pieces,
        note: String = "",
        notedBy: String = "",
        notedAt: Date = Date(),
        state: MissingState = .needed,
        orderedAt: Date? = nil,
        arrivedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.siteID = siteID
        self.name = name
        self.catalogItemID = catalogItemID
        self.quantity = quantity
        self.unit = unit
        self.note = note
        self.notedBy = notedBy
        self.notedAt = notedAt
        self.state = state
        self.orderedAt = orderedAt
        self.arrivedAt = arrivedAt
        self.updatedAt = updatedAt
    }

    /// "6 × Junction box IP65", "50 m Cable NYM 3×1.5".
    func line(in language: ExportLanguage, decimalSeparator: String) -> String {
        ExtraWorkItem(name: name, quantity: quantity, unit: unit).line(in: language, decimalSeparator: decimalSeparator)
    }

    /// "6 pcs", "50 m".
    func amount(in language: ExportLanguage, decimalSeparator: String) -> String {
        "\(ExtraWorkQuantity.string(quantity, decimalSeparator: decimalSeparator)) \(unit.name(in: language))"
    }
}

extension MissingItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, siteID, name, catalogItemID, quantity, unit, note, notedBy, notedAt, state, orderedAt, arrivedAt, updatedAt
    }

    /// The quantity as text, "12.5", exact everywhere, as extra work's is.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(siteID, forKey: .siteID)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(catalogItemID, forKey: .catalogItemID)
        try container.encode(ExtraWorkQuantity.string(quantity, decimalSeparator: "."), forKey: .quantity)
        try container.encode(unit, forKey: .unit)
        if !note.isEmpty { try container.encode(note, forKey: .note) }
        if !notedBy.isEmpty { try container.encode(notedBy, forKey: .notedBy) }
        try container.encode(notedAt, forKey: .notedAt)
        try container.encode(state.rawValue, forKey: .state)
        try container.encodeIfPresent(orderedAt, forKey: .orderedAt)
        try container.encodeIfPresent(arrivedAt, forKey: .arrivedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let quantityText: String = container.lenient(.quantity, "1")
        self.init(
            id: container.lenient(.id, UUID()),
            siteID: container.lenient(.siteID, UUID()),
            name: container.lenient(.name, ""),
            catalogItemID: container.lenientOptional(.catalogItemID),
            quantity: ExtraWorkQuantity.parse(quantityText) ?? 1,
            unit: container.lenient(.unit, .pieces),
            note: container.lenient(.note, ""),
            notedBy: container.lenient(.notedBy, ""),
            notedAt: container.lenient(.notedAt, Date(timeIntervalSince1970: 0)),
            state: MissingState(storedValue: container.lenient(.state, "needed")),
            orderedAt: container.lenientOptional(.orderedAt),
            arrivedAt: container.lenientOptional(.arrivedAt),
            updatedAt: container.lenient(.updatedAt, Date(timeIntervalSince1970: 0))
        )
    }
}

/// What the add sheet hands over.
struct MissingDraft: Hashable, Sendable {
    var name: String
    var quantity: Decimal
    var unit: ExtraWorkUnit
    var note: String = ""
    var notedBy: String = ""
    var catalogItemID: UUID? = nil
}

/// The rules of a site's Missing list. Pure: the repository stores what
/// these return.
enum MissingList {
    /// The list with the draft added: a needed item of the same name and unit
    /// on the site is counted up rather than listed twice (its first note
    /// kept, or this one if it had none); anything else is a new row,
    /// needed. A blank name or nothing of it adds nothing.
    static func adding(
        _ draft: MissingDraft,
        siteID: UUID,
        at moment: Date,
        to items: [MissingItem]
    ) -> (items: [MissingItem], item: MissingItem?) {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ExtraWorkCatalog.key(name).isEmpty, draft.quantity > 0 else { return (items, nil) }
        var result = items
        if let index = result.firstIndex(where: { candidate in
            candidate.siteID == siteID
                && candidate.state == .needed
                && ExtraWorkCatalog.key(candidate.name) == ExtraWorkCatalog.key(name)
                && candidate.unit.groupingKey == draft.unit.groupingKey
        }) {
            result[index].quantity = min(result[index].quantity + draft.quantity, ExtraWorkQuantity.maximum)
            if result[index].note.isEmpty { result[index].note = note }
            if result[index].catalogItemID == nil { result[index].catalogItemID = draft.catalogItemID }
            result[index].updatedAt = moment
            return (result, result[index])
        }
        let item = MissingItem(
            siteID: siteID,
            name: name,
            catalogItemID: draft.catalogItemID,
            quantity: min(draft.quantity, ExtraWorkQuantity.maximum),
            unit: draft.unit,
            note: note,
            notedBy: draft.notedBy.trimmingCharacters(in: .whitespacesAndNewlines),
            notedAt: moment,
            updatedAt: moment
        )
        result.append(item)
        return (result, item)
    }

    /// One item moved to a state, with the day it got there. Back to needed
    /// forgets both days; arriving keeps the day it was ordered, if it was.
    static func marking(_ id: UUID, _ state: MissingState, at moment: Date, in items: [MissingItem]) -> [MissingItem] {
        items.map { item in
            guard item.id == id else { return item }
            return moved(item, to: state, at: moment)
        }
    }

    static func moved(_ item: MissingItem, to state: MissingState, at moment: Date) -> MissingItem {
        var next = item
        next.state = state
        switch state {
        case .needed:
            next.orderedAt = nil
            next.arrivedAt = nil
        case .ordered:
            next.orderedAt = item.state == .ordered ? item.orderedAt : moment
            next.arrivedAt = nil
        case .arrived:
            next.arrivedAt = item.state == .arrived ? item.arrivedAt : moment
        }
        next.updatedAt = moment
        return next
    }

    static func removing(_ id: UUID, from items: [MissingItem]) -> [MissingItem] {
        items.filter { $0.id != id }
    }

    /// How many rows are in a state: "Needed 3".
    static func count(_ state: MissingState, in items: [MissingItem]) -> Int {
        items.filter { $0.state == state }.count
    }

    /// The rows in a state, in the order the list shows them: needed and
    /// ordered oldest first (the longest waiting at the top), arrived newest
    /// first.
    static func items(_ state: MissingState, in items: [MissingItem]) -> [MissingItem] {
        let rows = items.filter { $0.state == state }
        switch state {
        case .needed:
            return rows.sorted { ($0.notedAt, $0.name) < ($1.notedAt, $1.name) }
        case .ordered:
            return rows.sorted { ($0.orderedAt ?? $0.notedAt, $0.name) < ($1.orderedAt ?? $1.notedAt, $1.name) }
        case .arrived:
            return rows.sorted { ($0.arrivedAt ?? $0.notedAt) > ($1.arrivedAt ?? $1.notedAt) }
        }
    }

    /// What "Send the list" sends: everything needed, or, when nothing is
    /// needed any more, what is ordered and has not arrived — sent again.
    static func toSend(_ items: [MissingItem]) -> [MissingItem] {
        let needed = Self.items(.needed, in: items)
        return needed.isEmpty ? Self.items(.ordered, in: items) : needed
    }

    /// After sending with "Mark them as ordered" on: the needed items sent
    /// are ordered as of now; anything ordered before keeps its day.
    static func markingOrdered(_ sent: [MissingItem], at moment: Date, in items: [MissingItem]) -> [MissingItem] {
        let ids = Set(sent.filter { $0.state == .needed }.map(\.id))
        return items.map { ids.contains($0.id) ? moved($0, to: .ordered, at: moment) : $0 }
    }

    /// The item a scanned box would tick off: one with that code's item,
    /// ordered first and then needed, the longest waiting first.
    static func arrivalMatch(forCode code: String, catalog: [ExtraWorkCatalogItem], in items: [MissingItem]) -> MissingItem? {
        guard let item = ExtraWorkCatalog.item(forCode: code, in: catalog) else { return nil }
        let itemKey = ExtraWorkCatalog.key(item.name)
        func matches(_ row: MissingItem) -> Bool {
            row.catalogItemID == item.id || ExtraWorkCatalog.key(row.name) == itemKey
        }
        return Self.items(.ordered, in: items).first(where: matches) ?? Self.items(.needed, in: items).first(where: matches)
    }

    /// The codes printed beside an item: its remembered item's, found by id
    /// or else by name.
    static func codes(for item: MissingItem, in catalog: [ExtraWorkCatalogItem]) -> [String] {
        if let id = item.catalogItemID, let match = catalog.first(where: { $0.id == id }) { return match.barcodes }
        let itemKey = ExtraWorkCatalog.key(item.name)
        return catalog.first { ExtraWorkCatalog.key($0.name) == itemKey }?.barcodes ?? []
    }
}

/// The list as it is sent, in the export language: the message text for a
/// chat, and the same list as a one-page table for the PDF.
///
///     Trg Pravde Zagreb · missing, 4 Nov
///     6 × Junction box IP65
///     50 m Cable NYM 3×1.5
///
///     Marijo Mikša
struct MissingMessage: Sendable {
    let siteName: String
    let date: CalendarDate
    let items: [MissingItem]
    let catalog: [ExtraWorkCatalogItem]
    let includesCodes: Bool
    let ownerName: String
    let language: ExportLanguage
    let decimalSeparator: String
    let calendar: Calendar

    struct Row: Hashable, Sendable {
        let quantity: String
        let name: String
        let code: String
        let note: String
    }

    private var formatting: CalendarFormatting {
        CalendarFormatting(locale: language.locale, calendar: calendar)
    }

    private var owner: String {
        ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var heading: String {
        "\(siteName) · \(language(.missing)), \(formatting.shortDate(date))"
    }

    var text: String {
        var lines = [heading]
        for item in items {
            var line = item.line(in: language, decimalSeparator: decimalSeparator)
            let codes = MissingList.codes(for: item, in: catalog)
            if includesCodes, !codes.isEmpty { line += " (\(codes.joined(separator: ", ")))" }
            lines.append(line)
        }
        if !owner.isEmpty {
            lines.append("")
            lines.append(owner)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - The PDF

    var title: String { language(.missingMaterial) }

    var subtitle: String { "\(siteName) · \(formatting.dateWithYear(date))" }

    var byline: String { owner.isEmpty ? "" : "\(language(.recordedBy)) \(owner)" }

    var headings: [String] {
        [language(.quantity), language(.item), language(.code), language(.note)]
    }

    var rows: [Row] {
        items.map { item in
            Row(
                quantity: item.amount(in: language, decimalSeparator: decimalSeparator),
                name: item.name,
                code: MissingList.codes(for: item, in: catalog).joined(separator: "\n"),
                note: item.note
            )
        }
    }

    var fileName: String {
        "\(siteName) - \(language(.missingMaterial)) \(date)"
    }
}
