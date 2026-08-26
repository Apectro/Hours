import SwiftUI
import WidgetKit

/// Today's hours, on the Home Screen and on the Lock Screen.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursToday", provider: HoursProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("What you have worked today, and whether the clock is running.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var hasData: Bool { entry.state == .data || entry.state == .sample }
    /// A widget knows the device's zone and nothing else about the user's
    /// calendar preferences, and the zone is all "is this still today" needs.
    private var calendar: Calendar { .current }
    private var worked: Int { snapshot.todayIncludingRunningClock(at: entry.date, calendar: calendar) }
    private var expected: Int { snapshot.expectedMinutes(at: entry.date, calendar: calendar) }
    private var tint: Color { snapshot.isClockRunning ? WidgetPalette.running : .primary }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemMedium: medium
            default: small
            }
        }
        // Lock Screen accessories are drawn onto the wallpaper and must not
        // paint a background of their own.
        .widgetBackground(onHomeScreen: family == .systemSmall || family == .systemMedium)
    }

    // MARK: - Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 4)

            if hasData {
                Text(snapshot.formatting.string(worked))
                    .font(.widgetFigure(.title, weight: .bold))
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                expectationLine
                    .padding(.top, 1)

                if let fraction = snapshot.todayFraction(at: entry.date, calendar: calendar) {
                    ProgressBar(fraction: fraction, tint: tint)
                        .padding(.top, 8)
                }
            } else {
                Spacer(minLength: 0)
                EmptyStateView(state: entry.state, compact: true)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 4)
            footer
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            small
            if hasData {
                Divider()
                monthColumn
            }
        }
    }

    private var monthColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THIS MONTH")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Text(snapshot.formatting.string(snapshot.monthWorked(at: entry.date, calendar: calendar)))
                .font(.widgetFigure(.title2, weight: .bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("of \(snapshot.formatting.string(snapshot.monthExpected(at: entry.date, calendar: calendar)))")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let fraction = snapshot.monthFraction(at: entry.date, calendar: calendar) {
                ProgressBar(fraction: fraction, tint: .primary)
                    .padding(.top, 8)
            }

            Spacer(minLength: 4)

            if snapshot.showsBalance {
                Text(snapshot.formatting.signedString(snapshot.monthBalance(at: entry.date, calendar: calendar)))
                    .font(.widgetFigure(.subheadline, weight: .semibold))
                    .foregroundStyle(WidgetPalette.balance(snapshot.monthBalance(at: entry.date, calendar: calendar)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("TODAY")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            if snapshot.isClockRunning {
                Image(systemName: "record.circle")
                    .font(.caption2)
                    .foregroundStyle(WidgetPalette.running)
                    .accessibilityLabel("Clock running")
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var expectationLine: some View {
        if expected > 0 {
            Text("of \(snapshot.formatting.string(expected))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("Not a working day")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if hasData, let startedAt = snapshot.clockStartedAt, snapshot.isClockRunning {
            // `.timer` counts up on its own, so the elapsed figure stays live
            // between timeline entries instead of freezing for ten minutes.
            HStack(spacing: 4) {
                Image(systemName: "play.fill").font(.caption2)
                Text(startedAt, style: .timer)
                    .font(.widgetFigure(.caption, weight: .medium))
                    .fixedSize()
                // Only ever set when a second job exists, so a single-job
                // widget looks exactly as it did. With two, "clocked in" is
                // half an answer without it.
                if let job = snapshot.clockJobName {
                    Text(job)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .lineLimit(1)
            .foregroundStyle(WidgetPalette.running)
        } else if hasData, snapshot.showsBalance {
            Text("\(snapshot.formatting.signedString(snapshot.monthBalance(at: entry.date, calendar: calendar))) this month")
                .font(.caption2)
                .foregroundStyle(WidgetPalette.balance(snapshot.monthBalance(at: entry.date, calendar: calendar)))
                .lineLimit(1)
        }
    }

    // MARK: - Lock Screen

    private var circular: some View {
        Group {
            if hasData, let fraction = snapshot.todayFraction(at: entry.date, calendar: calendar) {
                ZStack {
                    ProgressRing(fraction: fraction, tint: .primary, lineWidth: 5)
                    Text(compactHours(worked))
                        .font(.widgetFigure(.caption, weight: .semibold))
                        .minimumScaleFactor(0.6)
                }
            } else {
                Image(systemName: hasData ? "clock" : "clock.badge.questionmark")
                    .font(.title3)
            }
        }
        .widgetAccentable()
        .accessibilityLabel("Worked today")
        .accessibilityValue(snapshot.formatting.string(worked))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if hasData {
                Text(snapshot.isClockRunning ? (snapshot.clockJobName ?? "Today") : "Today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(snapshot.formatting.string(worked))
                    .font(.widgetFigure(.headline, weight: .semibold))
                if snapshot.isClockRunning, let startedAt = snapshot.clockStartedAt {
                    Text(startedAt, style: .timer)
                        .font(.widgetFigure(.caption2, weight: .regular))
                } else if snapshot.showsBalance {
                    Text("\(snapshot.formatting.signedString(snapshot.monthBalance(at: entry.date, calendar: calendar))) this month")
                        .font(.caption2)
                }
            } else {
                EmptyStateView(state: entry.state, compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetAccentable()
    }

    private var inline: some View {
        Group {
            if hasData {
                Label(snapshot.formatting.string(worked), systemImage: snapshot.isClockRunning ? "record.circle" : "clock")
            } else {
                Label("Open Hours", systemImage: "clock.badge.questionmark")
            }
        }
    }

    /// A circular accessory is about four characters wide inside its ring, so
    /// the chosen duration style does not fit and clock notation is used
    /// regardless. It is the one place in the app that overrides the
    /// preference, and only because `8h 30m` there would render as an ellipsis.
    private func compactHours(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
