import XCTest
@testable import Hours

/// A site's Missing list: what the crew needs and has not got, noted the
/// moment it is noticed, ordered, and ticked off when it arrives.
final class MissingListTests: XCTestCase {
    private let site = UUID()
    private let otherSite = UUID()
    private let thursday = Date(timeIntervalSince1970: 1_793_268_000) // Thu 29 Oct 2026, 10:00 UTC
    private var friday: Date { thursday.addingTimeInterval(86_400) }
    private var wednesday: Date { thursday.addingTimeInterval(6 * 86_400) } // 4 Nov 2026

    private func add(
        _ name: String,
        _ quantity: Decimal = 1,
        _ unit: ExtraWorkUnit = .pieces,
        note: String = "",
        by who: String = "",
        on site: UUID? = nil,
        at moment: Date? = nil,
        catalogItemID: UUID? = nil,
        to items: [MissingItem] = []
    ) -> [MissingItem] {
        MissingList.adding(
            MissingDraft(name: name, quantity: quantity, unit: unit, note: note, notedBy: who, catalogItemID: catalogItemID),
            siteID: site ?? self.site,
            at: moment ?? thursday,
            to: items
        ).items
    }

    // MARK: - Adding

    func testAnItemIsNotedAsNeededWithWhoAndWhen() {
        let items = add(" Junction box IP65 ", 6, note: " 2nd floor corridor ", by: "Dusko")
        XCTAssertEqual(items.count, 1)
        let item = items[0]
        XCTAssertEqual(item.name, "Junction box IP65")
        XCTAssertEqual(item.quantity, 6)
        XCTAssertEqual(item.unit, .pieces)
        XCTAssertEqual(item.note, "2nd floor corridor")
        XCTAssertEqual(item.notedBy, "Dusko")
        XCTAssertEqual(item.notedAt, thursday)
        XCTAssertEqual(item.state, .needed)
        XCTAssertNil(item.orderedAt)
        XCTAssertNil(item.arrivedAt)
        XCTAssertEqual(item.siteID, site)
    }

    func testANameOfNothingAddsNothing() {
        XCTAssertTrue(add("   ").isEmpty)
        XCTAssertTrue(add("Box", 0).isEmpty, "none of something is not missing")
    }

    /// Adding the same needed item again counts it up instead of a second row.
    func testTheSameNeededItemAgainIncreasesItsQuantity() {
        var items = add("Junction box IP65", 6, note: "2nd floor")
        items = add("junction box ip65", 2, by: "Dusko", at: friday, to: items)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].quantity, 8)
        XCTAssertEqual(items[0].note, "2nd floor", "the first note stays")
        XCTAssertEqual(items[0].notedAt, thursday)
    }

    func testANoteIsTakenWhenTheFirstHadNone() {
        var items = add("Cable", 50, .metres)
        items = add("Cable", 10, .metres, note: "Stairwell", to: items)
        XCTAssertEqual(items[0].note, "Stairwell")
    }

    func testAnOrderedItemOrAnotherUnitOrSiteIsANewRow() {
        var items = add("Cable", 50, .metres)
        items = add("Cable", 2, .kilograms, to: items)
        items = add("Cable", 5, .metres, on: otherSite, to: items)
        XCTAssertEqual(items.count, 3)
        items = MissingList.marking(items[0].id, .ordered, at: friday, in: items)
        items = add("Cable", 20, .metres, at: friday, to: items)
        XCTAssertEqual(items.count, 4, "the ordered 50 m are on their way; 20 m more are needed")
    }

    // MARK: - Needed, ordered, arrived

    func testMarkingRecordsWhenAndCanGoBack() {
        var items = add("Cable", 50, .metres)
        let id = items[0].id
        items = MissingList.marking(id, .ordered, at: friday, in: items)
        XCTAssertEqual(items[0].state, .ordered)
        XCTAssertEqual(items[0].orderedAt, friday)
        items = MissingList.marking(id, .arrived, at: wednesday, in: items)
        XCTAssertEqual(items[0].state, .arrived)
        XCTAssertEqual(items[0].orderedAt, friday)
        XCTAssertEqual(items[0].arrivedAt, wednesday)
        items = MissingList.marking(id, .needed, at: wednesday, in: items)
        XCTAssertEqual(items[0].state, .needed)
        XCTAssertNil(items[0].orderedAt)
        XCTAssertNil(items[0].arrivedAt)
    }

    func testANeededItemCanArriveWithoutBeingOrdered() {
        var items = add("Cable", 50, .metres)
        items = MissingList.marking(items[0].id, .arrived, at: friday, in: items)
        XCTAssertEqual(items[0].state, .arrived)
        XCTAssertNil(items[0].orderedAt)
        XCTAssertEqual(items[0].arrivedAt, friday)
    }

    func testRemovingTakesTheRowAway() {
        var items = add("Cable", 50, .metres)
        items = add("Box", 2, to: items)
        items = MissingList.removing(items[0].id, from: items)
        XCTAssertEqual(items.map(\.name), ["Box"])
    }

    // MARK: - Counts and order

    func testCountsAreRowsPerState() {
        var items = add("A")
        items = add("B", to: items)
        items = add("C", to: items)
        items = add("D", to: items)
        items = MissingList.marking(items[3].id, .ordered, at: friday, in: items)
        items = MissingList.marking(items[2].id, .arrived, at: friday, in: items)
        XCTAssertEqual(MissingList.count(.needed, in: items), 2)
        XCTAssertEqual(MissingList.count(.ordered, in: items), 1)
        XCTAssertEqual(MissingList.count(.arrived, in: items), 1)
    }

    func testNeededAreOldestFirstAndArrivedNewestFirst() {
        var items = add("Today", at: wednesday)
        items = add("Thursday", at: thursday, to: items)
        items = add("Friday", at: friday, to: items)
        XCTAssertEqual(MissingList.items(.needed, in: items).map(\.name), ["Thursday", "Friday", "Today"])

        items = MissingList.marking(items[1].id, .arrived, at: friday, in: items)
        items = MissingList.marking(items[0].id, .arrived, at: wednesday, in: items)
        XCTAssertEqual(MissingList.items(.arrived, in: items).map(\.name), ["Today", "Thursday"])

        items = MissingList.marking(items[2].id, .ordered, at: wednesday, in: items)
        XCTAssertEqual(MissingList.items(.ordered, in: items).map(\.name), ["Friday"])
    }

    // MARK: - Scanning a delivery

    func testAScannedCodeFindsTheOrderedItemFirst() {
        let box = ExtraWorkCatalogItem(name: "Junction box IP65", unit: .pieces, barcodes: ["4015081677891"])
        var items = add("Junction box IP65", 6, catalogItemID: box.id)
        items = MissingList.marking(items[0].id, .ordered, at: friday, in: items)
        items = add("Junction box IP65", 2, at: wednesday, to: items)
        let match = MissingList.arrivalMatch(forCode: "4015081677891", catalog: [box], in: items)
        XCTAssertEqual(match?.quantity, 6)
        XCTAssertEqual(match?.state, .ordered)
    }

    func testAScannedCodeFindsANeededItemByName() {
        let box = ExtraWorkCatalogItem(name: "Junction box IP65", unit: .pieces, barcodes: ["111"])
        let items = add("junction box IP65", 6)
        XCTAssertEqual(MissingList.arrivalMatch(forCode: "111", catalog: [box], in: items)?.id, items[0].id)
        XCTAssertNil(MissingList.arrivalMatch(forCode: "222", catalog: [box], in: items))
        let arrived = MissingList.marking(items[0].id, .arrived, at: friday, in: items)
        XCTAssertNil(MissingList.arrivalMatch(forCode: "111", catalog: [box], in: arrived), "arrived already")
    }

    // MARK: - Sending

    private var sample: [MissingItem] {
        var items = add("Junction box IP65", 6, note: "2nd floor corridor", at: thursday)
        items = add("Cable NYM 3×1.5", 50, .metres, at: friday, to: items)
        items = add("LED panel 60×60", 4, by: "Dusko", at: wednesday, to: items)
        return items
    }

    func testTheMessageIsTheSiteTheDayTheLinesAndYourName() {
        let text = MissingMessage(
            siteName: "Trg Pravde Zagreb",
            date: CalendarDate(year: 2026, month: 11, day: 4),
            items: MissingList.toSend(sample),
            catalog: [],
            includesCodes: false,
            ownerName: "Marijo Mikša",
            language: .english,
            decimalSeparator: ".",
            calendar: Fixture.calendar()
        ).text
        XCTAssertEqual(text, """
        Trg Pravde Zagreb · missing, 4 Nov
        6 × Junction box IP65
        50 m Cable NYM 3×1.5
        4 × LED panel 60×60

        Marijo Mikša
        """)
    }

    func testTheMessageCanCarryTheCodesAndIsInTheExportLanguage() {
        let box = ExtraWorkCatalogItem(name: "Junction box IP65", unit: .pieces, barcodes: ["4015081677891"])
        let items = MissingList.toSend(add("Junction box IP65", 6, catalogItemID: box.id, to: add("Kabel", Decimal(string: "12.5")!, .metres)))
        let text = MissingMessage(
            siteName: "Bau Süd",
            date: CalendarDate(year: 2026, month: 11, day: 4),
            items: items,
            catalog: [box],
            includesCodes: true,
            ownerName: "",
            language: .german,
            decimalSeparator: ",",
            calendar: Fixture.calendar()
        ).text
        XCTAssertEqual(text, """
        Bau Süd · fehlt, 4. Nov.
        6 × Junction box IP65 (4015081677891)
        12,5 m Kabel
        """, "noted together: by name")
    }

    func testOnlyTheNeededAreSentAndSendingMarksThemOrdered() {
        var items = sample
        items = MissingList.marking(items[2].id, .ordered, at: thursday, in: items)
        let sent = MissingList.toSend(items)
        XCTAssertEqual(sent.map(\.name), ["Junction box IP65", "Cable NYM 3×1.5"])
        let after = MissingList.markingOrdered(sent, at: wednesday, in: items)
        XCTAssertEqual(MissingList.count(.needed, in: after), 0)
        XCTAssertEqual(MissingList.count(.ordered, in: after), 3)
        XCTAssertEqual(after.first { $0.id == items[2].id }?.orderedAt, thursday, "ordered before stays as it was")
        XCTAssertEqual(after.first { $0.id == items[0].id }?.orderedAt, wednesday)
    }

    func testWithNothingNeededTheOrderedAreSentAgain() {
        var items = add("Cable", 50, .metres)
        items = MissingList.marking(items[0].id, .ordered, at: friday, in: items)
        XCTAssertEqual(MissingList.toSend(items).map(\.name), ["Cable"])
        XCTAssertTrue(MissingList.toSend([]).isEmpty)
    }

    func testThePDFTableHasTheCodesAndNotes() {
        let box = ExtraWorkCatalogItem(name: "Junction box IP65", unit: .pieces, barcodes: ["4015081677891"])
        var items = add("Junction box IP65", 6, note: "2nd floor corridor", catalogItemID: box.id)
        items = add("Cable", 50, .metres, at: friday, to: items)
        let message = MissingMessage(
            siteName: "Trg Pravde Zagreb",
            date: CalendarDate(year: 2026, month: 11, day: 4),
            items: MissingList.toSend(items),
            catalog: [box],
            includesCodes: true,
            ownerName: "Marijo Mikša",
            language: .english,
            decimalSeparator: ".",
            calendar: Fixture.calendar()
        )
        XCTAssertEqual(message.title, "Missing material")
        XCTAssertEqual(message.subtitle, "Trg Pravde Zagreb · 4 Nov 2026")
        XCTAssertEqual(message.headings, ["Quantity", "Item", "Code", "Note"])
        XCTAssertEqual(message.rows.map(\.quantity), ["6 pcs", "50 m"])
        XCTAssertEqual(message.rows.map(\.code), ["4015081677891", ""])
        XCTAssertEqual(message.rows.map(\.note), ["2nd floor corridor", ""])
        XCTAssertEqual(message.fileName, "Trg Pravde Zagreb - Missing material 2026-11-04")
    }

    /// The day under a row: "Thu 29".
    func testARowsDayIsTheWeekdayAndTheDay() {
        let formatting = CalendarFormatting(locale: Locale(identifier: "en_GB"), calendar: Fixture.calendar())
        XCTAssertEqual(formatting.shortWeekdayAndDay(CalendarDate(year: 2026, month: 10, day: 29)), "Thu 29")
    }

    func testEveryNewTermHasAWordInEveryLanguage() {
        for language in ExportLanguage.allCases {
            for term in [ExtraWorkTerm.missing, .missingMaterial, .code, .note, .unitBoxes] {
                XCTAssertFalse(language(term).isEmpty, "\(term) in \(language)")
            }
        }
    }

    // MARK: - Backups

    func testAnItemSurvivesCodingAndAPartialOneReadsWithDefaults() throws {
        var items = add("Cable", Decimal(string: "12.5")!, .metres, note: "Stairwell", by: "Dusko")
        items = MissingList.marking(items[0].id, .ordered, at: friday, in: items)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MissingItem.self, from: encoder.encode(items[0]))
        XCTAssertEqual(decoded, items[0])
        XCTAssertTrue(String(decoding: try encoder.encode(items[0]), as: UTF8.self).contains(#""quantity":"12.5""#))

        let partial = Data(#"{"id":"\#(UUID().uuidString)","siteID":"\#(site.uuidString)","name":"Box","state":"later"}"#.utf8)
        let read = try decoder.decode(MissingItem.self, from: partial)
        XCTAssertEqual(read.name, "Box")
        XCTAssertEqual(read.quantity, 1)
        XCTAssertEqual(read.unit, .pieces)
        XCTAssertEqual(read.state, .needed, "a state from a later version reads as needed")
    }

    func testABackupCarriesTheListAndAnOlderOneHasNone() throws {
        var archive = BackupArchive(settings: AppSettings(), days: [], holidays: [], sites: [Site(name: "A")])
        let items = sample
        archive.missingItems = items
        let decoded = try BackupArchive.decoded(from: archive.encoded())
        XCTAssertEqual(decoded.missingItems, items)

        let older = BackupArchive(settings: AppSettings(), days: [], holidays: [])
        XCTAssertNil(try BackupArchive.decoded(from: older.encoded()).missingItems)
        XCTAssertFalse(String(decoding: try older.encoded(), as: UTF8.self).contains("missingItems"))
    }

    /// An older file keeps the device's list for the sites it restores, as
    /// the diary and extra work do.
    func testRestoringAnOlderFileKeepsTheListForTheSitesItRestores() {
        let onDevice = add("Box", on: site) + add("Cable", on: otherSite)
        let kept = BackupArchive.restoredItems(fromFile: nil, onDevice: onDevice, restoredSiteIDs: [site], siteID: \.siteID)
        XCTAssertEqual(kept.map(\.name), ["Box"])
    }
}
