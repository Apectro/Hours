import Foundation
import SwiftData
import WidgetKit

/// Builds the widget's snapshot from the real data and writes it out.
///
/// Called whenever something the widget shows could have changed: the app
/// becoming active, a day being saved, the clock starting or stopping.
@MainActor
struct WidgetSnapshotWriter {
    let repository: WorkdayRepository
    let settings: AppSettings
    let clock: ActiveShiftStore
    let calendar: Calendar

    func snapshot(at instant: Date = Date()) -> WidgetSnapshot {
        let today = CalendarDate.today(in: calendar, now: instant)
        let engine = PeriodEngine(settings: settings, calendar: calendar)
        let holidays = repository.holidayRules()

        let month = today.yearMonth.range(in: calendar)
        let monthDays = engine.days(
            in: month,
            records: repository.records(in: month),
            holidays: holidays
        )
        let monthSummary = PeriodAggregator.summarize(monthDays, range: month, countingThrough: today)
        let todayComputation = monthDays.first { $0.date == today }

        // The same window and the same rule the reminder uses.
        let window = GapFinder.window(
            endingAt: today,
            lookBackDays: settings.reminders.lookBackDays,
            calendar: calendar
        )
        let windowDays = engine.days(
            in: window,
            records: repository.records(in: window),
            holidays: holidays
        )
        let gaps = GapFinder.unrecordedWorkingDays(in: windowDays, asOf: today)

        let running = clock.running
        return WidgetSnapshot(
            generatedAt: instant,
            isClockRunning: running != nil,
            clockStartedAt: running?.startedAt,
            clockJobName: running.flatMap { shift in
                settings.tracksMultipleJobs ? settings.job(shift.jobID).name : nil
            },
            todayWorkedMinutes: todayComputation?.workedMinutes ?? 0,
            todayExpectedMinutes: todayComputation?.expectedMinutes ?? 0,
            monthWorkedMinutes: monthSummary.workedMinutes,
            monthExpectedMinutes: monthSummary.expectedMinutes,
            monthBalanceMinutes: monthSummary.balanceMinutes,
            showsBalance: settings.features.showsBalance,
            unrecordedDayCount: gaps.count,
            durationStyle: settings.displayDurationStyle
        )
    }

    /// Writes the snapshot and asks the widget to reload.
    ///
    /// Both are no-ops when the app group has not been set up, so nothing here
    /// fails or complains on a build without one.
    func refresh(at instant: Date = Date()) {
        guard WidgetSnapshotStore.isConfigured else { return }
        WidgetSnapshotStore.write(snapshot(at: instant))
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension HoursStack {
    static var widgetWriter: WidgetSnapshotWriter {
        WidgetSnapshotWriter(
            repository: repository,
            settings: settings.settings,
            clock: clock,
            calendar: calendar
        )
    }

    /// Refreshes what the widget shows. Safe to call often.
    static func refreshWidget() {
        widgetWriter.refresh()
    }
}
