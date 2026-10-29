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
        }
        .configurationDisplayName("This week")
        .description("Hours this week, day by day.")
        // Medium stays so a Week widget placed before 1.2 survives the
        // update; the design adds small, large and the Lock Screen.
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct WeekFigures {
    let entry: HoursEntry
    let calendar = Calendar.current

    var snapshot: WidgetSnapshot { entry.snapshot }
    var chart: WidgetWeekChart? { snapshot.weekChart(at: entry.date, calendar: calendar) }
    var rows: [WidgetWeekRow]? { snapshot.weekRows(at: entry.date, calendar: calendar) }
    var title: String { WidgetText.week(snapshot.weekNumber) }

    func duration(_ minutes: Int) -> String { snapshot.formatting.string(minutes) }
    func signed(_ minutes: Int) -> String { snapshot.formatting.signedString(minutes) }

    /// "of 40:00", and "· +0:24" where the app keeps a balance.
    var ofTarget: String? {
        guard let chart, chart.expectedMinutes > 0 else { return nil }
        let of = String(localized: "of \(duration(chart.expectedMinutes))")
        return snapshot.showsBalance ? of + " · " + signed(chart.balanceMinutes) : of
    }
}

struct WeekWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry

    var body: some View {
        let figures = WeekFigures(entry: entry)
        Group {
            switch family {
            case .accessoryRectangular: WeekRectangular(figures: figures)
            case .systemLarge: WeekLarge(figures: figures)
            case .systemMedium: WeekMedium(figures: figures)
            default: WeekSmall(figures: figures)
            }
        }
        .widgetSurface(onHomeScreen: family.isHomeScreen)
    }
}

/// The week's figure over seven small bars.
struct WeekSmall: View {
    let figures: WeekFigures

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: String(localized: "Week", comment: "Widget header, the week widget"), systemImage: "chart.bar.fill")
            if figures.entry.hasData, let chart = figures.chart {
                BigFigure(text: figures.duration(chart.paidMinutes)).padding(.top, 11)
                if chart.expectedMinutes > 0 {
                    SecondaryLine(text: String(localized: "of \(figures.duration(chart.expectedMinutes))")).padding(.top, 5)
                }
                Spacer(minLength: 6)
                WeekBarsView(chart: chart, height: 31, spacing: 5, cornerRadius: 2, showsLabels: false)
            } else {
                WeekWaiting(entry: figures.entry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The week's figure on the left, its bars with the days on the right.
struct WeekMedium: View {
    let figures: WeekFigures

    var body: some View {
        HStack(alignment: .top, spacing: 17) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(title: figures.title, systemImage: "chart.bar.fill")
                if figures.entry.hasData, let chart = figures.chart {
                    BigFigure(text: figures.duration(chart.paidMinutes)).padding(.top, 11)
                    if let line = figures.ofTarget { SecondaryLine(text: line).padding(.top, 5) }
                    Spacer(minLength: 0)
                } else {
                    WeekWaiting(entry: figures.entry)
                }
            }
            .frame(width: 125, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            if figures.entry.hasData, let chart = figures.chart {
                WeekBarsView(chart: chart, height: 100, spacing: 7, cornerRadius: 3, showsLabels: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

/// Large: the time card as a list — each day's from–to and hours, leave in
/// the secondary colour, today "now" while the clock runs, the days still to
/// come dimmed, and the balance and the site at the foot.
struct WeekLarge: View {
    let figures: WeekFigures
    private let calendar = Calendar.current

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    WidgetHeader(title: figures.title, systemImage: "chart.bar.fill")
                    if let span {
                        Text(verbatim: span).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if figures.entry.hasData, let chart = figures.chart {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(verbatim: figures.duration(chart.paidMinutes))
                            .font(.widgetFigure(size: 32))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .widgetAccentable()
                        if let line = figures.ofTarget {
                            Text(verbatim: line).font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if figures.entry.hasData, let rows = figures.rows {
                VStack(spacing: 0) {
                    ForEach(rows, id: \.day.date) { row in
                        WeekListRow(row: row, figures: figures)
                    }
                }
                .padding(.top, 13)
                Spacer(minLength: 6)
                HStack {
                    if let balance = figures.snapshot.totalBalanceMinutes {
                        Text(verbatim: String(localized: "Balance \(figures.signed(balance))", comment: "Widget, the running balance"))
                    }
                    Spacer(minLength: 8)
                    if let site = figures.snapshot.site?.name {
                        Text(verbatim: site).lineLimit(1)
                    }
                }
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                WeekWaiting(entry: figures.entry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// "19–25 October".
    private var span: String? {
        guard let first = figures.rows?.first?.day.date, let last = figures.rows?.last?.day.date else { return nil }
        let from = first.date(in: calendar)
        let to = last.date(in: calendar)
        if first.month == last.month {
            return from.formatted(.dateTime.day()) + "–" + to.formatted(.dateTime.day().month(.wide))
        }
        return from.formatted(.dateTime.day().month(.abbreviated)) + " – " + to.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// "Mon 19   07:00 – 15:30   8:00".
struct WeekListRow: View {
    let row: WidgetWeekRow
    let figures: WeekFigures
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(WidgetTheme.rule).frame(height: 0.75)
            HStack(spacing: 8) {
                Text(verbatim: dayName)
                    .fontWeight(row.isToday ? .semibold : .regular)
                    .foregroundStyle(row.isToday ? Color.primary : Color.secondary)
                    .frame(width: 62, alignment: .leading)
                middle
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: figure)
                    .fontWeight(row.isToday ? .semibold : .regular)
                    .foregroundStyle(isQuiet ? Color.secondary : Color.primary)
                    .frame(width: 54, alignment: .trailing)
            }
            .font(.system(size: 12.5).monospacedDigit())
            .lineLimit(1)
            .frame(height: 30)
        }
        .opacity(row.isFuture && row.paidMinutes == 0 && row.day.creditedMinutes == 0 ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    private var isQuiet: Bool { row.day.kind != .work && row.day.workedMinutes == 0 }

    private var dayName: String {
        row.day.date.date(in: calendar).formatted(.dateTime.weekday(.abbreviated).day())
    }

    private var figure: String {
        if row.isToday { return figures.duration(row.paidMinutes) }
        if row.isFuture && row.day.creditedMinutes == 0 { return "" }
        return row.paidMinutes > 0 ? figures.duration(row.paidMinutes) : ""
    }

    @ViewBuilder
    private var middle: some View {
        if row.isRunning, let started = figures.snapshot.clockStartedAt {
            HStack(spacing: 6) {
                Text(verbatim: (row.day.start.map { WidgetText.time($0, on: figures.entry.date) } ?? WidgetText.clockTime(started)) + " –")
                Circle().fill(WidgetTheme.accent).frame(width: 5.5, height: 5.5).widgetAccentable()
                Text("now", comment: "Widget week list, the running clock's end")
                    .foregroundStyle(WidgetTheme.accent)
                    .widgetAccentable()
            }
        } else if let start = row.day.start, let end = row.day.end, row.day.workedMinutes > 0 || row.isToday {
            Text(verbatim: WidgetText.time(start, on: figures.entry.date) + " – " + WidgetText.time(end, on: figures.entry.date))
        } else if let name = row.day.typeName {
            Text(verbatim: name).foregroundStyle(.secondary)
        } else {
            Text(verbatim: "")
        }
    }
}

/// The empty states, under a header that is already drawn.
private struct WeekWaiting: View {
    let entry: HoursEntry

    var body: some View {
        Spacer(minLength: 0)
        if entry.hasData {
            QuietNote(text: String(localized: "Open Zeitkonto once to fill this in"))
        } else {
            EmptyStateView(state: entry.state).frame(maxWidth: .infinity)
        }
        Spacer(minLength: 0)
    }
}

// MARK: - Lock Screen

/// "WEEK 43 · 40:24" over the bars and the days, leave outlined, today
/// full white, the target dashed.
struct WeekRectangular: View {
    let figures: WeekFigures

    var body: some View {
        if figures.entry.hasData, let chart = figures.chart {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: figures.title.uppercased())
                        .font(.lockLabel)
                        .tracking(0.6)
                        .opacity(0.72)
                    Spacer(minLength: 4)
                    Text(verbatim: figures.duration(chart.paidMinutes))
                        .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                        .widgetAccentable()
                }
                WeekBarsView(chart: chart, height: 24, spacing: 5, cornerRadius: 2, showsLabels: true, isLockScreen: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            EmptyStateView(state: figures.entry.state, compact: true)
        }
    }
}
