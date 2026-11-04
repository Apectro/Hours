import XCTest
@testable import Hours

/// Scanning material: a code is named once and known from then on, on every
/// site; the items used on the site are offered first; one box held in front
/// of the camera counts once.
final class BarcodeScanTests: XCTestCase {
    private let monday = Date(timeIntervalSince1970: 1_792_000_000)
    private var tuesday: Date { monday.addingTimeInterval(86_400) }
    private let zagreb = UUID()
    private let graz = UUID()

    // MARK: - Codes

    func testACodeIsTrimmedAndAnEmptyOneIsNone() {
        XCTAssertEqual(ExtraWorkCatalog.code("  4015081123456\n"), "4015081123456")
        XCTAssertEqual(ExtraWorkCatalog.code("ABC 123"), "ABC 123", "a QR code can hold a space")
        XCTAssertNil(ExtraWorkCatalog.code("   "))
        XCTAssertNil(ExtraWorkCatalog.code(""))
    }

    func testAnItemIsFoundByAnyOfItsCodes() {
        let lamp = ExtraWorkCatalogItem(name: "Emergency light 3h", unit: .pieces, barcodes: ["111", "222"])
        let cable = ExtraWorkCatalogItem(name: "Cable", unit: .metres)
        XCTAssertEqual(ExtraWorkCatalog.item(forCode: "222", in: [cable, lamp])?.id, lamp.id)
        XCTAssertEqual(ExtraWorkCatalog.item(forCode: " 111 ", in: [cable, lamp])?.id, lamp.id)
        XCTAssertNil(ExtraWorkCatalog.item(forCode: "333", in: [cable, lamp]))
    }

    func testNamingANewCodeMakesAnItemWithIt() {
        let named = ExtraWorkCatalog.naming(code: "4015081677891", name: " Junction box IP65 ", unit: .pieces, in: [], at: monday)
        XCTAssertEqual(named.catalog.count, 1)
        XCTAssertEqual(named.item.name, "Junction box IP65")
        XCTAssertEqual(named.item.barcodes, ["4015081677891"])
        XCTAssertEqual(named.item.unit, .pieces)
        XCTAssertEqual(named.catalog[0], named.item)
    }

    /// Naming a code with the name of an item already there gives that item
    /// the code instead of a second item of the same name.
    func testNamingACodeAfterAnItemAlreadyThereAddsTheCodeToIt() {
        let box = ExtraWorkCatalogItem(name: "Junction box IP65", unit: .pieces, useCount: 3, barcodes: ["111"])
        let named = ExtraWorkCatalog.naming(code: "222", name: "junction box ip65", unit: .boxes, in: [box], at: monday)
        XCTAssertEqual(named.catalog.count, 1)
        XCTAssertEqual(named.item.id, box.id)
        XCTAssertEqual(named.item.barcodes, ["111", "222"])
        XCTAssertEqual(named.item.unit, .boxes)
        XCTAssertEqual(named.item.useCount, 3)
    }

    /// One code is one item: given to another, it leaves the first.
    func testACodeBelongsToOneItem() {
        let first = ExtraWorkCatalogItem(name: "Cable tie", unit: .pieces, barcodes: ["999"])
        let second = ExtraWorkCatalogItem(name: "Wago 221", unit: .pieces)
        let moved = ExtraWorkCatalog.addingCode("999", to: second.id, in: [first, second])
        XCTAssertEqual(moved.first { $0.id == first.id }?.barcodes, [])
        XCTAssertEqual(moved.first { $0.id == second.id }?.barcodes, ["999"])
        let removed = ExtraWorkCatalog.removingCode("999", from: second.id, in: moved)
        XCTAssertEqual(removed.first { $0.id == second.id }?.barcodes, [])
    }

    func testTheSameCodeTwiceOnAnItemIsKeptOnce() {
        let item = ExtraWorkCatalogItem(name: "Cable tie", unit: .pieces, barcodes: ["999"])
        let again = ExtraWorkCatalog.addingCode(" 999", to: item.id, in: [item])
        XCTAssertEqual(again[0].barcodes, ["999"])
    }

    // MARK: - Per site

    func testUsingAnItemOnASiteRemembersTheSite() {
        let first = ExtraWorkCatalog.recording(
            [ExtraWorkItem(name: "Wago 221", quantity: 4, unit: .pieces)], into: [], at: monday, siteID: zagreb
        )
        XCTAssertEqual(first[0].siteIDs, [zagreb])
        let second = ExtraWorkCatalog.recording(
            [ExtraWorkItem(name: "wago 221", quantity: 1, unit: .pieces)], into: first, at: tuesday, siteID: graz
        )
        XCTAssertEqual(second[0].siteIDs, [zagreb, graz])
        let third = ExtraWorkCatalog.recording(
            [ExtraWorkItem(name: "Wago 221", quantity: 1, unit: .pieces)], into: second, at: tuesday, siteID: zagreb
        )
        XCTAssertEqual(third[0].siteIDs, [zagreb, graz])
    }

    /// Recording keeps the codes an item has.
    func testRecordingKeepsTheCodes() {
        let lamp = ExtraWorkCatalogItem(name: "Lamp", unit: .pieces, barcodes: ["111"])
        let after = ExtraWorkCatalog.recording([ExtraWorkItem(name: "Lamp", quantity: 1, unit: .pieces)], into: [lamp], at: monday)
        XCTAssertEqual(after[0].barcodes, ["111"])
    }

    func testTheSitesItemsAreSuggestedFirst() {
        let catalog = [
            ExtraWorkCatalogItem(name: "Socket", unit: .pieces, useCount: 9, lastUsed: tuesday, siteIDs: [graz]),
            ExtraWorkCatalogItem(name: "Junction box", unit: .pieces, useCount: 2, lastUsed: monday, siteIDs: [zagreb]),
            ExtraWorkCatalogItem(name: "Cable tie", unit: .pieces, useCount: 1, lastUsed: tuesday)
        ]
        XCTAssertEqual(ExtraWorkCatalog.suggestions(from: catalog, excluding: [], siteID: zagreb).map(\.name),
                       ["Junction box", "Socket", "Cable tie"])
        XCTAssertEqual(ExtraWorkCatalog.suggestions(from: catalog, excluding: []).map(\.name),
                       ["Socket", "Cable tie", "Junction box"], "without a site, as before")
    }

    func testSearchFindsPartOfANameWithTheSitesItemsFirst() {
        let catalog = [
            ExtraWorkCatalogItem(name: "Junction box 100×100", unit: .pieces, useCount: 1, lastUsed: tuesday),
            ExtraWorkCatalogItem(name: "Junction box IP65", unit: .pieces, useCount: 3, lastUsed: monday, siteIDs: [zagreb]),
            ExtraWorkCatalogItem(name: "Cable NYM 3×1.5", unit: .metres, useCount: 8, lastUsed: tuesday)
        ]
        XCTAssertEqual(ExtraWorkCatalog.search("junc", in: catalog, siteID: zagreb).map(\.name),
                       ["Junction box IP65", "Junction box 100×100"])
        XCTAssertEqual(ExtraWorkCatalog.search("  ", in: catalog, siteID: zagreb).map(\.name),
                       ["Junction box IP65", "Cable NYM 3×1.5", "Junction box 100×100"],
                       "nothing typed: everything, the site's first, then the most used")
        XCTAssertEqual(ExtraWorkCatalog.search("ÇABLE", in: catalog, siteID: nil).map(\.name), ["Cable NYM 3×1.5"])
    }

    func testSearchFindsAnItemByItsCode() {
        let catalog = [ExtraWorkCatalogItem(name: "Lamp", unit: .pieces, barcodes: ["4015081123456"])]
        XCTAssertEqual(ExtraWorkCatalog.search("40150811", in: catalog, siteID: nil).map(\.name), ["Lamp"])
    }

    // MARK: - Backups of the catalogue

    func testCodesAndSitesSurviveCodingAndAnOlderItemReadsWithNone() throws {
        let item = ExtraWorkCatalogItem(name: "Lamp", unit: .boxes, useCount: 2, lastUsed: monday, barcodes: ["111"], siteIDs: [zagreb])
        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(ExtraWorkCatalogItem.self, from: data), item)

        let old = Data(#"{"id":"\#(UUID().uuidString)","name":"Kabel","unit":"m","useCount":1,"lastUsed":0}"#.utf8)
        let decoded = try JSONDecoder().decode(ExtraWorkCatalogItem.self, from: old)
        XCTAssertEqual(decoded.barcodes, [])
        XCTAssertEqual(decoded.siteIDs, [])
    }

    func testAnItemWithoutCodesWritesNoCodeKeys() throws {
        let data = try JSONEncoder().encode(ExtraWorkCatalogItem(name: "Lamp", unit: .pieces))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("barcodes"))
        XCTAssertFalse(text.contains("siteIDs"))
    }

    // MARK: - Boxes

    func testBoxIsABuiltInUnitWithAWordInEveryLanguage() {
        XCTAssertTrue(ExtraWorkUnit.builtIn.contains(.boxes))
        XCTAssertEqual(ExtraWorkUnit(code: "box"), .boxes)
        XCTAssertEqual(ExtraWorkUnit.boxes.name(in: .english), "box")
        XCTAssertEqual(ExtraWorkUnit.boxes.name(in: .german), "Karton")
        XCTAssertEqual(ExtraWorkUnit.typed("Karton"), .boxes)
        XCTAssertFalse(ExtraWorkUnit.boxes.isCount, "6 box Junction box, not 6 × Junction box")
    }

    /// What the New item sheet offers under Counted in.
    func testTheScannerOffersFourUnits() {
        XCTAssertEqual(ExtraWorkScan.units, [.pieces, .metres, .kilograms, .boxes])
    }

    // MARK: - One box, counted once

    func testTheSameCodeWithinASecondAndAHalfIsIgnored() {
        var filter = ScanRepeatFilter()
        XCTAssertTrue(filter.accepts("111", at: monday))
        XCTAssertFalse(filter.accepts("111", at: monday.addingTimeInterval(0.5)))
        XCTAssertFalse(filter.accepts("111", at: monday.addingTimeInterval(1.9)), "still in front of the camera")
        XCTAssertTrue(filter.accepts("222", at: monday.addingTimeInterval(2)))
        XCTAssertTrue(filter.accepts("111", at: monday.addingTimeInterval(3.5)))
    }

    // MARK: - Adding to a job

    func testAScanAddsOneOfTheItemOrStartsALine() {
        let lamp = ExtraWorkCatalogItem(name: "Emergency light 3h", unit: .pieces)
        var items = [ExtraWorkItem(name: "Cable", quantity: 25, unit: .metres)]
        items = ExtraWorkScan.adding(lamp, by: 1, to: items)
        XCTAssertEqual(items.map(\.name), ["Cable", "Emergency light 3h"])
        XCTAssertEqual(items[1].quantity, 1)
        items = ExtraWorkScan.adding(lamp, by: 1, to: items)
        XCTAssertEqual(items[1].quantity, 2)
        items = ExtraWorkScan.adding(lamp, by: -1, to: items)
        XCTAssertEqual(items[1].quantity, 1)
        XCTAssertEqual(ExtraWorkScan.quantity(of: lamp, in: items), 1)
        items = ExtraWorkScan.adding(lamp, by: -1, to: items)
        XCTAssertEqual(items[1].quantity, 0, "kept at zero: the line is the editor's to remove")
    }

    func testTheSessionListsWhatWasScannedAndCountsWhatItAdded() {
        let lamp = ExtraWorkCatalogItem(name: "Emergency light 3h", unit: .pieces)
        let panel = ExtraWorkCatalogItem(name: "LED panel 60×60", unit: .pieces)
        var session = ScanSession()
        session.record(panel, by: 1)
        session.record(lamp, by: 1)
        session.record(panel, by: 1)
        session.record(lamp, by: -1)
        XCTAssertEqual(session.lines.map(\.name), ["LED panel 60×60", "Emergency light 3h"])
        XCTAssertEqual(session.last?.name, "Emergency light 3h")
        XCTAssertEqual(session.added, 2)
    }
}
