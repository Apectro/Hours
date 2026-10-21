import ActivityKit
import Foundation

/// Keeps the clock's Live Activity in line with the widget snapshot.
///
/// Driven from the snapshot rather than from each place the clock changes,
/// so there is one rule instead of five: a running clock that has been paid
/// for has exactly one Live Activity showing it, and anything else has none.
/// A clock stopped from Siri, a clock that was discarded, or one stopped on
/// another launch all end it the next time the app refreshes the widget,
/// which includes every launch.
@MainActor
enum ClockActivityController {
    static func sync(with snapshot: WidgetSnapshot) {
        let activities = Activity<ClockActivityAttributes>.activities

        // Gated as the widgets are: part of what was bought, and the same
        // answer the widget reads, so the two can never disagree about it.
        guard snapshot.isUnlocked, snapshot.isClockRunning, let startedAt = snapshot.clockStartedAt else {
            end(activities)
            return
        }

        let state = ClockActivityAttributes.ContentState(
            startedAt: startedAt,
            place: snapshot.clockSiteName ?? snapshot.clockJobName
        )
        let content = ActivityContent(state: state, staleDate: nil)

        guard let current = activities.first else {
            // Switched off in Settings is an answer, not a failure. Starting
            // also fails from the background unless an intent marked for
            // Live Activities asked, which is not worth reporting either:
            // the clock is running whether or not the lock screen shows it.
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            _ = try? Activity.request(attributes: ClockActivityAttributes(), content: content, pushType: nil)
            return
        }

        // Two can only exist if a request raced another; keep the first.
        end(Array(activities.dropFirst()))
        if current.content.state != state {
            Task { await current.update(content) }
        }
    }

    private static func end(_ activities: [Activity<ClockActivityAttributes>]) {
        for activity in activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
