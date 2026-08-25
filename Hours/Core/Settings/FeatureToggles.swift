import Foundation

/// Which parts of the app exist for this user.
///
/// Every toggle here removes UI as well as data entry — a disabled feature is
/// not greyed out, it is absent. Calculations respect them too, so switching
/// off "expected hours" genuinely stops the app computing a balance rather than
/// just hiding it.
struct FeatureToggles: Hashable, Codable, Sendable {
    var trackBreaks: Bool
    var multipleBreaksPerDay: Bool
    var trackExpectedHours: Bool
    var trackOvertime: Bool
    var trackHolidays: Bool
    var trackNotes: Bool
    var trackLocation: Bool
    var trackTags: Bool
    var allowManualAdjustments: Bool
    var allowPerDayExpectedOverride: Bool

    var autoCalculateWorkedHours: Bool
    var autoCalculateOvertime: Bool

    init(
        trackBreaks: Bool = true,
        multipleBreaksPerDay: Bool = false,
        trackExpectedHours: Bool = true,
        trackOvertime: Bool = true,
        trackHolidays: Bool = true,
        trackNotes: Bool = true,
        trackLocation: Bool = false,
        trackTags: Bool = false,
        allowManualAdjustments: Bool = true,
        allowPerDayExpectedOverride: Bool = true,
        autoCalculateWorkedHours: Bool = true,
        autoCalculateOvertime: Bool = true
    ) {
        self.trackBreaks = trackBreaks
        self.multipleBreaksPerDay = multipleBreaksPerDay
        self.trackExpectedHours = trackExpectedHours
        self.trackOvertime = trackOvertime
        self.trackHolidays = trackHolidays
        self.trackNotes = trackNotes
        self.trackLocation = trackLocation
        self.trackTags = trackTags
        self.allowManualAdjustments = allowManualAdjustments
        self.allowPerDayExpectedOverride = allowPerDayExpectedOverride
        self.autoCalculateWorkedHours = autoCalculateWorkedHours
        self.autoCalculateOvertime = autoCalculateOvertime
    }

    /// Overtime only means something if there is an expectation to exceed.
    var showsBalance: Bool { trackExpectedHours && trackOvertime }

    /// Columns that make sense given these toggles, in report order.
    func availableColumns() -> [ReportColumn] {
        ReportColumn.allCases.filter { column in
            switch column {
            case .breakTime: return trackBreaks
            case .expected, .credited: return trackExpectedHours
            case .overtime, .balance, .cumulativeBalance: return showsBalance
            case .holiday: return trackHolidays
            case .location: return trackLocation
            case .tags: return trackTags
            case .note: return trackNotes
            default: return true
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case trackBreaks, multipleBreaksPerDay, trackExpectedHours, trackOvertime
        case trackHolidays, trackNotes, trackLocation, trackTags
        case allowManualAdjustments, allowPerDayExpectedOverride
        case autoCalculateWorkedHours, autoCalculateOvertime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = FeatureToggles()
        self.init(
            trackBreaks: container.lenient(.trackBreaks, defaults.trackBreaks),
            multipleBreaksPerDay: container.lenient(.multipleBreaksPerDay, defaults.multipleBreaksPerDay),
            trackExpectedHours: container.lenient(.trackExpectedHours, defaults.trackExpectedHours),
            trackOvertime: container.lenient(.trackOvertime, defaults.trackOvertime),
            trackHolidays: container.lenient(.trackHolidays, defaults.trackHolidays),
            trackNotes: container.lenient(.trackNotes, defaults.trackNotes),
            trackLocation: container.lenient(.trackLocation, defaults.trackLocation),
            trackTags: container.lenient(.trackTags, defaults.trackTags),
            allowManualAdjustments: container.lenient(.allowManualAdjustments, defaults.allowManualAdjustments),
            allowPerDayExpectedOverride: container.lenient(.allowPerDayExpectedOverride, defaults.allowPerDayExpectedOverride),
            autoCalculateWorkedHours: container.lenient(.autoCalculateWorkedHours, defaults.autoCalculateWorkedHours),
            autoCalculateOvertime: container.lenient(.autoCalculateOvertime, defaults.autoCalculateOvertime)
        )
    }
}
