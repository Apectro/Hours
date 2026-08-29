import Foundation
import SwiftData

/// Starting and stopping the clock, and turning the result into a recorded day.
///
/// Kept out of the views so that clocking out from a button, from Siri and from
/// a widget all take exactly the same path.
@MainActor
struct TimeClock {
    let repository: WorkdayRepository
    let clock: ActiveShiftStore
    let settings: AppSettings
    let calendar: Calendar

    init(
        repository: WorkdayRepository,
        clock: ActiveShiftStore,
        settings: AppSettings,
        calendar: Calendar
    ) {
        self.repository = repository
        self.clock = clock
        self.settings = settings
        self.calendar = calendar
    }

    var running: RunningShift? { clock.running }

    // MARK: - In

    /// Starts the clock. Does nothing if one is already running, so a double
    /// tap or a repeated Shortcut cannot silently discard a shift in progress.
    @discardableResult
    func clockIn(at instant: Date = Date(), jobID: UUID? = nil) -> RunningShift? {
        guard clock.running == nil else { return nil }
        let resolved = jobID ?? (settings.tracksMultipleJobs ? settings.primaryJob.id : nil)
        let shift = RunningShift(startingAt: instant, calendar: calendar, jobID: resolved)
        clock.start(shift)
        return shift
    }

    // MARK: - Out

    enum ClockOutResult: Hashable, Sendable {
        case recorded(date: CalendarDate, workedMinutes: Int, wasCapped: Bool)
        case nothingRunning
        /// The clock stopped, and the day it belonged to is in a closed month.
        /// A distinct case rather than a silent failure: the shift is gone
        /// either way, and the person needs to know which month refused it.
        case monthIsClosed(YearMonth)
    }

    /// Stops the clock and appends the finished block to its day.
    ///
    /// The block is appended rather than replacing what is there, so clocking
    /// in and out twice in a day produces a split shift instead of losing the
    /// morning.
    @discardableResult
    func clockOut(at instant: Date = Date()) -> ClockOutResult {
        guard let running = clock.stop() else { return .nothingRunning }

        let finished = running.finished(at: instant, calendar: calendar)
        var record = repository.record(on: running.date) ?? DayRecord(date: running.date)
        record.shifts.append(finished)
        do {
            try repository.save(record)
        } catch {
            // The shift is lost either way — the clock has already stopped —
            // so say which month refused it rather than reporting a generic
            // failure the person cannot act on.
            if case let MonthLock.Refusal.monthIsClosed(month) = error {
                return .monthIsClosed(month)
            }
            return .nothingRunning
        }

        return .recorded(
            date: running.date,
            workedMinutes: workedMinutes(of: finished, on: running.date),
            wasCapped: running.hasRunTooLong(at: instant)
        )
    }

    /// Abandons a running clock without recording anything.
    func discard() {
        clock.stop()
    }

    // MARK: - Reading

    /// What the day would total if the clock were stopped right now.
    func projectedWorkedMinutes(at instant: Date = Date()) -> Int? {
        guard let running = clock.running else { return nil }
        return workedMinutes(of: running.finished(at: instant, calendar: calendar), on: running.date)
    }

    private func workedMinutes(of shift: Shift, on date: CalendarDate) -> Int {
        // Measured by the engine rather than by subtracting, so breaks,
        // rounding and the wall-clock/elapsed policy all apply exactly as they
        // do to a typed-in shift.
        let calculator = WorkdayCalculator(settings: settings, calendar: calendar)
        var warnings: [DayWarning] = []
        let definition = settings.dayTypeCatalog.definition(for: .work)
        return calculator.shiftMinutes(
            record: DayRecord(date: date, shifts: [shift]),
            on: date,
            definition: definition,
            warnings: &warnings
        ).workedMinutes
    }
}
