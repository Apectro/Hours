import Foundation
import SwiftData

/// Turns the store into a backup and a backup back into the store.
///
/// Lived in `DataSettingsScreen` until Sites made it large enough to need
/// tests, and a view cannot be tested. The screen still decides *whether* to
/// restore (an empty or damaged file changes nothing) and what to tell the
/// person; this only does the work.
///
/// Always built from a `modelContext` and used on the main actor, like the
/// repositories it drives. It writes without the month lock on purpose: a
/// restore is the file becoming the database, not an edit to a closed month,
/// and `Scripts/check-repository-lock.py` lists this file as exempt for that
/// reason.
struct BackupRestorer {
    let context: ModelContext

    /// The month lock in force on this device when the restore starts.
    ///
    /// Deliberately NOT applied: a restore is the file becoming the database,
    /// not an edit to a closed month, and refusing half of it would leave a
    /// mixture of the backup and what was there before. It is taken so the
    /// caller states which lock it is overriding and a test can hold the
    /// restorer to ignoring it; nothing reads it.
    let liveLock: MonthLock

    init(context: ModelContext, liveLock: MonthLock = .unlocked) {
        self.context = context
        self.liveLock = liveLock
    }

    // MARK: - Backup

    /// Everything on the device, ready to encode.
    ///
    /// Sites, crews and site days are always written, as empty lists when
    /// there are none, so a new backup always says "this file knows about
    /// sites" and restoring it replaces rather than keeps whatever is on the
    /// device. Archived sites and hidden crew members are included: past days
    /// still refer to them.
    func makeArchive(settings: AppSettings) -> BackupArchive {
        let workdays = WorkdayRepository(context: context)
        let siteRepository = SiteRepository(context: context)
        let sites = siteRepository.sites(includeArchived: true)
        let diary = SiteDiaryRepository(context: context).everything()
        let extraWork = ExtraWorkRepository(context: context).everything()
        var archive = BackupArchive(
            settings: settings,
            days: workdays.allEntries().map(\.record),
            holidays: workdays.holidayRules(),
            sites: sites,
            crew: sites.flatMap { siteRepository.crew(for: $0.id, includeHidden: true) },
            siteDays: siteRepository.siteDays(siteID: nil, in: Self.everything),
            diaries: diary.diaries,
            diaryPhotos: diary.photos,
            signatures: diary.signatures
        )
        // Always written, as empty lists when there is none, so a new backup
        // says it knows about extra work and restoring it replaces the device's.
        archive.extraWorkJobs = extraWork.jobs
        archive.extraWorkPhotos = extraWork.photos
        archive.extraWorkReports = extraWork.reports
        archive.extraWorkItems = extraWork.items
        return archive
    }

    /// Wide enough that no recorded date falls outside it.
    private static let everything = CalendarDateRange(
        start: CalendarDate(year: 1, month: 1, day: 1),
        end: CalendarDate(year: 9999, month: 12, day: 31)
    )

    // MARK: - Restore

    /// Whether restoring would put anything back. A file with no days, no
    /// holidays and no sites can only erase, and there is a button for that.
    /// A file holding only sites is not empty: it must restore.
    static func hasAnythingToRestore(_ archive: BackupArchive) -> Bool {
        !archive.days.isEmpty || !archive.holidays.isEmpty || !(archive.sites ?? []).isEmpty
    }

    /// Makes the archive the whole of the store: days and holidays, then site
    /// data, then the site shifts in the calendar.
    ///
    /// A file without site data (`sites == nil`, one written before Sites
    /// existed) leaves the sites, crews and site days already here alone; a
    /// file with it, even an empty list, replaces them.
    ///
    /// Settings are the caller's, since they live in the settings store rather
    /// than in SwiftData.
    func restore(_ archive: BackupArchive) {
        let workdays = WorkdayRepository(context: context, lock: .unlocked)
        workdays.deleteAllDays()
        workdays.deleteAllHolidays()
        for record in archive.days { _ = try? workdays.save(record) }
        for holiday in archive.holidays { workdays.upsert(holiday) }

        let siteRepository = SiteRepository(context: context, lock: .unlocked)
        if let sites = archive.sites {
            siteRepository.replaceAll(
                sites: sites,
                crew: archive.crew ?? [],
                siteDays: archive.siteDays ?? []
            )
        }
        restoreDiary(from: archive)
        restoreExtraWork(from: archive)

        rebuildSiteShifts(workdays: workdays, siteRepository: siteRepository)
    }

    /// The diary, its photos and the signatures: replaced by the file's when
    /// it has them; from a file older than them, the device's are kept for the
    /// sites the file restores and dropped for the sites it removed
    /// (`BackupArchive.restoredItems`).
    private func restoreDiary(from archive: BackupArchive) {
        let diaryRepository = SiteDiaryRepository(context: context)
        let onDevice = diaryRepository.everything()
        let restoredSites = archive.sites.map { Set($0.map(\.id)) }
        diaryRepository.replaceAll(
            diaries: BackupArchive.restoredItems(
                fromFile: archive.diaries, onDevice: onDevice.diaries, restoredSiteIDs: restoredSites, siteID: \.siteID
            ),
            photos: BackupArchive.restoredItems(
                fromFile: archive.diaryPhotos, onDevice: onDevice.photos, restoredSiteIDs: restoredSites, siteID: \.siteID
            ),
            signatures: BackupArchive.restoredItems(
                fromFile: archive.signatures, onDevice: onDevice.signatures, restoredSiteIDs: restoredSites, siteID: \.siteID
            )
        )
    }

    /// Extra work, by the diary's rule: replaced by the file's when it has
    /// it; from an older file, the device's jobs, photos and reports are kept
    /// for the sites the file restores. The remembered items belong to no
    /// site, so an older file keeps the device's.
    private func restoreExtraWork(from archive: BackupArchive) {
        let repository = ExtraWorkRepository(context: context)
        let onDevice = repository.everything()
        let restoredSites = archive.sites.map { Set($0.map(\.id)) }
        repository.replaceEverything(
            jobs: BackupArchive.restoredItems(
                fromFile: archive.extraWorkJobs, onDevice: onDevice.jobs, restoredSiteIDs: restoredSites, siteID: \.siteID
            ),
            photos: BackupArchive.restoredItems(
                fromFile: archive.extraWorkPhotos, onDevice: onDevice.photos, restoredSiteIDs: restoredSites, siteID: \.siteID
            ),
            reports: BackupArchive.restoredItems(
                fromFile: archive.extraWorkReports, onDevice: onDevice.reports, restoredSiteIDs: restoredSites, siteID: \.siteID
            ),
            items: BackupArchive.restoredCatalog(fromFile: archive.extraWorkItems, onDevice: onDevice.items)
        )
    }

    /// Removes every day, holiday, site, crew member and site day, every
    /// diary, photo and signature, and all extra work.
    ///
    /// Sites go with the days because the calendar's site shifts are made from
    /// them: keeping one without the other would leave the two disagreeing.
    func deleteEverything() {
        let workdays = WorkdayRepository(context: context, lock: .unlocked)
        workdays.deleteAllDays()
        workdays.deleteAllHolidays()
        SiteRepository(context: context, lock: .unlocked).replaceAll(sites: [], crew: [], siteDays: [])
        // A site's diary, photos and signatures go with it.
        SiteDiaryRepository(context: context).replaceAll(diaries: [], photos: [], signatures: [])
        // Extra work goes with its sites; the remembered items with the rest.
        ExtraWorkRepository(context: context).replaceEverything(jobs: [], photos: [], reports: [], items: [])
    }

    /// Brings the calendar's site shifts into line with the site days now in
    /// the store, so the two always agree after a restore.
    ///
    /// A shift whose site is not in the store is dropped, and a day left with
    /// nothing in it is deleted. Only days that actually change are written,
    /// so a restore does not stamp every day as edited.
    private func rebuildSiteShifts(workdays: WorkdayRepository, siteRepository: SiteRepository) {
        let current = workdays.allEntries().map(\.record)
        let siteDays = siteRepository.siteDays(siteID: nil, in: Self.everything)
        let rebuilt = Dictionary(
            SiteCalendarSync.rebuilt(days: current, siteDays: siteDays).map { ($0.date, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var seen = Set<CalendarDate>()
        for record in current where seen.insert(record.date).inserted {
            if let updated = rebuilt[record.date] {
                if updated != record { _ = try? workdays.save(updated) }
            } else {
                try? workdays.delete(on: record.date)
            }
        }
        for (date, record) in rebuilt where !seen.contains(date) {
            _ = try? workdays.save(record)
        }
    }
}
