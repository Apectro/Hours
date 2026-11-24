import Foundation

/// "Write today's hours" on the Today tab (2026-11-24): the one question,
/// "Where did you work today?", and its rows: each active site with what
/// is written on it today, then "Not on a site".
///
/// Whether a day is written is the rule the site's month uses
/// (`SiteDayStatus`): any site day stored for today, with "no work" told
/// apart. A paused site is not offered: nothing is expected on it.
enum WriteToday {
    enum State: Hashable, Sendable {
        /// Written: how many were ticked, and the site's times when it has
        /// them.
        case written(people: Int, start: TimeOfDay?, end: TimeOfDay?)
        /// Recorded as no work today (`SiteDay.isNoWorkDay`).
        case noWork
        case notWritten
    }

    struct Row: Hashable, Sendable, Identifiable {
        var siteID: UUID
        var siteName: String
        var state: State

        var id: UUID { siteID }
    }

    /// The sites to ask about: active, and not paused on `today`, in the
    /// Sites tab's order.
    static func sites(_ sites: [Site], settings: AppSettings, today: CalendarDate) -> [Site] {
        SitePalette.ordered(sites).filter {
            !$0.isArchived && !settings.siteSetup(for: $0.id).isPaused(on: today)
        }
    }

    /// Whether the Today tab shows the button at all: with no site to ask
    /// about there is no question, and the screen stays as it was.
    static func isOffered(sites: [Site], settings: AppSettings, today: CalendarDate) -> Bool {
        !self.sites(sites, settings: settings, today: today).isEmpty
    }

    /// One row per site to ask about. `siteDays` may hold other dates and
    /// other sites; the first day stored for a site today is the one read,
    /// as everywhere a duplicate is met.
    static func rows(sites: [Site], siteDays: [SiteDay], settings: AppSettings, today: CalendarDate) -> [Row] {
        var written: [UUID: SiteDay] = [:]
        for day in siteDays where day.date == today && written[day.siteID] == nil {
            written[day.siteID] = day
        }
        return self.sites(sites, settings: settings, today: today).map { site in
            Row(siteID: site.id, siteName: site.name, state: state(of: written[site.id]))
        }
    }

    static func state(of day: SiteDay?) -> State {
        guard let day else { return .notWritten }
        if day.isNoWorkDay { return .noWork }
        return .written(people: day.present.count, start: day.start, end: day.end)
    }
}
