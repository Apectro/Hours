import XCTest
import SwiftData
@testable import Hours

/// The Missing lists and the remembered items' codes in the store: written,
/// read back, backed up and restored.
@MainActor
final class MissingRepositoryTests: XCTestCase {
    private let site = Site(name: "Trg Pravde Zagreb")
    private let other = Site(name: "Bau Süd")

    private func makeContext() -> ModelContext {
        ModelContext(HoursModelContainer.ephemeral())
    }

    func testAddingTheSameNeededItemCountsItUpInOneRow() {
        let repository = MissingRepository(context: makeContext())
        repository.add(MissingDraft(name: "Junction box IP65", quantity: 6, unit: .pieces, note: "2nd floor"), siteID: site.id)
        repository.add(MissingDraft(name: "junction box IP65", quantity: 2, unit: .pieces), siteID: site.id)
        let items = repository.items(siteID: site.id)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.quantity, 8)
        XCTAssertEqual(items.first?.note, "2nd floor")
        XCTAssertEqual(repository.neededCount(siteID: site.id), 1)
        XCTAssertEqual(repository.neededCount(siteID: other.id), 0, "the list is the site's")
    }

    func testMarkingAndRemovingAreKept() throws {
        let context = makeContext()
        let repository = MissingRepository(context: context)
        let item = try XCTUnwrap(repository.add(MissingDraft(name: "Cable", quantity: 50, unit: .metres), siteID: site.id))
        repository.mark(item.id, .ordered, siteID: site.id)
        XCTAssertEqual(MissingRepository(context: context).items(siteID: site.id).first?.state, .ordered)
        repository.mark(item.id, .arrived, siteID: site.id)
        XCTAssertEqual(MissingRepository(context: context).items(siteID: site.id).first?.state, .arrived)
        repository.remove(id: item.id)
        XCTAssertTrue(MissingRepository(context: context).items(siteID: site.id).isEmpty)
    }

    func testSendingMarksTheNeededOrdered() {
        let repository = MissingRepository(context: makeContext())
        repository.add(MissingDraft(name: "Cable", quantity: 50, unit: .metres), siteID: site.id)
        repository.add(MissingDraft(name: "Box", quantity: 6, unit: .pieces), siteID: site.id)
        repository.markOrdered(MissingList.toSend(repository.items(siteID: site.id)), siteID: site.id)
        XCTAssertEqual(MissingList.count(.ordered, in: repository.items(siteID: site.id)), 2)
    }

    func testANamedCodeIsKnownAndOneCodeIsOneItem() {
        let repository = ExtraWorkRepository(context: makeContext())
        let named = repository.nameCode("4015081677891", name: "Junction box IP65", unit: .pieces)
        XCTAssertEqual(ExtraWorkCatalog.item(forCode: "4015081677891", in: repository.catalog())?.id, named.id)
        repository.recordUse(of: [ExtraWorkItem(name: "Junction box IP65", quantity: 1, unit: .pieces)], siteID: site.id)
        let used = repository.catalog().first
        XCTAssertEqual(used?.barcodes, ["4015081677891"])
        XCTAssertEqual(used?.siteIDs, [site.id])
        XCTAssertEqual(used?.useCount, 1)

        let other = repository.nameCode("4015081677891", name: "Something else", unit: .boxes)
        XCTAssertEqual(ExtraWorkCatalog.item(forCode: "4015081677891", in: repository.catalog())?.id, other.id)
        repository.removeCode("4015081677891", from: other.id)
        XCTAssertNil(ExtraWorkCatalog.item(forCode: "4015081677891", in: repository.catalog()))
    }

    // MARK: - Backup and restore

    private func populate(_ context: ModelContext) {
        SiteRepository(context: context).upsert(site)
        MissingRepository(context: context).add(MissingDraft(name: "Cable", quantity: 50, unit: .metres, notedBy: "Dusko"), siteID: site.id)
        ExtraWorkRepository(context: context).nameCode("111", name: "Lamp", unit: .boxes)
    }

    func testABackupRoundTripsTheListsAndTheCodes() throws {
        let source = makeContext()
        populate(source)
        let data = try BackupRestorer(context: source).makeArchive(settings: Fixture.settings()).encoded()

        let target = makeContext()
        BackupRestorer(context: target).restore(try BackupArchive.decoded(from: data))
        let restored = MissingRepository(context: target).items(siteID: site.id)
        XCTAssertEqual(restored.map(\.name), ["Cable"])
        XCTAssertEqual(restored.first?.notedBy, "Dusko")
        XCTAssertEqual(restored.first?.unit, .metres)
        let catalog = ExtraWorkRepository(context: target).catalog()
        XCTAssertEqual(catalog.first?.barcodes, ["111"])
        XCTAssertEqual(catalog.first?.unit, .boxes)
    }

    func testAnOlderBackupKeepsTheDevicesListForTheSitesItRestores() {
        let context = makeContext()
        populate(context)
        var archive = BackupRestorer(context: context).makeArchive(settings: Fixture.settings())
        archive.missingItems = nil
        BackupRestorer(context: context).restore(archive)
        XCTAssertEqual(MissingRepository(context: context).items(siteID: site.id).count, 1)

        archive.sites = []
        BackupRestorer(context: context).restore(archive)
        XCTAssertTrue(MissingRepository(context: context).everything().isEmpty, "its site is gone")
    }

    func testDeletingEverythingTakesTheListsToo() {
        let context = makeContext()
        populate(context)
        BackupRestorer(context: context).deleteEverything()
        XCTAssertTrue(MissingRepository(context: context).everything().isEmpty)
    }
}
