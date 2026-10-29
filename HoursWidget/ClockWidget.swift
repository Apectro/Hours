import AppIntents
import SwiftUI
import WidgetKit

/// The running clock on the Lock Screen, its seconds ticking: what it is
/// for, how long it has run, and — on the circular one — a tap to stop it.
///
/// New in 1.2, beside Today rather than inside it, because "is the clock
/// running and since when" is a different glance from "how much today".
struct ClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursClock", provider: HoursProvider()) { entry in
            ClockWidgetView(entry: entry)
                .widgetSurface(onHomeScreen: false)
        }
        .configurationDisplayName("Clock")
        .description("The running clock with its seconds, and where it is running.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct ClockWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry

    private var startedAt: Date? {
        entry.snapshot.isClockRunning ? entry.snapshot.clockStartedAt : nil
    }

    var body: some View {
        switch family {
        case .accessoryCircular: ClockCircular(entry: entry, startedAt: startedAt)
        case .accessoryInline: ClockInline(entry: entry, startedAt: startedAt)
        default: ClockRectangular(entry: entry, startedAt: startedAt)
        }
    }
}

/// "● HAUPTSTRASSE 12 / 6:09:24 / since 07:02 · off 15:30".
struct ClockRectangular: View {
    let entry: HoursEntry
    let startedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !entry.hasData {
                EmptyStateView(state: entry.state, compact: true)
            } else if let startedAt {
                HStack(spacing: 5) {
                    Circle().frame(width: 7, height: 7).widgetAccentable()
                    Text(verbatim: (entry.snapshot.clockPlace ?? String(localized: "Clocked in")).uppercased())
                        .font(.lockLabel)
                        .tracking(0.6)
                        .lineLimit(1)
                }
                ClockTimer.text(startedAt)
                    .font(.lockFigure())
                    .lineLimit(1)
                    .widgetAccentable()
                Text(verbatim: line(startedAt))
                    .font(.lockLine)
                    .opacity(0.78)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                HStack(spacing: 5) {
                    Circle().strokeBorder(lineWidth: 1.25).frame(width: 7, height: 7)
                    Text(verbatim: String(localized: "Clock").uppercased())
                        .font(.lockLabel)
                        .tracking(0.6)
                        .opacity(0.72)
                }
                Text("Not running", comment: "Lock Screen, the clock is stopped")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .opacity(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func line(_ startedAt: Date) -> String {
        let since = String(
            localized: "since \(WidgetText.clockTime(startedAt))",
            comment: "Widget, the time the running clock was started"
        )
        guard let end = entry.snapshot.defaultEnd(at: entry.date, calendar: .current) else { return since }
        let off = String(localized: "off \(WidgetText.time(end, on: entry.date))", comment: "Widget, when today's work is due to end, e.g. off 15:30")
        return since + " · " + off
    }
}

/// The stop glyph, the live time and the site's initials; a tap stops it.
struct ClockCircular: View {
    let entry: HoursEntry
    let startedAt: Date?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.hasData, let startedAt {
                Button(intent: StopClockIntent()) {
                    VStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .frame(width: 8, height: 8)
                        ClockTimer.text(startedAt)
                            .font(.lockFigure(size: 15))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: 58)
                        if let place = entry.snapshot.clockPlace {
                            Text(verbatim: WidgetSnapshotBuilder.shortName(of: place))
                                .font(.system(size: 8.5))
                                .opacity(0.75)
                                .lineLimit(1)
                        }
                    }
                    .widgetAccentable()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clock out"))
            } else {
                VStack(spacing: 2) {
                    ClockRim().frame(width: 18, height: 18)
                    Text("Not running", comment: "Lock Screen, the clock is stopped")
                        .font(.system(size: 8.5))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 6)
            }
        }
    }
}

/// Above the clock: "6:09:24 · Hauptstraße 12".
struct ClockInline: View {
    let entry: HoursEntry
    let startedAt: Date?

    var body: some View {
        if entry.hasData, let startedAt {
            if let place = entry.snapshot.clockPlace {
                ClockTimer.text(startedAt) + Text(verbatim: " · " + place)
            } else {
                ClockTimer.text(startedAt)
            }
        } else {
            Text("Not running", comment: "Lock Screen, the clock is stopped")
        }
    }
}
