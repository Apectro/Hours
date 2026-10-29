import SwiftUI
import WidgetKit

/// The month at a glance: its hours, the balance, the money, and a dot for
/// every day.
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
        // Small stays so a Month widget placed before 1.2 survives the update.
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

/// The figures every Month family reads.
struct MonthFigures {
    let entry: HoursEntry
    let calendar = Calendar.current

    var snapshot: WidgetSnapshot { entry.snapshot }
    var worked: Int { snapshot.monthWorked(at: entry.date, calendar: calendar) }
    var balance: Int { snapshot.monthBalance(at: entry.date, calendar: calendar) }
    var days: [WidgetMonthDay] { snapshot.monthDays(at: entry.date, calendar: calendar) }
    var earned: WidgetMonthEarned? { snapshot.monthEarned(at: entry.date, calendar: calendar) }

    /// "October".
    var monthName: String { WidgetText.monthName(entry.date) }
    /// "106 h".
    var hours: String { WidgetText.wholeHours(worked) }

    /// "1.088 €", while a rate is set.
    var money: String? {
        guard let earned else { return nil }
        return MoneyFormatting(currencyCode: earned.currencyCode).string(earned.totalCents, showsCents: false)
    }

    /// "balance +3:30", where the app keeps a balance.
    var balanceLine: String? {
        guard snapshot.showsBalance else { return nil }
        return String(
            localized: "balance \(snapshot.formatting.signedString(balance))",
            comment: "Widget, the month's balance after its hours, e.g. balance +3:30"
        )
    }
}

struct MonthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry

    var body: some View {
        let figures = MonthFigures(entry: entry)
        Group {
            switch family {
            case .accessoryInline: MonthInline(figures: figures)
            case .accessoryRectangular: MonthRectangular(figures: figures)
            case .systemMedium: MonthMedium(figures: figures)
            default: MonthSmall(figures: figures)
            }
        }
        .widgetSurface(onHomeScreen: family.isHomeScreen)
    }
}

// MARK: - Home Screen

/// "October / 106 h / balance +3:30 / 1.088 €".
struct MonthColumn: View {
    let figures: MonthFigures

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: figures.monthName, systemImage: "calendar")
            if figures.entry.hasData {
                BigFigure(text: figures.hours).padding(.top, 11)
                if let line = figures.balanceLine { SecondaryLine(text: line).padding(.top, 5) }
                Spacer(minLength: 4)
                if let money = figures.money { SecondaryLine(text: money) }
            } else {
                Spacer(minLength: 0)
                EmptyStateView(state: figures.entry.state).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MonthSmall: View {
    let figures: MonthFigures

    var body: some View {
        MonthColumn(figures: figures)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The month's figures beside a dot for every day: filled worked, a ring for
/// leave, dashed for sick, a small dot for a weekend, an empty disc for a
/// day still to come, today ringed.
struct MonthMedium: View {
    let figures: MonthFigures

    var body: some View {
        HStack(alignment: .top, spacing: 17) {
            MonthColumn(figures: figures).frame(width: 125, alignment: .leading)
            if figures.entry.hasData, !figures.days.isEmpty {
                MonthDots(days: figures.days, firstWeekday: figures.snapshot.week?.firstWeekday ?? Calendar.current.firstWeekday)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct MonthDots: View {
    let days: [WidgetMonthDay]
    /// The user's own first weekday, which the snapshot carries.
    let firstWeekday: Int
    private let calendar = Calendar.current

    /// Blank places before the first day, from the phone's first weekday.
    private var leading: Int {
        guard let first = days.first else { return 0 }
        return (first.date.weekday(in: calendar) - firstWeekday + 7) % 7
    }

    private var weekdayLetters: [String] {
        let symbols = CalendarFormatting(locale: .current, calendar: calendar)
        return (0..<7).map { offset in
            symbols.veryShortWeekdaySymbol(for: (firstWeekday - 1 + offset) % 7 + 1)
        }
    }

    var body: some View {
        let cells: [WidgetMonthDay?] = Array(repeating: nil, count: leading) + days.map(Optional.some)
        let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(verbatim: letter)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { index in
                        Group {
                            if index < row.count, let day = row[index] { DayDot(kind: day.kind) } else { Color.clear }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 16)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: summary))
    }

    private var summary: String {
        let worked = days.filter { $0.kind == .worked }.count
        let missing = days.filter { $0.kind == .missing }.count
        return String(
            localized: "Working days: \(worked) done, \(missing) short",
            comment: "VoiceOver, the month widget's squares"
        )
    }
}

/// One day's dot, 8pt across.
struct DayDot: View {
    let kind: WidgetMonthDay.Kind
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        switch kind {
        case .worked:
            Circle().fill(WidgetTheme.accent).frame(width: 8, height: 8).widgetAccentable()
        case .leave:
            Circle().strokeBorder(WidgetTheme.accent, lineWidth: 1.25).frame(width: 8, height: 8).widgetAccentable()
        case .sick:
            Circle()
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.25, dash: [1.6, 1.4]))
                .frame(width: 8, height: 8)
        case .off:
            Circle().fill(Color.secondary.opacity(0.45)).frame(width: 3, height: 3)
        case .missing:
            Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1).frame(width: 8, height: 8)
        case .future:
            Circle().fill(renderingMode.isFullColor ? WidgetTheme.fill : Color.primary.opacity(0.15)).frame(width: 8, height: 8)
        case .today:
            Circle()
                .fill(Color.primary)
                .frame(width: 8, height: 8)
                .padding(2)
                .overlay(Circle().stroke(Color.primary, lineWidth: 1))
        }
    }
}

// MARK: - Lock Screen

/// "OCTOBER / 1.088 € / 106 h · balance +3:30"; without a rate the hours
/// are the figure and there is no money.
struct MonthRectangular: View {
    let figures: MonthFigures

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if figures.entry.hasData {
                HStack(spacing: 5) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .widgetAccentable()
                    Text(verbatim: figures.monthName.uppercased())
                        .font(.lockLabel)
                        .tracking(0.6)
                        .opacity(0.72)
                        .lineLimit(1)
                }
                Text(verbatim: figures.money ?? figures.hours)
                    .font(.lockFigure())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
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

    private var line: String? {
        let parts = (figures.money != nil ? [figures.hours] : []) + [figures.balanceLine].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Above the clock: "October 106 h · +3:30".
struct MonthInline: View {
    let figures: MonthFigures

    var body: some View {
        if figures.entry.hasData {
            Label {
                Text(verbatim: line)
            } icon: {
                Image(systemName: "calendar")
            }
        } else {
            Label("Open Zeitkonto", systemImage: "calendar")
        }
    }

    private var line: String {
        var parts = [figures.monthName, figures.money ?? figures.hours]
        if figures.snapshot.showsBalance { parts.append(figures.snapshot.formatting.signedString(figures.balance)) }
        return parts.joined(separator: " · ")
    }
}
