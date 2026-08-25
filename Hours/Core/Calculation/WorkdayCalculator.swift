import Foundation

/// Turns one day's raw input into a resolved, arithmetic-complete result.
///
/// Pure and deterministic: no clock, no storage, no UI. Every rule the app
/// applies to a day lives here exactly once, which is why the calendar, the
/// statistics and the exports cannot disagree.
struct WorkdayCalculator: Sendable {
    let settings: AppSettings
    let calendar: Calendar
    private let catalog: DayTypeCatalog

    init(settings: AppSettings, calendar: Calendar) {
        self.settings = settings
        self.calendar = calendar
        self.catalog = settings.dayTypeCatalog
    }

    // MARK: - Entry point

    func compute(record: DayRecord?, on date: CalendarDate, holiday: HolidayRule? = nil) -> DayComputation {
        let features = settings.features
        let effectiveHoliday = features.trackHolidays ? holiday : nil
        let typeID = resolveDayTypeID(record: record, date: date, holiday: effectiveHoliday)
        let definition = catalog.definition(for: typeID)

        var warnings: [DayWarning] = []

        let expected = expectedMinutes(record: record, date: date, definition: definition)
        let shift = shiftMinutes(record: record, on: date, definition: definition, warnings: &warnings)

        // A manual figure always wins: it is either the only source (automatic
        // calculation switched off) or a deliberate override for this one day.
        let rawWorked = record?.manualWorkedMinutes ?? shift.workedMinutes
        let worked = max(0, settings.rounding.apply(to: rawWorked))

        let credited = definition.expectation == .creditedAbsence ? expected : 0
        let adjustment = features.allowManualAdjustments ? (record?.adjustmentMinutes ?? 0) : 0
        let balance = balanceMinutes(
            paid: worked + credited,
            expected: expected,
            adjustment: adjustment,
            record: record
        )

        let isIncluded = record?.isIncluded ?? true
        if !isIncluded { warnings.append(.excludedFromTotals) }

        return DayComputation(
            date: date,
            dayType: definition,
            holidayName: effectiveHoliday?.name,
            start: record?.start,
            end: record?.end,
            breakMinutes: shift.breakMinutes,
            workedMinutes: worked,
            creditedMinutes: credited,
            expectedMinutes: expected,
            adjustmentMinutes: adjustment,
            balanceMinutes: balance,
            hasEntry: record.map { !$0.isBlank } ?? false,
            isIncluded: isIncluded,
            crossesMidnight: shift.crossesMidnight,
            note: features.trackNotes ? (record?.note ?? "") : "",
            location: features.trackLocation ? (record?.location ?? "") : "",
            tags: features.trackTags ? (record?.tags ?? []) : [],
            warnings: warnings
        )
    }

    // MARK: - Day type

    /// Precedence: an explicit choice, then a holiday rule, then the weekly
    /// schedule, then an ordinary working day.
    func resolveDayTypeID(record: DayRecord?, date: CalendarDate, holiday: HolidayRule?) -> DayTypeID {
        if let explicit = record?.dayTypeID { return explicit }
        let weekday = date.weekday(in: calendar)
        let contracted = settings.schedule.contractedMinutes(forWeekday: weekday)
        if let holiday {
            // A "working holiday" is still an ordinary day for the arithmetic;
            // only its name is carried through to the calendar and reports.
            if holiday.countsAsWorkingDay {
                return contracted > 0 ? .work : .weekend
            }
            return .holiday
        }
        return contracted > 0 ? .work : .weekend
    }

    // MARK: - Expected hours

    func expectedMinutes(record: DayRecord?, date: CalendarDate, definition: DayTypeDefinition) -> Int {
        guard settings.features.trackExpectedHours else { return 0 }
        if settings.features.allowPerDayExpectedOverride, let override = record?.expectedOverrideMinutes {
            return max(0, override)
        }
        switch definition.expectation {
        case .zero:
            return 0
        case .scheduled, .creditedAbsence:
            return settings.schedule.contractedMinutes(forWeekday: date.weekday(in: calendar))
        }
    }

    // MARK: - Shift arithmetic

    struct ShiftResult: Hashable, Sendable {
        var workedMinutes: Int
        var breakMinutes: Int
        var grossMinutes: Int
        var crossesMidnight: Bool
    }

    /// Gross shift length minus breaks, never negative.
    func shiftMinutes(
        record: DayRecord?,
        on date: CalendarDate,
        definition: DayTypeDefinition,
        warnings: inout [DayWarning]
    ) -> ShiftResult {
        guard let record else {
            return ShiftResult(workedMinutes: 0, breakMinutes: 0, grossMinutes: 0, crossesMidnight: false)
        }

        guard let start = record.start, let end = record.end else {
            // Only nag when times were expected: a vacation day with no times is
            // complete, a work day with a start but no end is not.
            let expectsTimes = definition.showsTimesByDefault || record.start != nil || record.end != nil
            if expectsTimes && record.hasEntryWorthValidating {
                if record.start == nil { warnings.append(.missingStartTime) }
                if record.end == nil { warnings.append(.missingEndTime) }
            }
            return ShiftResult(workedMinutes: 0, breakMinutes: 0, grossMinutes: 0, crossesMidnight: false)
        }

        let crossesMidnight = end.minutes < start.minutes
        let gross = grossMinutes(start: start, end: end, on: date, record: record, warnings: &warnings)
        if gross == 0 && start.minutes == end.minutes {
            warnings.append(.zeroLengthShift)
        }

        let breakTotal = settings.features.trackBreaks
            ? breakMinutes(record: record, start: start, grossMinutes: gross, warnings: &warnings)
            : 0

        if breakTotal > gross && gross > 0 {
            warnings.append(.breakLongerThanShift)
        }

        return ShiftResult(
            workedMinutes: max(0, gross - breakTotal),
            breakMinutes: breakTotal,
            grossMinutes: gross,
            crossesMidnight: crossesMidnight
        )
    }

    /// Length of the shift before breaks.
    ///
    /// An end at or before the start is read as an overnight shift, except when
    /// the two are identical — "08:00 to 08:00" is far more likely to be a
    /// half-finished entry than a 24-hour day, so it counts as zero and warns.
    private func grossMinutes(
        start: TimeOfDay,
        end: TimeOfDay,
        on date: CalendarDate,
        record: DayRecord,
        warnings: inout [DayWarning]
    ) -> Int {
        if start.minutes == end.minutes { return 0 }

        let wallClock = end.minutes > start.minutes
            ? end.minutes - start.minutes
            : end.minutes + TimeOfDay.minutesPerDay - start.minutes

        guard settings.durationPolicy == .elapsedReal else { return wallClock }

        var shiftCalendar = calendar
        if let identifier = record.timeZoneIdentifier, let zone = TimeZone(identifier: identifier) {
            shiftCalendar.timeZone = zone
        }

        let endDate = end.minutes > start.minutes ? date : date.adding(days: 1, in: shiftCalendar)
        guard
            let startInstant = start.date(on: date, in: shiftCalendar),
            let endInstant = end.date(on: endDate, in: shiftCalendar)
        else {
            // One of the wall-clock times was skipped by a clock change. Fall
            // back to the wall-clock length rather than inventing a duration.
            warnings.append(.timeSkippedByClockChange)
            return wallClock
        }

        let elapsed = Int((endInstant.timeIntervalSince(startInstant) / 60.0).rounded())
        return max(0, elapsed)
    }

    /// Total break time, with timed breaks normalised into shift-relative
    /// minutes, clipped to the shift, and merged so overlaps are not deducted
    /// twice.
    func breakMinutes(
        record: DayRecord,
        start: TimeOfDay,
        grossMinutes: Int,
        warnings: inout [DayWarning]
    ) -> Int {
        var intervals: [(Int, Int)] = []
        var explicitTotal = 0
        var sawOutsideShift = false

        for span in record.breaks {
            if let breakStart = span.start, let breakEnd = span.end {
                var relativeStart = breakStart.minutes - start.minutes
                if relativeStart < 0 { relativeStart += TimeOfDay.minutesPerDay }
                var relativeEnd = breakEnd.minutes - start.minutes
                if relativeEnd < 0 { relativeEnd += TimeOfDay.minutesPerDay }
                if relativeEnd < relativeStart { relativeEnd += TimeOfDay.minutesPerDay }

                let clippedStart = min(max(relativeStart, 0), grossMinutes)
                let clippedEnd = min(max(relativeEnd, 0), grossMinutes)
                if clippedEnd <= clippedStart {
                    if relativeEnd > relativeStart { sawOutsideShift = true }
                    continue
                }
                intervals.append((clippedStart, clippedEnd))
            } else if let minutes = span.explicitMinutes {
                explicitTotal += max(0, minutes)
            }
        }

        if sawOutsideShift { warnings.append(.breakOutsideShift) }

        let merged = WorkdayCalculator.merge(intervals)
        if merged.count < intervals.count { warnings.append(.overlappingBreaksMerged) }
        let timedTotal = merged.reduce(0) { $0 + ($1.1 - $1.0) }

        return max(0, timedTotal + explicitTotal)
    }

    /// Merges overlapping or touching intervals.
    static func merge(_ intervals: [(Int, Int)]) -> [(Int, Int)] {
        guard intervals.count > 1 else { return intervals }
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var result: [(Int, Int)] = [sorted[0]]
        for interval in sorted.dropFirst() {
            let last = result[result.count - 1]
            if interval.0 <= last.1 {
                result[result.count - 1] = (last.0, max(last.1, interval.1))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    // MARK: - Balance

    private func balanceMinutes(paid: Int, expected: Int, adjustment: Int, record: DayRecord?) -> Int {
        guard settings.features.showsBalance else { return 0 }
        if let manual = record?.manualBalanceMinutes { return manual }
        guard settings.features.autoCalculateOvertime else { return adjustment }
        return paid - expected + adjustment
    }
}

private extension DayRecord {
    /// A record is worth validating once the user has committed to the day in
    /// some way; a completely blank day should never show warnings.
    var hasEntryWorthValidating: Bool {
        start != nil || end != nil || !breaks.isEmpty || dayTypeID != nil
    }
}
