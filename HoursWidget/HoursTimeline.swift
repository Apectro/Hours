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
    /// What previews and the gallery show: the figures the design was drawn
    /// with, so a widget is judged on its layout rather than on zeroes.
    static func sample(at date: Date = Date()) -> HoursEntry {
        HoursEntry(date: date, snapshot: sampleSnapshot(at: date), state: .sample)
    }

    /// The clock stopped: before work on a working day.
    static func sampleIdle(at date: Date = Date()) -> HoursEntry {
        var snapshot = sampleSnapshot(at: date)
        snapshot.isClockRunning = false
        snapshot.clockStartedAt = nil
        snapshot.todayWorkedMinutes = 0
        return HoursEntry(date: date, snapshot: snapshot, state: .sample)
    }

    /// A day with nothing expected and nothing worked.
    static func sampleDayOff(at date: Date = Date()) -> HoursEntry {
        var snapshot = sampleIdle(at: date).snapshot
        snapshot.todayExpectedMinutes = 0
        let today = CalendarDate(date, calendar: .current)
        snapshot.weekDays = snapshot.weekDays.map { day in
            guard day.date == today else { return day }
            var off = day
            off.kind = .off
            off.expectedMinutes = 0
            off.usualStart = nil
            return off
        }
        return HoursEntry(date: date, snapshot: snapshot, state: .sample)
    }

    /// No rate, no leave allowance, overtime switched off: the quiet notes.
    static func sampleUnset(at date: Date = Date()) -> HoursEntry {
        var snapshot = sampleSnapshot(at: date)
        snapshot.monthEarned = nil
        snapshot.leave = nil
        snapshot.totalBalanceMinutes = nil
        snapshot.balanceDaysOffHalves = nil
        snapshot.showsBalance = false
        snapshot.site = nil
        return HoursEntry(date: date, snapshot: snapshot, state: .sample)
    }

    private static func sampleSnapshot(at date: Date) -> WidgetSnapshot {
        let calendar = Calendar.current
        let today = CalendarDate(date, calendar: calendar)
        let week = sampleWeekDays(today: today, calendar: calendar)
        let site = UUID()
        return WidgetSnapshot(
            generatedAt: date,
            isClockRunning: true,
            clockStartedAt: date.addingTimeInterval(-6 * 3600 - 9 * 60),
            clockJobName: nil,
            todayWorkedMinutes: 0,
            todayExpectedMinutes: 480,
            monthWorkedMinutes: 6_360,
            monthExpectedMinutes: 6_240,
            monthBalanceMinutes: 210,
            showsBalance: true,
            unrecordedDayCount: 0,
            durationStyle: .hoursAndMinutes,
            isUnlocked: true,
            week: WidgetWeek(
                start: week[0].date,
                firstWeekday: calendar.firstWeekday,
                workedMinutes: week.map(\.workedMinutes),
                expectedMinutes: 2_400
            ),
            monthMarks: [],
            clockSiteName: "Hauptstraße 12",
            todayDefaultEnd: TimeOfDay(hour: 15, minute: 30),
            site: WidgetSite(
                id: site,
                name: "Hauptstraße 12",
                isTodayWritten: true,
                lastDay: today,
                lastDayPeople: 4,
                includesYou: true,
                initials: ["IH", "AB", "MP"],
                lastStart: TimeOfDay(hour: 7, minute: 0),
                lastEnd: TimeOfDay(hour: 15, minute: 30),
                crew: [
                    WidgetCrewRow(name: "Ivan Horvat", isPresent: true, reason: nil),
                    WidgetCrewRow(name: "Ana Babić", isPresent: true, reason: nil),
                    WidgetCrewRow(name: "Marko Perić", isPresent: true, reason: nil),
                    WidgetCrewRow(name: "Luka Šimić", isPresent: false, reason: ExportLanguage.device.callAsFunction(.sickLeave)),
                    WidgetCrewRow(name: "Josip Kovač", isPresent: true, reason: nil),
                ]
            ),
            weekDays: week,
            weekNumber: calendar.component(.weekOfYear, from: date),
            averageDayMinutes: 480,
            monthDays: sampleMonth(today: today, calendar: calendar),
            totalBalanceMinutes: 750,
            balanceDaysOffHalves: 3,
            leave: WidgetLeave(
                leaveYear: today.year,
                available: HalfDays(halves: 50),
                taken: HalfDays(halves: 16),
                booked: HalfDays(halves: 6),
                nextStart: CalendarDate(year: today.year, month: 12, day: 22),
                nextEnd: CalendarDate(year: today.year, month: 12, day: 24)
            ),
            monthEarned: WidgetMonthEarned(
                year: today.year,
                month: today.month,
                currencyCode: "EUR",
                hoursCents: 980_00,
                paidMinutes: 6_360,
                allowanceDays: 6,
                allowanceCents: 84_00,
                kilometres: 120,
                mileageCents: 24_00
            ),
            usesTimeClock: true
        )
    }

    /// The design's week: three full days, a day of leave, today running.
    private static func sampleWeekDays(today: CalendarDate, calendar: Calendar) -> [WidgetWeekDay] {
        let range = CalendarDateRange.week(containing: today, in: calendar)
        let pattern: [(Int, Int, Int, Int)] = [(7, 0, 15, 30), (6, 45, 16, 0), (7, 0, 17, 0), (0, 0, 0, 0), (0, 0, 0, 0)]
        return range.days(in: calendar).enumerated().map { index, date in
            let isWeekday = index < 5
            guard isWeekday, date < today else {
                return WidgetWeekDay(
                    date: date,
                    kind: isWeekday ? .work : .off,
                    balanceMinutes: date == today ? -480 : 0,
                    expectedMinutes: isWeekday ? 480 : 0,
                    usualStart: isWeekday ? TimeOfDay(hour: 7, minute: 0) : nil
                )
            }
            if index == 3 {
                return WidgetWeekDay(
                    date: date, kind: .leave, creditedMinutes: 480, expectedMinutes: 480,
                    typeName: ExportLanguage.device.callAsFunction(.vacation)
                )
            }
            let (startHour, startMinute, endHour, endMinute) = pattern[index]
            let worked = [480, 525, 570, 0, 0][index]
            return WidgetWeekDay(
                date: date, kind: .work, workedMinutes: worked, balanceMinutes: worked - 480, expectedMinutes: 480,
                start: TimeOfDay(hour: startHour, minute: startMinute),
                end: TimeOfDay(hour: endHour, minute: endMinute),
                usualStart: TimeOfDay(hour: 7, minute: 0)
            )
        }
    }

    /// The month's days: worked weekdays, one sick, two of leave, the rest to come.
    private static func sampleMonth(today: CalendarDate, calendar: Calendar) -> [WidgetMonthDay] {
        today.yearMonth.range(in: calendar).days(in: calendar).map { date in
            let weekend = calendar.isDateInWeekend(date.date(in: calendar))
            let kind: WidgetMonthDay.Kind
            if date == today {
                kind = .today
            } else if weekend {
                kind = .off
            } else if date > today {
                kind = .future
            } else if date.day == 7 {
                kind = .sick
            } else if date.day == 12 || date.day == 13 {
                kind = .leave
            } else {
                kind = .worked
            }
            return WidgetMonthDay(date: date, kind: kind)
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

        // One read, a rendering a minute for the next hour and a half. The
        // figures that must tick by the second are system timers; the rest
        // move once a minute. Reading the file again for each entry would let
        // a timeline be built from two different snapshots, and the figures
        // within one timeline have to come from one file.
        let steps = stride(from: 0, through: 90, by: 1).map { minutes in
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
