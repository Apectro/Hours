import Foundation
import SwiftData

/// Reads and writes a site's defects and their photos (1.3).
///
/// Thin in the way `MissingRepository` is: it converts between the entries
/// and `Defect` / `DefectPhoto`, owns the one-row-per-id rule and collapses
/// the duplicates sync can leave, last edit winning. The rules (what a new
/// defect is, fixed and reopened, the order) are `DefectList`'s.
///
/// **Not under the month lock**: a defect is nobody's hours, and the one
/// found on the 31st is fixed in the next month. Only a read-only site (the
/// Pro rule) stops adding, and that is the screens' to check. The method
/// names avoid `save`, `delete` and `replaceAll` so
/// `Scripts/check-repository-lock.py` does not take these writes for the
/// hours'.
///
/// Always built from a view's `modelContext` and used on the main actor.
struct DefectRepository {
    let context: ModelContext

    // MARK: - Defects

    /// A site's defects, open and fixed.
    func defects(siteID: UUID) -> [Defect] {
        let key = siteID.uuidString
        let descriptor = FetchDescriptor<DefectEntry>(
            predicate: #Predicate<DefectEntry> { $0.siteID == key },
            sortBy: [SortDescriptor(\DefectEntry.notedAt)]
        )
        return deduplicated(fetch(descriptor)).map(\.defect)
    }

    func defect(id: UUID) -> Defect? {
        entries(id: id).first?.defect
    }

    /// How many are still open on the site: the site page's "4 open".
    func openCount(siteID: UUID) -> Int {
        DefectList.count(.open, in: defects(siteID: siteID))
    }

    /// A new defect from the sheet, with its photos in order — the first
    /// the marked one. Returns it, or nil when it says nothing.
    @discardableResult
    func add(
        _ draft: DefectDraft,
        siteID: UUID,
        photos: [(jpegData: Data, marks: [DefectMark])] = [],
        at moment: Date = Date()
    ) -> Defect? {
        guard let defect = DefectList.making(draft, siteID: siteID, at: moment) else { return nil }
        context.insert(DefectEntry(defect: defect))
        for (index, photo) in photos.prefix(DefectPhoto.maximumBefore).enumerated() {
            context.insert(DefectPhotoEntry(photo: DefectPhoto(
                defectID: defect.id,
                siteID: siteID,
                sortOrder: index,
                marks: photo.marks,
                takenAt: moment,
                jpegData: photo.jpegData
            )))
        }
        persist()
        return defect
    }

    /// Fixed today, by you.
    func markFixed(_ id: UUID, at moment: Date = Date()) {
        change(id) { DefectList.fixed($0, at: moment) }
    }

    func reopen(_ id: UUID, at moment: Date = Date()) {
        change(id) { DefectList.reopened($0, at: moment) }
    }

    /// The defect and every photo of it.
    func remove(id: UUID) {
        for entry in entries(id: id) { context.delete(entry) }
        for entry in photoEntries(defectID: id) { context.delete(entry) }
        persist()
    }

    private func change(_ id: UUID, _ transform: (Defect) -> Defect) {
        guard let entry = entries(id: id).first else { return }
        let next = transform(entry.defect)
        guard next != entry.defect else { return }
        entry.apply(next)
        persist()
    }

    // MARK: - Photos

    /// A defect's photos with their bytes, before the after ones.
    func photos(defectID: UUID) -> [DefectPhoto] {
        DefectPhoto.ordered(photoEntries(defectID: defectID).map(\.photo))
    }

    /// Each defect's first photo of the problem — the marked one — by the
    /// defect's id: the thumbnails of the list and the PDF.
    func firstPhotos(siteID: UUID) -> [UUID: DefectPhoto] {
        let key = siteID.uuidString
        let descriptor = FetchDescriptor<DefectPhotoEntry>(
            predicate: #Predicate<DefectPhotoEntry> { $0.siteID == key && $0.isAfter == false },
            sortBy: [SortDescriptor(\DefectPhotoEntry.sortOrder)]
        )
        var result: [UUID: DefectPhoto] = [:]
        for entry in deduplicatedPhotos(fetch(descriptor)) {
            guard let defectID = UUID(uuidString: entry.defectID), result[defectID] == nil else { continue }
            result[defectID] = entry.photo
        }
        return result
    }

    /// Another photo of the defect, at the end of the before or the after
    /// ones, unless there are as many as there may be. Returns it if added.
    @discardableResult
    func addPhoto(_ jpegData: Data, to defect: Defect, isAfter: Bool, marks: [DefectMark] = [], at moment: Date = Date()) -> DefectPhoto? {
        let existing = photoEntries(defectID: defect.id).filter { $0.isAfter == isAfter }
        let limit = isAfter ? DefectPhoto.maximumAfter : DefectPhoto.maximumBefore
        guard existing.count < limit else { return nil }
        let photo = DefectPhoto(
            defectID: defect.id,
            siteID: defect.siteID,
            sortOrder: (existing.map(\.sortOrder).max() ?? -1) + 1,
            isAfter: isAfter,
            marks: marks,
            takenAt: moment,
            jpegData: jpegData
        )
        context.insert(DefectPhotoEntry(photo: photo))
        touch(defect.id, at: moment)
        persist()
        return photo
    }

    /// "Edit marking": the photo's marks replaced, the photo untouched.
    func setMarks(_ marks: [DefectMark], onPhoto id: UUID) {
        guard let entry = photoEntries(id: id).first else { return }
        entry.setMarks(marks)
        if let defectID = UUID(uuidString: entry.defectID) { touch(defectID, at: Date()) }
        persist()
    }

    func removePhoto(id: UUID) {
        for entry in photoEntries(id: id) { context.delete(entry) }
        persist()
    }

    /// The bytes of the given photos, by id: what a PDF draws.
    func photoData(ids: Set<UUID>) -> [UUID: Data] {
        var result: [UUID: Data] = [:]
        for id in ids {
            if let data = photoEntries(id: id).first?.jpegData { result[id] = data }
        }
        return result
    }

    /// A change to a photo is a change to its defect, for the collapse.
    private func touch(_ defectID: UUID, at moment: Date) {
        entries(id: defectID).first?.updatedAt = moment
    }

    // MARK: - Backup and restore

    func everything() -> (defects: [Defect], photos: [DefectPhoto]) {
        let defects = deduplicated(fetch(FetchDescriptor<DefectEntry>(sortBy: [SortDescriptor(\DefectEntry.notedAt)]))).map(\.defect)
        let photos = deduplicatedPhotos(fetch(FetchDescriptor<DefectPhotoEntry>(sortBy: [SortDescriptor(\DefectPhotoEntry.sortOrder)])))
            .map(\.photo)
        return (defects, photos)
    }

    /// Makes the given defects and photos the whole of every site's, as a
    /// restore and "Delete everything" do. A file holding one twice keeps
    /// the first.
    func replaceEverything(defects: [Defect], photos: [DefectPhoto]) {
        for entry in fetch(FetchDescriptor<DefectEntry>()) { context.delete(entry) }
        for entry in fetch(FetchDescriptor<DefectPhotoEntry>()) { context.delete(entry) }
        var seen = Set<UUID>()
        for defect in defects where seen.insert(defect.id).inserted {
            context.insert(DefectEntry(defect: defect))
        }
        var seenPhotos = Set<UUID>()
        for photo in photos where seen.contains(photo.defectID) && seenPhotos.insert(photo.id).inserted {
            context.insert(DefectPhotoEntry(photo: photo))
        }
        persist()
    }

    // MARK: - Rows

    private func entries(id: UUID) -> [DefectEntry] {
        let key = id.uuidString
        return deduplicated(fetch(FetchDescriptor<DefectEntry>(predicate: #Predicate<DefectEntry> { $0.defectID == key })))
    }

    private func photoEntries(defectID: UUID) -> [DefectPhotoEntry] {
        let key = defectID.uuidString
        let descriptor = FetchDescriptor<DefectPhotoEntry>(
            predicate: #Predicate<DefectPhotoEntry> { $0.defectID == key },
            sortBy: [SortDescriptor(\DefectPhotoEntry.sortOrder)]
        )
        return deduplicatedPhotos(fetch(descriptor))
    }

    private func photoEntries(id: UUID) -> [DefectPhotoEntry] {
        let key = id.uuidString
        return deduplicatedPhotos(fetch(FetchDescriptor<DefectPhotoEntry>(predicate: #Predicate<DefectPhotoEntry> { $0.photoID == key })))
    }

    private func deduplicated(_ entries: [DefectEntry]) -> [DefectEntry] {
        let kept = context.collapseDuplicates(entries, by: \.defectID) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt)
        }.kept
        var seen = Set<String>()
        return kept.filter { seen.insert($0.defectID).inserted }
    }

    private func deduplicatedPhotos(_ entries: [DefectPhotoEntry]) -> [DefectPhotoEntry] {
        let kept = context.collapseDuplicates(entries, by: \.photoID) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt)
        }.kept
        var seen = Set<String>()
        return kept.filter { seen.insert($0.photoID).inserted }
    }

    private func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> [Model] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func persist() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
