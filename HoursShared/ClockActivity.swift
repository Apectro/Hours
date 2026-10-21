import ActivityKit
import AppIntents
import Foundation

// The running clock as a Live Activity, in the part of the code both targets
// compile: the app starts, updates and ends it, and the widget extension
// draws it. Apple-only, which is why it lives here and not in the engine.

/// What the Live Activity shows. Kept to what cannot be worked out on the
/// lock screen: the elapsed time is drawn by the system from `startedAt`, so
/// the app never has to wake up to move it on.
struct ClockActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        /// The site the clock belongs to, or its job when there is more than
        /// one; nil when there is nothing worth naming.
        var place: String?
    }
}

/// The Live Activity's stop button.
///
/// A `LiveActivityIntent` runs in the app's process, even when the button is
/// pressed on the lock screen with the app closed, which is what lets it use
/// the same clock-out as the clock card and Siri. The widget extension needs
/// the type too, to put it on the button, but never runs it — hence the
/// condition, which only the extension's build sets.
struct StopClockIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Clock out"
    static var description = IntentDescription(
        "Stops the clock and records the hours against the day the shift started."
    )
    /// The Clock out shortcut already offers this; one is enough in Shortcuts.
    static var isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        HoursStack.timeClock.clockOut()
        // Also ends this Live Activity: see `WidgetSnapshotWriter.refresh`.
        HoursStack.refreshWidget()
        #endif
        return .result()
    }
}
