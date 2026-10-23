import AppIntents
import SwiftUI
import WidgetKit

// Controls: Control Center, the Lock Screen and the Action Button (iOS 18).
//
// Like the widgets, they read the snapshot and never the store. The toggle's
// intent runs in the app (see `ToggleClockIntent`); the two buttons are
// links, as the site widget's are, because opening the app on the right
// screen is the whole of what they do (see `AppLink`).

/// The control kinds, for reloading one by kind from the app.
enum ControlKind {
    static let clock = "app.zeitkonto.hours.control.clock"
    static let sameAsYesterday = "app.zeitkonto.hours.control.same-as-yesterday"
    static let writeToday = "app.zeitkonto.hours.control.write-today"
}

/// Clock in and out: on while the clock is running.
struct ClockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.clock, provider: ClockControlProvider()) { isRunning in
            ControlWidgetToggle("Clock in and out", isOn: isRunning, action: ToggleClockIntent()) { isOn in
                Label(isOn ? "Clocked in" : "Clocked out", systemImage: isOn ? "stop.circle.fill" : "play.circle")
            }
            .tint(.orange)
        }
        .displayName("Clock in and out")
        .description("Starts the clock, or stops it and records the hours.")
    }
}

/// Whether the clock is running, from the snapshot the app writes whenever
/// it starts or stops — and reloads the controls after.
struct ClockControlProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        WidgetSnapshotStore.read()?.isClockRunning ?? false
    }
}

/// Same as yesterday: today on the site card's site, filled from its last
/// written day — the site widget's button, without the widget.
struct SameAsYesterdayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.sameAsYesterday, provider: SameAsYesterdayProvider()) { link in
            ControlWidgetButton(action: OpenURLIntent(link.url)) {
                // "Same as last day", the site screen's own words: the
                // control cannot know the gap, and on a Monday it copies
                // Friday.
                Label("Same as last day", systemImage: "arrow.uturn.backward.circle")
            }
        }
        .displayName("Same as last day")
        .description("Opens today on your site, filled in like the last day.")
    }
}

/// Which site, decided where the site card is (`AppLink.sameAsYesterday`).
struct SameAsYesterdayProvider: ControlValueProvider {
    var previewValue: AppLink { .sites }

    func currentValue() async throws -> AppLink {
        AppLink.sameAsYesterday(from: WidgetSnapshotStore.read())
    }
}

/// Write today: today's day editor, over the calendar.
struct WriteTodayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.writeToday) {
            ControlWidgetButton(action: OpenURLIntent(AppLink.writeToday.url)) {
                Label("Write today", systemImage: "square.and.pencil")
            }
        }
        .displayName("Write today")
        .description("Opens today's day to write it.")
    }
}
