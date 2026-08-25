import Foundation

/// What the calendar shows and how it is laid out.
struct CalendarPreferences: Hashable, Codable, Sendable {
    /// 1 = Sunday ... 7 = Saturday. `nil` follows the device locale.
    var firstWeekdayOverride: Int?
    var showWeekends: Bool
    var showHolidayMarkers: Bool
    var showMonthSummary: Bool
    var dayCellDetail: DayCellDetail
    var preferredScope: CalendarScope

    init(
        firstWeekdayOverride: Int? = nil,
        showWeekends: Bool = true,
        showHolidayMarkers: Bool = true,
        showMonthSummary: Bool = true,
        dayCellDetail: DayCellDetail = .workedHours,
        preferredScope: CalendarScope = .month
    ) {
        self.firstWeekdayOverride = firstWeekdayOverride.flatMap { (1...7).contains($0) ? $0 : nil }
        self.showWeekends = showWeekends
        self.showHolidayMarkers = showHolidayMarkers
        self.showMonthSummary = showMonthSummary
        self.dayCellDetail = dayCellDetail
        self.preferredScope = preferredScope
    }

    func firstWeekday(in locale: Locale) -> Int {
        firstWeekdayOverride ?? Calendar.firstWeekday(for: locale)
    }

    private enum CodingKeys: String, CodingKey {
        case firstWeekdayOverride, showWeekends, showHolidayMarkers, showMonthSummary
        case dayCellDetail, preferredScope
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CalendarPreferences()
        self.init(
            firstWeekdayOverride: container.lenientOptional(.firstWeekdayOverride, Int.self),
            showWeekends: container.lenient(.showWeekends, defaults.showWeekends),
            showHolidayMarkers: container.lenient(.showHolidayMarkers, defaults.showHolidayMarkers),
            showMonthSummary: container.lenient(.showMonthSummary, defaults.showMonthSummary),
            dayCellDetail: container.lenient(.dayCellDetail, defaults.dayCellDetail),
            preferredScope: container.lenient(.preferredScope, defaults.preferredScope)
        )
    }
}

/// The secondary line inside a day cell. Kept to one short value — a calendar
/// that tries to show everything is unreadable at a glance.
enum DayCellDetail: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case hidden
    case workedHours
    case balance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hidden: return "Nothing"
        case .workedHours: return "Worked hours"
        case .balance: return "Balance"
        }
    }
}

enum CalendarScope: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case month
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: return "Month"
        case .week: return "Week"
        }
    }
}

extension Calendar {
    /// `Calendar(identifier:)` does not adopt the locale's first weekday on its
    /// own; this reads it from a locale-configured calendar.
    static func firstWeekday(for locale: Locale) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.firstWeekday
    }
}
