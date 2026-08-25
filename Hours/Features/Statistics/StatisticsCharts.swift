import SwiftUI
import Charts

/// Hours worked per day, with the contracted day as a reference line.
///
/// A chart is here because the shape of a month — which days ran long, which
/// were empty — is genuinely easier to see than to read.
struct DailyHoursChart: View {
    let days: [DayComputation]
    let calendar: Calendar
    let referenceHours: Double?

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Date", day.date.date(in: calendar), unit: .day),
                    y: .value("Hours", hours(for: day))
                )
                .foregroundStyle(color(for: day))
                .cornerRadius(2)
            }

            if let referenceHours, referenceHours > 0 {
                RuleMark(y: .value("Contracted", referenceHours))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.hoursSubdued)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text("\(Int(hours))h")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day())
            }
        }
        .frame(height: 180)
        .accessibilityLabel("Hours worked per day")
    }

    /// A day of paid absence is plotted at its credited hours, in the day
    /// type's own colour. Plotting only worked time would draw a fortnight of
    /// leave as a fortnight of nothing, which is the opposite of what happened.
    private func hours(for day: DayComputation) -> Double {
        let minutes = day.workedMinutes > 0 ? day.workedMinutes : day.creditedMinutes
        return Double(minutes) / 60.0
    }

    private func color(for day: DayComputation) -> Color {
        if day.creditedMinutes > 0 && day.workedMinutes == 0 { return day.dayType.tint.color }
        return day.balanceMinutes > 0 ? Color.hoursPositive : Color.accentColor
    }
}

/// Monthly balance as bars, with the running balance as a line over the top.
///
/// Both series are in hours, so they share one axis honestly rather than being
/// forced onto two scales that invite a false comparison.
struct MonthlyBalanceChart: View {
    let points: [MonthlyBalancePoint]
    let formatting: CalendarFormatting
    let showsCumulative: Bool

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Month", formatting.monthAbbreviation(point.month)),
                    y: .value("Balance", Double(point.balanceMinutes) / 60.0)
                )
                .foregroundStyle(point.balanceMinutes >= 0 ? Color.hoursPositive : Color.hoursNegative)
                .cornerRadius(2)
            }

            if showsCumulative {
                ForEach(points) { point in
                    LineMark(
                        x: .value("Month", formatting.monthAbbreviation(point.month)),
                        y: .value("Running balance", Double(point.cumulativeMinutes) / 60.0),
                        series: .value("Series", "Running")
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Month", formatting.monthAbbreviation(point.month)),
                        y: .value("Running balance", Double(point.cumulativeMinutes) / 60.0)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(18)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text("\(Int(hours))h")
                    }
                }
            }
        }
        .frame(height: 200)
        .accessibilityLabel("Balance by month")
    }
}
