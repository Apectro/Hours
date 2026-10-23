import Foundation

/// What sick leave pays where the app knows the rule.
///
/// Only Croatia so far: the employer pays sick leave for the first 42 days at
/// at least 70% of the average pay of the last six months (a collective
/// agreement may pay more; a work injury, an occupational disease and
/// pregnancy complications are paid in full), and from the 43rd day the
/// health insurer, HZZO, pays instead. The app uses the hourly rate, not the
/// six-month average, and says so where the percentage is set.
enum SickPay {
    /// Sets the built-in Sick type to the country's rule, when there is one
    /// and Sick has not been changed. A Sick type the person edited — any
    /// stored definition with its id — is theirs and is left alone, whatever
    /// it says.
    ///
    /// Called where the country is chosen: the first-run "Where do you
    /// work?" step and adding a country's public holidays.
    static func applyCountryDefault(_ country: HolidayCountry?, to settings: inout AppSettings) {
        guard country == .hr, !settings.customDayTypes.contains(where: { $0.id == .sick }) else { return }
        var sick = DayTypeCatalog.standard.definition(for: .sick)
        sick.paidPercent = 70
        sick.employerPaysFirst42Days = true
        settings.customDayTypes.append(sick)
    }
}
