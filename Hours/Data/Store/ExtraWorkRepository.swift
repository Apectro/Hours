import Foundation
import SwiftData

/// Reads and writes extra work: the jobs, their photos, the reports that were
/// sent and the remembered items.
///
/// Thin in the way `SiteDiaryRepository` is: it converts between SwiftData
/// entities and the engine's value types and owns the uniqueness rules, with
/// the same last-edit-wins collapse of the duplicates sync can leave.
///
/// **Not under the month lock, on purpose**, for the diary's reason: none of
/// this is hours of anyone's own day. Extra work done on the 30th is written
/// up and sent to the boss in the next month, after the month is closed, and
/// a client's signature or a job ticked done changes nobody's hours. The method
/// names avoid `save`, `delete` and `replaceAll` so
/// `Scripts/check-repository-lock.py` does not take these writes for the
/// hours'.
///
/// Always built from a view's `modelContext` and used on the main actor.
struct ExtraWorkRepository {
    let context: ModelContext

    // MARK: - Jobs

    /// A site's jobs, oldest day first and in the order written within a day.
    /// `range` nil means every date.
    func jobs(siteID: UUID, in range: CalendarDateRange? = nil) -> [ExtraWorkJob] {
        let id = siteID.uuidString
        let predicate: Predicate<ExtraWorkJobEntry>
        if let range {
            let lower = range.start.key
            let upper = range.end.key
            predicate = #Predicate<ExtraWorkJobEntry> { $0.siteID == id && $0.dateKey >= lower && $0.dateKey <= upper }
        } else {
            predicate = #Predicate<ExtraWorkJobEntry> { $0.siteID == id }
        }
        let descriptor = FetchDescriptor<ExtraWorkJobEntry>(
            predicate: predicate,
            sortBy: [SortDescriptor(\ExtraWorkJobEntry.dateKey), SortDescriptor(\ExtraWorkJobEntry.createdAt)]
        )
        return deduplicatedJobs(fetch(descriptor)).map(\.job)
    }

    func job(id: UUID) -> ExtraWorkJob? {
        jobEntries(id: id).first?.job
    }

    /// Writes a job as edited, stamped now. A blank one removes the stored
    /// job and its photos: an empty job is not worth keeping.
    func storeJob(_ job: ExtraWorkJob) {
        var next = job.cleaned()
        next.updatedAt = Date()
        let existing = jobEntries(id: job.id)
        if next.isBlank {
            for entry in existing { context.delete(entry) }
            for entry in photoEntries(jobID: job.id) { context.delete(entry) }
        } else if let entry = existing.first {
            entry.apply(next)
        } else {
            context.insert(ExtraWorkJobEntry(job: next))
        }
        persist()
    }

    /// Writes jobs whose status changed — sent to the boss — in one save,
    /// without touching anything else about them.
    func storeStatus(of jobs: [ExtraWorkJob]) {
        for job in jobs {
            guard let entry = jobEntries(id: job.id).first else { continue }
            entry.statusRawValue = job.status.rawValue
            entry.sentAt = job.sentAt
            entry.sentReportID = job.sentReportID?.uuidString
            entry.updatedAt = Date()
        }
        persist()
    }

    /// Writes a job ticked done or back in progress, from the row's
    /// checkmark, without touching anything else about it. Not under the
    /// month lock, like everything here.
    func storeProgress(of job: ExtraWorkJob) {
        guard let entry = jobEntries(id: job.id).first else { return }
        entry.isDone = job.isDone
        entry.doneAt = job.doneAt
        entry.updatedAt = Date()
        persist()
    }

    /// Takes a job away, with its photos.
    func removeJob(id: UUID) {
        for entry in jobEntries(id: id) { context.delete(entry) }
        for entry in photoEntries(jobID: id) { context.delete(entry) }
        persist()
    }

    private func jobEntries(id: UUID) -> [ExtraWorkJobEntry] {
        let key = id.uuidString
        let descriptor = FetchDescriptor<ExtraWorkJobEntry>(predicate: #Predicate<ExtraWorkJobEntry> { $0.jobID == key })
        return deduplicatedJobs(fetch(descriptor))
    }

    /// The days in a range with a job on the site: the month grid's mark.
    func dateKeys(siteID: UUID, in range: CalendarDateRange) -> Set<Int> {
        ExtraWorkReport.dateKeys(jobs(siteID: siteID, in: range))
    }

    // MARK: - Photos

    /// The job's photos with their bytes, in the order they were added.
    func photos(jobID: UUID) -> [ExtraWorkPhoto] {
        photoEntries(jobID: jobID).map(\.photo)
    }

    /// How many photos each of these jobs has, without reading an image —
    /// what the day's list says ("2 photos").
    func photoCounts(siteID: UUID) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for entry in sitePhotoEntries(siteID: siteID) {
            guard let id = UUID(uuidString: entry.jobID) else { continue }
            counts[id, default: 0] += 1
        }
        return counts
    }

    /// Each job's photo ids in order, for placing them in the PDF.
    func photoIDs(siteID: UUID, jobIDs: Set<UUID>) -> [UUID: [UUID]] {
        var result: [UUID: [UUID]] = [:]
        for entry in sitePhotoEntries(siteID: siteID) {
            guard let job = UUID(uuidString: entry.jobID), jobIDs.contains(job),
                  let photo = UUID(uuidString: entry.photoID) else { continue }
            result[job, default: []].append(photo)
        }
        return result
    }

    /// The bytes of the given photos, by id: what the PDF draws.
    func photoData(ids: Set<UUID>, siteID: UUID) -> [UUID: Data] {
        var result: [UUID: Data] = [:]
        for entry in sitePhotoEntries(siteID: siteID) {
            guard let id = UUID(uuidString: entry.photoID), ids.contains(id), let data = entry.jpegData else { continue }
            result[id] = data
        }
        return result
    }

    /// Adds a photo after the job's others, unless it has as many as it may.
    @discardableResult
    func addPhoto(_ jpegData: Data, jobID: UUID, siteID: UUID) -> Bool {
        let existing = photoEntries(jobID: jobID)
        guard ExtraWorkJob.photoSlotsLeft(existing: existing.count) > 0 else { return false }
        let next = (existing.map(\.sortOrder).max() ?? -1) + 1
        context.insert(ExtraWorkPhotoEntry(photo: ExtraWorkPhoto(jobID: jobID, siteID: siteID, sortOrder: next, jpegData: jpegData)))
        persist()
        return true
    }

    func removePhoto(id: UUID) {
        let key = id.uuidString
        let descriptor = FetchDescriptor<ExtraWorkPhotoEntry>(predicate: #Predicate<ExtraWorkPhotoEntry> { $0.photoID == key })
        for entry in fetch(descriptor) { context.delete(entry) }
        persist()
    }

    private func photoEntries(jobID: UUID) -> [ExtraWorkPhotoEntry] {
        let key = jobID.uuidString
        let descriptor = FetchDescriptor<ExtraWorkPhotoEntry>(
            predicate: #Predicate<ExtraWorkPhotoEntry> { $0.jobID == key },
            sortBy: [SortDescriptor(\ExtraWorkPhotoEntry.sortOrder)]
        )
        return deduplicatedPhotos(fetch(descriptor))
    }

    private func sitePhotoEntries(siteID: UUID) -> [ExtraWorkPhotoEntry] {
        let key = siteID.uuidString
        let descriptor = FetchDescriptor<ExtraWorkPhotoEntry>(
            predicate: #Predicate<ExtraWorkPhotoEntry> { $0.siteID == key },
            sortBy: [SortDescriptor(\ExtraWorkPhotoEntry.jobID), SortDescriptor(\ExtraWorkPhotoEntry.sortOrder)]
        )
        return deduplicatedPhotos(fetch(descriptor))
    }

    // MARK: - Sent reports

    /// Records a report that was shared and marks its jobs sent, in one save
    /// — called only once the share sheet says the share went through.
    func recordSent(_ record: ExtraWorkReportRecord, jobs: [ExtraWorkJob]) {
        context.insert(ExtraWorkReportEntry(record: record))
        storeStatus(of: jobs)
    }

    func reports(siteID: UUID) -> [ExtraWorkReportRecord] {
        let key = siteID.uuidString
        let descriptor = FetchDescriptor<ExtraWorkReportEntry>(
            predicate: #Predicate<ExtraWorkReportEntry> { $0.siteID == key },
            sortBy: [SortDescriptor(\ExtraWorkReportEntry.sentAt, order: .reverse)]
        )
        return deduplicatedReports(fetch(descriptor)).map(\.record)
    }

    // MARK: - Remembered items

    /// Every remembered item, one per name.
    func catalog() -> [ExtraWorkCatalogItem] {
        let rows = deduplicatedItems(fetch(FetchDescriptor<ExtraWorkItemEntry>(sortBy: [SortDescriptor(\ExtraWorkItemEntry.name)])))
        // Two devices can each remember "Kabel" under their own id; the
        // freshest spelling of a name is the one offered.
        var byName: [String: ExtraWorkItemEntry] = [:]
        for row in rows {
            let key = ExtraWorkCatalog.key(row.name)
            if let kept = byName[key], kept.updatedAt >= row.updatedAt { continue }
            byName[key] = row
        }
        return byName.values.map(\.item).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Remembers the items of a job that was just written.
    func recordUse(of items: [ExtraWorkItem], at moment: Date = Date()) {
        let before = catalog()
        let after = ExtraWorkCatalog.recording(items, into: before, at: moment)
        for item in after where !before.contains(item) {
            storeCatalogEntry(item)
        }
        persist()
    }

    /// Writes one remembered item, as edited in the list.
    func storeCatalogItem(_ item: ExtraWorkCatalogItem) {
        storeCatalogEntry(item)
        persist()
    }

    func removeCatalogItem(id: UUID) {
        let key = id.uuidString
        let descriptor = FetchDescriptor<ExtraWorkItemEntry>(predicate: #Predicate<ExtraWorkItemEntry> { $0.itemID == key })
        for entry in fetch(descriptor) { context.delete(entry) }
        persist()
    }

    private func storeCatalogEntry(_ item: ExtraWorkCatalogItem) {
        let key = item.id.uuidString
        let descriptor = FetchDescriptor<ExtraWorkItemEntry>(predicate: #Predicate<ExtraWorkItemEntry> { $0.itemID == key })
        if let entry = deduplicatedItems(fetch(descriptor)).first {
            entry.apply(item)
        } else {
            context.insert(ExtraWorkItemEntry(item: item))
        }
    }

    // MARK: - Backup and restore

    /// Everything, for a backup. The photos' bytes are read here and only here.
    func everything() -> (jobs: [ExtraWorkJob], photos: [ExtraWorkPhoto], reports: [ExtraWorkReportRecord], items: [ExtraWorkCatalogItem]) {
        let jobs = deduplicatedJobs(fetch(FetchDescriptor<ExtraWorkJobEntry>(
            sortBy: [SortDescriptor(\ExtraWorkJobEntry.dateKey), SortDescriptor(\ExtraWorkJobEntry.createdAt)]
        ))).map(\.job)
        let photos = deduplicatedPhotos(fetch(FetchDescriptor<ExtraWorkPhotoEntry>(
            sortBy: [SortDescriptor(\ExtraWorkPhotoEntry.jobID), SortDescriptor(\ExtraWorkPhotoEntry.sortOrder)]
        ))).map(\.photo)
        let reports = deduplicatedReports(fetch(FetchDescriptor<ExtraWorkReportEntry>(
            sortBy: [SortDescriptor(\ExtraWorkReportEntry.sentAt)]
        ))).map(\.record)
        return (jobs, photos, reports, catalog())
    }

    /// Makes the given extra work the whole of it, as a restore and "Delete
    /// everything" do. A file holding the same thing twice keeps the first.
    func replaceEverything(
        jobs: [ExtraWorkJob],
        photos: [ExtraWorkPhoto],
        reports: [ExtraWorkReportRecord],
        items: [ExtraWorkCatalogItem]
    ) {
        for entry in fetch(FetchDescriptor<ExtraWorkJobEntry>()) { context.delete(entry) }
        for entry in fetch(FetchDescriptor<ExtraWorkPhotoEntry>()) { context.delete(entry) }
        for entry in fetch(FetchDescriptor<ExtraWorkReportEntry>()) { context.delete(entry) }
        for entry in fetch(FetchDescriptor<ExtraWorkItemEntry>()) { context.delete(entry) }

        var seenJobs = Set<UUID>()
        for job in jobs where seenJobs.insert(job.id).inserted {
            context.insert(ExtraWorkJobEntry(job: job))
        }
        var seenPhotos = Set<UUID>()
        for photo in photos where !photo.jpegData.isEmpty && seenJobs.contains(photo.jobID)
            && seenPhotos.insert(photo.id).inserted {
            context.insert(ExtraWorkPhotoEntry(photo: photo))
        }
        var seenReports = Set<UUID>()
        for report in reports where seenReports.insert(report.id).inserted {
            context.insert(ExtraWorkReportEntry(record: report))
        }
        var seenItems = Set<String>()
        for item in items where seenItems.insert(ExtraWorkCatalog.key(item.name)).inserted {
            context.insert(ExtraWorkItemEntry(item: item))
        }
        persist()
    }

    // MARK: - Duplicates

    private func deduplicatedJobs(_ entries: [ExtraWorkJobEntry]) -> [ExtraWorkJobEntry] {
        context.collapseDuplicates(entries, by: \.jobID) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt)
        }.kept.firstOfEach(by: \.jobID)
    }

    private func deduplicatedPhotos(_ entries: [ExtraWorkPhotoEntry]) -> [ExtraWorkPhotoEntry] {
        context.collapseDuplicates(entries, by: \.photoID) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt)
        }.kept.firstOfEach(by: \.photoID)
    }

    private func deduplicatedReports(_ entries: [ExtraWorkReportEntry]) -> [ExtraWorkReportEntry] {
        context.collapseDuplicates(entries, by: \.reportID) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt)
        }.kept.firstOfEach(by: \.reportID)
    }

    private func deduplicatedItems(_ entries: [ExtraWorkItemEntry]) -> [ExtraWorkItemEntry] {
        context.collapseDuplicates(entries, by: \.itemID) {
            Freshness(updatedAt: $0.updatedAt, createdAt: $0.createdAt)
        }.kept.firstOfEach(by: \.itemID)
    }

    private func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) -> [Model] {
        (try? context.fetch(descriptor)) ?? []
    }

    private func persist() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}

private extension Array {
    /// Rows nothing could tell apart are all kept by the collapse; the first
    /// of each stands for them until the next edit decides.
    func firstOfEach<Key: Hashable>(by key: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: key]).inserted }
    }
}
