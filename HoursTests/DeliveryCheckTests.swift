import XCTest
@testable import Hours

/// Checking a delivery against what is ordered: boxes scanned count up,
/// a roll of cable is set to the order and corrected, what was not ordered
/// comes anyway; saving splits what partly came and the message says what
/// is still missing.
final class DeliveryCheckTests: XCTestCase {
    private let site = UUID()
    private let monday = Date(timeIntervalSince1970: 1_793_613_600) // Mon 2 Nov 2026, 10:00 UTC
    private var wednesday: Date { monday.addingTimeInterval(2 * 86_400) } // 4 Nov 2026

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let box = ExtraWorkCatalogItem(name: "Junction box IP65", unit: .pieces, barcodes: ["111"])
    private let cable = ExtraWorkCatalogItem(name: "Cable NYM 3×1.5", unit: .metres, barcodes: ["222"])
    private let panel = ExtraWorkCatalogItem(name: "LED panel 60×60", unit: .pieces, barcodes: ["333"])
    private let light = ExtraWorkCatalogItem(name: "Emergency light 3h", unit: .pieces, barcodes: ["444"])
    private var catalog: [ExtraWorkCatalogItem] { [box, cable, panel, light] }

    /// Junction boxes (6), cable (50 m) and panels (4) ordered on Monday;
    /// something needed but not ordered yet.
    private func list() -> [MissingItem] {
        func ordered(_ item: ExtraWorkCatalogItem, _ quantity: Decimal, catalogued: Bool = true) -> MissingItem {
            MissingItem(
                siteID: site, name: item.name, catalogItemID: catalogued ? item.id : nil, quantity: quantity, unit: item.unit,
                notedAt: monday, state: .ordered, orderedAt: monday, updatedAt: monday
            )
        }
        return [
            ordered(box, 6),
            ordered(cable, 50),
            // Picked by name, not from the remembered list: matched by name.
            ordered(panel, 4, catalogued: false),
            MissingItem(siteID: site, name: "Wall bracket", quantity: 20, notedAt: monday),
        ]
    }

    private func expected(_ check: DeliveryCheck, _ prefix: String) -> MissingItem {
        check.expected.first { $0.name.hasPrefix(prefix) }!
    }

    func testOnlyTheOrderedItemsAreExpected() {
        let check = DeliveryCheck(expected: list())
        XCTAssertEqual(check.expected.map(\.name), ["Cable NYM 3×1.5", "Junction box IP65", "LED panel 60×60"], "as the Ordered tab lists them")
        XCTAssertFalse(check.hasAnything)
    }

    func testEachBoxCountsOneOfItsItem() {
        var check = DeliveryCheck(expected: list())
        let boxes = expected(check, "Junction")
        for _ in 0..<5 { XCTAssertEqual(check.scan("111", catalog: catalog), .counted(boxes.id)) }
        XCTAssertEqual(check.progress(of: boxes), .partly)
        _ = check.scan(" 111 ", catalog: catalog)
        XCTAssertEqual(check.cameAmount(of: boxes.id), 6)
        XCTAssertEqual(check.progress(of: boxes), .full)
        XCTAssertEqual(check.progress(of: expected(check, "LED")), .notYet)
        XCTAssertEqual(check.hereCount, 1)
        XCTAssertEqual(check.focus, .expected(boxes.id))
    }

    func testARollIsSetToTheOrderAndCorrected() {
        var check = DeliveryCheck(expected: list())
        let roll = expected(check, "Cable")
        XCTAssertEqual(check.scan("222", catalog: catalog), .measured(roll.id))
        XCTAssertEqual(check.cameAmount(of: roll.id), 50, "the order's amount")
        _ = check.scan("222", catalog: catalog)
        XCTAssertEqual(check.cameAmount(of: roll.id), 50, "scanning it again does not add another order")
        for _ in 0..<20 { check.step(roll.id, by: -1) }
        XCTAssertEqual(check.cameAmount(of: roll.id), 30)
        XCTAssertEqual(check.progress(of: roll), .partly)
        for _ in 0..<40 { check.step(roll.id, by: -1) }
        XCTAssertEqual(check.cameAmount(of: roll.id), 0, "never below none")
    }

    func testAnItemPickedByNameIsFoundByItsCodesName() {
        var check = DeliveryCheck(expected: list())
        XCTAssertEqual(check.scan("333", catalog: catalog), .counted(expected(check, "LED").id))
    }

    func testWhatIsNotOrderedComesAnywayAndANewCodeAsksFirst() {
        var check = DeliveryCheck(expected: list())
        XCTAssertEqual(check.scan("444", catalog: catalog), .extra(0))
        XCTAssertEqual(check.scan("444", catalog: catalog), .extra(0))
        XCTAssertEqual(check.extras.first?.came, 2)
        XCTAssertEqual(check.scan("999", catalog: catalog), .unknown("999"))
        XCTAssertEqual(check.scan("   ", catalog: catalog), .ignored)

        let named = ExtraWorkCatalogItem(name: "Wago 221", unit: .boxes, barcodes: ["999"])
        XCTAssertEqual(check.addingExtra(named), 1)
        XCTAssertEqual(check.extras.map(\.name), ["Emergency light 3h", "Wago 221"])
        XCTAssertTrue(check.hasAnything)

        check.stepExtra(1, by: -1)
        XCTAssertEqual(check.extras.map(\.name), ["Emergency light 3h"], "at none it is gone")
    }

    /// The mockup's delivery: the boxes all came, 30 of 50 m of cable, no
    /// panels, and two emergency lights nobody ordered.
    private func mockupDelivery(of items: [MissingItem]? = nil) -> DeliveryCheck {
        var check = DeliveryCheck(expected: items ?? list())
        for _ in 0..<6 { _ = check.scan("111", catalog: catalog) }
        _ = check.scan("222", catalog: catalog)
        for _ in 0..<20 { check.step(expected(check, "Cable").id, by: -1) }
        _ = check.scan("444", catalog: catalog)
        _ = check.scan("444", catalog: catalog)
        return check
    }

    func testTheResultSaysArrivedShortAndExtra() {
        let lines = mockupDelivery().lines
        XCTAssertEqual(lines.map(\.kind), [.arrived, .short, .short, .extra])
        XCTAssertEqual(lines.map(\.name), ["Junction box IP65", "Cable NYM 3×1.5", "LED panel 60×60", "Emergency light 3h"])
        XCTAssertEqual(lines[1].came, 30)
        XCTAssertEqual(lines[1].remainder, 20)
        XCTAssertEqual(lines[2].remainder, 4, "nothing came: all of it stays ordered")
        XCTAssertEqual(lines[0].cameAmount(in: .english, decimalSeparator: "."), "6 pcs")
        XCTAssertEqual(lines[1].remainderLine(in: .english, decimalSeparator: "."), "20 m Cable NYM 3×1.5")
        XCTAssertEqual(lines[3].cameLine(in: .english, decimalSeparator: "."), "2 × Emergency light 3h")
        XCTAssertNil(lines[3].missingItemID)
    }

    func testSavingMovesWhatCameAndKeepsTheRestOrdered() {
        let before = list()
        let after = DeliveryCheck.applying(mockupDelivery(of: before).lines, to: before, at: wednesday)

        let arrived = MissingList.items(.arrived, in: after)
        let ordered = MissingList.items(.ordered, in: after)
        XCTAssertEqual(arrived.map(\.name).sorted(), ["Cable NYM 3×1.5", "Junction box IP65"])
        XCTAssertEqual(arrived.first { $0.name.hasPrefix("Cable") }?.quantity, 30, "the part that came")
        XCTAssertEqual(arrived.first { $0.name.hasPrefix("Junction") }?.arrivedAt, wednesday)
        XCTAssertEqual(ordered.map(\.name), ["Cable NYM 3×1.5", "LED panel 60×60"])
        let rest = ordered[0]
        XCTAssertEqual(rest.quantity, 20, "the remainder stays ordered")
        XCTAssertEqual(rest.id, before.first { $0.name.hasPrefix("Cable") }?.id, "on the item's own row")
        XCTAssertEqual(rest.orderedAt, monday, "ordered when it was")
        XCTAssertEqual(ordered[1].quantity, 4)
        XCTAssertEqual(MissingList.count(.needed, in: after), 1, "the needed item is untouched")
        XCTAssertFalse(after.contains { $0.name.hasPrefix("Emergency") }, "what came anyway is not added to Missing")
        XCTAssertEqual(after.count, before.count + 1, "one split")
    }

    func testTheMessageSaysWhatIsStillMissingAndWhatCameAnyway() {
        let message = DeliveryMessage(
            siteName: "Trg Pravde Zagreb",
            date: CalendarDate(year: 2026, month: 11, day: 4),
            lines: mockupDelivery().lines,
            ownerName: "Marijo Mikša",
            language: .english,
            decimalSeparator: ".",
            calendar: utc
        )
        XCTAssertEqual(
            message.text,
            """
            Trg Pravde Zagreb · delivery, 4 Nov

            Still missing:
            20 m Cable NYM 3×1.5
            4 × LED panel 60×60

            Not ordered, came anyway:
            2 × Emergency light 3h

            Marijo Mikša
            """
        )
    }

    func testEverythingCameSaysSo() {
        var check = DeliveryCheck(expected: [list()[0]])
        for _ in 0..<6 { _ = check.scan("111", catalog: catalog) }
        let message = DeliveryMessage(
            siteName: "Bau Süd", date: CalendarDate(year: 2026, month: 11, day: 4), lines: check.lines,
            ownerName: "", language: .german, decimalSeparator: ",", calendar: utc
        )
        XCTAssertEqual(message.text, "Bau Süd · Lieferung, 4. Nov.\n\nAlles Bestellte ist gekommen.")
    }

    func testADeliveryRoundTripsWithItsPhotoAndReadsLeniently() throws {
        let delivery = Delivery(
            siteID: site, receivedAt: wednesday, lines: mockupDelivery().lines, photoData: Data([9, 8, 7]), updatedAt: wednesday
        )
        XCTAssertTrue(delivery.hasPhoto)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Delivery.self, from: try encoder.encode(delivery))
        XCTAssertEqual(decoded, delivery)
        XCTAssertEqual(decoded.lines(.short).count, 2)

        let odd = try decoder.decode(DeliveryLine.self, from: Data(#"{"kind":"lost","name":"Box","came":"2.5"}"#.utf8))
        XCTAssertEqual(odd.kind, .extra)
        XCTAssertEqual(odd.came, Decimal(string: "2.5"))
        XCTAssertEqual(odd.ordered, Decimal(string: "2.5"))
    }
}
