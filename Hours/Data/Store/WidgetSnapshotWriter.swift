import Foundation
import SwiftData
import WidgetKit

/// Builds the widget's snapshot from the real data and writes it out.
///
/// Called whenever something the widget shows could have changed: the app
/// becoming active, a day or a site day being saved, the clock starting or
/// stopping.
///
/// It only fetches. What the figures mean is decided by the engine —
/// `PeriodEngine` for the days, `WidgetSnapshotBuilder` for the week, the
/// month's squares and the site card — so the widget cannot disagree with
/// the calendar.
@MainActor
struct WidgetSnapshotWriter {
    let repository: WorkdayRepository
    /// Read only. Its reads collapse duplicates, which writes, so this runs
    /// outside any view's body, as every refresh does.
    let sites: SiteRepository
    let settings: AppSettings
    let clock: ActiveShiftStore
    let calendar: Calendar
    let isUnlocked: Bool

    func snapshot(at instant: Date = Date()) -> WidgetSnapshot {
        let today = CalendarDate.today(in: calendar, now: instant)
        let engine = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: repository.firstRecordedDate())
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

        let week = CalendarDateRange.week(containing: today, in: calendar)
        let weekDays = engine.days(
            in: week,
            records: repository.records(in: week),
            holidays: holidays
        )

        let running = clock.running
        let allSites = sites.sites(includeArchived: true)
        let earned = settings.showsEarnings
            ? earnings(engine: engine, month: month, week: week, today: today, holidays: holidays)
            : nil
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
            durationStyle: settings.displayDurationStyle,
            isUnlocked: isUnlocked,
            week: WidgetSnapshotBuilder.week(weekDays, today: today, calendar: calendar),
            monthMarks: WidgetSnapshotBuilder.monthMarks(monthDays, today: today),
            clockSiteName: WidgetSnapshotBuilder.clockSiteName(for: running, among: allSites),
            todayDefaultEnd: WidgetSnapshotBuilder.defaultEnd(today: todayComputation, running: running, settings: settings),
            site: siteCard(among: allSites, today: today),
            earnings: earned
        )
    }

    /// The month's and the week's earnings through today, from one fetch of
    /// the whole weeks around both — overtime after the contracted week is
    /// counted from the week's first day, which the month may not hold.
    private func earnings(
        engine: PeriodEngine,
        month: CalendarDateRange,
        week: CalendarDateRange,
        today: CalendarDate,
        holidays: [HolidayRule]
    ) -> WidgetEarnings? {
        let fetched = engine.earningsRange(covering: CalendarDateRange(
            start: min(month.start, week.start),
            end: max(month.end, week.end)
        ))
        let records = repository.records(in: fetched)
        return WidgetSnapshotBuilder.earnings(
            month: engine.earnings(in: month, records: records, holidays: holidays, countingThrough: today),
            week: engine.earnings(in: week, records: records, holidays: holidays, countingThrough: today),
            today: today,
            settings: settings,
            currencyCode: settings.money.currencyCode
        )
    }

    /// How far back a site counts as one you are working on. Two months: long
    /// enough to cover a holiday, short enough that last year's site does not
    /// win over the one you added on Monday and have not written up yet.
    private static let recentSiteDays = 62

    private func siteCard(among allSites: [Site], today: CalendarDate) -> WidgetSite? {
        let window = CalendarDateRange(
            start: today.adding(days: -Self.recentSiteDays, in: calendar),
            end: today
        )
        guard let site = WidgetSnapshotBuilder.mostRecentSite(
            among: allSites,
            recentDays: sites.siteDays(siteID: nil, in: window),
            today: today
        ) else { return nil }

        // Today's day when it is written, otherwise the last one before it,
        // however long ago: the card says which day it is describing.
        let lastDay = sites.siteDay(siteID: site.id, on: today)
            ?? sites.lastSiteDay(siteID: site.id, before: today)
        return WidgetSnapshotBuilder.site(
            site,
            today: today,
            lastDay: lastDay,
            // Hidden members included: a past day may name one.
            crew: sites.crew(for: site.id, includeHidden: true)
        )
    }

    /// Writes the snapshot, asks the widget to reload, and brings the clock's
    /// Live Activity in line with it.
    ///
    /// The Live Activity is kept in step from here because every path that
    /// starts, stops or changes the clock already ends in this call — the
    /// clock card, Siri and Shortcuts, the Live Activity's own stop button and
    /// the app coming back — so none of them has to remember a second one.
    /// It does not need the app group, so it goes first; the file and the
    /// reload are no-ops without one, so nothing here fails or complains on a
    /// build that has none.
    func refresh(at instant: Date = Date()) {
        let snapshot = snapshot(at: instant)
        ClockActivityController.sync(with: snapshot)
        guard WidgetSnapshotStore.isConfigured else { return }
        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        // The Clock in and out control shows whether the clock is running,
        // and Same as yesterday which site it opens; both read this file.
        ControlCenter.shared.reloadAllControls()
    }
}

extension HoursStack {
    static var widgetWriter: WidgetSnapshotWriter {
        WidgetSnapshotWriter(
            repository: repository,
            sites: SiteRepository(context: container.mainContext),
            settings: settings.settings,
            clock: clock,
            calendar: calendar,
            isUnlocked: subscriptions.allows(.widgets)
        )
    }

    /// Refreshes what the widget shows. Safe to call often.
    static func refreshWidget() {
        widgetWriter.refresh()
    }
}
