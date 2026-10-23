import SwiftUI
import WidgetKit

/// The week so far, day by day, against the week's target.
///
/// Its own widget rather than another size of Today or Month: it answers a
/// third question — "how is this week shaping up" — which is the one a
/// Friday afternoon asks.
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursWeek", provider: HoursProvider()) { entry in
            WeekWidgetView(entry: entry)
                .widgetCard(.navy, onHomeScreen: true)
        }
        .configurationDisplayName("This week")
        .description("Hours this week, day by day.")
        .supportedFamilies([.systemMedium])
    }
}

/// Board 11, middle: the week's total and target on the left, seven bars on
/// the right with today's in amber.
struct WeekWidgetView: View {
    let entry: HoursEntry
    private let calendar = Calendar.current

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var bars: [WidgetWeekBar] { snapshot.weekBars(at: entry.date, calendar: calendar) ?? [] }
    private var monthBalance: Int { snapshot.monthBalance(at: entry.date, calendar: calendar) }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeading(text: Text("THIS WEEK"), color: WidgetPalette.amber)
                Spacer(minLength: 4)
                if entry.hasData {
                    totals
                    Spacer(minLength: 4)
                    if let earned = snapshot.weekEarnings(at: entry.date, calendar: calendar), let money = snapshot.money {
                        WidgetChip(
                            text: String(
                                localized: "\(money.string(earned, showsCents: false)) this week",
                                comment: "Widget, the week's earnings in a chip"
                            ),
                            foreground: WidgetPalette.amber,
                            background: WidgetPalette.amber.opacity(0.18)
                        )
                    } else if snapshot.showsBalance {
                        WidgetChip(
                            text: String(
                                localized: "\(snapshot.formatting.signedString(monthBalance)) month",
                                comment: "Lock Screen and widgets, the month's balance in two words"
                            ),
                            foreground: WidgetPalette.balance(monthBalance),
                            background: WidgetPalette.balance(monthBalance).opacity(0.18)
                        )
                    }
                } else {
                    EmptyStateView(state: entry.state, compact: false)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 112, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            if entry.hasData {
                WeekBars(bars: bars, formatting: snapshot.formatting, calendar: calendar)
            }
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(snapshot.formatting.string(snapshot.weekWorked(at: entry.date, calendar: calendar)))
                .font(.widgetFigure(size: 30))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
            Text("of \(snapshot.formatting.string(snapshot.weekExpected(at: entry.date, calendar: calendar)))")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(WidgetPalette.mist)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Seven bars, Monday to Sunday or however the user's week runs, each with
/// its hours above and its day below.
struct WeekBars: View {
    let bars: [WidgetWeekBar]
    let formatting: DurationFormatting
    let calendar: Calendar
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// Ten hours reach the top; a longer day stops there rather than pushing
    /// every other bar down to nothing.
    private static let fullHeight = 86.0
    private static let scaleMinutes = 600.0

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(bars, id: \.date) { bar in
                VStack(spacing: 5) {
                    BarValue(minutes: bar.minutes, formatting: formatting)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(fill(for: bar))
                        .frame(height: height(for: bar))
                        .widgetAccentable(bar.isToday)
                    Text(weekdayLetter(bar.date))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(bar.isToday ? WidgetPalette.amber : WidgetPalette.mist)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(bar.date.date(in: calendar), format: .dateTime.weekday(.wide)))
                .accessibilityValue(formatting.string(bar.minutes))
            }
        }
    }

    private func height(for bar: WidgetWeekBar) -> Double {
        guard bar.minutes > 0 else { return 4 }
        return max(6, min(Double(bar.minutes) / Self.scaleMinutes, 1) * Self.fullHeight)
    }

    private func fill(for bar: WidgetWeekBar) -> AnyShapeStyle {
        if bar.isToday {
            return renderingMode.isFullColor
                ? AnyShapeStyle(LinearGradient(colors: [WidgetPalette.amberLight, WidgetPalette.amber], startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(Color.primary)
        }
        return AnyShapeStyle(Color.white.opacity(bar.minutes > 0 ? 0.85 : 0.15))
    }

    private func weekdayLetter(_ date: CalendarDate) -> String {
        CalendarFormatting(locale: .current, calendar: calendar)
            .veryShortWeekdaySymbol(for: date.weekday(in: calendar))
    }
}

/// The hours above a bar, never smaller than 11pt: 9pt could not be read
/// outdoors. Where "8:30" does not fit the bar's width it becomes the
/// nearest whole hour, and where even that does not fit it is left out.
/// The bar's accessibility value always has the exact figure.
private struct BarValue: View {
    let minutes: Int
    let formatting: DurationFormatting

    var body: some View {
        Group {
            if minutes > 0 {
                ViewThatFits(in: .horizontal) {
                    label(formatting.string(minutes))
                    label(String((minutes + 30) / 60))
                    label(" ")
                }
            } else {
                label(" ")
            }
        }
        .accessibilityHidden(true)
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11, design: .rounded).monospacedDigit())
            .foregroundStyle(WidgetPalette.mist)
            .lineLimit(1)
            .fixedSize()
    }
}
