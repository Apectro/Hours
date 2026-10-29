import SwiftUI
import WidgetKit

/// Vacation days left this leave year, and when the next leave starts.
/// New in 1.2; reads the leave allowance set in the app.
struct LeaveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursLeave", provider: HoursProvider()) { entry in
            LeaveWidgetView(entry: entry)
                .widgetSurface(onHomeScreen: false)
        }
        .configurationDisplayName("Leave")
        .description("Vacation days left this year, and your next days off.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

struct LeaveWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry

    var body: some View {
        switch family {
        case .accessoryCircular: LeaveCircular(entry: entry)
        default: LeaveRectangular(entry: entry)
        }
    }
}

/// "LEAVE 2026 / 14 of 25 days left / next: 22–24 Dec".
struct LeaveRectangular: View {
    let entry: HoursEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !entry.hasData {
                EmptyStateView(state: entry.state, compact: true)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .widgetAccentable()
                    Text(verbatim: title.uppercased())
                        .font(.lockLabel)
                        .tracking(0.6)
                        .opacity(0.72)
                        .lineLimit(1)
                }
                if let leave = entry.snapshot.leave {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(verbatim: leave.remaining.withHalfSign)
                            .font(.lockFigure())
                            .widgetAccentable()
                        Text(verbatim: String(
                            localized: "of \(leave.available.withHalfSign) days left",
                            comment: "Leave widget, after the days left, e.g. 14 of 25 days left"
                        ))
                        .font(.system(size: 14))
                        .opacity(0.7)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    if let start = leave.nextStart, let end = leave.nextEnd {
                        Text(verbatim: String(
                            localized: "next: \(WidgetText.range(start, end))",
                            comment: "Leave widget, the next stretch of leave, e.g. next: 22–24 Dec"
                        ))
                        .font(.lockLine)
                        .opacity(0.78)
                        .lineLimit(1)
                    }
                } else {
                    Text(verbatim: String(localized: "Set your leave days in the app", comment: "Leave widget, before a leave allowance is set"))
                        .font(.lockLine)
                        .opacity(0.78)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "Leave 2026".
    private var title: String {
        guard let year = entry.snapshot.leave?.leaveYear else {
            return String(localized: "Leave", comment: "Leave widget header")
        }
        return String(localized: "Leave \(String(year))", comment: "Leave widget header with the leave year, e.g. Leave 2026")
    }
}

/// A ring of what is left, the days in the middle.
struct LeaveCircular: View {
    let entry: HoursEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.hasData, let leave = entry.snapshot.leave {
                Circle()
                    .stroke(Color.primary.opacity(0.25), lineWidth: 2.5)
                    .padding(3)
                Circle()
                    .trim(from: 0, to: leave.remainingFraction)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(3)
                    .widgetAccentable()
                VStack(spacing: 0) {
                    Text(verbatim: leave.remaining.withHalfSign)
                        .font(.lockFigure(size: 21))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("days left", comment: "Leave circular widget, under the number of vacation days left")
                        .font(.system(size: 8.5))
                        .opacity(0.75)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 8)
            } else {
                Image(systemName: "calendar")
                    .font(.title3)
                    .widgetAccentable()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
