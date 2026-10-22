import Foundation
import SwiftData

/// Reads and writes the site diary, its photos and the crew's signatures.
///
/// Thin in the way `SiteRepository` is: it converts between SwiftData
/// entities and the engine's value types and owns the upsert and uniqueness
/// rules, with the same last-edit-wins collapse of duplicates sync can leave.
///
/// **Not under the month lock, on purpose.** The lock keeps the hours of a
/// closed month as they were handed in, and none of this is hours: a diary
/// written up the next morning, a photo added late, and above all a crew
/// signing their month — which happens after the month ends, often after it
/// has been closed — must all still be possible. A signature cannot change
/// anyone's hours; it only records that they were read. The method names
/// avoid `save`/`delete` so `Scripts/check-repository-lock.py` does not take
/// these writes for the hours'.
///
/// Always built from a view's `modelContext` and used on the main actor.
struct SiteDiaryRepository {
    let context: ModelContext

    // MARK: - Diaries

    /// The site's diary on a date, if one is stored.
    func diary(siteID: UUID, on date: CalendarDate) -> SiteDiary? {
        diaryEntries(siteID: siteID, on: date).first?.diary
    }

    /// The site's diaries in a range, oldest first. `nil` means every site.
    func diaries(siteID: UUID?, in range: CalendarDateRange) -> [SiteDiary] {
        let lower = range.start.key
        let upper = range.end.key
        let predicate: Predicate<SiteDiaryEntry>
        if let siteID {
            let id = siteID.uuidString
            predicate = #Predicate<SiteDiaryEntry> { $0.siteID == id && $0.dateKey >= lower && $0.dateKey <= upper }
        } else {
            predicate = #Predicate<SiteDiaryEntry> { $0.dateKey >= lower && $0.dateKey <= upper }
        }
        let descriptor = FetchDescriptor<SiteDiaryEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\SiteDiaryEntry.dateKey), SortDescriptor(\SiteDiaryEntry.siteID)]
        )
        return firstOfEach(deduplicatedDiaries(fetch(descriptor)), by: \.identity).map(\.diary)
    }

    /// Writes a diary, or removes it when it is blank: an empty diary stores
    /// nothing, as an empty site day does not.
    func store(_ diary: SiteDiary) {
        let existing = diaryEntries(siteID: diary.siteID, on: diary.date)
        if diary.isBlank {
            for entry in existing { context.delete(entry) }
        } else if let entry = existing.first {
            entry.apply(diary)
        } else {
            context.insert(SiteDiaryEntry(diary: diary))
        }
        persist()
    }

    private func diaryEntries(siteID: UUID, on date: CalendarDate) -> [SiteDiaryEntry] {
        let id = siteID.uuidString
        let key = date.key
        let descriptor = FetchDescriptor<SiteDiaryEntry>(
            predicate: #Predicate<SiteDiaryEntry> { $0.siteID == id && $0.dateKey == key }
        )
        return deduplicatedDiaries(fetch(descriptor))
    }

    /// The dates in a range that have a diary or a photo on the site, for the
    /// month grid's mark. Reads no image.
    func datesWithEntries(siteID: UUID, in range: CalendarDateRange) -> Set<CalendarDate> {
        SiteDiary.datesWithEntries(
            diaries: diaries(siteID: siteID, in: range),
            photoDates: photoReferences(siteID: siteID, in: range).map(\.date)
        )
    }

    // MARK: - Photos

    /// Where the site's photos in a range sit, without reading an image.
    func photoReferences(siteID: UUID, in range: CalendarDateRange) -> [DiaryPhotoReference] {
        photoEntries(siteID: siteID, in: range).map(\.reference)
    }

    /// The day's photos with their bytes, in the order they were added.
    func photos(siteID: UUID, on date: CalendarDate) -> [DiaryPhoto] {
        photoEntries(siteID: siteID, in: CalendarDateRange(single: date)).map(\.photo)
    }

    /// The bytes of the given photos, by id: what the PDF draws.
    func photoData(ids: Set<UUID>, siteID: UUID, in range: CalendarDateRange) -> [UUID: Data] {
        var result: [UUID: Data] = [:]
        for entry in photoEntries(siteID: siteID, in: range) {
            guard let id = UUID(uuidString: entry.photoID), ids.contains(id), let data = entry.jpegData else { continue }
            result[id] = data
        }
        return result
    }

    /// Adds a photo at the end of the day's photos, unless the day already
    /// has as many as it may. Returns whether it was added.
    @discardableResult
    func addPhoto(_ jpegData: Data, siteID: UUID, on date: CalendarDate) -> Bool {
        let existing = photoEntries(siteID: siteID, in: CalendarDateRange(single: date))
        guard SiteDiary.photoSlotsLeft(existing: existing.count) > 0 else { return false }
        let next = (existing.map(\.sortOrder).max() ?? -1) + 1
        context.insert(SiteDiaryPhotoEntry(photo: DiaryPhoto(siteID: siteID, date: date, sortOrder: next, jpegData: jpegData)))
        persist()
        return true
    }

    func removePhoto(id: UUID) {
        let key = id.uuidString
        let descriptor = FetchDescriptor<SiteDiaryPhotoEntry>(predicate: #Predicate<SiteDiaryPhotoEntry> { $0.photoID == key })
        for entry in fetch(descriptor) { context.delete(entry) }
        persist()
    }

    private func photoEntries(siteID: UUID, in range: CalendarDateRange) -> [SiteDiaryPhotoEntry] {
        let id = siteID.uuidString
        let lower = range.start.key
        let upper = range.end.key
        let descriptor = FetchDescriptor<SiteDiaryPhotoEntry>(
            predicate: #Predicate<SiteDiaryPhotoEntry> { $0.siteID == id && $0.dateKey >= lower && $0.dateKey <= upper },
            sortBy: [SortDescriptor(\SiteDiaryPhotoEntry.dateKey), SortDescriptor(\SiteDiaryPhotoEntry.sortOrder)]
        )
        let kept = context.collapseDuplicates(fetch(descriptor), by: \.photoID) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt)
        }.kept
        return firstOfEach(kept, by: \.photoID)
    }

    // MARK: - Signatures

    /// Every signature for a site and month.
    func signatures(siteID: UUID, month: YearMonth) -> [CrewSignature] {
        let id = siteID.uuidString
        let key = month.year * 100 + month.month
        let descriptor = FetchDescriptor<CrewSignatureEntry>(
            predicate: #Predicate<CrewSignatureEntry> { $0.siteID == id && $0.monthKey == key }
        )
        return firstOfEach(deduplicatedSignatures(fetch(descriptor)), by: \.identity).map(\.signature)
    }

    /// Records a signature, replacing that person's earlier one for the
    /// month: signing again is how a changed month is signed for.
    func storeSignature(_ signature: CrewSignature) {
        let id = signature.siteID.uuidString
        let member = signature.memberID.uuidString
        let key = signature.month.year * 100 + signature.month.month
        let descriptor = FetchDescriptor<CrewSignatureEntry>(
            predicate: #Predicate<CrewSignatureEntry> { $0.siteID == id && $0.memberID == member && $0.monthKey == key }
        )
        let existing = deduplicatedSignatures(fetch(descriptor))
        if let entry = existing.first {
            entry.apply(signature)
        } else {
            context.insert(CrewSignatureEntry(signature: signature))
        }
        persist()
    }

    /// Takes a person's signature for the month away.
    func removeSignature(siteID: UUID, memberID: UUID, month: YearMonth) {
        let id = siteID.uuidString
        let member = memberID.uuidString
        let key = month.year * 100 + month.month
        let descriptor = FetchDescriptor<CrewSignatureEntry>(
            predicate: #Predicate<CrewSignatureEntry> { $0.siteID == id && $0.memberID == member && $0.monthKey == key }
        )
        for entry in fetch(descriptor) { context.delete(entry) }
        persist()
    }

    // MARK: - Backup and restore

    /// Everything, for a backup. The photos' bytes are read here and only here.
    func everything() -> (diaries: [SiteDiary], photos: [DiaryPhoto], signatures: [CrewSignature]) {
        let diaries = firstOfEach(
            deduplicatedDiaries(fetch(FetchDescriptor<SiteDiaryEntry>(sortBy: [SortDescriptor(\SiteDiaryEntry.dateKey)]))),
            by: \.identity
        ).map(\.diary)
        let photoRows = context.collapseDuplicates(
            fetch(FetchDescriptor<SiteDiaryPhotoEntry>(sortBy: [SortDescriptor(\SiteDiaryPhotoEntry.dateKey), SortDescriptor(\SiteDiaryPhotoEntry.sortOrder)])),
            by: \.photoID
        ) { Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt) }.kept
        let signatures = firstOfEach(deduplicatedSignatures(fetch(FetchDescriptor<CrewSignatureEntry>())), by: \.identity)
            .map(\.signature)
        return (diaries, firstOfEach(photoRows, by: \.photoID).map(\.photo), signatures)
    }

    /// Makes the given diaries, photos and signatures the whole of them, as a
    /// restore does. A file holding the same thing twice keeps the first.
    func replaceAll(diaries: [SiteDiary], photos: [DiaryPhoto], signatures: [CrewSignature]) {
        for entry in fetch(FetchDescriptor<SiteDiaryEntry>()) { context.delete(entry) }
        for entry in fetch(FetchDescriptor<SiteDiaryPhotoEntry>()) { context.delete(entry) }
        for entry in fetch(FetchDescriptor<CrewSignatureEntry>()) { context.delete(entry) }

        var seenDiaries = Set<SiteDayIdentity>()
        for diary in diaries where !diary.isBlank
            && seenDiaries.insert(SiteDayIdentity(siteID: diary.siteID.uuidString, dateKey: diary.date.key)).inserted {
            context.insert(SiteDiaryEntry(diary: diary))
        }
        var seenPhotos = Set<UUID>()
        for photo in photos where !photo.jpegData.isEmpty && seenPhotos.insert(photo.id).inserted {
            context.insert(SiteDiaryPhotoEntry(photo: photo))
        }
        var seenSignatures = Set<String>()
        for signature in signatures {
            let entry = CrewSignatureEntry(signature: signature)
            if seenSignatures.insert(entry.identity).inserted { context.insert(entry) }
        }
        persist()
    }

    // MARK: - Duplicates

    private func deduplicatedDiaries(_ entries: [SiteDiaryEntry]) -> [SiteDiaryEntry] {
        context.collapseDuplicates(entries, by: \.identity) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt)
        }.kept
    }

    private func deduplicatedSignatures(_ entries: [CrewSignatureEntry]) -> [CrewSignatureEntry] {
        context.collapseDuplicates(entries, by: \.identity) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.updatedAt)
        }.kept
    }

    private func firstOfEach<Model, Key: Hashable>(_ models: [Model], by key: KeyPath<Model, Key>) -> [Model] {
        var seen = Set<Key>()
        return models.filter { seen.insert($0[keyPath: key]).inserted }
    }

    private func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> [Model] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func persist() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
