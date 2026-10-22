import XCTest
import SwiftData
@testable import Hours

/// Extra work in the store: writing jobs, their photos and the remembered
/// items, backing them up and restoring them.
@MainActor
final class ExtraWorkRepositoryTests: XCTestCase {
    private let site = Site(name: "Trg Pravde Zagreb")
    private let date = Fixture.date(2026, 10, 22)

    private func makeContext() -> ModelContext {
        ModelContext(HoursModelContainer.ephemeral())
    }

    private func job(_ description: String = "Emergency lighting", site: Site? = nil) -> ExtraWorkJob {
        ExtraWorkJob(
            siteID: (site ?? self.site).id,
            date: date,
            description: description,
            items: [ExtraWorkItem(name: "Emergency light", quantity: 8, unit: .pieces)]
        )
    }

    func testAJobIsWrittenAndReadBack() {
        let repository = ExtraWorkRepository(context: makeContext())
        let written = job()
        repository.storeJob(written)
        let read = repository.jobs(siteID: site.id)
        XCTAssertEqual(read.map(\.id), [written.id])
        XCTAssertEqual(read.first?.items, written.items)
        XCTAssertEqual(repository.dateKeys(siteID: site.id, in: CalendarDateRange(single: date)), [date.key])
    }

    func testEditingKeepsOneRow() {
        let context = makeContext()
        let repository = ExtraWorkRepository(context: context)
        var written = job()
        repository.storeJob(written)
        written.description = "Emergency lighting, stairwell"
        repository.storeJob(written)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExtraWorkJobEntry>()), 1)
        XCTAssertEqual(repository.job(id: written.id)?.description, "Emergency lighting, stairwell")
    }

    func testABlankJobRemovesTheStoredOneAndItsPhotos() {
        let repository = ExtraWorkRepository(context: makeContext())
        var written = job()
        repository.storeJob(written)
        repository.addPhoto(Data([1]), jobID: written.id, siteID: site.id)
        written.description = ""
        written.items = []
        repository.storeJob(written)
        XCTAssertTrue(repository.jobs(siteID: site.id).isEmpty)
        XCTAssertTrue(repository.photos(jobID: written.id).isEmpty)
    }

    func testPhotosStopAtSix() {
        let repository = ExtraWorkRepository(context: makeContext())
        let written = job()
        repository.storeJob(written)
        for index in 0..<6 { XCTAssertTrue(repository.addPhoto(Data([UInt8(index)]), jobID: written.id, siteID: site.id)) }
        XCTAssertFalse(repository.addPhoto(Data([9]), jobID: written.id, siteID: site.id))
        XCTAssertEqual(repository.photos(jobID: written.id).map(\.sortOrder), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(repository.photoCounts(siteID: site.id)[written.id], 6)
    }

    func testSendingMarksTheJobsAndKeepsTheReport() {
        let repository = ExtraWorkRepository(context: makeContext())
        let first = job("a")
        let second = job("b")
        repository.storeJob(first)
        repository.storeJob(second)
        let record = ExtraWorkReportRecord(siteID: site.id, sentAt: Date(), jobIDs: [first.id, second.id])
        let marked = ExtraWorkSending.marked(repository.jobs(siteID: site.id), after: .completed, reportID: record.id, at: record.sentAt)
        repository.recordSent(record, jobs: marked)
        XCTAssertTrue(repository.jobs(siteID: site.id).allSatisfy { $0.status == .sent && $0.sentReportID == record.id })
        XCTAssertEqual(repository.reports(siteID: site.id).map(\.id), [record.id])
    }

    func testANewJobIsStoredInProgressAndTickingItDoneIsKept() {
        let repository = ExtraWorkRepository(context: makeContext())
        let written = job()
        repository.storeJob(written)
        XCTAssertEqual(repository.job(id: written.id)?.isDone, false)

        let moment = Date(timeIntervalSince1970: 1_792_000_000)
        repository.storeProgress(of: written.togglingDone(at: moment))
        let done = repository.job(id: written.id)
        XCTAssertEqual(done?.isDone, true)
        XCTAssertEqual(done?.doneAt, moment)
        XCTAssertEqual(done?.description, written.description, "nothing else changes")

        repository.storeProgress(of: done!.togglingDone(at: moment))
        XCTAssertEqual(repository.job(id: written.id)?.isDone, false)
        XCTAssertNil(repository.job(id: written.id)?.doneAt)
    }

    func testUsingItemsRemembersThem() {
        let repository = ExtraWorkRepository(context: makeContext())
        repository.recordUse(of: [ExtraWorkItem(name: "Kabel", quantity: 3, unit: .metres)])
        repository.recordUse(of: [ExtraWorkItem(name: "kabel", quantity: 4, unit: .metres)])
        let catalog = repository.catalog()
        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(catalog.first?.useCount, 2)
        repository.removeCatalogItem(id: catalog[0].id)
        XCTAssertTrue(repository.catalog().isEmpty)
    }

    // MARK: - Backup and restore

    private func populate(_ context: ModelContext) -> ExtraWorkJob {
        SiteRepository(context: context).upsert(site)
        let repository = ExtraWorkRepository(context: context)
        var written = job().markingDone(at: Date(timeIntervalSince1970: 1_792_000_000))
        written.clientSignature = ExtraWorkSignature(signerName: "Horvat", signedAt: Date(timeIntervalSince1970: 1_792_000_000),
                                                     strokes: [[SignaturePoint(x: 0, y: 0), SignaturePoint(x: 1, y: 1)]])
        repository.storeJob(written)
        repository.addPhoto(Data([0xFF, 0xD8, 0xFF, 0xD9]), jobID: written.id, siteID: site.id)
        repository.recordUse(of: written.items)
        return repository.job(id: written.id)!
    }

    func testABackupRoundTripsExtraWork() throws {
        let source = makeContext()
        let written = populate(source)
        let data = try BackupRestorer(context: source).makeArchive(settings: Fixture.settings()).encoded()

        let target = makeContext()
        BackupRestorer(context: target).restore(try BackupArchive.decoded(from: data))
        let repository = ExtraWorkRepository(context: target)
        // Compared without the timestamps, which a backup keeps to the second.
        let restored = repository.jobs(siteID: site.id)
        XCTAssertEqual(restored.map(\.id), [written.id])
        XCTAssertEqual(restored.first?.items, written.items)
        XCTAssertEqual(restored.first?.clientSignature?.signerName, "Horvat")
        XCTAssertEqual(restored.first?.isDone, written.isDone)
        XCTAssertEqual(restored.first?.doneAt, written.doneAt)
        XCTAssertEqual(repository.photos(jobID: written.id).map(\.jpegData), [Data([0xFF, 0xD8, 0xFF, 0xD9])])
        XCTAssertEqual(repository.catalog().map(\.name), ["Emergency light"])
    }

    func testAnOlderBackupKeepsTheDevicesExtraWorkForTheSitesItRestores() throws {
        let context = makeContext()
        let written = populate(context)
        var archive = BackupRestorer(context: context).makeArchive(settings: Fixture.settings())
        archive.extraWorkJobs = nil
        archive.extraWorkPhotos = nil
        archive.extraWorkReports = nil
        archive.extraWorkItems = nil

        BackupRestorer(context: context).restore(archive)
        let repository = ExtraWorkRepository(context: context)
        XCTAssertEqual(repository.jobs(siteID: site.id).map(\.id), [written.id])
        XCTAssertEqual(repository.photos(jobID: written.id).count, 1)
        XCTAssertEqual(repository.catalog().count, 1)
    }

    func testDeletingEverythingTakesExtraWorkToo() {
        let context = makeContext()
        _ = populate(context)
        BackupRestorer(context: context).deleteEverything()
        let everything = ExtraWorkRepository(context: context).everything()
        XCTAssertTrue(everything.jobs.isEmpty)
        XCTAssertTrue(everything.photos.isEmpty)
        XCTAssertTrue(everything.items.isEmpty)
    }
}
