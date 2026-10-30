import Foundation

/// The day editor's three choices (1.2): Worked · Away · Day off.
///
/// A grouping of the day types the app already has, not a new field: the
/// day's type decides its kind and choosing a kind sets the type. Work and
/// any type that takes times and expects hours is worked; paid absence and
/// time off in lieu are away; a type that expects nothing and takes no
/// times (a day off, the weekend) is a day off.
enum DayKind: String, CaseIterable, Hashable, Sendable {
    case worked
    case away
    case dayOff

    static func of(_ definition: DayTypeDefinition) -> DayKind {
        if definition.id == .timeOffInLieu { return .away }
        switch definition.expectation {
        case .creditedAbsence:
            return .away
        case .zero:
            return definition.showsTimesByDefault ? .worked : .dayOff
        case .scheduled:
            return definition.showsTimesByDefault ? .worked : .away
        }
    }

    /// `record` with this kind chosen, the way the editor's segments do it.
    ///
    /// - `automatic`: the type the day resolves to with nothing chosen (the
    ///   schedule, or a public holiday). When it is already of this kind the
    ///   day is left automatic, so a holiday stays the holiday it is.
    /// - `prefilled`: your usual times, given to a day switched to worked
    ///   that has none of your own.
    /// - `contractedMinutes`: what the week in force expects of the day, to
    ///   tell a half day of leave from expected hours set for another reason.
    ///
    /// Away and day off drop your own times, as a bulk edit to leave does:
    /// keeping them would pay the day twice. Hours from a site stay; they
    /// belong to the site's day.
    func apply(
        to record: DayRecord,
        automatic: DayTypeDefinition,
        catalog: DayTypeCatalog,
        prefilled: Shift,
        contractedMinutes: Int = 0
    ) -> DayRecord {
        var record = record
        let current = record.dayTypeID.map { catalog.definition(for: $0) } ?? automatic

        if HalfDay.isHalf(expectedOverride: record.expectedOverrideMinutes, contracted: contractedMinutes),
           DayKind.of(current) != self {
            record.expectedOverrideMinutes = nil
        }

        if DayKind.of(automatic) == self {
            record.dayTypeID = nil
        } else if DayKind.of(current) != self {
            record.dayTypeID = defaultType(in: catalog)
        }

        switch self {
        case .worked:
            if !record.shifts.contains(where: { $0.siteID == nil }) && record.manualWorkedMinutes == nil {
                record.shifts.append(prefilled)
            }
        case .away, .dayOff:
            record.shifts = record.shifts.filter { $0.siteID != nil }
            record.manualWorkedMinutes = nil
        }
        return record
    }

    /// The type a day gets when switched to this kind by hand.
    private func defaultType(in catalog: DayTypeCatalog) -> DayTypeID {
        switch self {
        case .worked: return .work
        case .away: return .vacation
        case .dayOff: return .dayOff
        }
    }
}

extension DayTypeCatalog {
    /// The types of one kind, in the catalogue's order: the Away grid.
    func types(of kind: DayKind) -> [DayTypeDefinition] {
        all.filter { DayKind.of($0) == kind }
    }
}

/// Half a day away (1.2). The app has no half-day type: a day of leave
/// whose expected hours are set to half of what the week contracts is half
/// a day, which is how `LeaveCalculator` already counts it.
enum HalfDay {
    /// Half the contracted hours, rounded down to the minute.
    static func minutes(contracted: Int) -> Int {
        max(0, contracted) / 2
    }

    /// Whether expected hours set by hand are half a day.
    static func isHalf(expectedOverride: Int?, contracted: Int) -> Bool {
        guard let expectedOverride, contracted > 0 else { return false }
        return expectedOverride == minutes(contracted: contracted) && expectedOverride > 0
    }
}

/// "I worked the usual day" (1.2): today written with the week's times in
/// one tap.
enum UsualDay {
    /// The record to save, or nil when there are already hours of your own
    /// on the day (by times or typed as a figure), which this must never
    /// overwrite. Whatever else the day holds — a site's hours, a note — is
    /// kept; the type is left as the day resolves, as "I worked" on a
    /// holiday does, so a public holiday stays paid.
    static func record(
        for date: CalendarDate,
        existing: DayRecord?,
        engine: PeriodEngine,
        holidays: [HolidayRule]
    ) -> DayRecord? {
        if let existing {
            guard !existing.shifts.contains(where: { $0.siteID == nil }), existing.manualWorkedMinutes == nil else {
                return nil
            }
            var record = existing
            record.shifts.append(engine.settings.prefilledShift(on: date))
            return record
        }
        var record = engine.draftRecord(for: date, holidays: holidays, working: true)
        if !record.shifts.contains(where: { $0.siteID == nil }) {
            record.shifts.append(engine.settings.prefilledShift(on: date))
        }
        return record
    }
}
