import SwiftUI
import Charts

/// Hours worked per day in the accent colour, with the normal day as a
/// dashed rule and few labels (design v2, More board phone 2).
///
/// A chart is here because the shape of a month — which days ran long, which
/// were empty — is genuinely easier to see than to read.
struct DailyHoursChart: View {
    let days: [DayComputation]
    let calendar: Calendar
    let referenceHours: Double?
    /// His duration format, for the axis and the callout.
    let duration: DurationFormatting
    let formatting: CalendarFormatting

    /// The day under his finger: tapping or dragging over a bar shows
    /// "Thu 29  10h 30m" over it (polish, 2026-11).
    @State private var selectedDate: Date?
    /// The last day touched, kept once the finger lifts so a tap leaves
    /// its callout up. A day outside the period shows nothing.
    @State private var shownDate: Date?

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Date", day.date.date(in: calendar), unit: .day),
                    y: .value("Hours", hours(for: day))
                )
                .foregroundStyle(color(for: day))
                .opacity(selectedDay == nil || selectedDay?.date == day.date ? 1 : 0.6)
                .cornerRadius(3)
            }

            if let referenceHours, referenceHours > 0 {
                RuleMark(y: .value("Contracted", referenceHours))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.hoursSubdued)
            }

            if let selectedDay {
                RuleMark(x: .value("Date", selectedDay.date.date(in: calendar), unit: .day))
                    .foregroundStyle(Color.hoursSubdued.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                    ) {
                        ChartCallout(
                            label: formatting.shortWeekdayAndDay(selectedDay.date),
                            value: duration.string(minutes(for: selectedDay))
                        )
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .onChange(of: selectedDate) { _, date in
            if let date { shownDate = date }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(verbatim: duration.axisString(hours: hours))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.day())
            }
        }
        .frame(height: 160)
        .accessibilityLabel("Hours worked per day")
        .accessibilityIdentifier("insights-chart")
    }

    private var selectedDay: DayComputation? {
        guard let shown = selectedDate ?? shownDate else { return nil }
        let date = CalendarDate(shown, calendar: calendar)
        return days.first { $0.date == date }
    }

    private func minutes(for day: DayComputation) -> Int {
        day.workedMinutes > 0 ? day.workedMinutes : day.creditedMinutes
    }

    /// A day of paid absence is plotted at its credited hours, in the day
    /// type's own colour. Plotting only worked time would draw a fortnight of
    /// leave as a fortnight of nothing, which is the opposite of what happened.
    private func hours(for day: DayComputation) -> Double {
        Double(minutes(for: day)) / 60.0
    }

    private func color(for day: DayComputation) -> Color {
        if day.creditedMinutes > 0 && day.workedMinutes == 0 { return day.dayType.tint.color }
        return Color.accentColor
    }
}

/// Monthly balance as bars, with the running balance as a line over the top.
///
/// Both series are in hours, so they share one axis honestly rather than being
/// forced onto two scales that invite a false comparison.
struct MonthlyBalanceChart: View {
    let points: [MonthlyBalancePoint]
    let formatting: CalendarFormatting
    let duration: DurationFormatting
    let showsCumulative: Bool

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Month", formatting.monthAbbreviation(point.month)),
                    y: .value("Balance", Double(point.balanceMinutes) / 60.0)
                )
                .foregroundStyle(point.balanceMinutes >= 0 ? Color.hoursPositive : Color.hoursMissingFill)
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
                        Text(verbatim: duration.axisString(hours: hours))
                    }
                }
            }
        }
        .frame(height: 200)
        .accessibilityLabel("Balance by month")
    }
}

/// The small callout over a selected bar: "Thu 29" in grey, the hours in
/// bold, on the grouped background so it reads in light and dark.
struct ChartCallout: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: label)
                .foregroundStyle(.hoursSecondaryText)
            Text(verbatim: value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        )
        .accessibilityElement(children: .combine)
    }
}
