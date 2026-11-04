import Foundation

/// What "Something's missing" has chosen while it is open: several items,
/// each with how many in its own unit, added to the list in one go.
///
/// Each row of the sheet has its own − / +: "+" from nothing sets one, "−"
/// at one goes back to nothing, and amounts step one at a time in any unit
/// (a typed 2.5 m steps to 1.5 m), as the stepper always did. The rows chosen
/// stay at the top while the sheet is open, but only move there when the
/// search changes (`searchChanged`), so nothing jumps under the thumb.
///
/// Pure: the sheet keeps one in its state and the repository adds its
/// `drafts` by `MissingList.adding`.
struct MissingSelection: Hashable, Sendable {
    /// One row: a remembered item, or a name typed that nothing has yet.
    enum Key: Hashable, Sendable {
        case item(UUID)
        /// The typed name's `ExtraWorkCatalog.key`, so spellings are one.
        case new(String)
    }

    /// Something that can be chosen: what a row shows and what is added.
    struct Candidate: Hashable, Sendable, Identifiable {
        let key: Key
        let name: String
        let unit: ExtraWorkUnit
        let catalogItemID: UUID?

        var id: Key { key }

        var isNew: Bool {
            if case .new = key { return true }
            return false
        }

        init(_ item: ExtraWorkCatalogItem) {
            key = .item(item.id)
            name = item.name
            unit = item.unit
            catalogItemID = item.id
        }

        /// "Add "<text>" as a new item".
        init(newName: String, unit: ExtraWorkUnit) {
            let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            key = .new(ExtraWorkCatalog.key(name))
            self.name = name
            self.unit = unit
            catalogItemID = nil
        }

        fileprivate init(key: Key, name: String, unit: ExtraWorkUnit, catalogItemID: UUID?) {
            self.key = key
            self.name = name
            self.unit = unit
            self.catalogItemID = catalogItemID
        }
    }

    /// A row chosen, with how many. One taken back to nothing is kept until
    /// the search changes, so its row stays where it was.
    struct Pick: Hashable, Sendable {
        var candidate: Candidate
        var quantity: Decimal

        var key: Key { candidate.key }
        var name: String { candidate.name }
        var unit: ExtraWorkUnit { candidate.unit }
    }

    /// In the order first chosen.
    private(set) var picks: [Pick] = []
    /// The rows shown at the top, in this order: what was chosen when the
    /// search last changed (or a box was last scanned).
    private(set) var pinned: [Key] = []

    init() {}

    // MARK: - Reading

    /// How many items are chosen: "Add 3 to missing".
    var count: Int {
        picks.filter { $0.quantity > 0 }.count
    }

    func quantity(of key: Key) -> Decimal {
        picks.first { $0.key == key }?.quantity ?? 0
    }

    /// The unit a chosen row is counted in; nil when it is not chosen.
    func unit(of key: Key) -> ExtraWorkUnit? {
        picks.first { $0.key == key && $0.quantity > 0 }?.unit
    }

    /// The new items chosen, whose unit the sheet asks for.
    var newPicks: [Pick] {
        picks.filter { $0.candidate.isNew && $0.quantity > 0 }
    }

    // MARK: - Changing

    /// A tap on the row: one, when it had none; otherwise as it was.
    mutating func choose(_ candidate: Candidate) {
        if quantity(of: candidate.key) <= 0 { set(candidate, to: 1) }
    }

    /// − or +: one at a time, never below nothing.
    mutating func step(_ candidate: Candidate, by step: Int) {
        set(candidate, to: ExtraWorkQuantity.stepped(quantity(of: candidate.key), by: step))
    }

    /// An amount typed; nothing (or less) takes the row back to nothing.
    mutating func set(_ candidate: Candidate, to value: Decimal) {
        let clamped = min(max(value, 0), ExtraWorkQuantity.maximum)
        if let index = picks.firstIndex(where: { $0.key == candidate.key }) {
            picks[index].quantity = clamped
        } else if clamped > 0 {
            picks.append(Pick(candidate: candidate, quantity: clamped))
        }
    }

    /// A new item's unit ("Counted in"); a remembered item keeps its own.
    mutating func setUnit(_ unit: ExtraWorkUnit, for key: Key) {
        guard case .new = key, let index = picks.firstIndex(where: { $0.key == key }) else { return }
        let old = picks[index].candidate
        picks[index].candidate = Candidate(key: old.key, name: old.name, unit: unit, catalogItemID: old.catalogItemID)
    }

    /// A known code scanned: one more of its item, its row brought to the
    /// top so the box just scanned is in sight.
    mutating func scanned(_ item: ExtraWorkCatalogItem) {
        step(Candidate(item), by: 1)
        searchChanged()
    }

    /// The search text changed: the rows chosen move to the top, and rows
    /// taken back to nothing go.
    mutating func searchChanged() {
        picks.removeAll { $0.quantity <= 0 }
        let chosen = picks.map(\.key)
        pinned = pinned.filter(chosen.contains) + chosen.filter { !pinned.contains($0) }
    }

    // MARK: - The rows and the result

    /// The rows in the order shown: the pinned ones first, then what the
    /// search found (with "Add "<text>" as a new item" last, when offered),
    /// none twice.
    func rows(matches: [Candidate]) -> [Candidate] {
        let top = pinned.compactMap { key in picks.first { $0.key == key }?.candidate }
        let shown = Set(top.map(\.key))
        var seen = shown
        let rest = matches.filter { seen.insert($0.key).inserted }
        return top + rest
    }

    /// What is added, in the order chosen: every item with some, with the one
    /// note and who noticed.
    func drafts(note: String, notedBy: String) -> [MissingDraft] {
        picks.filter { $0.quantity > 0 }.map { pick in
            MissingDraft(
                name: pick.name,
                quantity: pick.quantity,
                unit: pick.unit,
                note: note,
                notedBy: notedBy,
                catalogItemID: pick.candidate.catalogItemID
            )
        }
    }
}

extension MissingList {
    /// Several drafts added in one go, each by `adding(_:siteID:at:to:)`: an
    /// item already needed is counted up, the same item twice is one row.
    static func adding(_ drafts: [MissingDraft], siteID: UUID, at moment: Date, to items: [MissingItem]) -> [MissingItem] {
        drafts.reduce(items) { list, draft in
            adding(draft, siteID: siteID, at: moment, to: list).items
        }
    }
}
