import SwiftUI

/// A site's month as the director gets it, from the site's own screen: the
/// export screen, opened on this site and this month.
///
/// Kept as its own name so the site screen's call stays `SiteExportScreen(site:
/// month:)`; everything else is `ExportScreen`, which serves your own hours
/// and every site from one place.
struct SiteExportScreen: View {
    let site: Site
    let month: YearMonth

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        // Your own timesheet, should the switch at the top be moved to it,
        // starts on this month, as it does from the calendar.
        let calendar = settingsStore.workCalendar
        ExportScreen(
            initialRange: CalendarDate.today(in: calendar).yearMonth.range(in: calendar),
            site: site,
            month: month
        )
    }
}
