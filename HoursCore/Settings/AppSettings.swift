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

    /// Nudges about days with nothing recorded.
    var reminders: ReminderPreferences

    /// Balance carried in from before the app was used, so someone starting
    /// mid-year does not begin at zero.
    var openingBalanceMinutes: Int
    /// Days before this date are excluded from the running balance.
    var balanceStartDate: CalendarDate?

    /// How the balance is carried across a year boundary. Off by default: an
    /// app that silently starts zeroing balances every December is worse than
    /// one that never had the feature.
    var carryOver: CarryOverPolicy
    /// Years that have been closed off, and what each handed to the next.
    ///
    /// Recorded rather than recomputed, because the point of closing a year is
    /// that the figure stops moving. Editing a Tuesday in March two years
    /// later must not quietly change what was carried into January.
    var yearCloses: [YearClose]

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
        reminders: ReminderPreferences = ReminderPreferences(),
        openingBalanceMinutes: Int = 0,
        balanceStartDate: CalendarDate? = nil,
        carryOver: CarryOverPolicy = CarryOverPolicy(),
        yearCloses: [YearClose] = []
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
        self.reminders = reminders
        self.openingBalanceMinutes = openingBalanceMinutes
        self.balanceStartDate = balanceStartDate
        self.carryOver = carryOver
        self.yearCloses = yearCloses
    }

    var dayTypeCatalog: DayTypeCatalog { DayTypeCatalog(custom: customDayTypes) }

    /// The formatter every on-screen duration goes through.
    var displayFormatting: DurationFormatting {
        DurationFormatting(style: displayDurationStyle)
    }

    /// The columns this configuration could show, whether or not they are
    /// currently selected.
    var allowedExportColumns: Set<ReportColumn> {
        var allowed = Set(features.availableColumns())
        if !tracksMultipleJobs { allowed.remove(.job) }
        return allowed
    }

    /// Export columns filtered by the enabled features, preserving the user's
    /// chosen order.
    var effectiveExportColumns: [ReportColumn] {
        let allowed = allowedExportColumns
        let selected = export.columns.filter { allowed.contains($0) }
        return selected.isEmpty ? ReportColumn.defaultSelection.filter { allowed.contains($0) } : selected
    }

    /// Puts a newly switched-on field into the export as well as into the app.
    ///
    /// The export shows the intersection of the columns you have chosen and
    /// the fields you have switched on, and the chosen list was written before
    /// you switched anything on — so turning on Tags added the field to the
    /// day editor, added it to the backup, and left it out of every timesheet
    /// you produced afterwards. Nothing said so. The same went for Location,
    /// and for the Job column the moment a second job existed.
    ///
    /// A field that has just become available is added at its natural place in
    /// the column order. One switched off and on again does not come back if
    /// it was removed from the columns in between — that removal is a decision
    /// and outranks this.
    mutating func adoptColumnsMadeAvailable(since previous: AppSettings) {
        let appeared = allowedExportColumns.subtracting(previous.allowedExportColumns)
        guard !appeared.isEmpty else { return }

        func rank(_ column: ReportColumn) -> Int {
            ReportColumn.allCases.firstIndex(of: column) ?? ReportColumn.allCases.count
        }
        var columns = export.columns
        for column in appeared.sorted(by: { rank($0) < rank($1) }) where !columns.contains(column) {
            let position = columns.firstIndex { rank($0) > rank(column) } ?? columns.count
            columns.insert(column, at: position)
        }
        export.columns = columns
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, features, schedule, calendar, export, appearance
        case durationPolicy, rounding, displayDurationStyle
        case customDayTypes, jobs, reminders, openingBalanceMinutes, balanceStartDate
        case carryOver, yearCloses
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
            reminders: container.lenient(.reminders, defaults.reminders),
            openingBalanceMinutes: container.lenient(.openingBalanceMinutes, defaults.openingBalanceMinutes),
            balanceStartDate: container.lenientOptional(.balanceStartDate, CalendarDate.self),
            // Both absent from anything written before carry-over existed, so
            // the lenient decode is what makes an old settings file open
            // rather than fail.
            carryOver: container.lenient(.carryOver, defaults.carryOver),
            yearCloses: container.lenient(.yearCloses, defaults.yearCloses)
        )
    }
}
