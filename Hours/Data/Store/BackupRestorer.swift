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

    init(context: ModelContext) {
        self.context = context
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
        return BackupArchive(
            settings: settings,
            days: workdays.allEntries().map(\.record),
            holidays: workdays.holidayRules(),
            sites: sites,
            crew: sites.flatMap { siteRepository.crew(for: $0.id, includeHidden: true) },
            siteDays: siteRepository.siteDays(siteID: nil, in: Self.everything)
        )
    }

    /// Wide enough that no recorded date falls outside it.
    private static let everything = CalendarDateRange(
        start: CalendarDate(year: 1, month: 1, day: 1),
        end: CalendarDate(year: 9999, month: 12, day: 31)
    )

    // MARK: - Restore

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
        for record in archive.days { try? workdays.save(record) }
        for holiday in archive.holidays { workdays.upsert(holiday) }

        let siteRepository = SiteRepository(context: context, lock: .unlocked)
        if let sites = archive.sites {
            siteRepository.replaceAll(
                sites: sites,
                crew: archive.crew ?? [],
                siteDays: archive.siteDays ?? []
            )
        }

        rebuildSiteShifts(workdays: workdays, siteRepository: siteRepository)
    }

    /// Removes every day, holiday, site, crew member and site day.
    ///
    /// Sites go with the days because the calendar's site shifts are made from
    /// them: keeping one without the other would leave the two disagreeing.
    func deleteEverything() {
        let workdays = WorkdayRepository(context: context, lock: .unlocked)
        workdays.deleteAllDays()
        workdays.deleteAllHolidays()
        SiteRepository(context: context, lock: .unlocked).replaceAll(sites: [], crew: [], siteDays: [])
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
                if updated != record { try? workdays.save(updated) }
            } else {
                try? workdays.delete(on: record.date)
            }
        }
        for (date, record) in rebuilt where !seen.contains(date) {
            try? workdays.save(record)
        }
    }
}
