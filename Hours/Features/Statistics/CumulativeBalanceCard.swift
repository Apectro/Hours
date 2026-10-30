import SwiftUI
import SwiftData
import Charts

/// The running balance, from the opening figure to a given day: a list
/// section with the figure, its line through the period, and what it
/// covers in the footer (design v2: no card).
///
/// Always recomputed from the days themselves, never stored, so correcting a
/// day recorded months ago fixes this number too.
struct CumulativeBalanceCard: View {
    let through: CalendarDate
    /// The period the line runs through (1.2); nil for the figure alone.
    var trend: CalendarDateRange?
    let settings: AppSettings
    let calendar: Calendar

    @Query private var entries: [DayEntry]
    @Query private var holidayRecords: [HolidayRecord]
    @Environment(\.modelContext) private var modelContext

    init(through: CalendarDate, trend: CalendarDateRange? = nil, settings: AppSettings, calendar: Calendar) {
        self.through = through
        self.trend = trend
        self.settings = settings
        self.calendar = calendar
        let upper = through.key
        _entries = Query(
            filter: #Predicate<DayEntry> { $0.dateKey <= upper },
            sort: \DayEntry.dateKey
        )
        _holidayRecords = Query(sort: \HolidayRecord.name)
    }

    var body: some View {
        Section {
            let balance = self.balance
            InsightsRow(title: String(localized: "Balance")) {
                BalanceText(
                    minutes: balance,
                    formatting: settings.displayFormatting,
                    font: .title3.weight(.semibold).monospacedDigit()
                )
            }

            let points = trendPoints(endingAt: balance)
            if points.count > 1 {
                BalanceTrendChart(points: points, calendar: calendar)
                    .padding(.vertical, Metrics.small)
            }

            if let available = overtimeAvailable(balance) {
                Text(available)
                    .monospacedDigit()
                    .foregroundStyle(Color.hoursPositive)
                    .accessibilityIdentifier("insights-overtime-available")
            }
        } header: {
            Text("Running balance")
        } footer: {
            Text(caption)
        }
    }

    /// The line: the balance at the end of each day of the period, through
    /// today, ending at the figure above (`BalanceTrend`).
    private func trendPoints(endingAt balance: Int) -> [BalanceTrend.Point] {
        guard let trend else { return [] }
        var records: [Int: DayRecord] = [:]
        for entry in entries where entry.dateKey >= trend.start.key && entry.dateKey <= trend.end.key {
            records[entry.dateKey] = entry.record
        }
        let days = PeriodEngine(
            settings: settings,
            calendar: calendar,
            firstRecorded: WorkdayRepository(context: modelContext).firstRecordedDate()
        ).days(in: trend, records: records, holidays: holidayRecords.map(\.rule))
        return BalanceTrend.points(
            days: days,
            endingMinutes: balance,
            through: min(trend.end, CalendarDate.today(in: calendar))
        )
    }

    private var balance: Int {
        // A closed year behaves exactly as the opening balance always did: a
        // figure, and a date before which days do not count. So carry-over
        // arrives here as a different origin rather than as a second concept.
        //
        // The engine's `runningBalance` is the one rule for this, shared with
        // the export and with closing a year, so the three cannot drift apart.
        var records: [Int: DayRecord] = [:]
        for entry in entries { records[entry.dateKey] = entry.record }

        // The first recorded day from the store rather than from `entries`,
        // which holds only calendar days: a site day written before any of
        // them is where everything else starts the balance, so it starts here.
        return PeriodEngine(
            settings: settings,
            calendar: calendar,
            firstRecorded: WorkdayRepository(context: modelContext).firstRecordedDate()
        ).runningBalance(
            through: through,
            holidays: holidayRecords.map(\.rule),
            countingThrough: CalendarDate.today(in: calendar),
            records: { _ in records }
        )
    }

    /// "Overtime available: +12h 30m · about 1.5 days off", from the week in
    /// force on the last day the balance covers, or today if that is later.
    private func overtimeAvailable(_ balance: Int) -> String? {
        let day = min(through, CalendarDate.today(in: calendar))
        guard let available = OvertimeAvailable(balanceMinutes: balance, on: day, settings: settings) else { return nil }
        let amount = settings.displayFormatting.signedString(available.minutes)
        switch available.daysOff {
        case .some(let days) where days == HalfDays(days: 1):
            return String(
                localized: "Overtime available: \(amount) · about 1 day off",
                comment: "Insights, under the running balance; the value is a duration"
            )
        case .some(let days) where days > .zero:
            return String(
                localized: "Overtime available: \(amount) · about \(days.localized) days off",
                comment: "Insights, under the running balance; a duration, then a number of days such as 1.5"
            )
        default:
            return String(
                localized: "Overtime available: \(amount)",
                comment: "Insights, under the running balance; the value is a duration"
            )
        }
    }

    private var caption: String {
        let formatting = CalendarFormatting(locale: .current, calendar: calendar)
        if let start = settings.balanceStartDate {
            return String(
                localized: "Since \(formatting.mediumDate(start)), through \(formatting.mediumDate(through)).",
                comment: "What span the running balance covers"
            )
        }
        return String(
                localized: "Everything recorded through \(formatting.mediumDate(through)).",
                comment: "The running balance covers everything up to this date"
            )
    }
}

/// The running balance as a line, with zero marked.
private struct BalanceTrendChart: View {
    let points: [BalanceTrend.Point]
    let calendar: Calendar

    var body: some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(Color.hoursSubdued)
            ForEach(points, id: \.date) { point in
                LineMark(
                    x: .value("Date", point.date.date(in: calendar), unit: .day),
                    y: .value("Balance", Double(point.minutes) / 60.0)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.hoursBalance(points.last?.minutes ?? 0))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(verbatim: "\(Int(hours))h")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 140)
        .accessibilityLabel(Text("Running balance"))
    }
}
