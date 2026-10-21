import Foundation
import WidgetKit

/// One rendering of the widget, at one moment.
struct HoursEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// The states worth telling apart, because each needs different words:
    /// real data, sample data behind a preview, and three different kinds of
    /// nothing.
    let state: State

    enum State: Equatable {
        case data
        case sample
        /// The app group is not set up, so there is nothing to read and never
        /// will be until it is. Says so rather than showing convincing zeroes.
        case unavailable
        /// The group exists but the app has not written yet — usually a widget
        /// added before the app was opened once.
        case waiting
        /// Read perfectly well; the widgets are simply not part of what was
        /// bought. The only one of these three the person can act on from
        /// here, and the only one that is not a fault.
        case locked
    }
}

extension HoursEntry {
    /// What previews and the gallery show. Plausible figures, so the widget is
    /// judged on its layout rather than on a grid of zeroes.
    static func sample(at date: Date = Date()) -> HoursEntry {
        let calendar = Calendar.current
        let today = CalendarDate(date, calendar: calendar)
        return HoursEntry(
            date: date,
            snapshot: WidgetSnapshot(
                generatedAt: date,
                isClockRunning: true,
                clockStartedAt: date.addingTimeInterval(-3 * 3600 - 25 * 60),
                clockJobName: nil,
                todayWorkedMinutes: 145,
                todayExpectedMinutes: 480,
                monthWorkedMinutes: 6_420,
                monthExpectedMinutes: 6_240,
                monthBalanceMinutes: 180,
                showsBalance: true,
                unrecordedDayCount: 1,
                durationStyle: .hoursAndMinutes,
                isUnlocked: true,
                week: sampleWeek(today: today, calendar: calendar),
                monthMarks: sampleMonth(today: today, calendar: calendar),
                clockSiteName: "Trg Pravde",
                todayDefaultEnd: TimeOfDay(hour: 16, minute: 0),
                site: WidgetSite(
                    id: UUID(),
                    name: "Trg Pravde",
                    isTodayWritten: false,
                    lastDay: today.adding(days: -1, in: calendar),
                    lastDayPeople: 4,
                    includesYou: true,
                    initials: ["IH", "DB", "MK"],
                    lastStart: TimeOfDay(hour: 7, minute: 0),
                    lastEnd: TimeOfDay(hour: 16, minute: 0)
                )
            ),
            state: .sample
        )
    }

    /// A full-looking week up to today and nothing after it.
    private static func sampleWeek(today: CalendarDate, calendar: Calendar) -> WidgetWeek {
        let range = CalendarDateRange.week(containing: today, in: calendar)
        let pattern = [510, 540, 372, 480, 450, 0, 0]
        let worked = range.days(in: calendar).enumerated().map { index, date in
            date < today ? pattern[index] : 0
        }
        return WidgetWeek(
            start: range.start,
            firstWeekday: calendar.firstWeekday,
            workedMinutes: worked,
            expectedMinutes: 2_400
        )
    }

    /// The month's weekdays, one of them short.
    private static func sampleMonth(today: CalendarDate, calendar: Calendar) -> [WidgetDayMark] {
        let weekdays = today.yearMonth.range(in: calendar).days(in: calendar).filter { date in
            !calendar.isDateInWeekend(date.date(in: calendar))
        }
        return weekdays.enumerated().map { index, date in
            let state: WidgetDayMark.State
            if date == today {
                state = .today
            } else if date > today {
                state = .toCome
            } else {
                state = index == 5 ? .short : .done
            }
            return WidgetDayMark(date: date, state: state)
        }
    }
}

/// Reads the snapshot and decides when to render again.
struct HoursProvider: TimelineProvider {
    func placeholder(in context: Context) -> HoursEntry {
        .sample()
    }

    func getSnapshot(in context: Context, completion: @escaping (HoursEntry) -> Void) {
        completion(context.isPreview ? .sample() : entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HoursEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)

        // The app reloads the timeline whenever anything changes, so most of
        // the time one entry is enough and the next reload is whatever the app
        // does next. The exception is a running clock, which changes on its own
        // with nobody to announce it.
        guard current.snapshot.isClockRunning else {
            completion(Timeline(entries: [current], policy: .after(nextRefresh(after: now))))
            return
        }

        // One read, twelve renderings of it. Reading the file again for each
        // entry would let a timeline be built from two different snapshots,
        // and the figures within one timeline have to come from one file.
        let steps = stride(from: 0, through: 110, by: 10).map { minutes in
            HoursEntry(
                date: now.addingTimeInterval(TimeInterval(minutes * 60)),
                snapshot: current.snapshot,
                state: current.state
            )
        }
        completion(Timeline(entries: steps, policy: .atEnd))
    }

    private func entry(at date: Date) -> HoursEntry {
        guard WidgetSnapshotStore.isConfigured else {
            return HoursEntry(date: date, snapshot: .empty, state: .unavailable)
        }
        guard let snapshot = WidgetSnapshotStore.read() else {
            return HoursEntry(date: date, snapshot: .empty, state: .waiting)
        }
        guard snapshot.isUnlocked else {
            return HoursEntry(date: date, snapshot: snapshot, state: .locked)
        }
        return HoursEntry(date: date, snapshot: snapshot, state: .data)
    }

    /// Midnight, so "today" stops meaning yesterday, with an hourly floor in
    /// case the calculation ever fails.
    private func nextRefresh(after date: Date) -> Date {
        let calendar = Calendar.current
        let midnight = calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        )
        return midnight ?? date.addingTimeInterval(3600)
    }
}
