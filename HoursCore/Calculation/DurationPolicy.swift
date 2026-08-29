import Foundation

/// How the length of a shift is measured — the app's answer to daylight saving.
///
/// On the two DST transition days a year, "08:00 to 16:00" is eight hours on
/// the wall clock but seven or nine hours of elapsed time. Neither answer is
/// wrong; they answer different questions, and payroll practice varies.
///
/// - `wallClock` (default): the shift is as long as the clock says. A contract
///   that says "eight hours" is satisfied by 08:00–16:00 on every day of the
///   year. This is what most salaried timesheets do, and it has the practical
///   virtue of being stable when the phone changes time zone.
/// - `elapsedReal`: the shift is as long as it actually lasted. Choose this if
///   the hours are billed or paid by elapsed time — a night shift that runs
///   through a transition really is an hour longer or shorter.
enum DurationPolicy: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case wallClock
    case elapsedReal

    var id: String { rawValue }

    var title: String { label(in: .device) }

    var explanation: String { explanation(in: .device) }

    func label(in language: ExportLanguage) -> String {
        switch self {
        case .wallClock: return language(.wallClock)
        case .elapsedReal: return language(.elapsedReal)
        }
    }

    func explanation(in language: ExportLanguage) -> String {
        switch self {
        case .wallClock: return language(.wallClockExplained)
        case .elapsedReal: return language(.elapsedRealExplained)
        }
    }
}

/// Optional rounding applied to the worked total of a day.
enum RoundingRule: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    // Named `exact` rather than `none` so it can never be mistaken for
    // `Optional.none` at a call site.
    case exact
    case nearestFiveMinutes
    case nearestQuarterHour

    var id: String { rawValue }

    var title: String { label(in: .device) }

    func label(in language: ExportLanguage) -> String {
        switch self {
        case .exact: return language(.roundingExact)
        case .nearestFiveMinutes: return language(.roundingFiveMinutes)
        case .nearestQuarterHour: return language(.roundingQuarterHour)
        }
    }

    var step: Int {
        switch self {
        case .exact: return 1
        case .nearestFiveMinutes: return 5
        case .nearestQuarterHour: return 15
        }
    }

    func apply(to minutes: Int) -> Int {
        guard step > 1 else { return minutes }
        let sign = minutes < 0 ? -1 : 1
        let magnitude = abs(minutes)
        let rounded = ((magnitude + step / 2) / step) * step
        return sign * rounded
    }
}
