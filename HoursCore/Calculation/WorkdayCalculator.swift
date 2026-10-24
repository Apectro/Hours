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
    /// Each job's break rule, and the primary job's for shifts that name no
    /// job or a job that no longer exists. Resolved once here rather than
    /// through `settings.job(_:)` per shift, which sorts the job list every
    /// time it is asked.
    private let paidBreaksByJob: [UUID: Bool]
    private let primaryPaysBreaks: Bool
    /// The jobs that expect hours, resolved once for the same reason: every
    /// day asks them for the week in force on its date.
    private let activeJobs: [Job]

    init(settings: AppSettings, calendar: Calendar) {
        self.settings = settings
        self.calendar = calendar
        self.catalog = settings.dayTypeCatalog
        self.paidBreaksByJob = Dictionary(
            settings.resolvedJobs.map { ($0.id, $0.breaksArePaid) },
            uniquingKeysWith: { first, _ in first }
        )
        self.primaryPaysBreaks = settings.primaryJob.breaksArePaid
        self.activeJobs = settings.activeJobs
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

        // A typed-in figure is the source only while automatic calculation is
        // switched off. Every other stored override here is gated by the toggle
        // that produces it — the adjustment, the per-day expectation, the manual
        // balance — and this one was not.
        //
        // So a figure typed while the toggle was off went on outranking the
        // clock times forever once it was switched back on, and the day editor
        // in that state shows times and offers no way to see or clear it: the
        // screen said 08:00–16:30 and the total said something else. The value
        // is kept rather than deleted, so switching back restores what was
        // typed.
        let manualWorked = features.autoCalculateWorkedHours ? nil : record?.manualWorkedMinutes
        let rawWorked = manualWorked ?? shift.workedMinutes
        // Travel is added after rounding, as typed: the rule rounds a shift's
        // clock times, and travel has none. Only while the allowance and
        // travel are tracked, and only when travel is set to count as work;
        // otherwise it is recorded and shown, and adds nothing.
        let extras = allowanceExtras(of: record)
        let countedTravel = settings.allowance.travelCountsAsWork ? extras.travel : 0
        let worked = max(0, settings.rounding.apply(to: rawWorked)) + countedTravel

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

        // Site hours reach the calendar as shifts, but only the automatic,
        // included, non-credited path adds them up. In the other cases they
        // are on screen and silently absent from the total, which is worth
        // saying once rather than per shift.
        if record?.shifts.contains(where: { $0.siteID != nil }) == true
            && (!features.autoCalculateWorkedHours || definition.expectation == .creditedAbsence || !isIncluded) {
            warnings.append(.siteHoursNotCounted)
        }

        return DayComputation(
            date: date,
            dayType: definition,
            holidayName: effectiveHoliday?.name,
            start: shift.periods.first?.start,
            end: shift.periods.last?.end,
            breakMinutes: shift.breakMinutes,
            shifts: shift.periods,
            workedMinutes: worked,
            creditedMinutes: credited,
            expectedMinutes: expected,
            adjustmentMinutes: adjustment,
            adjustmentReason: record?.adjustmentReason ?? .correction,
            balanceMinutes: balance,
            hasEntry: record.map { !$0.isBlank } ?? false,
            isIncluded: isIncluded,
            crossesMidnight: shift.crossesMidnight,
            note: features.trackNotes ? (record?.note ?? "") : "",
            location: features.trackLocation ? (record?.location ?? "") : "",
            tags: features.trackTags ? (record?.tags ?? []) : [],
            warnings: warnings,
            hasFieldAllowance: extras.allowance,
            kilometres: extras.kilometres,
            travelMinutes: extras.travel,
            countedTravelMinutes: countedTravel
        )
    }

    // MARK: - Allowance and travel

    /// The day's field allowance, kilometres and travel, all nothing while
    /// they are not tracked. Your own allowance or a site's: either gives the
    /// day one, never two. Your own kilometres and every site's vehicle
    /// kilometres add up, since each is a separate drive.
    private func allowanceExtras(of record: DayRecord?) -> (allowance: Bool, kilometres: Int, travel: Int) {
        guard settings.allowance.isEnabled, let record else { return (false, 0, 0) }
        let siteShifts = record.shifts.filter { $0.siteID != nil }
        return (
            record.hasFieldAllowance || siteShifts.contains(where: \.fieldAllowance),
            record.kilometres + siteShifts.reduce(0) { $0 + $1.kilometres },
            record.travelMinutes
        )
    }

    // MARK: - Day type

    /// Precedence: an explicit choice, then a holiday rule, then the weekly
    /// schedule, then an ordinary working day.
    func resolveDayTypeID(record: DayRecord?, date: CalendarDate, holiday: HolidayRule?) -> DayTypeID {
        if let explicit = record?.dayTypeID { return explicit }
        // Summed across jobs: a day is a working day if any job expects hours.
        let contracted = contractedMinutes(on: date)
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
            // Summed across active jobs. With one job this is exactly the
            // contracted week it always was.
            //
            // A day type applies to the whole day rather than to one job, so a
            // day of leave credits every job's hours. That is the right answer
            // for someone taking a day off, and the wrong one for someone off
            // from one job and working another — who should record the day as
            // worked and set the leave with a per-day expected override.
            return contractedMinutes(on: date)
        }
    }

    /// What every active job expects of `date`, each from the week it had in
    /// force that day — `AppSettings.contractedMinutes(on:calendar:)`, with
    /// the jobs already resolved.
    private func contractedMinutes(on date: CalendarDate) -> Int {
        let weekday = date.weekday(in: calendar)
        return activeJobs.reduce(0) { $0 + $1.schedule(on: date).expectedMinutes(forWeekday: weekday) }
    }

    // MARK: - Shift arithmetic

    struct ShiftResult: Hashable, Sendable {
        var workedMinutes: Int
        var breakMinutes: Int
        var grossMinutes: Int
        var crossesMidnight: Bool
        /// One entry per shift that resolved to something, in the order entered.
        var periods: [ShiftPeriod] = []
    }

    /// The day's shifts, summed. Each is measured independently and then added,
    /// so a split shift is two real blocks of work rather than one long block
    /// with a hole punched in it.
    func shiftMinutes(
        record: DayRecord?,
        on date: CalendarDate,
        definition: DayTypeDefinition,
        warnings: inout [DayWarning]
    ) -> ShiftResult {
        guard let record, !record.shifts.isEmpty else {
            return ShiftResult(workedMinutes: 0, breakMinutes: 0, grossMinutes: 0, crossesMidnight: false)
        }

        var total = ShiftResult(workedMinutes: 0, breakMinutes: 0, grossMinutes: 0, crossesMidnight: false)

        for shift in record.shifts {
            guard let start = shift.start, let end = shift.end else {
                // Only nag when times were expected: a vacation day with no
                // times is complete, a work day with a start but no end is not.
                let expectsTimes = definition.showsTimesByDefault || shift.start != nil || shift.end != nil
                if expectsTimes && record.hasEntryWorthValidating {
                    if shift.start == nil && !warnings.contains(.missingStartTime) {
                        warnings.append(.missingStartTime)
                    }
                    if shift.end == nil && !warnings.contains(.missingEndTime) {
                        warnings.append(.missingEndTime)
                    }
                }
                continue
            }

            let crossesMidnight = end.minutes < start.minutes
            let gross = grossMinutes(start: start, end: end, on: date, record: record, warnings: &warnings)
            if gross == 0 && start.minutes == end.minutes && !warnings.contains(.zeroLengthShift) {
                warnings.append(.zeroLengthShift)
            }

            var timedBreaks: [Range<Int>] = []
            let breakTotal = settings.features.trackBreaks
                ? breakMinutes(shift: shift, start: start, grossMinutes: gross, timed: &timedBreaks, warnings: &warnings)
                : 0

            if breakTotal > gross && gross > 0 && !warnings.contains(.breakLongerThanShift) {
                warnings.append(.breakLongerThanShift)
            }

            // A paid break is worked time. It is still measured, kept and
            // reported as a break; it just is not taken off. Decided per shift,
            // because a split day can be one employer in the morning and
            // another in the evening.
            let worked = breaksArePaid(forJob: shift.jobID) ? gross : max(0, gross - breakTotal)
            total.workedMinutes += worked
            total.breakMinutes += breakTotal
            total.grossMinutes += gross
            total.crossesMidnight = total.crossesMidnight || crossesMidnight
            total.periods.append(
                ShiftPeriod(
                    id: shift.id,
                    start: start,
                    end: end,
                    workedMinutes: worked,
                    breakMinutes: breakTotal,
                    crossesMidnight: crossesMidnight,
                    jobID: shift.jobID,
                    timedBreaks: timedBreaks,
                    siteID: shift.siteID
                )
            )
        }

        // Chronological, not the order the blocks were typed in.
        //
        // The day's start and end are read off the first and last period, and
        // those are what the Start and End columns of an export contain. Left
        // in entry order, a split shift whose afternoon was entered before its
        // morning exported "13:00" as the start and "12:00" as the end — a
        // reversed range, on a timesheet, going to a payroll department.
        // Adding a block appends it, so entering two out of order takes no
        // effort at all.
        //
        // Only when nothing crosses midnight. A day running past it has no
        // unambiguous wall-clock order — 00:30 sorts before 22:00 and is later
        // in real time — so entry order is left alone there rather than
        // replaced by an ordering that is confidently wrong.
        if !total.crossesMidnight {
            total.periods.sort { ($0.start?.minutes ?? 0) < ($1.start?.minutes ?? 0) }
        }

        return total
    }

    /// Whether a shift's job pays for its breaks. Resolves the way
    /// `AppSettings.job(_:)` does: no job, or a job since deleted, is the
    /// primary one. An archived job keeps its rule, so its history keeps
    /// adding up to what it did.
    func breaksArePaid(forJob id: UUID?) -> Bool {
        id.flatMap { paidBreaksByJob[$0] } ?? primaryPaysBreaks
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
    /// twice. The timed ones also come back in `timed`, where they fell.
    func breakMinutes(
        shift: Shift,
        start: TimeOfDay,
        grossMinutes: Int,
        timed: inout [Range<Int>],
        warnings: inout [DayWarning]
    ) -> Int {
        var intervals: [(Int, Int)] = []
        var explicitTotal = 0
        var sawOutsideShift = false

        for span in shift.breaks {
            if let breakStart = span.start, span.end != nil {
                let length = span.minutes
                // A wall-clock break has no day of its own, so it can sit at
                // either of two places relative to the shift: so many minutes
                // after its start, or — when it began before the shift did —
                // a day less than that. Only reading the first made a lunch
                // of 11:30–12:30 on a shift from 12:00 land twenty-three hours
                // into the shift and deduct nothing, while the same overlap at
                // the other end of a shift was clipped and deducted. Whichever
                // placement overlaps the shift more is the one that was meant.
                let forward = (breakStart.minutes - start.minutes + TimeOfDay.minutesPerDay) % TimeOfDay.minutesPerDay
                let placements = [forward, forward - TimeOfDay.minutesPerDay].map { relativeStart in
                    (min(max(relativeStart, 0), grossMinutes), min(max(relativeStart + length, 0), grossMinutes))
                }
                let (clippedStart, clippedEnd) = placements.max { ($0.1 - $0.0) < ($1.1 - $1.0) } ?? placements[0]
                if clippedEnd <= clippedStart {
                    if length > 0 { sawOutsideShift = true }
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
        // The earnings need to know which minutes of a night were a break.
        timed = merged.map { $0.0..<$0.1 }

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
        shifts.contains { !$0.isEmpty } || dayTypeID != nil
    }
}
