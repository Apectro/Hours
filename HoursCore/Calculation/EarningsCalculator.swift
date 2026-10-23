import Foundation

/// What a day, or a span of days, earned, in cents, by where it came from.
///
/// The parts always add up to the total exactly, because each is the
/// difference between two rounded running totals rather than rounded on its
/// own; see `EarningsCalculator`.
struct EarningsBreakdown: Hashable, Sendable {
    /// Hours worked, at the rate.
    var baseCents = 0
    /// What overtime adds on top of the rate.
    var overtimeCents = 0
    var saturdayCents = 0
    var sundayAndHolidayCents = 0
    var nightCents = 0
    /// Credited hours of paid absence, at the rate.
    var paidAbsenceCents = 0

    var totalCents: Int {
        baseCents + overtimeCents + saturdayCents + sundayAndHolidayCents + nightCents + paidAbsenceCents
    }

    /// Everything on top of the rate.
    var surchargeCents: Int {
        overtimeCents + saturdayCents + sundayAndHolidayCents + nightCents
    }

    static let zero = EarningsBreakdown()

    static func + (lhs: EarningsBreakdown, rhs: EarningsBreakdown) -> EarningsBreakdown {
        EarningsBreakdown(
            baseCents: lhs.baseCents + rhs.baseCents,
            overtimeCents: lhs.overtimeCents + rhs.overtimeCents,
            saturdayCents: lhs.saturdayCents + rhs.saturdayCents,
            sundayAndHolidayCents: lhs.sundayAndHolidayCents + rhs.sundayAndHolidayCents,
            nightCents: lhs.nightCents + rhs.nightCents,
            paidAbsenceCents: lhs.paidAbsenceCents + rhs.paidAbsenceCents
        )
    }

    static func += (lhs: inout EarningsBreakdown, rhs: EarningsBreakdown) {
        lhs = lhs + rhs
    }
}

/// One day's earnings, and the minutes each surcharge was paid on.
struct DayEarnings: Identifiable, Hashable, Sendable {
    var date: CalendarDate
    var breakdown: EarningsBreakdown
    var overtimeMinutes: Int = 0
    var saturdayMinutes: Int = 0
    var sundayAndHolidayMinutes: Int = 0
    var nightMinutes: Int = 0
    /// The percentage the day's credited hours were paid at, when its type
    /// pays less than all of them (sick leave at 70%); nil when in full or
    /// when nothing was credited.
    var absencePaidPercent: Int?
    /// A day past the employer's first 42 days of a sick-leave run: the
    /// health insurer pays it (HZZO in Croatia), so it earns nothing here.
    var isPaidByHealthInsurance = false

    var id: Int { date.key }
    var totalCents: Int { breakdown.totalCents }

    static func nothing(on date: CalendarDate) -> DayEarnings {
        DayEarnings(date: date, breakdown: .zero)
    }
}

/// Works out what days earned, from days the engine has already resolved.
///
/// Nothing here measures a shift again. Worked minutes are the day's own —
/// paid breaks, rounding and each shift's job already applied — and this only
/// decides where in the day those minutes fell and what each one pays.
///
/// **Surcharges add up.** An hour on a Sunday night that is also overtime is
/// paid the rate plus the Sunday, night and overtime percentages, each on the
/// rate. So each part is simply its minutes times the rate times its
/// percentage, and which minutes are overtime only matters for which day they
/// belong to.
///
/// **Rounding happens once a day.** Every part is worked out exactly, in
/// hundredths of a cent-minute, and the day is rounded to the cent — half a
/// cent up — at the end. The parts are rounded through a running total, as
/// `WorkSchedule.expectedMinutes(forWeekday:)` spreads a weekly target, so
/// they add up to the day's total exactly; a period is a sum of days and so
/// adds up to the cent as well.
struct EarningsCalculator: Sendable {
    let settings: AppSettings
    let calendar: Calendar
    private let holidays: HolidayResolver
    private let jobsByID: [UUID: Job]
    private let primary: Job
    /// The jobs whose weeks make up a day's expected hours, as in
    /// `WorkdayCalculator`.
    private let activeJobs: [Job]

    init(settings: AppSettings, calendar: Calendar, holidays: HolidayResolver) {
        self.settings = settings
        self.calendar = calendar
        self.holidays = holidays
        self.jobsByID = Dictionary(
            settings.resolvedJobs.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.primary = settings.primaryJob
        self.activeJobs = settings.activeJobs
    }

    /// One entry per day, in the order given.
    ///
    /// `days` must be in date order and should be whole weeks: overtime after
    /// the contracted week is counted from the week's first day, so a week
    /// handed over from its middle would find less overtime than there was.
    /// `PeriodEngine.earnings(in:records:holidays:countingThrough:)` widens
    /// its range to whole weeks for exactly this.
    func earnings(for days: [DayComputation]) -> [DayEarnings] {
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        var week = WeekTally(start: nil)
        let positions = Self.runPositions(of: days, in: calendar)
        return zip(days, positions).map { day, position in
            let start = CalendarDateRange.week(containing: day.date, in: calendar).start
            if week.start != start { week = WeekTally(start: start) }
            return earnings(for: day, week: &week, byDate: byDate, runPosition: position)
        }
    }

    /// For each day whose type pays only the first 42 days of a run, which
    /// calendar day of its run it is (1 for the first); nil for every other
    /// day.
    ///
    /// A run is consecutive dates of the same such type. Sick leave counts
    /// calendar days, so a weekend or a public holiday left as it is — no
    /// type chosen over it, nothing worked — does not end a run that carries
    /// on after it, and counts in it; any other day does. A run reaching back
    /// before the first day given is counted from that first day, so the
    /// days handed over must start early enough to see it
    /// (`PeriodEngine.earningsRange(covering:)` reaches back for this).
    static func runPositions(of days: [DayComputation], in calendar: Calendar) -> [Int?] {
        var runStart: CalendarDate?
        var runType: DayTypeID?
        var previous: CalendarDate?
        return days.map { day in
            defer { previous = day.date }
            if let previous, previous.adding(days: 1, in: calendar) != day.date {
                runStart = nil
            }
            if day.dayType.employerPaysFirst42Days {
                if runStart == nil || runType != day.dayType.id {
                    runStart = day.date
                    runType = day.dayType.id
                }
                return (runStart?.days(until: day.date, in: calendar) ?? 0) + 1
            }
            let bridges = (day.dayType.id == .weekend || day.dayType.id == .holiday) && day.workedMinutes == 0
            if !bridges { runStart = nil }
            return nil
        }
    }

    /// Each job's minutes so far in one week, and its contracted week.
    private struct WeekTally {
        var start: CalendarDate?
        var counted: [UUID: Int] = [:]
        var contracted: [UUID: Int] = [:]
    }

    // MARK: - One day

    /// Hundredths of a cent-minute: minutes × cents an hour × percent. A
    /// minute at the rate is `rate × 100`, and 6,000 of these are a cent.
    private struct Exact {
        var base = 0
        var overtime = 0
        var saturday = 0
        var sundayAndHoliday = 0
        var night = 0
        var paidAbsence = 0

        /// Rounded through a running total, so the parts add up to the
        /// rounded whole.
        var rounded: EarningsBreakdown {
            var running = 0
            var previous = 0
            func cents(_ part: Int) -> Int {
                running += part
                let whole = (running + 3_000) / 6_000
                defer { previous = whole }
                return whole - previous
            }
            return EarningsBreakdown(
                baseCents: cents(base),
                overtimeCents: cents(overtime),
                saturdayCents: cents(saturday),
                sundayAndHolidayCents: cents(sundayAndHoliday),
                nightCents: cents(night),
                paidAbsenceCents: cents(paidAbsence)
            )
        }
    }

    private func earnings(
        for day: DayComputation,
        week: inout WeekTally,
        byDate: [CalendarDate: DayComputation],
        runPosition: Int?
    ) -> DayEarnings {
        // Excluded days and days before the balance starts count for nothing
        // anywhere else, so they earn nothing and add nothing to the week.
        guard day.isIncluded, !day.precedesBalanceStart else { return .nothing(on: day.date) }

        // Paid absence earns its type's percentage of the credited hours —
        // nothing at all past the employer's days of a run. Surcharges never
        // applied to credited hours, so nothing else changes.
        let pastEmployerDays = runPosition.map { $0 > DayTypeDefinition.employerPaidDays } ?? false
        let absencePercent = pastEmployerDays ? 0 : day.dayType.paidPercent

        let pieces = workedPieces(of: day)
        let credited = creditedShares(of: day)
        var jobIDs = Set(pieces.map(\.jobID))
        jobIDs.formUnion(credited.keys)

        var exact = Exact()
        var result = DayEarnings.nothing(on: day.date)

        for id in jobIDs {
            let job = jobsByID[id] ?? primary
            let jobPieces = pieces.filter { $0.jobID == id }
            let worked = jobPieces.reduce(0) { $0 + $1.minutes }
            let creditedMinutes = credited[id] ?? 0

            // The week is counted whether or not the job pays, so a rate set
            // on a Wednesday still finds Monday's and Tuesday's hours there.
            let before = week.counted[id] ?? 0
            let afterCredited = before + creditedMinutes
            let after = afterCredited + worked
            week.counted[id] = after

            guard let rules = job.pay?.value(on: day.date) else { continue }
            let rate = rules.hourlyRateCents

            exact.base += worked * rate * 100
            if rules.paidAbsenceEarns { exact.paidAbsence += creditedMinutes * rate * absencePercent }

            // Credited hours fill the normal day or week first, as they do in
            // the balance, but are never themselves overtime.
            let overtime: Int
            switch rules.overtimeMode {
            case .sameRate:
                overtime = 0
            case .afterDailyHours:
                let threshold = rules.dailyThresholdMinutes ?? expectedShare(of: job, on: day)
                overtime = max(0, creditedMinutes + worked - max(threshold, creditedMinutes))
            case .afterWeeklyHours:
                let threshold = rules.weeklyThresholdMinutes ?? contractedWeek(of: job, week: &week)
                overtime = max(0, after - max(threshold, afterCredited))
            }
            exact.overtime += overtime * rate * rules.overtimePercent
            result.overtimeMinutes += overtime

            for piece in jobPieces {
                let covered = coverage(of: piece, on: day, rules: rules, byDate: byDate)
                exact.saturday += covered.saturday * rate * rules.saturdayPercent
                exact.sundayAndHoliday += covered.sundayAndHoliday * rate * rules.sundayAndHolidayPercent
                exact.night += covered.night * rate * rules.nightPercent
                if rules.saturdayPercent > 0 { result.saturdayMinutes += covered.saturday }
                if rules.sundayAndHolidayPercent > 0 { result.sundayAndHolidayMinutes += covered.sundayAndHoliday }
                if rules.nightPercent > 0 { result.nightMinutes += covered.night }
            }
        }

        result.breakdown = exact.rounded
        result.isPaidByHealthInsurance = pastEmployerDays
        if !pastEmployerDays, absencePercent < 100, day.creditedMinutes > 0 {
            result.absencePaidPercent = absencePercent
        }
        return result
    }

    // MARK: - Where the minutes fell

    /// A shift's worked minutes, as minutes after the midnight that starts
    /// the day. Past 1,440 is the next calendar day.
    private struct Piece {
        var jobID: UUID
        var segments: [Range<Int>]
        /// False for worked time with no clock times — typed in as a figure —
        /// which has a day but no hour, so no night.
        var isPlaced: Bool

        var minutes: Int { segments.reduce(0) { $0 + $1.count } }
        var end: Int { segments.last?.upperBound ?? 0 }
    }

    /// The day's worked minutes, placed on the clock.
    ///
    /// Each shift runs from its start for its wall-clock length. Unpaid breaks
    /// with times come out where they were; one with no times comes out of
    /// the middle of the shift, which is where a break usually is and the
    /// fairest guess at which minutes it took. A paid break stays in.
    ///
    /// The result is then made to agree with the worked minutes the engine
    /// already decided on: a shift's own, then the day's, which rounding or a
    /// typed-in figure can make different. The difference goes on, or comes
    /// off, the end of the day.
    private func workedPieces(of day: DayComputation) -> [Piece] {
        var pieces: [Piece] = []
        for shift in day.shifts {
            guard let start = shift.start?.minutes, let end = shift.end?.minutes else { continue }
            let job = jobsByID[shift.jobID ?? primary.id] ?? primary
            let span = end > start ? end - start : (end == start ? 0 : end + TimeOfDay.minutesPerDay - start)

            var segments = span > 0 ? [0..<span] : []
            if !job.breaksArePaid {
                for gap in shift.timedBreaks { segments = Self.subtract(gap, from: segments) }
                let timed = shift.timedBreaks.reduce(0) { $0 + $1.count }
                segments = Self.removeFromMiddle(max(0, shift.breakMinutes - timed), of: segments)
            }
            segments = Self.resized(segments, to: shift.workedMinutes)
            pieces.append(Piece(
                jobID: job.id,
                segments: segments.map { (start + $0.lowerBound)..<(start + $0.upperBound) },
                isPlaced: true
            ))
        }

        let placed = pieces.reduce(0) { $0 + $1.minutes }
        let difference = day.workedMinutes - placed
        if difference > 0 {
            if let last = pieces.indices.max(by: { pieces[$0].end < pieces[$1].end }) {
                pieces[last].segments = Self.resized(pieces[last].segments, to: pieces[last].minutes + difference)
            } else {
                pieces.append(Piece(jobID: primary.id, segments: [0..<difference], isPlaced: false))
            }
        } else if difference < 0 {
            Self.trimLatest(-difference, from: &pieces)
        }
        return pieces.filter { $0.minutes > 0 }
    }

    /// The minutes of a piece each surcharge covers.
    private func coverage(
        of piece: Piece,
        on day: DayComputation,
        rules: PayRules,
        byDate: [CalendarDate: DayComputation]
    ) -> (saturday: Int, sundayAndHoliday: Int, night: Int) {
        var saturday = 0
        var sundayAndHoliday = 0
        var night = 0
        let window = Self.nightIntervals(rules)

        for segment in piece.segments where !segment.isEmpty {
            // A segment can run past midnight; each calendar day's part is
            // judged on that day, so a Saturday night shift is Saturday until
            // midnight and Sunday after it.
            let firstDay = segment.lowerBound / TimeOfDay.minutesPerDay
            let lastDay = (segment.upperBound - 1) / TimeOfDay.minutesPerDay
            for offset in firstDay...lastDay {
                let dayStart = offset * TimeOfDay.minutesPerDay
                let from = max(segment.lowerBound, dayStart) - dayStart
                let to = min(segment.upperBound, dayStart + TimeOfDay.minutesPerDay) - dayStart
                guard to > from else { continue }
                let minutes = to - from

                let date = offset == 0 ? day.date : day.date.adding(days: offset, in: calendar)
                switch kind(of: date, byDate: byDate) {
                case .sundayOrHoliday: sundayAndHoliday += minutes
                case .saturday: saturday += minutes
                case .ordinary: break
                }

                if piece.isPlaced {
                    night += window.reduce(0) { $0 + max(0, min(to, $1.upperBound) - max(from, $1.lowerBound)) }
                }
            }
        }
        return (saturday, sundayAndHoliday, night)
    }

    private enum DayKind {
        case ordinary
        case saturday
        case sundayOrHoliday
    }

    /// A public holiday is one the holiday rules say is a day off, or a day
    /// recorded as one. A holiday on a Saturday pays the holiday rate alone:
    /// the two are not stacked, since a Saturday holiday is not two days off.
    private func kind(of date: CalendarDate, byDate: [CalendarDate: DayComputation]) -> DayKind {
        if isPublicHoliday(date, byDate: byDate) { return .sundayOrHoliday }
        switch date.weekday(in: calendar) {
        case 1: return .sundayOrHoliday
        case 7: return .saturday
        default: return .ordinary
        }
    }

    private func isPublicHoliday(_ date: CalendarDate, byDate: [CalendarDate: DayComputation]) -> Bool {
        if byDate[date]?.dayType.id == .holiday { return true }
        // A holiday that counts as a working day is one the employer does
        // not observe, so it is an ordinary day here too.
        guard settings.features.trackHolidays, let rule = holidays.primaryHoliday(on: date) else { return false }
        return !rule.countsAsWorkingDay
    }

    /// The night window as one or two spans of a day's minutes.
    private static func nightIntervals(_ rules: PayRules) -> [Range<Int>] {
        let start = rules.nightStart.minutes
        let end = rules.nightEnd.minutes
        if start == end { return [] }
        if start < end { return [start..<end] }
        return [start..<TimeOfDay.minutesPerDay, 0..<end]
    }

    // MARK: - Shares between jobs

    /// What `job`'s week expects of the day, by the day's type.
    private func share(of job: Job, on day: DayComputation) -> Int {
        guard day.dayType.expectation != .zero else { return 0 }
        return job.schedule(on: day.date).expectedMinutes(forWeekday: day.date.weekday(in: calendar))
    }

    /// The normal day for daily overtime: what the job's week expects of it.
    ///
    /// When the day's expected hours are not the jobs' weeks added up, a
    /// per-day figure was typed in for the whole day; it is the primary job's
    /// to keep, since there is no telling how it splits.
    private func expectedShare(of job: Job, on day: DayComputation) -> Int {
        if settings.features.trackExpectedHours {
            let scheduled = activeJobs.reduce(0) { $0 + share(of: $1, on: day) }
            if scheduled != day.expectedMinutes {
                return job.id == primary.id ? day.expectedMinutes : 0
            }
        }
        return share(of: job, on: day)
    }

    /// Credited minutes by job: each its own week's share, as `jobTotals`
    /// splits them, or all of it to the primary job when a typed-in figure
    /// makes the shares not add up.
    private func creditedShares(of day: DayComputation) -> [UUID: Int] {
        guard day.creditedMinutes > 0 else { return [:] }
        var shares: [UUID: Int] = [:]
        for job in activeJobs { shares[job.id, default: 0] += share(of: job, on: day) }
        guard shares.values.reduce(0, +) == day.creditedMinutes else {
            return [primary.id: day.creditedMinutes]
        }
        return shares.filter { $0.value > 0 }
    }

    /// The contracted week for weekly overtime: each day of the week at the
    /// version in force that day, so a week a contract changes in is counted
    /// against both.
    private func contractedWeek(of job: Job, week: inout WeekTally) -> Int {
        if let known = week.contracted[job.id] { return known }
        guard let start = week.start else { return 0 }
        let total = (0..<7).reduce(0) { total, offset in
            let date = start.adding(days: offset, in: calendar)
            return total + job.schedule(on: date).expectedMinutes(forWeekday: date.weekday(in: calendar))
        }
        week.contracted[job.id] = total
        return total
    }

    // MARK: - Interval arithmetic

    /// `segments` with `gap` taken out of them.
    static func subtract(_ gap: Range<Int>, from segments: [Range<Int>]) -> [Range<Int>] {
        segments.flatMap { segment -> [Range<Int>] in
            guard gap.overlaps(segment) else { return [segment] }
            var parts: [Range<Int>] = []
            if segment.lowerBound < gap.lowerBound { parts.append(segment.lowerBound..<gap.lowerBound) }
            if gap.upperBound < segment.upperBound { parts.append(gap.upperBound..<segment.upperBound) }
            return parts
        }
    }

    /// `segments` with `minutes` of them taken out of the middle — counted in
    /// minutes worked, so a gap already there is stepped over.
    static func removeFromMiddle(_ minutes: Int, of segments: [Range<Int>]) -> [Range<Int>] {
        let total = segments.reduce(0) { $0 + $1.count }
        guard minutes > 0 else { return segments }
        guard minutes < total else { return [] }

        let first = (total - minutes) / 2
        var result = segments
        var seen = 0
        var remaining = minutes
        var cut: [Range<Int>] = []
        for segment in segments where remaining > 0 {
            let skip = max(0, first - seen)
            seen += segment.count
            guard skip < segment.count else { continue }
            let from = segment.lowerBound + skip
            let to = min(segment.upperBound, from + remaining)
            cut.append(from..<to)
            remaining -= to - from
        }
        for gap in cut { result = subtract(gap, from: result) }
        return result
    }

    /// `segments` made `minutes` long: cut from the end, or the last one
    /// carried on past it.
    static func resized(_ segments: [Range<Int>], to minutes: Int) -> [Range<Int>] {
        var result = segments
        var excess = result.reduce(0) { $0 + $1.count } - max(0, minutes)
        while excess > 0, let last = result.last {
            if last.count <= excess {
                excess -= last.count
                result.removeLast()
            } else {
                result[result.count - 1] = last.lowerBound..<(last.upperBound - excess)
                excess = 0
            }
        }
        if excess < 0 {
            if let last = result.last {
                result[result.count - 1] = last.lowerBound..<(last.upperBound - excess)
            } else {
                result = [0..<(-excess)]
            }
        }
        return result
    }

    /// Takes `minutes` off the latest worked minutes of the day, whichever
    /// shift they are in.
    private static func trimLatest(_ minutes: Int, from pieces: inout [Piece]) {
        var remaining = minutes
        while remaining > 0 {
            guard let index = pieces.indices
                .filter({ !pieces[$0].segments.isEmpty })
                .max(by: { pieces[$0].end < pieces[$1].end })
            else { return }
            let last = pieces[index].segments[pieces[index].segments.count - 1]
            let taken = min(remaining, last.count)
            pieces[index].segments = resized(pieces[index].segments, to: pieces[index].minutes - taken)
            remaining -= taken
        }
    }
}
