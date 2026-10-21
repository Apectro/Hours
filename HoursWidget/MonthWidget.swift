import SwiftUI
import WidgetKit

/// The month at a glance: the balance, and a square for each working day.
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

/// The figures every Month family reads.
struct MonthFigures {
    let entry: HoursEntry
    let calendar = Calendar.current

    var snapshot: WidgetSnapshot { entry.snapshot }
    var worked: Int { snapshot.monthWorked(at: entry.date, calendar: calendar) }
    var expected: Int { snapshot.monthExpected(at: entry.date, calendar: calendar) }
    var balance: Int { snapshot.monthBalance(at: entry.date, calendar: calendar) }
    var fraction: Double? { snapshot.monthFraction(at: entry.date, calendar: calendar) }
    var marks: [WidgetDayMark] { snapshot.monthMarks(at: entry.date, calendar: calendar) }
    /// The month's earnings, while they are what the app leads with.
    var earned: Int? { snapshot.monthEarnings(at: entry.date, calendar: calendar) }

    func duration(_ minutes: Int) -> String { snapshot.formatting.string(minutes) }

    /// "OCTOBER", in the phone's language.
    var monthName: String {
        entry.date.formatted(.dateTime.month(.wide)).uppercased()
    }

    /// The big figure: what the month earned, the balance, or the hours
    /// themselves for someone who has switched the balance off.
    var headline: String {
        if let earned, let money = snapshot.money { return money.string(earned, showsCents: false) }
        return snapshot.showsBalance ? snapshot.formatting.signedString(balance) : duration(worked)
    }

    var verdict: String {
        if earned != nil {
            return String(localized: "this month · \(duration(worked))", comment: "Widget, under the month's earnings; the value is the hours worked")
        }
        guard snapshot.showsBalance else {
            return String(localized: "of \(duration(expected))", comment: "Widget, the month's target beneath the hours worked so far")
        }
        if balance > 0 { return String(localized: "ahead of plan") }
        if balance < 0 { return String(localized: "behind plan") }
        return String(localized: "on plan")
    }
}

struct MonthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: MonthInline(figures: MonthFigures(entry: entry))
            case .accessoryRectangular: MonthRectangular(figures: MonthFigures(entry: entry))
            case .systemMedium: MonthMedium(figures: MonthFigures(entry: entry))
            default: MonthSmall(figures: MonthFigures(entry: entry))
            }
        }
        .widgetCard(.amber, onHomeScreen: family == .systemSmall || family == .systemMedium)
    }
}

// MARK: - Home Screen

/// Board 11, top right: the month's name and hours, the balance in large,
/// and a square per working day.
struct MonthSmall: View {
    let figures: MonthFigures

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                WidgetHeading(text: Text(verbatim: figures.monthName), color: WidgetPalette.navy)
                Spacer(minLength: 4)
                // With earnings the hours are under the figure instead.
                if figures.entry.hasData, figures.snapshot.showsBalance, figures.earned == nil {
                    Text(figures.duration(figures.worked))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetPalette.navy.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            if figures.entry.hasData {
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(figures.headline)
                        .font(.widgetFigure(size: 34, weight: .heavy))
                        .foregroundStyle(WidgetPalette.navy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .widgetAccentable()
                    Text(figures.verdict)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetPalette.navy.opacity(0.75))
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 4)
                DaySquares(marks: figures.marks)
            } else {
                Spacer(minLength: 0)
                EmptyStateView(state: figures.entry.state, compact: false)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct MonthMedium: View {
    let figures: MonthFigures

    var body: some View {
        HStack(spacing: 16) {
            MonthSmall(figures: figures)
            if figures.entry.hasData, let fraction = figures.fraction {
                VStack(spacing: 6) {
                    ZStack {
                        ProgressRing(fraction: fraction, tint: WidgetPalette.navy, lineWidth: 8)
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.widgetFigure(size: 15))
                            .foregroundStyle(WidgetPalette.navy)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 10)
                    }
                    .frame(width: 72, height: 72)
                    if figures.snapshot.unrecordedDayCount > 0 {
                        Text(UnrecordedDays.text(figures.snapshot.unrecordedDayCount))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(WidgetPalette.navy.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// One square per working day: done, short, today, still to come.
///
/// Rows of eleven, as the design has them, so a month of twenty-odd working
/// days is two rows and a short month still lines up.
struct DaySquares: View {
    let marks: [WidgetDayMark]
    @Environment(\.widgetRenderingMode) private var renderingMode

    private static let perRow = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(stride(from: 0, to: marks.count, by: Self.perRow)), id: \.self) { start in
                HStack(spacing: 3) {
                    ForEach(start..<min(start + Self.perRow, marks.count), id: \.self) { index in
                        square(marks[index].state)
                    }
                    // Empty places keep a short last row aligned with the one above.
                    ForEach(0..<(Self.perRow - min(Self.perRow, marks.count - start)), id: \.self) { _ in
                        Color.clear.frame(height: 8)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private func square(_ state: WidgetDayMark.State) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        switch state {
        case .done:
            shape.fill(WidgetPalette.navy).frame(height: 8).widgetAccentable()
        case .short:
            shape.fill(WidgetPalette.navy.opacity(0.45)).frame(height: 8)
        case .toCome:
            shape.fill(WidgetPalette.navy.opacity(0.15)).frame(height: 8)
        case .today:
            // White on amber in full colour; tinted, white would read as
            // "done", so today is an outline there.
            if renderingMode.isFullColor {
                shape.fill(Color.white).frame(height: 8)
            } else {
                shape.strokeBorder(Color.primary, lineWidth: 1.5).frame(height: 8).widgetAccentable()
            }
        }
    }

    private var accessibilitySummary: String {
        let done = marks.filter { $0.state == .done }.count
        let short = marks.filter { $0.state == .short }.count
        return String(
            localized: "Working days: \(done) done, \(short) short",
            comment: "VoiceOver, the month widget's squares"
        )
    }
}

// MARK: - Lock Screen

struct MonthRectangular: View {
    let figures: MonthFigures

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if figures.entry.hasData {
                HStack(spacing: 4) {
                    HardHat()
                        .frame(width: 11, height: 6)
                        .widgetAccentable()
                    Text("This month")
                        .font(.caption.weight(.bold))
                }
                Text(figures.headline)
                    .font(.widgetFigure(.headline, weight: .bold))
                    .widgetAccentable()
                Text(figures.snapshot.showsBalance || figures.earned != nil ? figures.verdict : String(localized: "of \(figures.duration(figures.expected))", comment: "Widget, the month's target beneath the hours worked so far"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                EmptyStateView(state: figures.entry.state, compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MonthInline: View {
    let figures: MonthFigures

    var body: some View {
        if figures.entry.hasData, figures.earned != nil {
            Label(
                String(
                    localized: "\(figures.headline) month",
                    comment: "Lock Screen and widgets, the month's balance in two words"
                ),
                systemImage: "calendar"
            )
        } else if figures.entry.hasData, figures.snapshot.showsBalance {
            Label(
                String(
                    localized: "\(figures.snapshot.formatting.signedString(figures.balance)) month",
                    comment: "Lock Screen and widgets, the month's balance in two words"
                ),
                systemImage: "calendar"
            )
        } else if figures.entry.hasData {
            Label(figures.duration(figures.worked), systemImage: "calendar")
        } else {
            Label("Open Zeitkonto", systemImage: "calendar")
        }
    }
}
