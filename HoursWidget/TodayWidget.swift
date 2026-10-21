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

/// The figures every Today family reads, worked out once per entry.
struct TodayFigures {
    let entry: HoursEntry
    /// A widget knows the device's zone and nothing else about the user's
    /// calendar preferences, and the zone is all "is this still today" needs.
    let calendar = Calendar.current

    var snapshot: WidgetSnapshot { entry.snapshot }
    var worked: Int { snapshot.todayIncludingRunningClock(at: entry.date, calendar: calendar) }
    var expected: Int { snapshot.expectedMinutes(at: entry.date, calendar: calendar) }
    var fraction: Double? { snapshot.todayFraction(at: entry.date, calendar: calendar) }
    var monthBalance: Int { snapshot.monthBalance(at: entry.date, calendar: calendar) }
    var monthWorked: Int { snapshot.monthWorked(at: entry.date, calendar: calendar) }
    var startedAt: Date? { snapshot.isClockRunning ? snapshot.clockStartedAt : nil }

    func duration(_ minutes: Int) -> String { snapshot.formatting.string(minutes) }
    func signed(_ minutes: Int) -> String { snapshot.formatting.signedString(minutes) }

    /// "16:30" or "4:30 PM", as the phone tells the time.
    func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Trg Pravde · off at 16:00": what the clock is for and when the day
    /// is due to end, whichever of the two is known.
    var footer: String? {
        var parts: [String] = []
        if snapshot.isClockRunning, let place = snapshot.clockPlace { parts.append(place) }
        if let end = snapshot.defaultEnd(at: entry.date, calendar: calendar) {
            let time = CalendarFormatting(locale: .current, calendar: calendar)
                .time(end, on: CalendarDate(entry.date, calendar: calendar))
            parts.append(String(localized: "off at \(time)", comment: "Widget, when today's work is due to end"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Month +3:30", or the month's hours when the balance is switched off.
    var monthLine: String {
        let figure = snapshot.showsBalance ? signed(monthBalance) : duration(monthWorked)
        return String(localized: "Month \(figure)", comment: "Widget, the month's balance or hours on one line")
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: TodayCircular(figures: TodayFigures(entry: entry))
            case .accessoryRectangular: TodayRectangular(figures: TodayFigures(entry: entry))
            case .accessoryInline: TodayInline(figures: TodayFigures(entry: entry))
            case .systemMedium: TodayMedium(figures: TodayFigures(entry: entry))
            default: TodaySmall(figures: TodayFigures(entry: entry))
            }
        }
        .widgetCard(.navy, onHomeScreen: family == .systemSmall || family == .systemMedium)
    }
}

// MARK: - Home Screen

/// Board 11, top left: the ring, today's hours, and what the clock is doing.
struct TodaySmall: View {
    let figures: TodayFigures

    var body: some View {
        if figures.entry.hasData {
            VStack(alignment: .leading, spacing: 0) {
                TodayHeader(figures: figures)
                Spacer(minLength: 6)
                TodayRingRow(figures: figures)
                Spacer(minLength: 6)
                if let footer = figures.footer {
                    Text(footer)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(WidgetPalette.mist)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeading(text: Text("TODAY"), color: WidgetPalette.amber)
                Spacer(minLength: 0)
                EmptyStateView(state: figures.entry.state, compact: false)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
    }
}

/// The small widget's content beside what the running clock says live, or
/// the month when no clock is running.
struct TodayMedium: View {
    let figures: TodayFigures

    var body: some View {
        HStack(spacing: 16) {
            TodaySmall(figures: figures)
            if figures.entry.hasData {
                Divider().overlay(WidgetPalette.mist.opacity(0.3))
                if let startedAt = figures.startedAt {
                    RunningColumn(figures: figures, startedAt: startedAt)
                } else {
                    MonthColumn(figures: figures)
                }
            }
        }
    }
}

struct TodayHeader: View {
    let figures: TodayFigures

    var body: some View {
        HStack(spacing: 4) {
            WidgetHeading(text: Text("TODAY"), color: WidgetPalette.amber)
            Spacer(minLength: 4)
            if let startedAt = figures.startedAt {
                Circle()
                    .fill(WidgetPalette.running)
                    .frame(width: 7, height: 7)
                    .shadow(color: WidgetPalette.running, radius: 3)
                    .widgetAccentable()
                Text(String(
                    localized: "since \(figures.clockTime(startedAt))",
                    comment: "Widget, the time the running clock was started"
                ))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(WidgetPalette.mist)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TodayRingRow: View {
    let figures: TodayFigures

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ProgressRing(fraction: figures.fraction ?? 0, tint: WidgetPalette.amber, lineWidth: 7)
                if let fraction = figures.fraction {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.widgetFigure(size: 13))
                        .foregroundStyle(WidgetPalette.amber)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 8)
                        .widgetAccentable()
                } else {
                    // A ring at zero on a Sunday reads as a failure rather
                    // than as a day off, so the mark sits there instead.
                    HardHat()
                        .fill(WidgetPalette.amber)
                        .frame(width: 22, height: 13)
                        .widgetAccentable()
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 1) {
                Text(figures.duration(figures.worked))
                    .font(.widgetFigure(size: 30))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Group {
                    if figures.expected > 0 {
                        Text("of \(figures.duration(figures.expected))")
                    } else {
                        Text("Not a working day")
                    }
                }
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(WidgetPalette.mist)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Worked today")
        .accessibilityValue(figures.duration(figures.worked))
    }
}

/// The running clock, ticking on its own between timeline entries.
struct RunningColumn: View {
    let figures: TodayFigures
    let startedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Clocked in")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetPalette.running)
                .widgetAccentable()
            // `.timer` counts up by itself, so the figure stays live instead
            // of freezing for the ten minutes between entries.
            Text(startedAt, style: .timer)
                .font(.widgetFigure(size: 24))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let place = figures.snapshot.clockPlace {
                Text(place)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(WidgetPalette.mist)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The month's balance and the days still to write, when no clock runs.
struct MonthColumn: View {
    let figures: TodayFigures

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeading(text: Text("THIS MONTH"), color: WidgetPalette.amber)
            if figures.snapshot.showsBalance {
                Text(figures.signed(figures.monthBalance))
                    .font(.widgetFigure(size: 24))
                    .foregroundStyle(WidgetPalette.balance(figures.monthBalance))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text(figures.duration(figures.monthWorked))
                    .font(.widgetFigure(size: 24))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if figures.snapshot.unrecordedDayCount > 0 {
                Text(UnrecordedDays.text(figures.snapshot.unrecordedDayCount))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(WidgetPalette.mist)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Lock Screen

/// Board 12: the ring around the hard hat and today's hours.
struct TodayCircular: View {
    let figures: TodayFigures

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if figures.entry.hasData {
                ProgressRing(fraction: figures.fraction ?? 0, tint: .primary, lineWidth: 4)
                    .padding(3)
                VStack(spacing: 1) {
                    HardHat()
                        .frame(width: 13, height: 7)
                        .widgetAccentable()
                    Text(compactHours(figures.worked))
                        .font(.widgetFigure(.caption, weight: .bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
            } else {
                HardHat()
                    .frame(width: 20, height: 11)
                    .widgetAccentable()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Worked today")
        .accessibilityValue(figures.duration(figures.worked))
    }

    /// A circular accessory is about four characters wide inside its ring, so
    /// the chosen duration style does not fit and clock notation is used
    /// regardless. It is the one place in the app that overrides the
    /// preference, and only because `8h 30m` there would render as an ellipsis.
    private func compactHours(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

/// Board 12: where the clock is, how long it has run, and the month.
struct TodayRectangular: View {
    let figures: TodayFigures

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if figures.entry.hasData {
                HStack(spacing: 4) {
                    HardHat()
                        .frame(width: 11, height: 6)
                        .widgetAccentable()
                    Text(figures.snapshot.isClockRunning ? (figures.snapshot.clockPlace ?? String(localized: "Clocked in")) : String(localized: "Today"))
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                }
                if let startedAt = figures.startedAt {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(startedAt, style: .timer)
                            .font(.widgetFigure(.headline, weight: .bold))
                            .lineLimit(1)
                        Text("running")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .widgetAccentable()
                } else {
                    Text(figures.duration(figures.worked))
                        .font(.widgetFigure(.headline, weight: .bold))
                        .widgetAccentable()
                }
                Text(monthAndGaps)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                EmptyStateView(state: figures.entry.state, compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Month +3:30 · 1 day to write".
    private var monthAndGaps: String {
        let gaps = figures.snapshot.unrecordedDayCount
        guard gaps > 0 else { return figures.monthLine }
        return figures.monthLine + " · " + UnrecordedDays.text(gaps)
    }
}

/// Above the clock: "⛑ 6:42 today · +3:30 month". Inline accessories draw
/// text and at most one system image, so the mark is the emoji rather than
/// the shape.
struct TodayInline: View {
    let figures: TodayFigures

    var body: some View {
        if figures.entry.hasData {
            Text(line)
        } else {
            Label("Open Zeitkonto", systemImage: "clock.badge.questionmark")
        }
    }

    private var line: String {
        let today = String(
            localized: "\(figures.duration(figures.worked)) today",
            comment: "Lock Screen, the hours worked today"
        )
        guard figures.snapshot.showsBalance else { return "⛑ " + today }
        let month = String(
            localized: "\(figures.signed(figures.monthBalance)) month",
            comment: "Lock Screen and widgets, the month's balance in two words"
        )
        return "⛑ " + today + " · " + month
    }
}

/// "2 days to write": recorded nowhere, in the fortnight the reminder looks at.
enum UnrecordedDays {
    static func text(_ count: Int) -> String {
        String(inflected: "^[\(count) day](inflect: true) to write")
    }
}
