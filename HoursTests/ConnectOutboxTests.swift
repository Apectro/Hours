import XCTest
@testable import Hours

/// Sending: the app's records written as the protocol's, with the company's
/// people in them and the server's name-based ids.
final class ConnectOutboxTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_611_800)
    private let web = UUID(uuidString: "a2364fc3-f9d6-51dc-9eb9-41868669e10f")!
    private let mine = UUID()
    private let marko = UUID(uuidString: "0ac76ab9-cd7d-55fe-8b38-bb4a40fbff11")!
    private let ivan = UUID(uuidString: "eabdee49-f0eb-575b-9032-773c56337457")!
    private let october1 = CalendarDate(year: 2026, month: 10, day: 1)

    private struct World {
        var state: ConnectState
        var sites: [Site]
        var crew: [CrewMember]
        var ivanRow: CrewMember
        var anteRow: CrewMember
    }

    /// A web site with Ivan (from the web) and Ante (added on the phone),
    /// and a private site of the phone's own.
    private func world() -> World {
        var state = ConnectState()
        state.people.you = marko
        state.people.company[marko] = ConnectPeople.ConnectPerson(name: "Marko", hidden: false)
        state.people.company[ivan] = ConnectPeople.ConnectPerson(name: "Ivan Horvat", hidden: false)
        state.companySites = [web]
        let ivanRow = CrewMember(id: ConnectUUID.crewRowID(siteID: web, personID: ivan), siteID: web, name: "Ivan Horvat")
        state.people.rows[ivanRow.id] = ivan
        state.assignments["28e27f54"] = ConnectAssignmentMark(siteID: web, personID: ivan, rowID: ivanRow.id)
        let anteRow = CrewMember(siteID: web, name: "Ante", sortOrder: 1)
        let privateRow = CrewMember(siteID: mine, name: "Josip")
        return World(
            state: state,
            sites: [Site(id: web, name: "Hauptstraße 12"), Site(id: mine, name: "My garden")],
            crew: [ivanRow, anteRow, privateRow],
            ivanRow: ivanRow,
            anteRow: anteRow
        )
    }

    private func day(_ world: World) -> SiteDay {
        SiteDay(
            siteID: web,
            date: october1,
            start: TimeOfDay(hour: 7, minute: 0),
            end: TimeOfDay(hour: 15, minute: 30),
            breakMinutes: 30,
            present: [Attendance(memberID: CrewMember.youID), Attendance(memberID: world.ivanRow.id, end: TimeOfDay(hour: 12, minute: 0))],
            note: "Rain at noon",
            absences: [CrewAbsence(memberID: world.anteRow.id, dayTypeID: .sick)],
            allowanceMemberIDs: [CrewMember.youID, world.ivanRow.id, world.anteRow.id],
            kilometres: 42
        )
    }

    private func records(_ world: World, days: [SiteDay] = [], signatures: [CrewSignature] = []) -> [ConnectOutgoing] {
        ConnectOutbox.records(ConnectOutboxInput(sites: world.sites, crew: world.crew, siteDays: days, signatures: signatures, yourName: "Marko", now: now), state: world.state)
    }

    func testASiteDayCarriesTheCompanysPeopleAndTheServersId() throws {
        let world = world()
        let out = records(world, days: [day(world), SiteDay(siteID: mine, date: october1, present: [Attendance(memberID: CrewMember.youID)])])
        let days = out.filter { $0.kind == .siteDay }
        XCTAssertEqual(days.count, 1, "a private site is never sent")
        let record = try XCTUnwrap(days.first)
        let data = try ConnectJSON.decode(ConnectV1.SiteDay.self, from: ConnectJSON.encode(XCTUnwrap(record.data)))
        XCTAssertEqual(data.id, "77593f12-e0f2-556b-af9a-7fadea4eb5df", "siteDayId(siteId, date), as the fixture")
        XCTAssertEqual(record.id, data.id)
        XCTAssertEqual(data.date, "2026-10-01")
        XCTAssertEqual(data.attendance.map(\.memberId), [ConnectID.string(marko), ConnectID.string(ivan)])
        XCTAssertEqual(data.attendance[1].end, "12:00")
        XCTAssertNil(data.attendance[0].end, "the site's times are not repeated per person")
        let ante = try XCTUnwrap(data.absences.first)
        XCTAssertEqual(ante.reason.type, "dayType")
        XCTAssertEqual(ante.reason.dayType, "sick")
        XCTAssertEqual(data.allowanceMemberIds.count, 2, "only someone present has the allowance")
        XCTAssertEqual(data.kilometres, 42)
        XCTAssertEqual(data.writtenBy, ConnectID.string(marko))
        XCTAssertEqual(record.month, YearMonth(year: 2026, month: 10))

        // The app's fixed You is never in what is sent.
        let json = String(decoding: try ConnectJSON.encode(XCTUnwrap(record.data)), as: UTF8.self).lowercased()
        XCTAssertFalse(json.contains(CrewMember.youID.uuidString.lowercased()))
    }

    func testSomeoneAddedOnThePhoneIsSentAsAPersonOnTheSite() throws {
        let world = world()
        let out = records(world)
        let people = out.filter { $0.kind == .crewMember }
        XCTAssertEqual(people.count, 1, "Ivan is the web's; only Ante is new")
        XCTAssertEqual(people.first?.id, ConnectID.string(world.anteRow.id), "his id is his row's")
        XCTAssertEqual(people.first?.data?["name"], .string("Ante"))
        let assignments = out.filter { $0.kind == .assignment }
        XCTAssertEqual(assignments.count, 1, "Ivan's assignment is the web's")
        XCTAssertEqual(assignments.first?.data?["memberId"], .string(ConnectID.string(world.anteRow.id)))
        XCTAssertEqual(assignments.first?.data?["siteId"], .string(ConnectID.string(web)))
        XCTAssertFalse(out.contains { $0.kind == .site }, "a web site is the web's")
    }

    func testASharedSiteOfThePhonesIsSent() throws {
        var world = world()
        world.state.sharedSites = [mine]
        let out = ConnectOutbox.records(ConnectOutboxInput(
            sites: world.sites,
            crew: world.crew,
            setups: [mine: SiteSetup(start: TimeOfDay(hour: 7, minute: 0), end: TimeOfDay(hour: 16, minute: 0), breakMinutes: 30, workDays: [2, 3])],
            yourName: "Marko",
            now: now
        ), state: world.state)
        let site = try XCTUnwrap(out.first { $0.kind == .site })
        XCTAssertEqual(site.id, ConnectID.string(mine))
        XCTAssertEqual(site.data?["usualDay"]?["start"], .string("07:00"))
        XCTAssertEqual(site.data?["workDays"], .array([.number(2), .number(3)]))
        XCTAssertTrue(out.contains { $0.kind == .crewMember && $0.data?["name"] == .string("Josip") })
        XCTAssertTrue(out.contains { $0.kind == .assignment && $0.data?["memberId"] == .string(ConnectID.string(marko)) && $0.data?["siteId"] == .string(ConnectID.string(mine)) },
                      "You on a site made here")
    }

    func testASignOffIsKeyedByThePerson() throws {
        let world = world()
        let signature = CrewSignature(siteID: web, memberID: world.ivanRow.id, month: YearMonth(year: 2026, month: 10), signedOn: CalendarDate(year: 2026, month: 10, day: 30), fingerprint: "v1:3f9a0c1b2d4e5f60", strokes: [[SignaturePoint(x: 0.2, y: 0.6), SignaturePoint(x: 0.5, y: 0.3)]], aspectRatio: 3)
        let out = records(world, signatures: [signature])
        let record = try XCTUnwrap(out.first { $0.kind == .signOff })
        XCTAssertEqual(record.id, "d8c3924a-f379-57d9-b438-0ff9e8c4580b", "signOffId(siteId, memberId, month), as the fixture")
        XCTAssertEqual(record.data?["memberId"], .string(ConnectID.string(ivan)))
        XCTAssertEqual(record.data?["signedOn"], .string("2026-10-30"))
    }

    func testOtherRecordsKeepTheirOwnIdsAndFiles() throws {
        let world = world()
        let job = ExtraWorkJob(siteID: web, date: october1, description: "Emergency lighting", items: [ExtraWorkItem(name: "NYM-J 3x1.5", quantity: Decimal(string: "45.5")!, unit: .metres)],
                               hours: [ExtraWorkHours(memberID: world.ivanRow.id, name: "Ivan Horvat", minutes: 180)],
                               clientSignature: ExtraWorkSignature(signerName: "H. Gruber", signedAt: now, strokes: []), isDone: true, doneAt: now, createdAt: now, updatedAt: now)
        let photo = ConnectPhotoInfo(id: UUID(), ownerID: job.id, sortOrder: 0, byteSize: 412_880)
        let defect = Defect(id: UUID(), siteID: web, what: "Socket cover broken", floor: "2nd floor", room: "2.14", assignee: .person("Luka"), notedBy: "Marko", notedAt: now, state: .open, fixedAt: nil, updatedAt: now)
        let defectPhoto = ConnectPhotoInfo(id: UUID(), ownerID: defect.id, sortOrder: 0, byteSize: 100, marks: [DefectMark(kind: .circle, points: [DefectPoint(x: 0.41, y: 0.33), DefectPoint(x: 0.58, y: 0.49)])])
        let item = MissingItem(id: UUID(), siteID: web, name: "NYM-J 5x2.5", catalogItemID: nil, quantity: 100, unit: .metres, note: "", notedBy: "Marko", notedAt: now, state: .needed, orderedAt: nil, arrivedAt: nil, updatedAt: now)
        let delivery = Delivery(siteID: web, receivedAt: now, lines: [DeliveryLine(kind: .short, name: "NYM-J 5x2.5", unit: .metres, came: 50, ordered: 100, missingItemID: item.id)], hasPhoto: true, updatedAt: now)
        let out = ConnectOutbox.records(ConnectOutboxInput(
            sites: world.sites, crew: world.crew,
            jobs: [job], jobPhotos: [photo], jobSignatureSizes: [job.id: 6210],
            defects: [defect], defectPhotos: [defectPhoto],
            missing: [item],
            deliveries: [delivery], deliveryPhotoSizes: [delivery.id: 290_004],
            yourName: "Marko", now: now
        ), state: world.state)

        let extra = try XCTUnwrap(out.first { $0.kind == .extraWork })
        XCTAssertEqual(extra.id, ConnectID.string(job.id))
        let work = try ConnectJSON.decode(ConnectV1.ExtraWork.self, from: ConnectJSON.encode(XCTUnwrap(extra.data)))
        XCTAssertEqual(work.materials.first?.quantity, "45.5")
        XCTAssertEqual(work.materials.first?.unit, "m")
        XCTAssertEqual(work.hours.first?.memberId, ConnectID.string(ivan))
        XCTAssertEqual(work.photos.first?.fileId, ConnectID.string(photo.id), "a file's id is the app's own for the photo")
        XCTAssertEqual(work.clientSignature?.image.contentType, "image/png")
        XCTAssertEqual(extra.files.map(\.purpose), [.photo, .signature])
        XCTAssertTrue(work.done)

        let defectOut = try ConnectJSON.decode(ConnectV1.Defect.self, from: ConnectJSON.encode(XCTUnwrap(out.first { $0.kind == .defect }?.data)))
        XCTAssertEqual(defectOut.assignee.kind, "person")
        XCTAssertEqual(defectOut.photos.first?.marks.first?.kind, "circle")
        XCTAssertEqual(defectOut.photos.first?.marks.first?.points.count, 2)

        XCTAssertEqual(out.first { $0.kind == .missingItem }?.data?["quantity"], .string("100"))
        let deliveryOut = try XCTUnwrap(out.first { $0.kind == .delivery })
        XCTAssertEqual(deliveryOut.data?["lines"]?.stringValue, nil)
        XCTAssertEqual(deliveryOut.files.first?.purpose, .deliveryPhoto)
        XCTAssertEqual(deliveryOut.data?["photo"]?["byteSize"], .number(290_004))
    }

    /// Everything sent decodes as the protocol's own type: what the server
    /// will validate.
    func testEveryRecordDecodesAsItsKind() throws {
        let world = world()
        for record in records(world, days: [day(world)]) {
            let data = try XCTUnwrap(record.data)
            let bytes = try ConnectJSON.encode(data)
            switch record.kind {
            case .siteDay: _ = try ConnectJSON.decode(ConnectV1.SiteDay.self, from: bytes)
            case .crewMember: _ = try ConnectJSON.decode(ConnectV1.CrewMemberInput.self, from: bytes)
            case .assignment: _ = try ConnectJSON.decode(ConnectV1.AssignmentInput.self, from: bytes)
            default: break
            }
        }
    }

    func testTheMonthSheetAddsUpPersonByPerson() throws {
        let world = world()
        let settings = AppSettings()
        let calculator = SiteDayCalculator(settings: settings, calendar: Calendar(identifier: .gregorian))
        let second = SiteDay(siteID: web, date: CalendarDate(year: 2026, month: 10, day: 2), start: TimeOfDay(hour: 7, minute: 0), end: TimeOfDay(hour: 15, minute: 30), breakMinutes: 30,
                             present: [Attendance(memberID: CrewMember.youID)])
        let results = [day(world), second].map(calculator.compute)
        let people = world.state.people.linking(world.crew)
        let pdf = ConnectV1.FileRef(fileId: "6949219a-d46e-5306-ba54-9e3cc349ec18", contentType: "application/pdf", byteSize: 184_233)
        let sheet = ConnectSheet.make(
            sites: [ConnectSheet.SiteInput(site: world.sites[0], crew: world.crew, results: results)],
            month: YearMonth(year: 2026, month: 10),
            title: "Hauptstraße 12, October 2026",
            holidays: [(CalendarDate(year: 2026, month: 10, day: 26), "National Day")],
            breaksPaid: false,
            rounding: .exact,
            people: people,
            yourName: "Marko",
            pdf: pdf,
            sentAt: now
        )
        XCTAssertEqual(sheet.month, "2026-10")
        XCTAssertEqual(sheet.siteIds, [ConnectID.string(web)])
        let you = try XCTUnwrap(sheet.people.first)
        XCTAssertEqual(you.memberId, ConnectID.string(marko), "You first, as the paired person")
        XCTAssertEqual(you.workedMinutes, 960)
        XCTAssertEqual(you.daysWorked, 2)
        let ivanLine = try XCTUnwrap(sheet.people.first { $0.memberId == ConnectID.string(ivan) })
        XCTAssertEqual(ivanLine.workedMinutes, 270, "07:00 to 12:00 less the break")
        let ante = try XCTUnwrap(sheet.people.first { $0.name == "Ante" })
        XCTAssertEqual(ante.dayTypes, ["sick": 1])
        XCTAssertEqual(ante.days.first?.dayType, "sick")
        XCTAssertEqual(sheet.totals.workedMinutes, 960 + 270)
        XCTAssertEqual(sheet.totals.people, 3)
        XCTAssertEqual(sheet.totals.kilometres, 42)
        XCTAssertEqual(sheet.sites.first?.workedMinutes, 1230)
        XCTAssertEqual(sheet.holidays.map(\.date), ["2026-10-26"])
        XCTAssertEqual(sheet.pdf?.fileId, pdf.fileId)
        XCTAssertEqual(sheet.sentBy.memberId, ConnectID.string(marko))
        XCTAssertEqual(sheet.id, ConnectID.string(ConnectSheet.id(siteIDs: [web], month: YearMonth(year: 2026, month: 10))), "one sheet per sites and month")

        let record = try ConnectSheet.outgoing(sheet, pdfFile: nil, siteIDs: [web])
        XCTAssertEqual(record.kind, .sheet)
        let back = try ConnectJSON.decode(ConnectV1.MonthSheet.self, from: ConnectJSON.encode(XCTUnwrap(record.data)))
        XCTAssertEqual(back, sheet)
    }

    func testScopeIsCompanyAndSharedSitesOnly() {
        var state = ConnectState()
        state.companySites = [web]
        let other = UUID()
        XCTAssertEqual(ConnectOutbox.scope(state, sites: [Site(id: web, name: "a"), Site(id: mine, name: "b"), Site(id: other, name: "c")]), [web])
        state.sharedSites = [mine]
        XCTAssertEqual(ConnectOutbox.scope(state, sites: [Site(id: web, name: "a"), Site(id: mine, name: "b")]), [web, mine])
    }
}
