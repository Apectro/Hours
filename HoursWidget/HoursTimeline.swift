import Foundation
import WidgetKit

/// One rendering of the widget, at one moment.
struct HoursEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// Three states worth telling apart: real data, sample data behind a
    /// preview, and "the app has never written anything I can read".
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
    }
}

extension HoursEntry {
    /// What previews and the gallery show. Plausible figures, so the widget is
    /// judged on its layout rather than on a grid of zeroes.
    static func sample(at date: Date = Date()) -> HoursEntry {
        HoursEntry(
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
                durationStyle: .hoursAndMinutes
            ),
            state: .sample
        )
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

        let steps = stride(from: 0, through: 110, by: 10).map { minutes in
            entry(at: now.addingTimeInterval(TimeInterval(minutes * 60)))
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
