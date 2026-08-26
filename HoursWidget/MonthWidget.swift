import SwiftUI
import WidgetKit

/// The month at a glance: worked against expected, and the balance.
///
/// Separate from the Today widget rather than a size of it, because the two
/// answer different questions and people want different ones on their Home
/// Screen. Someone paid by the month rarely cares what today has been.
struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursMonth", provider: HoursProvider()) { entry in
            MonthWidgetView(entry: entry)
        }
        .configurationDisplayName("This month")
        .description("Hours worked this month, and whether you are ahead or behind.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct MonthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var hasData: Bool { entry.state == .data || entry.state == .sample }
    private var calendar: Calendar { .current }
    private var worked: Int { snapshot.monthWorked(at: entry.date, calendar: calendar) }
    private var expected: Int { snapshot.monthExpected(at: entry.date, calendar: calendar) }
    private var balance: Int { snapshot.monthBalance(at: entry.date, calendar: calendar) }
    private var fraction: Double? { snapshot.monthFraction(at: entry.date, calendar: calendar) }
    private var balanceColor: Color { WidgetPalette.balance(balance) }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .widgetBackground(onHomeScreen: family == .systemSmall || family == .systemMedium)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THIS MONTH")
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            if hasData {
                Text(snapshot.formatting.string(worked))
                    .font(.widgetFigure(.title, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text("of \(snapshot.formatting.string(expected))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let fraction {
                    ProgressBar(fraction: fraction, tint: balanceColor)
                        .padding(.top, 8)
                }

                Spacer(minLength: 4)
                balanceLine
            } else {
                Spacer(minLength: 0)
                EmptyStateView(state: entry.state, compact: true)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 16) {
            small

            if hasData {
                Divider()

                VStack(spacing: 6) {
                    if let fraction {
                        ZStack {
                            ProgressRing(fraction: fraction, tint: balanceColor)
                            Text("\(Int((fraction * 100).rounded()))%")
                                .font(.widgetFigure(.subheadline, weight: .semibold))
                                .minimumScaleFactor(0.6)
                        }
                        .frame(width: 68, height: 68)
                    }
                    if snapshot.unrecordedDayCount > 0 {
                        Label(unrecordedText, systemImage: "exclamationmark.circle")
                            .font(.caption2)
                            .foregroundStyle(WidgetPalette.negative)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if hasData {
                Text("This month")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(snapshot.formatting.string(worked))
                    .font(.widgetFigure(.headline, weight: .semibold))
                if snapshot.showsBalance {
                    Text(snapshot.formatting.signedString(balance))
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
            if hasData, snapshot.showsBalance {
                Label(snapshot.formatting.signedString(balance), systemImage: "calendar")
            } else if hasData {
                Label(snapshot.formatting.string(worked), systemImage: "calendar")
            } else {
                Label("Open Hours", systemImage: "calendar")
            }
        }
    }

    @ViewBuilder
    private var balanceLine: some View {
        if snapshot.showsBalance {
            Text(snapshot.formatting.signedString(balance))
                .font(.widgetFigure(.subheadline, weight: .semibold))
                .foregroundStyle(balanceColor)
                .lineLimit(1)
        } else if snapshot.unrecordedDayCount > 0 {
            Text(unrecordedText)
                .font(.caption2)
                .foregroundStyle(WidgetPalette.negative)
                .lineLimit(1)
        }
    }

    private var unrecordedText: String {
        String(localized: "^[\(snapshot.unrecordedDayCount) day](inflect: true) missing")
    }
}
