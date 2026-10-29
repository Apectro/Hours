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
    var state: WidgetTodayState { snapshot.todayState(at: entry.date, calendar: calendar) }
    var worked: Int { snapshot.todayIncludingRunningClock(at: entry.date, calendar: calendar) }
    var expected: Int { snapshot.expectedMinutes(at: entry.date, calendar: calendar) }
    var fraction: Double? { snapshot.todayFraction(at: entry.date, calendar: calendar) }
    var chart: WidgetWeekChart? { snapshot.weekChart(at: entry.date, calendar: calendar) }
    var startedAt: Date? { snapshot.isClockRunning ? snapshot.clockStartedAt : nil }

    func duration(_ minutes: Int) -> String { snapshot.formatting.string(minutes) }
    func signed(_ minutes: Int) -> String { snapshot.formatting.signedString(minutes) }

    var isDayOff: Bool { state == .dayOff }

    /// "of 8:00", when something is expected.
    var ofExpected: String? {
        expected > 0 ? String(localized: "of \(duration(expected))") : nil
    }

    /// "since 07:02".
    var since: String? {
        startedAt.map { String(localized: "since \(WidgetText.clockTime($0))", comment: "Widget, the time the running clock was started") }
    }

    /// "off 15:30": when today's work is due to end.
    var offAt: String? {
        snapshot.defaultEnd(at: entry.date, calendar: calendar).map {
            String(localized: "off \(WidgetText.time($0, on: entry.date))", comment: "Widget, when today's work is due to end, e.g. off 15:30")
        }
    }

    /// "usually 07:00", before anything is worked on a working day.
    var usually: String? {
        guard case let .idle(usualStart?) = state, worked == 0 else { return nil }
        return String(localized: "usually \(WidgetText.time(usualStart, on: entry.date))", comment: "Widget, when work usually starts")
    }

    /// "Week 40:24 · +0:24", the balance left out where the app keeps none.
    var weekLine: String? {
        guard let chart else { return nil }
        let total = String(localized: "Week \(duration(chart.paidMinutes))", comment: "Widget, the week's hours so far")
        guard snapshot.showsBalance else { return total }
        return total + " · " + signed(chart.balanceMinutes)
    }

    /// The line under the big figure on the small widget.
    var smallLine: String? {
        switch state {
        case .running: return [ofExpected, since].compactMap { $0 }.joined(separator: " · ")
        case .idle: return usually ?? ofExpected
        case .dayOff: return weekLine
        }
    }

    /// "6:09", or "Day off" on a day off.
    var headline: String {
        isDayOff ? String(localized: "Day off", comment: "Widget, today is not a working day") : duration(worked)
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry

    var body: some View {
        let figures = TodayFigures(entry: entry)
        Group {
            switch family {
            case .accessoryCircular: TodayCircular(figures: figures)
            case .accessoryRectangular: TodayRectangular(figures: figures)
            case .accessoryInline: TodayInline(figures: figures)
            case .systemMedium: TodayMedium(figures: figures)
            default: TodaySmall(figures: figures)
            }
        }
        .widgetSurface(onHomeScreen: family.isHomeScreen)
    }
}

// MARK: - Home Screen

/// The clock wedge when something is worked, its rim alone otherwise.
struct TodaySymbol: View {
    let figures: TodayFigures

    var body: some View {
        if figures.worked > 0 || figures.startedAt != nil {
            ClockMark().fill(WidgetTheme.accent)
        } else {
            ClockRim().fill(WidgetTheme.accent)
        }
    }
}

/// Small: today's figure, a line, and Start or Stop.
struct TodaySmall: View {
    let figures: TodayFigures

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: String(localized: "Today")) { TodaySymbol(figures: figures) }
            if figures.entry.hasData {
                BigFigure(text: figures.headline)
                    .padding(.top, 11)
                    .accessibilityLabel(Text("Worked today"))
                    .accessibilityValue(Text(verbatim: figures.headline))
                if let line = figures.smallLine, !line.isEmpty {
                    SecondaryLine(text: line).padding(.top, 5)
                }
                Spacer(minLength: 6)
                if figures.snapshot.usesTimeClock {
                    ClockButton(isRunning: figures.startedAt != nil)
                }
            } else {
                Spacer(minLength: 0)
                EmptyStateView(state: figures.entry.state).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Medium: today on the left, the week's bars on the right.
struct TodayMedium: View {
    let figures: TodayFigures

    var body: some View {
        HStack(alignment: .top, spacing: 17) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(title: String(localized: "Today")) { TodaySymbol(figures: figures) }
                if figures.entry.hasData {
                    BigFigure(text: figures.headline).padding(.top, 11)
                    if let line = figures.isDayOff ? figures.weekLine : figures.ofExpected {
                        SecondaryLine(text: line).padding(.top, 5)
                    }
                    Spacer(minLength: 4)
                    if let bottom = figures.since ?? figures.usually ?? figures.offAt {
                        SecondaryLine(text: bottom)
                    }
                } else {
                    Spacer(minLength: 0)
                    EmptyStateView(state: figures.entry.state).frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: 125, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            if figures.entry.hasData, let chart = figures.chart {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: WidgetText.week(figures.snapshot.weekNumber))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(verbatim: figures.duration(chart.paidMinutes))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    }
                    Spacer(minLength: 6)
                    WeekBarsView(chart: chart, height: 90, spacing: 7, cornerRadius: 3, showsLabels: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - The week's bars, shared by Today, Week and the Lock Screen

/// Seven bars from the user's first weekday: worked filled in the accent,
/// leave outlined at the hours it credits, today in the primary colour, and
/// a dashed line where a normal day ends.
struct WeekBarsView: View {
    let chart: WidgetWeekChart
    var height: CGFloat
    var spacing: CGFloat
    var cornerRadius: CGFloat
    var showsLabels: Bool
    /// Monochrome, for the Lock Screen: shades of the primary colour.
    var isLockScreen: Bool = false
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(chart.columns, id: \.date) { column in
                        bar(column)
                            .frame(maxWidth: .infinity)
                            .accessibilityElement()
                            .accessibilityLabel(Text(column.date.date(in: calendar), format: .dateTime.weekday(.wide)))
                            .accessibilityValue(Text(verbatim: column.minutes > 0 ? DurationFormatting(style: .hoursAndMinutes).string(column.minutes) : "–"))
                    }
                }
                .frame(height: height, alignment: .bottom)

                if let target = chart.targetFraction {
                    TargetLine()
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(isLockScreen ? Color.primary.opacity(0.45) : Color.secondary.opacity(0.5))
                        .frame(height: 1)
                        .offset(y: -height * min(target, 1))
                        .accessibilityHidden(true)
                }
            }
            .frame(height: height)

            if showsLabels {
                HStack(spacing: spacing) {
                    ForEach(chart.columns, id: \.date) { column in
                        Text(verbatim: WidgetText.weekdayLetter(column.date))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(column.isToday ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func bar(_ column: WidgetWeekColumn) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let barHeight = max(height * column.fraction, 2)
        switch column.style {
        case .worked:
            shape
                .fill(isLockScreen ? AnyShapeStyle(Color.primary.opacity(0.8)) : AnyShapeStyle(WidgetTheme.accent))
                .frame(height: barHeight)
                .widgetAccentable()
        case .leave:
            shape
                .strokeBorder(isLockScreen ? Color.primary.opacity(0.8) : WidgetTheme.accent, lineWidth: 1.25)
                .frame(height: barHeight)
                .widgetAccentable()
        case .today:
            shape
                .fill(Color.primary)
                .frame(height: column.minutes > 0 ? barHeight : 2)
        case .empty:
            Capsule()
                .fill(isLockScreen ? AnyShapeStyle(Color.primary.opacity(0.35)) : AnyShapeStyle(WidgetTheme.track))
                .frame(height: 2.5)
        }
    }
}

/// A horizontal line across the chart.
private struct TargetLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Lock Screen

/// The day filled like the app icon, the figure, and "of 8:00".
struct TodayCircular: View {
    let figures: TodayFigures

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if figures.entry.hasData {
                DayWedge(fraction: figures.fraction ?? 0)
                    .fill(Color.primary.opacity(0.28))
                    .padding(2.5)
                    .widgetAccentable()
                Ticks()
                    .stroke(Color.primary.opacity(0.7), lineWidth: 1)
                VStack(spacing: 0) {
                    Text(verbatim: compactHours(figures.worked))
                        .font(.lockFigure(size: 20))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    if figures.expected > 0 {
                        Text(verbatim: String(localized: "of \(compactHours(figures.expected))"))
                            .font(.system(size: 8.5))
                            .opacity(0.75)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 6)
            } else {
                ClockMark()
                    .frame(width: 18, height: 18)
                    .widgetAccentable()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Worked today"))
        .accessibilityValue(Text(verbatim: figures.duration(figures.worked)))
    }

    /// A circular accessory is about four characters wide, so the chosen
    /// duration style does not fit and clock notation is used regardless.
    private func compactHours(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

/// The quarter-hour ticks at twelve, three, six and nine.
private struct Ticks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        for (dx, dy) in [(0.0, -1.0), (1.0, 0.0), (0.0, 1.0), (-1.0, 0.0)] {
            path.move(to: CGPoint(x: c.x + dx * (r - 1), y: c.y + dy * (r - 1)))
            path.addLine(to: CGPoint(x: c.x + dx * (r - 3), y: c.y + dy * (r - 3)))
        }
        return path
    }
}

/// "TODAY / 6:09 / 8:00 / running since 07:02 · off 15:30". The label is
/// said once, in the header; nothing under it says "today" again.
struct TodayRectangular: View {
    let figures: TodayFigures

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if figures.entry.hasData {
                HStack(spacing: 5) {
                    Group {
                        if figures.isDayOff { ClockRim() } else { ClockMark() }
                    }
                    .frame(width: 12, height: 12)
                    .widgetAccentable()
                    Text(verbatim: label.uppercased())
                        .font(.lockLabel)
                        .tracking(0.6)
                        .opacity(0.72)
                        .lineLimit(1)
                }
                if figures.isDayOff {
                    Text(verbatim: figures.headline)
                        .font(.lockFigure())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .widgetAccentable()
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(verbatim: figures.duration(figures.worked))
                            .font(.lockFigure())
                            .lineLimit(1)
                            .widgetAccentable()
                        if figures.expected > 0 {
                            Text(verbatim: "/ " + figures.duration(figures.expected))
                                .font(.system(size: 14).monospacedDigit())
                                .opacity(0.6)
                                .lineLimit(1)
                        }
                    }
                    .minimumScaleFactor(0.6)
                }
                if let line {
                    Text(verbatim: line)
                        .font(.lockLine)
                        .opacity(0.78)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            } else {
                EmptyStateView(state: figures.entry.state, compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// "Today", or the weekday's name on a day off: "Saturday".
    private var label: String {
        figures.isDayOff
            ? figures.entry.date.formatted(.dateTime.weekday(.wide))
            : String(localized: "Today")
    }

    private var line: String? {
        switch figures.state {
        case let .running(since):
            let running = String(
                localized: "running since \(WidgetText.clockTime(since))",
                comment: "Lock Screen, the running clock and when it started"
            )
            return [running, figures.offAt].compactMap { $0 }.joined(separator: " · ")
        case .idle:
            return figures.usually ?? figures.offAt ?? figures.weekLine
        case .dayOff:
            return figures.weekLine
        }
    }
}

/// Above the clock: "6:09 today · week 40:24".
struct TodayInline: View {
    let figures: TodayFigures

    var body: some View {
        if figures.entry.hasData {
            Label {
                Text(verbatim: line)
            } icon: {
                Image(systemName: "clock")
            }
        } else {
            Label("Open Zeitkonto", systemImage: "clock.badge.questionmark")
        }
    }

    private var line: String {
        let today = String(
            localized: "\(figures.duration(figures.worked)) today",
            comment: "Lock Screen, the hours worked today"
        )
        guard let chart = figures.chart else { return today }
        let week = String(
            localized: "week \(figures.duration(chart.paidMinutes))",
            comment: "Lock Screen above the clock, the week's hours after today's"
        )
        return today + " · " + week
    }
}
