import XCTest
import SwiftData
@testable import Hours

/// Defects with their photos and marks, and checked deliveries, in the
/// store: written, read back, backed up and restored.
@MainActor
final class DefectRepositoryTests: XCTestCase {
    private let site = Site(name: "Trg Pravde Zagreb")

    private func makeContext() -> ModelContext {
        ModelContext(HoursModelContainer.ephemeral())
    }

    private let circle = DefectMark(kind: .circle, colour: .yellow, points: [DefectPoint(x: 0.2, y: 0.3), DefectPoint(x: 0.6, y: 0.7)])

    func testADefectIsAddedWithItsPhotosFixedAndReopened() throws {
        let context = makeContext()
        let repository = DefectRepository(context: context)
        let defect = try XCTUnwrap(repository.add(
            DefectDraft(what: "Socket loose", floor: "2nd floor", room: "Room 4", assignee: .person("Ivan"), notedBy: "Marko"),
            siteID: site.id,
            photos: [(Data([1]), [circle]), (Data([2]), [])]
        ))
        XCTAssertNil(repository.add(DefectDraft(what: "  "), siteID: site.id), "a defect says what is wrong")

        let read = DefectRepository(context: context).defects(siteID: site.id)
        XCTAssertEqual(read.map(\.what), ["Socket loose"])
        XCTAssertEqual(read.first?.assignee, .person("Ivan"))
        XCTAssertEqual(read.first?.notedBy, "Marko")
        XCTAssertEqual(repository.openCount(siteID: site.id), 1)

        let photos = repository.photos(defectID: defect.id)
        XCTAssertEqual(photos.map(\.jpegData), [Data([1]), Data([2])])
        XCTAssertEqual(photos.first?.marks, [circle])
        XCTAssertEqual(repository.firstPhotos(siteID: site.id)[defect.id]?.jpegData, Data([1]))

        repository.markFixed(defect.id)
        XCTAssertEqual(DefectRepository(context: context).defect(id: defect.id)?.state, .fixed)
        XCTAssertNotNil(DefectRepository(context: context).defect(id: defect.id)?.fixedAt)
        XCTAssertEqual(repository.openCount(siteID: site.id), 0)
        repository.reopen(defect.id)
        XCTAssertNil(DefectRepository(context: context).defect(id: defect.id)?.fixedAt)
    }

    func testAfterPhotosAndEditedMarksKeepThePhoto() throws {
        let context = makeContext()
        let repository = DefectRepository(context: context)
        let defect = try XCTUnwrap(repository.add(DefectDraft(what: "Cover missing"), siteID: site.id, photos: [(Data([1]), [])]))
        let after = try XCTUnwrap(repository.addPhoto(Data([9]), to: defect, isAfter: true))
        XCTAssertEqual(repository.photos(defectID: defect.id).map(\.isAfter), [false, true])
        XCTAssertNotEqual(repository.firstPhotos(siteID: site.id)[defect.id]?.id, after.id, "the thumbnail is the problem, not the fix")

        let first = try XCTUnwrap(repository.photos(defectID: defect.id).first)
        repository.setMarks([circle], onPhoto: first.id)
        let edited = try XCTUnwrap(DefectRepository(context: context).photos(defectID: defect.id).first)
        XCTAssertEqual(edited.marks, [circle])
        XCTAssertEqual(edited.jpegData, Data([1]), "the photo is never changed by its marks")

        repository.remove(id: defect.id)
        XCTAssertTrue(repository.defects(siteID: site.id).isEmpty)
        XCTAssertTrue(repository.photos(defectID: defect.id).isEmpty, "its photos go with it")
    }

    // MARK: - Backup and restore

    private func populate(_ context: ModelContext) throws -> UUID {
        SiteRepository(context: context).upsert(site)
        let defect = try XCTUnwrap(DefectRepository(context: context).add(
            DefectDraft(what: "Socket loose", floor: "Ground"), siteID: site.id, photos: [(Data([7, 7]), [circle])]
        ))
        DeliveryRepository(context: context).record(
            lines: [DeliveryLine(kind: .extra, name: "Emergency light", unit: .pieces, came: 2, ordered: 2)],
            photo: Data([5, 5, 5]),
            siteID: site.id
        )
        return defect.id
    }

    func testABackupRoundTripsDefectsPhotosMarksAndDeliveries() throws {
        let source = makeContext()
        let defectID = try populate(source)
        let data = try BackupRestorer(context: source).makeArchive(settings: Fixture.settings()).encoded()

        let target = makeContext()
        BackupRestorer(context: target).restore(try BackupArchive.decoded(from: data))
        XCTAssertEqual(DefectRepository(context: target).defects(siteID: site.id).map(\.what), ["Socket loose"])
        let photo = try XCTUnwrap(DefectRepository(context: target).photos(defectID: defectID).first)
        XCTAssertEqual(photo.jpegData, Data([7, 7]))
        XCTAssertEqual(photo.marks, [circle])
        let delivery = try XCTUnwrap(DeliveryRepository(context: target).deliveries(siteID: site.id).first)
        XCTAssertTrue(delivery.hasPhoto)
        XCTAssertNil(delivery.photoData, "a list never reads the photo")
        XCTAssertEqual(DeliveryRepository(context: target).delivery(id: delivery.id)?.photoData, Data([5, 5, 5]))
        XCTAssertEqual(delivery.lines.first?.came, 2)
    }

    func testAnOlderBackupKeepsTheDevicesDefectsForTheSitesItRestores() throws {
        let context = makeContext()
        _ = try populate(context)
        var archive = BackupRestorer(context: context).makeArchive(settings: Fixture.settings())
        archive.defects = nil
        archive.defectPhotos = nil
        archive.deliveries = nil
        BackupRestorer(context: context).restore(archive)
        XCTAssertEqual(DefectRepository(context: context).defects(siteID: site.id).count, 1)
        XCTAssertEqual(DeliveryRepository(context: context).deliveries(siteID: site.id).count, 1)

        archive.sites = []
        BackupRestorer(context: context).restore(archive)
        XCTAssertTrue(DefectRepository(context: context).everything().defects.isEmpty, "its site is gone")
        XCTAssertTrue(DeliveryRepository(context: context).everything().isEmpty)
    }

    func testDeletingEverythingTakesDefectsAndDeliveries() throws {
        let context = makeContext()
        _ = try populate(context)
        BackupRestorer(context: context).deleteEverything()
        XCTAssertTrue(DefectRepository(context: context).everything().defects.isEmpty)
        XCTAssertTrue(DefectRepository(context: context).everything().photos.isEmpty)
        XCTAssertTrue(DeliveryRepository(context: context).everything().isEmpty)
    }
}
