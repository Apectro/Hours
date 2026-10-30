import SwiftUI

/// A site's month as the director gets it, from the site's Sheet button: the
/// export screen with Crew sheet chosen and this site ticked, on this month.
///
/// Kept as its own name so the site screen's call stays `SiteExportScreen(site:
/// month:)`; everything else is `ExportScreen`, which serves your own hours
/// and every site from one place.
struct SiteExportScreen: View {
    let site: Site
    let month: YearMonth

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        // Your own timesheet, should WHAT be moved to My hours, starts on
        // this month, as it does from the calendar.
        let calendar = settingsStore.workCalendar
        ExportScreen(
            initialRange: CalendarDate.today(in: calendar).yearMonth.range(in: calendar),
            site: site,
            month: month
        )
    }
}
