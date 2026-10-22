import Foundation

/// The figures over a site's month on the site screen: days written, the
/// crew's hours, yours, and how many days the weather stopped work.
///
/// Worked out here rather than in the view so the count of bad-weather days
/// on the screen and on the director's sheet follow one rule.
struct SiteMonthFigures: Hashable, Sendable {
    var daysWritten: Int
    var crewMinutes: Int
    var yourMinutes: Int
    var badWeatherDays: Int

    /// - Parameter days: the site's stored days; any outside `month` are
    ///   ignored, so the grid's borrowed neighbouring days can be passed as
    ///   they are.
    init(days: [SiteDay], month: YearMonth, calculator: SiteDayCalculator) {
        let written = days.filter { month.contains($0.date) }
        let results = written.map { calculator.compute($0) }
        daysWritten = written.count
        crewMinutes = results.reduce(0) { $0 + $1.crewTotalMinutes }
        yourMinutes = results.reduce(0) { total, result in
            total + (result.people.first { $0.memberID == CrewMember.youID }?.workedMinutes ?? 0)
        }
        badWeatherDays = written.filter(\.isBadWeatherStop).count
    }
}
