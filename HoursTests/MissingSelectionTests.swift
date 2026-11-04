import XCTest
@testable import Hours

/// "Something's missing" with several items at once: each row has its own
/// − / + in the item's unit, the rows chosen stay at the top while the sheet
/// is open, and Add puts them all on the list in one go.
final class MissingSelectionTests: XCTestCase {
    private let site = UUID()
    private let thursday = Date(timeIntervalSince1970: 1_793_268_000) // Thu 29 Oct 2026, 10:00 UTC

    private let box = ExtraWorkCatalogItem(name: "Junction box IP65", unit: .pieces)
    private let cable = ExtraWorkCatalogItem(name: "Cable NYM 3x1.5", unit: .metres)
    private let lamp = ExtraWorkCatalogItem(name: "Emergency light", unit: .pieces)

    private var boxRow: MissingSelection.Candidate { .init(box) }
    private var cableRow: MissingSelection.Candidate { .init(cable) }
    private var lampRow: MissingSelection.Candidate { .init(lamp) }

    // MARK: - Stepping

    func testNothingIsChosenAtFirst() {
        let selection = MissingSelection()
        XCTAssertEqual(selection.count, 0)
        XCTAssertEqual(selection.quantity(of: boxRow.key), 0)
        XCTAssertTrue(selection.drafts(note: "", notedBy: "").isEmpty)
    }

    func testPlusFromNothingSetsOneAndCountsUpByOne() {
        var selection = MissingSelection()
        selection.step(boxRow, by: 1)
        XCTAssertEqual(selection.quantity(of: boxRow.key), 1)
        selection.step(boxRow, by: 1)
        selection.step(boxRow, by: 1)
        XCTAssertEqual(selection.quantity(of: boxRow.key), 3)
        XCTAssertEqual(selection.count, 1, "one item, however many of it")
    }

    func testChoosingARowSetsOneOnlyWhenItHadNone() {
        var selection = MissingSelection()
        selection.choose(boxRow)
        XCTAssertEqual(selection.quantity(of: boxRow.key), 1)
        selection.step(boxRow, by: 1)
        selection.choose(boxRow)
        XCTAssertEqual(selection.quantity(of: boxRow.key), 2, "a tap on a chosen row keeps what it has")
    }

    func testMinusAtOneGoesBackToNothing() {
        var selection = MissingSelection()
        selection.step(boxRow, by: 1)
        selection.step(boxRow, by: -1)
        XCTAssertEqual(selection.quantity(of: boxRow.key), 0)
        XCTAssertEqual(selection.count, 0)
        selection.step(boxRow, by: -1)
        XCTAssertEqual(selection.quantity(of: boxRow.key), 0, "never below nothing")
    }

    /// Metres step one at a time like the stepper; a typed 2.5 m steps to
    /// 1.5 m and 0.5 m, and then to nothing.
    func testMetresStepByOneFromATypedAmount() {
        var selection = MissingSelection()
        selection.set(cableRow, to: 2.5)
        XCTAssertEqual(selection.quantity(of: cableRow.key), 2.5)
        selection.step(cableRow, by: -1)
        XCTAssertEqual(selection.quantity(of: cableRow.key), 1.5)
        selection.step(cableRow, by: -1)
        XCTAssertEqual(selection.quantity(of: cableRow.key), 0.5)
        selection.step(cableRow, by: -1)
        XCTAssertEqual(selection.quantity(of: cableRow.key), 0)
        selection.step(cableRow, by: 1)
        XCTAssertEqual(selection.quantity(of: cableRow.key), 1)
    }

    func testATypedAmountIsKeptWithinTheMaximumAndZeroUnchooses() {
        var selection = MissingSelection()
        selection.set(boxRow, to: 5_000_000)
        XCTAssertEqual(selection.quantity(of: boxRow.key), ExtraWorkQuantity.maximum)
        selection.set(boxRow, to: 0)
        XCTAssertEqual(selection.count, 0)
        selection.step(boxRow, by: 1)
        selection.step(boxRow, by: 1)
        selection.set(boxRow, to: -3)
        XCTAssertEqual(selection.quantity(of: boxRow.key), 0)
    }

    // MARK: - New items

    /// Typed text is one new item whatever its spelling, counted in the unit
    /// chosen for it.
    func testANewItemIsKeyedByItsNameAndKeepsItsUnit() {
        var selection = MissingSelection()
        let typed = MissingSelection.Candidate(newName: " Wago 221 ", unit: .pieces)
        XCTAssertEqual(typed.name, "Wago 221")
        XCTAssertTrue(typed.isNew)
        selection.step(typed, by: 1)
        let again = MissingSelection.Candidate(newName: "wago  221", unit: .pieces)
        selection.step(again, by: 1)
        XCTAssertEqual(selection.count, 1)
        XCTAssertEqual(selection.quantity(of: typed.key), 2)

        selection.setUnit(.boxes, for: typed.key)
        XCTAssertEqual(selection.newPicks.map(\.unit), [.boxes])
        XCTAssertEqual(selection.unit(of: typed.key), .boxes)
        selection.setUnit(.metres, for: boxRow.key)
        XCTAssertNil(selection.unit(of: boxRow.key), "a remembered item keeps its own unit and is not chosen")
    }

    // MARK: - Scanning

    func testAScannedItemIsChosenWithOneOrCountedUp() {
        var selection = MissingSelection()
        selection.scanned(box)
        XCTAssertEqual(selection.quantity(of: boxRow.key), 1)
        selection.scanned(box)
        XCTAssertEqual(selection.quantity(of: boxRow.key), 2)
        XCTAssertEqual(selection.pinned, [boxRow.key], "a scanned row comes to the top")
    }

    // MARK: - Order

    /// Rows chosen stay where they are while the plus is tapped; they move to
    /// the top only when the search changes.
    func testTheOrderDoesNotJumpUntilTheSearchChanges() {
        var selection = MissingSelection()
        let matches = [boxRow, cableRow, lampRow]
        selection.step(lampRow, by: 1)
        XCTAssertEqual(selection.rows(matches: matches).map(\.key), matches.map(\.key), "no jump while tapping")

        selection.searchChanged()
        XCTAssertEqual(selection.rows(matches: matches).map(\.key), [lampRow.key, boxRow.key, cableRow.key])

        // The search finds something else: the chosen one is still on top.
        selection.searchChanged()
        XCTAssertEqual(selection.rows(matches: [cableRow]).map(\.key), [lampRow.key, cableRow.key])
    }

    /// A pinned row taken back to nothing stays put, so a slip can be undone,
    /// and goes when the search changes.
    func testARowTakenBackToNothingStaysUntilTheSearchChanges() {
        var selection = MissingSelection()
        selection.step(lampRow, by: 1)
        selection.searchChanged()
        selection.step(lampRow, by: -1)
        XCTAssertEqual(selection.rows(matches: [boxRow]).map(\.key), [lampRow.key, boxRow.key])
        XCTAssertEqual(selection.count, 0)
        selection.searchChanged()
        XCTAssertEqual(selection.rows(matches: [boxRow]).map(\.key), [boxRow.key])
    }

    /// A new item typed under an earlier search is still offered on top.
    func testANewItemFromAnEarlierSearchStaysOnTop() {
        var selection = MissingSelection()
        let typed = MissingSelection.Candidate(newName: "Wago 221", unit: .pieces)
        selection.step(typed, by: 1)
        selection.searchChanged()
        let rows = selection.rows(matches: [boxRow])
        XCTAssertEqual(rows.map(\.key), [typed.key, boxRow.key])
        XCTAssertTrue(rows[0].isNew)
    }

    // MARK: - Adding

    /// Every chosen item is a draft, in the order chosen, with the one note
    /// and who noticed.
    func testTheDraftsAreEveryChosenItemWithTheNote() {
        var selection = MissingSelection()
        selection.step(boxRow, by: 1)
        selection.step(boxRow, by: 1)
        selection.set(cableRow, to: 50)
        selection.step(lampRow, by: 1)
        selection.step(lampRow, by: -1)
        let drafts = selection.drafts(note: "2nd floor", notedBy: "Dusko")
        XCTAssertEqual(drafts, [
            MissingDraft(name: "Junction box IP65", quantity: 2, unit: .pieces, note: "2nd floor", notedBy: "Dusko", catalogItemID: box.id),
            MissingDraft(name: "Cable NYM 3x1.5", quantity: 50, unit: .metres, note: "2nd floor", notedBy: "Dusko", catalogItemID: cable.id),
        ])
    }

    /// Added in one go: an item already needed is counted up, the rest are
    /// new rows.
    func testAddingThemAllCountsUpWhatIsAlreadyNeeded() {
        let before = MissingList.adding(
            MissingDraft(name: "junction box ip65", quantity: 6, unit: .pieces),
            siteID: site, at: thursday, to: []
        ).items
        var selection = MissingSelection()
        selection.set(boxRow, to: 2)
        selection.set(cableRow, to: 50)
        let typed = MissingSelection.Candidate(newName: "Wago 221", unit: .pieces)
        selection.step(typed, by: 1)
        selection.setUnit(.boxes, for: typed.key)

        let after = MissingList.adding(selection.drafts(note: "", notedBy: ""), siteID: site, at: thursday, to: before)
        XCTAssertEqual(after.count, 3)
        XCTAssertEqual(after[0].quantity, 8, "the box already needed is counted up")
        XCTAssertEqual(after[1].name, "Cable NYM 3x1.5")
        XCTAssertEqual(after[1].quantity, 50)
        XCTAssertEqual(after[1].unit, .metres)
        XCTAssertEqual(after[2].name, "Wago 221")
        XCTAssertEqual(after[2].unit, .boxes)
    }

    /// The same item twice in one go (picked and typed again) is one row.
    func testTheSameItemTwiceInOneGoIsOneRow() {
        let drafts = [
            MissingDraft(name: "Junction box IP65", quantity: 2, unit: .pieces),
            MissingDraft(name: "junction box IP65", quantity: 1, unit: .pieces),
        ]
        let after = MissingList.adding(drafts, siteID: site, at: thursday, to: [])
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].quantity, 3)
    }
}
