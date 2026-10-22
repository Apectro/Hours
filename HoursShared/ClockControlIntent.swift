import AppIntents
import Foundation

/// What the Clock in and out control does when it is flipped.
///
/// The control lives in the widget extension, and the extension cannot write
/// the store — it lives in the app's own container. So this is a
/// `LiveActivityIntent`, which iOS runs in the app's process even when the
/// control is flipped on the Lock Screen with the app closed, exactly as the
/// Live Activity's stop button (`StopClockIntent`) is. The extension compiles
/// the type only to put it on the control; its `perform` is compiled out
/// there by the `WIDGET_EXTENSION` condition. Being a Live Activity intent is
/// also what lets clocking in from Control Center start the Live Activity
/// from the background, as the clock card does in the app.
///
/// `value` is the state the control was flipped to, so a control that was
/// out of date when it was flipped — the clock stopped from Siri a moment
/// earlier — does not do the opposite of what it showed: clocking in while
/// running and clocking out while stopped each change nothing.
struct ToggleClockIntent: SetValueIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Clock in and out"
    static var description = IntentDescription(
        "Starts the clock, or stops it and records the hours."
    )
    /// The Clock in and Clock out shortcuts already offer this in Shortcuts.
    static var isDiscoverable = false

    @Parameter(title: "Clocked in")
    var value: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let clock = HoursStack.timeClock
        if value {
            clock.clockIn()
        } else {
            clock.clockOut()
        }
        // Writes the snapshot, which also reloads the controls, starts or
        // ends the Live Activity and tells the watch.
        HoursStack.refreshWidget()
        #endif
        return .result()
    }
}
