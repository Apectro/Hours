import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The running clock on the Lock Screen and in the Dynamic Island.
///
/// The app starts and ends it (see `ClockActivityController`); this only
/// draws it. Every elapsed figure is a system timer counting up from the
/// start, so it stays live for as long as the shift runs without the app
/// sending a single update.
struct ClockLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClockActivityAttributes.self) { context in
            ClockBanner(state: context.state)
                .activityBackgroundTint(WidgetPalette.navy.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ClockBadge(size: 38)
                }
                DynamicIslandExpandedRegion(.center) {
                    ClockTitle(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StopClockButton()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ClockSince(state: context.state)
                }
            } compactLeading: {
                ClockMark()
                    .fill(WidgetPalette.amber)
                    .frame(width: 13, height: 13)
                    .accessibilityHidden(true)
            } compactTrailing: {
                ClockTimer(startedAt: context.state.startedAt)
                    .frame(maxWidth: 56)
                    .foregroundStyle(WidgetPalette.amber)
            } minimal: {
                ClockMark()
                    .fill(WidgetPalette.amber)
                    .frame(width: 12, height: 12)
                    .accessibilityLabel("Clocked in")
            }
            .keylineTint(WidgetPalette.amber)
        }
    }
}

/// Board 12, bottom: the mark, what the clock is for, since when and how
/// long, and a stop button.
struct ClockBanner: View {
    let state: ClockActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            ClockBadge(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                ClockTitle(state: state)
                ClockSince(state: state)
            }
            Spacer(minLength: 0)
            StopClockButton()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .environment(\.colorScheme, .dark)
    }
}

/// "Clocked in · Trg Pravde".
struct ClockTitle: View {
    let state: ClockActivityAttributes.ContentState

    var body: some View {
        Group {
            if let place = state.place {
                Text(String(
                    localized: "Clocked in · \(place)",
                    comment: "Live Activity, the running clock and the site or job it is for"
                ))
            } else {
                Text("Clocked in")
            }
        }
        .font(.system(.subheadline, design: .rounded, weight: .bold))
        .foregroundStyle(.white)
        .lineLimit(1)
    }
}

/// "Since 07:02 · 7:22:14 so far", the second figure ticking.
struct ClockSince: View {
    let state: ClockActivityAttributes.ContentState

    var body: some View {
        let since = state.startedAt.formatted(date: .omitted, time: .shortened)
        let timer = ClockTimer.text(state.startedAt)
        // A key rather than `String(localized:)`, because one of the values
        // is a live timer, which only a `Text` can carry.
        return Text("Since \(since) · \(timer) so far")
            .font(.system(.caption, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
    }
}

/// The elapsed time, counted by the system rather than by the app.
struct ClockTimer: View {
    let startedAt: Date

    static func text(_ startedAt: Date) -> Text {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
    }

    var body: some View {
        Self.text(startedAt)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

/// Stops the clock from the Lock Screen. The intent runs in the app's process
/// and records the shift exactly as the clock card would.
struct StopClockButton: View {
    var body: some View {
        Button(intent: StopClockIntent()) {
            ZStack {
                Circle().fill(WidgetPalette.stop)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clock out")
    }
}
