import SwiftUI

/// The body of the insights screen for one period.
struct StatisticsContent: View {
    let range: CalendarDateRange
    let scope: StatisticsScope
    let settings: AppSettings
    let calendar: Calendar
    let formatting: CalendarFormatting

    private let days: [DayComputation]
    private let summary: PeriodSummary
    private var duration: DurationFormatting { settings.displayFormatting }

    init(
        range: CalendarDateRange,
        scope: StatisticsScope,
        data: PeriodData,
        settings: AppSettings,
        calendar: Calendar,
        formatting: CalendarFormatting
    ) {
        self.range = range
        self.scope = scope
        self.settings = settings
        self.calendar = calendar
        self.formatting = formatting

        let engine = PeriodEngine(settings: settings, calendar: calendar)
        let resolved = engine.resolve(
            in: range,
            records: data.records,
            holidays: data.holidays,
            countingThrough: CalendarDate.today(in: calendar)
        )
        self.days = resolved.days
        self.summary = resolved.summary
    }

    var body: some View {
        VStack(spacing: Metrics.large) {
            headline

            if summary.isEmpty && summary.expectedMinutes == 0 {
                ContentUnavailableView(
                    "Nothing recorded",
                    systemImage: "calendar.badge.clock",
                    description: Text("Hours you enter in the calendar appear here.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Metrics.large)
            } else {
                breakdown
                chartSection
                dayTypeBreakdown
            }
        }
    }

    // MARK: - Headline

    private var headline: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Metrics.large) {
                HStack(alignment: .top, spacing: Metrics.small) {
                    StatTile(label: "Worked", value: duration.string(summary.workedMinutes))
                    if settings.features.trackExpectedHours {
                        Divider().frame(height: 34)
                        StatTile(label: "Expected", value: duration.string(summary.expectedMinutes))
                    }
                    if settings.features.showsBalance {
                        Divider().frame(height: 34)
                        StatTile(
                            label: "Balance",
                            value: duration.signedString(summary.balanceMinutes),
                            tint: Color.hoursBalance(summary.balanceMinutes)
                        )
                    }
                }

                if settings.features.trackExpectedHours && summary.expectedMinutes > 0 {
                    ProgressBar(
                        fraction: min(Double(summary.paidMinutes) / Double(summary.expectedMinutes), 1.5),
                        label: "\(Int((Double(summary.paidMinutes) / Double(summary.expectedMinutes) * 100).rounded()))% of expected"
                    )
                }
            }
        }
    }

    // MARK: - Breakdown

    private var breakdown: some View {
        SurfaceCard {
            VStack(spacing: Metrics.medium) {
                MetricRow(label: "Days worked", value: "\(summary.daysWorked)", systemImage: "calendar")
                if settings.features.trackExpectedHours {
                    MetricRow(label: "Scheduled working days", value: "\(summary.scheduledWorkingDays)", systemImage: "target")
                }
                MetricRow(
                    label: "Average per day worked",
                    value: duration.string(summary.averageWorkedMinutesPerWorkedDay),
                    systemImage: "chart.bar"
                )
                if settings.features.showsBalance && (summary.overtimeMinutes > 0 || summary.deficitMinutes > 0) {
                    MetricRow(
                        label: "Overtime",
                        value: duration.string(summary.overtimeMinutes),
                        tint: summary.overtimeMinutes > 0 ? .hoursPositive : .primary,
                        systemImage: "arrow.up.right"
                    )
                    MetricRow(
                        label: "Short",
                        value: duration.string(summary.deficitMinutes),
                        tint: summary.deficitMinutes > 0 ? .hoursNegative : .primary,
                        systemImage: "arrow.down.right"
                    )
                }
                if settings.features.trackBreaks && summary.breakMinutes > 0 {
                    MetricRow(label: "Breaks", value: duration.string(summary.breakMinutes), systemImage: "cup.and.saucer")
                }
                if summary.creditedMinutes > 0 {
                    MetricRow(
                        label: "Paid absence",
                        value: duration.string(summary.creditedMinutes),
                        systemImage: "checkmark.seal"
                    )
                }
            }
        }
    }

    // MARK: - Charts

    @ViewBuilder
    private var chartSection: some View {
        switch scope {
        case .today:
            EmptyView()
        case .week, .month:
            SurfaceCard {
                VStack(alignment: .leading, spacing: Metrics.medium) {
                    Text("Hours per day")
                        .font(.subheadline.weight(.semibold))
                    DailyHoursChart(
                        days: days,
                        calendar: calendar,
                        referenceHours: referenceHours
                    )
                }
            }
        case .year:
            SurfaceCard {
                VStack(alignment: .leading, spacing: Metrics.medium) {
                    Text("Month by month")
                        .font(.subheadline.weight(.semibold))
                    MonthlyBalanceChart(
                        points: monthlyPoints,
                        formatting: formatting,
                        showsCumulative: settings.features.showsBalance
                    )
                }
            }
        }
    }

    private var referenceHours: Double? {
        guard settings.features.trackExpectedHours else { return nil }
        let scheduled = days.filter { $0.isScheduledWorkingDay }
        guard !scheduled.isEmpty else { return nil }
        let total = scheduled.reduce(0) { $0 + $1.expectedMinutes }
        return Double(total) / Double(scheduled.count) / 60.0
    }

    private var monthlyPoints: [MonthlyBalancePoint] {
        BalanceLedger.monthlySeries(
            over: days,
            openingMinutes: 0,
            startDate: settings.balanceStartDate,
            countingThrough: CalendarDate.today(in: calendar)
        )
    }

    // MARK: - Day types

    @ViewBuilder
    private var dayTypeBreakdown: some View {
        let entries = settings.dayTypeCatalog.all.compactMap { definition -> DayTypeCount? in
            let count = summary.count(of: definition.id)
            return count > 0 ? DayTypeCount(definition: definition, count: count) : nil
        }
        if !entries.isEmpty {
            SurfaceCard {
                VStack(spacing: Metrics.medium) {
                    ForEach(entries) { entry in
                        HStack(spacing: Metrics.medium) {
                            DayTypeBadge(definition: entry.definition, size: 26)
                            Text(entry.definition.name)
                                .font(.subheadline)
                            Spacer(minLength: Metrics.small)
                            Text("\(entry.count)")
                                .font(.hoursFigure(.body, weight: .medium))
                        }
                    }
                }
            }
        }
    }
}

/// One day type and how often it occurred in the period.
private struct DayTypeCount: Identifiable {
    let definition: DayTypeDefinition
    let count: Int
    var id: DayTypeID { definition.id }
}

/// A slim progress bar. Goes past 100% deliberately — being over your hours is
/// information, not an overflow to be clipped.
struct ProgressBar: View {
    let fraction: Double
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.hoursSubdued.opacity(0.25))
                    Capsule()
                        .fill(fraction > 1 ? Color.hoursPositive : Color.accentColor)
                        .frame(width: max(0, min(fraction, 1.5) / 1.5) * proxy.size.width)
                }
            }
            .frame(height: 8)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
