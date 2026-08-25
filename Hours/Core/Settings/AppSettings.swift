import Foundation

/// The complete, user-owned configuration of the app.
///
/// Held as a single value type because every calculation takes it as an input:
/// passing one immutable struct into a pure function is what makes the
/// engine trivially testable, and what guarantees the calendar, the statistics
/// and an export can never disagree about the rules.
///
/// Persisted as JSON in `UserDefaults` (see `SettingsStore`) rather than in
/// SwiftData: preferences are a singleton read on nearly every view update,
/// not a queryable entity.
struct AppSettings: Hashable, Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var features: FeatureToggles
    var schedule: WorkSchedule
    var calendar: CalendarPreferences
    var export: ExportPreferences
    var appearance: AppearancePreference
    var durationPolicy: DurationPolicy
    var rounding: RoundingRule
    /// How durations are written on screen. Independent of the export setting:
    /// people often want `8h 30m` to read and `8.50` to hand to payroll.
    var displayDurationStyle: DurationStyle

    /// User-defined day types, merged with the built-ins at read time.
    var customDayTypes: [DayTypeDefinition]

    /// Places you work. Empty means the single-job case, where the primary job
    /// is synthesised from `schedule`; see `resolvedJobs`.
    var jobs: [Job]

    /// Balance carried in from before the app was used, so someone starting
    /// mid-year does not begin at zero.
    var openingBalanceMinutes: Int
    /// Days before this date are excluded from the running balance.
    var balanceStartDate: CalendarDate?

    init(
        schemaVersion: Int = AppSettings.currentSchemaVersion,
        features: FeatureToggles = FeatureToggles(),
        schedule: WorkSchedule = WorkSchedule(),
        calendar: CalendarPreferences = CalendarPreferences(),
        export: ExportPreferences = ExportPreferences(),
        appearance: AppearancePreference = .system,
        durationPolicy: DurationPolicy = .wallClock,
        rounding: RoundingRule = .exact,
        displayDurationStyle: DurationStyle = .hoursAndMinutes,
        customDayTypes: [DayTypeDefinition] = [],
        jobs: [Job] = [],
        openingBalanceMinutes: Int = 0,
        balanceStartDate: CalendarDate? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.features = features
        self.schedule = schedule
        self.calendar = calendar
        self.export = export
        self.appearance = appearance
        self.durationPolicy = durationPolicy
        self.rounding = rounding
        self.displayDurationStyle = displayDurationStyle
        self.customDayTypes = customDayTypes
        self.jobs = jobs
        self.openingBalanceMinutes = openingBalanceMinutes
        self.balanceStartDate = balanceStartDate
    }

    var dayTypeCatalog: DayTypeCatalog { DayTypeCatalog(custom: customDayTypes) }

    /// The formatter every on-screen duration goes through.
    var displayFormatting: DurationFormatting {
        DurationFormatting(style: displayDurationStyle)
    }

    /// Export columns filtered by the enabled features, preserving the user's
    /// chosen order.
    var effectiveExportColumns: [ReportColumn] {
        let allowed = Set(features.availableColumns())
        let selected = export.columns.filter { allowed.contains($0) }
        return selected.isEmpty ? ReportColumn.defaultSelection.filter { allowed.contains($0) } : selected
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, features, schedule, calendar, export, appearance
        case durationPolicy, rounding, displayDurationStyle
        case customDayTypes, jobs, openingBalanceMinutes, balanceStartDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        self.init(
            schemaVersion: container.lenient(.schemaVersion, AppSettings.currentSchemaVersion),
            features: container.lenient(.features, defaults.features),
            schedule: container.lenient(.schedule, defaults.schedule),
            calendar: container.lenient(.calendar, defaults.calendar),
            export: container.lenient(.export, defaults.export),
            appearance: container.lenient(.appearance, defaults.appearance),
            durationPolicy: container.lenient(.durationPolicy, defaults.durationPolicy),
            rounding: container.lenient(.rounding, defaults.rounding),
            displayDurationStyle: container.lenient(.displayDurationStyle, defaults.displayDurationStyle),
            customDayTypes: container.lenient(.customDayTypes, defaults.customDayTypes),
            jobs: container.lenient(.jobs, defaults.jobs),
            openingBalanceMinutes: container.lenient(.openingBalanceMinutes, defaults.openingBalanceMinutes),
            balanceStartDate: container.lenientOptional(.balanceStartDate, CalendarDate.self)
        )
    }
}
