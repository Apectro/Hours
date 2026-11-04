import XCTest
@testable import Hours

/// A site's defects: noted with a photo and where, grouped by the site's
/// floors, fixed by you with the day, sent as a list; the marks over the
/// photo; the site's floors and rooms.
final class DefectListTests: XCTestCase {
    private let site = UUID()
    private let monday = Date(timeIntervalSince1970: 1_793_613_600) // Mon 2 Nov 2026, 10:00 UTC
    private var tuesday: Date { monday.addingTimeInterval(86_400) }
    private var wednesday: Date { monday.addingTimeInterval(2 * 86_400) }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func defect(
        _ what: String,
        floor: String = "",
        room: String = "",
        at moment: Date? = nil,
        assignee: DefectAssignee = .nobody,
        notedBy: String = ""
    ) -> Defect {
        DefectList.making(
            DefectDraft(what: what, floor: floor, room: room, assignee: assignee, notedBy: notedBy),
            siteID: site,
            at: moment ?? monday
        )!
    }

    // MARK: - States

    func testANewDefectIsOpenWithItsTextsTidied() throws {
        let made = try XCTUnwrap(DefectList.making(
            DefectDraft(what: "  Socket   loose ", floor: " 2nd floor", room: "Room 4 ", notedBy: " Ivan "),
            siteID: site,
            at: monday
        ))
        XCTAssertEqual(made.what, "Socket loose")
        XCTAssertEqual(made.floor, "2nd floor")
        XCTAssertEqual(made.room, "Room 4")
        XCTAssertEqual(made.notedBy, "Ivan")
        XCTAssertEqual(made.state, .open)
        XCTAssertNil(made.fixedAt)
        XCTAssertEqual(made.whereLine, "2nd floor · Room 4")
    }

    func testADefectMustSayWhatIsWrong() {
        XCTAssertNil(DefectList.making(DefectDraft(what: "   ", floor: "Roof"), siteID: site, at: monday))
    }

    func testFixedIsByYouWithTheDayAndReopeningForgetsIt() {
        let open = defect("Socket loose")
        let fixed = DefectList.fixed(open, at: tuesday)
        XCTAssertEqual(fixed.state, .fixed)
        XCTAssertEqual(fixed.fixedAt, tuesday)
        XCTAssertEqual(DefectList.fixed(fixed, at: wednesday).fixedAt, tuesday, "fixing again keeps the day")
        let reopened = DefectList.reopened(fixed, at: wednesday)
        XCTAssertEqual(reopened.state, .open)
        XCTAssertNil(reopened.fixedAt)
        XCTAssertEqual(reopened.updatedAt, wednesday)
    }

    func testAStateThisVersionDoesNotKnowReadsAsOpen() {
        XCTAssertEqual(DefectState(storedValue: "verified"), .open)
        XCTAssertEqual(DefectState(storedValue: "fixed"), .fixed)
    }

    func testCountsAndTheOrderOfEachTab() {
        let a = defect("A", at: tuesday)
        let b = defect("B", at: monday)
        let c = DefectList.fixed(defect("C", at: monday), at: tuesday)
        let d = DefectList.fixed(defect("D", at: monday), at: wednesday)
        let all = [a, b, c, d]
        XCTAssertEqual(DefectList.count(.open, in: all), 2)
        XCTAssertEqual(DefectList.count(.fixed, in: all), 2)
        XCTAssertEqual(DefectList.items(.open, in: all).map(\.what), ["B", "A"], "the longest waiting first")
        XCTAssertEqual(DefectList.items(.fixed, in: all).map(\.what), ["D", "C"], "the latest fixed first")
    }

    // MARK: - Grouping by floor

    func testGroupsFollowTheSiteFloorOrderUnlistedNextNoFloorLast() {
        let floors = ["Basement", "Ground", "1st floor", "2nd floor", "Roof"]
        let defects = [
            defect("Cable not labelled", floor: "ground"),
            defect("Gutter", floor: "Attic"),
            defect("Loose tile"),
            defect("Socket loose", floor: "2nd floor"),
            defect("Emergency light", floor: "Ground"),
        ]
        let groups = DefectList.groupedByFloor(defects, floors: floors)
        XCTAssertEqual(groups.map(\.floor), ["Ground", "2nd floor", "Attic", ""])
        XCTAssertEqual(groups[0].defects.map(\.what), ["Cable not labelled", "Emergency light"], "a floor matches whatever its case")
        XCTAssertEqual(groups.last?.defects.map(\.what), ["Loose tile"])
    }

    func testTheListedOrderNumbersByFloor() {
        let floors = ["Ground", "1st floor", "2nd floor"]
        let defects = [
            defect("Socket loose", floor: "2nd floor", at: monday),
            defect("Cable", floor: "Ground", at: tuesday),
            DefectList.fixed(defect("Fixed one", floor: "Ground", at: monday), at: tuesday),
        ]
        XCTAssertEqual(DefectList.listed(defects, state: .open, floors: floors).map(\.what), ["Cable", "Socket loose"])
        XCTAssertEqual(DefectList.listed(defects, state: nil, floors: floors).map(\.what), ["Cable", "Fixed one", "Socket loose"])
    }

    // MARK: - Chips

    func testWhatSuggestionsAreTheMostUsedFirstThenTheLatest() {
        let defects = [
            defect("Socket loose", at: monday),
            defect("Cover missing", at: wednesday),
            defect("socket  LOOSE", at: tuesday),
            defect("Not labelled", at: tuesday),
        ]
        XCTAssertEqual(
            DefectList.whatSuggestions(defects),
            ["socket LOOSE", "Cover missing", "Not labelled"],
            "two uses first, written as last written; then the latest"
        )
        XCTAssertEqual(DefectList.whatSuggestions(defects, limit: 1).count, 1)
    }

    func testRoomSuggestionsRankUsesAndKeepRememberedRooms() {
        let defects = [
            defect("A", room: "Corridor", at: monday),
            defect("B", room: "Room 4", at: tuesday),
            defect("C", room: "room 4", at: wednesday),
        ]
        XCTAssertEqual(
            DefectList.roomSuggestions(defects, remembered: ["Stairs", "Corridor", "Room 4"]),
            ["room 4", "Corridor", "Stairs"]
        )
        XCTAssertEqual(DefectList.remembering(room: " Panel  room ", in: ["Stairs"]), ["Stairs", "Panel room"])
        XCTAssertEqual(DefectList.remembering(room: "stairs", in: ["Stairs"]), ["Stairs"], "once whatever its case")
        XCTAssertEqual(DefectList.remembering(room: "  ", in: ["Stairs"]), ["Stairs"])
    }

    // MARK: - Floors

    private func floorName(_ number: Int) -> String { "\(number). OG" }

    func testAddingFloorsOneToNGoesUnderTheRoofAndSkipsThoseThere() {
        let floors = SiteFloors.addingNumbered(
            upTo: 3,
            to: ["Ground", "1. OG", "Roof"],
            name: floorName,
            above: ["Roof"]
        )
        XCTAssertEqual(floors, ["Ground", "1. OG", "2. OG", "3. OG", "Roof"])
        XCTAssertEqual(SiteFloors.addingNumbered(upTo: 2, to: ["Basement"], name: floorName), ["Basement", "1. OG", "2. OG"])
        XCTAssertEqual(SiteFloors.addingNumbered(upTo: 0, to: ["Basement"], name: floorName), ["Basement"])
    }

    func testAFloorListTypedOnOneLine() {
        XCTAssertEqual(
            SiteFloors.parsing("Basement, Ground, 1–3, Roof, ground", name: floorName),
            ["Basement", "Ground", "1. OG", "2. OG", "3. OG", "Roof"]
        )
        XCTAssertEqual(SiteFloors.normalised([" Ground ", "", "ground", "Roof"]), ["Ground", "Roof"])
    }

    func testASiteWithoutFloorsOffersTheDefaults() {
        let defaults = ["Ground", "1st floor", "2nd floor", "Roof"]
        XCTAssertEqual(SiteSetup().floorList(defaults: defaults), defaults)
        XCTAssertEqual(SiteSetup(floors: ["Basement", "Ground"]).floorList(defaults: defaults), ["Basement", "Ground"])
    }

    func testTheSiteSettingsForDefectsAreKeptOnlyWhenSet() throws {
        XCTAssertTrue(SiteSetup().isStandard)
        let setup = SiteSetup(floors: ["Ground", "Roof"], rooms: ["Room 4"], assignsDefects: true, defectsOnSignOff: true)
        XCTAssertFalse(setup.isStandard)
        let data = try JSONEncoder().encode(setup)
        let decoded = try JSONDecoder().decode(SiteSetup.self, from: data)
        XCTAssertEqual(decoded, setup)

        let plain = String(decoding: try JSONEncoder().encode(SiteSetup(keepsDiary: false)), as: UTF8.self)
        XCTAssertFalse(plain.contains("floors") || plain.contains("rooms") || plain.contains("assigns"), plain)

        // A setup written before defects: none of it, every default.
        let old = try JSONDecoder().decode(SiteSetup.self, from: Data(#"{"keepsDiary":false,"breakMinutes":30}"#.utf8))
        XCTAssertNil(old.floors)
        XCTAssertEqual(old.rooms, [])
        XCTAssertFalse(old.assignsDefects)
        XCTAssertFalse(old.defectsOnSignOff)
        XCTAssertEqual(old.breakMinutes, 30)
    }

    func testCopyingASiteLeavesItsFloorsAndRoomsBehind() {
        let source = Site(name: "Trg Pravde")
        let setup = SiteSetup(
            start: TimeOfDay(hour: 7, minute: 0), end: TimeOfDay(hour: 15, minute: 0), workDays: [2, 3],
            floors: ["Ground"], rooms: ["Room 4"], assignsDefects: true
        )
        let copied = SiteBlueprint.copying(site: source, setup: setup, crew: [], recentDays: [], calendar: utc, fallback: SiteSetup())
        XCTAssertNil(copied.setup.floors)
        XCTAssertEqual(copied.setup.rooms, [])
        XCTAssertTrue(copied.setup.assignsDefects, "how you work comes along")
    }

    // MARK: - Coding

    func testADefectAndItsPhotoRoundTripAndOlderShapesRead() throws {
        let original = Defect(
            siteID: site, what: "Socket loose", floor: "2nd floor", room: "Room 4",
            assignee: .person("Ivan"), notedBy: "Marko", notedAt: monday, state: .fixed, fixedAt: tuesday, updatedAt: tuesday
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(Defect.self, from: try encoder.encode(original)), original)

        let you = Defect(siteID: site, what: "Cable", assignee: .you, notedAt: monday, updatedAt: monday)
        XCTAssertEqual(try decoder.decode(Defect.self, from: try encoder.encode(you)).assignee, .you)

        let minimal = try decoder.decode(Defect.self, from: Data(#"{"what":"Gutter","state":"later"}"#.utf8))
        XCTAssertEqual(minimal.what, "Gutter")
        XCTAssertEqual(minimal.state, .open)
        XCTAssertEqual(minimal.assignee, .nobody)

        let photo = DefectPhoto(
            defectID: original.id, siteID: site, sortOrder: 0,
            marks: [DefectMark(kind: .circle, colour: .yellow, points: [DefectPoint(x: 0.2, y: 0.3), DefectPoint(x: 0.6, y: 0.7)])],
            takenAt: monday, jpegData: Data([1, 2, 3])
        )
        XCTAssertEqual(try decoder.decode(DefectPhoto.self, from: try encoder.encode(photo)), photo)
    }

    func testAnAssigneeReadsFromItsStoredPair() {
        XCTAssertEqual(DefectAssignee(kind: "person", name: " Ivan "), .person("Ivan"))
        XCTAssertEqual(DefectAssignee(kind: "person", name: "  "), .nobody)
        XCTAssertEqual(DefectAssignee(kind: "you", name: ""), .you)
        XCTAssertEqual(DefectAssignee(kind: "robot", name: "x"), .nobody)
        XCTAssertEqual(DefectAssignee.person("Ivan").kind, "person")
        XCTAssertEqual(DefectAssignee.person("Ivan").name, "Ivan")
    }

    // MARK: - Marks

    /// A touch on a photo drawn at any size is stored normalised and comes
    /// back where it was, on screen or on a thumbnail of another shape.
    func testAMarkRoundTripsBetweenTheScreenAndTheStoredPoint() throws {
        // A 4:3 photo in a tall container: drawn 390 × 292.5, centred.
        let container = DefectRect(x: 0, y: 0, width: 390, height: 700)
        let drawn = DefectGeometry.fitted(imageWidth: 1600, imageHeight: 1200, in: container)
        XCTAssertEqual(drawn.width, 390, accuracy: 0.001)
        XCTAssertEqual(drawn.height, 292.5, accuracy: 0.001)
        XCTAssertEqual(drawn.y, (700 - 292.5) / 2, accuracy: 0.001)

        let touch = (x: 97.5, y: drawn.y + 146.25)
        let stored = DefectGeometry.normalised(x: touch.x, y: touch.y, in: drawn)
        XCTAssertEqual(stored.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(stored.y, 0.5, accuracy: 0.0001)
        let back = DefectGeometry.absolute(stored, in: drawn)
        XCTAssertEqual(back.x, touch.x, accuracy: 0.001)
        XCTAssertEqual(back.y, touch.y, accuracy: 0.001)

        // On a 60 × 45 thumbnail the same point is a quarter across, halfway down.
        let thumbnail = DefectRect(x: 10, y: 20, width: 60, height: 45)
        let onThumbnail = DefectGeometry.absolute(stored, in: thumbnail)
        XCTAssertEqual(onThumbnail.x, 25, accuracy: 0.001)
        XCTAssertEqual(onThumbnail.y, 42.5, accuracy: 0.001)

        // Outside the photo is held at its edge.
        XCTAssertEqual(DefectGeometry.normalised(x: -20, y: 5000, in: drawn), DefectPoint(x: 0, y: 1))

        // And through JSON, as stored, to four decimals.
        let mark = DefectMark(kind: .draw, colour: .white, points: [stored, DefectPoint(x: 0.123456789, y: 0.9)])
        let decoded = try JSONDecoder().decode(DefectMark.self, from: try JSONEncoder().encode(mark))
        XCTAssertEqual(decoded.kind, .draw)
        XCTAssertEqual(decoded.colour, .white)
        XCTAssertEqual(decoded.points[0], stored)
        XCTAssertEqual(decoded.points[1].x, 0.1235, accuracy: 0.00001)
    }

    func testACircleIsTheBoxTheDragSpannedAndATapIsNoMark() throws {
        let circle = DefectMark(kind: .circle, points: [DefectPoint(x: 0.6, y: 0.7), DefectPoint(x: 0.2, y: 0.3)])
        let box = try XCTUnwrap(circle.box)
        XCTAssertEqual(box.x, 0.2, accuracy: 0.0001)
        XCTAssertEqual(box.y, 0.3, accuracy: 0.0001)
        XCTAssertEqual(box.width, 0.4, accuracy: 0.0001)
        XCTAssertEqual(box.height, 0.4, accuracy: 0.0001)
        XCTAssertTrue(circle.isMeaningful)
        let onScreen = DefectGeometry.absolute(box, in: DefectRect(x: 0, y: 100, width: 200, height: 100))
        XCTAssertEqual(onScreen.x, 40, accuracy: 0.001)
        XCTAssertEqual(onScreen.y, 130, accuracy: 0.001)
        XCTAssertEqual(onScreen.width, 80, accuracy: 0.001)

        XCTAssertFalse(DefectMark(kind: .arrow, points: [DefectPoint(x: 0.5, y: 0.5), DefectPoint(x: 0.505, y: 0.5)]).isMeaningful)
        XCTAssertFalse(DefectMark(kind: .draw, points: [DefectPoint(x: 0.5, y: 0.5)]).isMeaningful)
        XCTAssertTrue(DefectMark(kind: .draw, points: [DefectPoint(x: 0.5, y: 0.5), DefectPoint(x: 0.6, y: 0.5)]).isMeaningful)
    }

    func testAnArrowHeadPointsBackFromTheTip() {
        let wings = DefectGeometry.arrowHead(tail: DefectPoint(x: 0, y: 0), tip: DefectPoint(x: 100, y: 0), length: 10)
        XCTAssertEqual(wings.count, 2)
        for wing in wings {
            XCTAssertLessThan(wing.x, 100, "behind the tip")
            XCTAssertEqual(DefectGeometry.distance(wing, DefectPoint(x: 100, y: 0)), 10, accuracy: 0.0001)
        }
        XCTAssertEqual(wings[0].y, -wings[1].y, accuracy: 0.0001, "one on each side")
    }

    // MARK: - The list sent

    private func document(onlyOpen: Bool = true, assigns: Bool = true, owner: String = "Marijo Mikša") -> DefectsDocument {
        let defects = [
            defect("Socket loose", floor: "2nd floor", room: "Room 4", at: tuesday, assignee: .person("Ivan"), notedBy: "Ivan"),
            defect("Cable not labelled", floor: "Ground", room: "Panel room", at: monday, assignee: .you),
            defect("Emergency light not lit", floor: "Ground", room: "Stairs", at: tuesday),
            DefectList.fixed(defect("Cover plate missing", floor: "2nd floor", room: "Corridor", at: monday), at: wednesday),
        ]
        return DefectsDocument(
            siteName: "Trg Pravde Zagreb",
            address: "Ilica 207C",
            date: CalendarDate(year: 2026, month: 11, day: 4),
            defects: defects,
            floors: ["Ground", "1st floor", "2nd floor", "Roof"],
            onlyOpen: onlyOpen,
            showsAssignee: assigns,
            ownerName: owner,
            language: .english,
            calendar: utc
        )
    }

    func testTheListNumbersTheOpenDefectsByFloorWithTheFixer() {
        let document = document()
        XCTAssertEqual(document.title, "Trg Pravde Zagreb · Defects")
        XCTAssertEqual(document.subtitle, "Ilica 207C · 4 Nov 2026 · 3 open")
        XCTAssertEqual(document.rows.map(\.title), ["1. Cable not labelled", "2. Emergency light not lit", "3. Socket loose"])
        XCTAssertEqual(document.rows[0].whereLine, "Ground · Panel room")
        XCTAssertEqual(document.rows[0].detail, "Fixes: Marijo Mikša · since 2 Nov")
        XCTAssertEqual(document.rows[1].detail, "Fixes: nobody yet · since 3 Nov")
        XCTAssertEqual(document.rows[2].detail, "Fixes: Ivan · since 3 Nov")
        XCTAssertEqual(
            document.text,
            """
            Trg Pravde Zagreb · Defects
            Ilica 207C · 4 Nov 2026 · 3 open

            1. Cable not labelled
            Ground · Panel room · Fixes: Marijo Mikša · since 2 Nov

            2. Emergency light not lit
            Ground · Stairs · Fixes: nobody yet · since 3 Nov

            3. Socket loose
            2nd floor · Room 4 · Fixes: Ivan · since 3 Nov

            Marijo Mikša
            """
        )
    }

    func testWithFixedOnesAndNoAssigningTheFixerIsNowhere() {
        let document = document(onlyOpen: false, assigns: false, owner: "")
        XCTAssertEqual(document.rows.count, 4)
        XCTAssertEqual(document.rows[3].title, "4. Cover plate missing")
        XCTAssertEqual(document.rows[3].detail, "fixed 4 Nov")
        XCTAssertTrue(document.rows[3].isFixed)
        XCTAssertEqual(document.rows[0].detail, "since 2 Nov")
        XCTAssertFalse(document.text.contains("Fixes"))
        XCTAssertTrue(document.text.hasSuffix("fixed 4 Nov"), "no name, no closing line")
    }

    func testYourDefectWithNoNameOnTheSheetsIsYours() {
        XCTAssertEqual(document(owner: "").rows[0].detail, "Fixes: me · since 2 Nov")
    }

    func testTheListInGerman() {
        let base = document()
        let german = DefectsDocument(
            siteName: base.siteName, address: base.address, date: base.date, defects: base.defects, floors: base.floors,
            onlyOpen: true, showsAssignee: true, ownerName: "", language: .german, calendar: utc
        )
        XCTAssertEqual(german.title, "Trg Pravde Zagreb · Mängel")
        XCTAssertTrue(german.subtitle.hasSuffix("3 offen"), german.subtitle)
        XCTAssertTrue(german.rows[1].detail.hasPrefix("Behebt: noch niemand · seit "), german.rows[1].detail)
    }

    func testTheSignOffListsTheOpenOnesWithTheirMarkedPhoto() {
        let document = document()
        let first = document.listed[0]
        let mark = DefectMark(kind: .circle, points: [DefectPoint(x: 0.1, y: 0.1), DefectPoint(x: 0.5, y: 0.5)])
        let photo = DefectPhoto(defectID: first.id, siteID: site, sortOrder: 0, marks: [mark], jpegData: Data([1]))
        let rows = document.signOffRows(firstPhotos: [first.id: photo])
        XCTAssertEqual(rows.map(\.number), [1, 2, 3])
        XCTAssertEqual(rows[0].what, "Cable not labelled")
        XCTAssertEqual(rows[0].whereLine, "Ground · Panel room")
        XCTAssertEqual(rows[0].since, "since 2 Nov")
        XCTAssertEqual(rows[0].photoID, photo.id)
        XCTAssertEqual(rows[0].marks, [mark])
        XCTAssertNil(rows[1].photoID)
    }

    func testEveryTermHasAWordInEveryLanguage() {
        for language in ExportLanguage.allCases {
            for term in SiteListTerm.allCases {
                XCTAssertFalse(language(term).isEmpty, "\(term) in \(language)")
            }
        }
    }
}
