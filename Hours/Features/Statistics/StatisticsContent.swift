import SwiftUI
import SwiftData

/// The body of the insights screen for one period, as list sections
/// (design v2, More board phone 2): one big figure first, the hours a day
/// under it, then the figures as rows, by site, the money, and the less used
/// detail lower down. Goes inside the screen's `List`.
struct StatisticsContent: View {
    let range: CalendarDateRange
    let scope: StatisticsScope
    let settings: AppSettings
    let calendar: Calendar
    let formatting: CalendarFormatting

    private let engine: PeriodEngine
    private let days: [DayComputation]
    private let summary: PeriodSummary
    /// Nil while no job has a rate.
    private let earnings: EarningsSummary?
    /// Field allowance, kilometres and travel through today; empty while
    /// they are not tracked.
    private let allowance: AllowanceSummary
    private var duration: DurationFormatting { settings.displayFormatting }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The month's payslip check, open as a sheet.
    @State private var checksPayslip = false

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

        let engine = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: data.firstRecorded)
        self.engine = engine
        let resolved = engine.resolve(
            in: range,
            records: data.records,
            holidays: data.holidays,
            countingThrough: CalendarDate.today(in: calendar)
        )
        self.days = resolved.days
        self.summary = resolved.summary
        self.allowance = AllowanceSummary(days: resolved.days, settings: settings, countingThrough: CalendarDate.today(in: calendar))
        // Through today, and only from whole weeks, which the screen fetches.
        self.earnings = engine.earnings(
            in: range,
            records: data.records,
            holidays: data.holidays,
            countingThrough: CalendarDate.today(in: calendar)
        )
    }

    var body: some View {
        figureSection

        if isEmptyPeriod {
            Section {
                ContentUnavailableView(
                    "Nothing recorded",
                    systemImage: "calendar.badge.clock",
                    description: Text("Hours you enter in the calendar appear here.")
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        } else {
            figuresSection
            SiteHoursSection(
                totals: SiteHours.totals(days, countingThrough: CalendarDate.today(in: calendar)),
                duration: duration
            )
        }

        if let earnings {
            if !summary.isEmpty || earnings.totalCents > 0 {
                EarningsCard(
                    earnings: earnings,
                    money: settings.money,
                    formatting: formatting,
                    showsMonths: false,
                    allowance: allowance
                )
            }
        } else {
            // Tracked without an hourly rate: the days, kilometres and
            // travel still have somewhere to be, and what they come to.
            if !allowance.isEmpty {
                Section {
                    AllowanceLines(allowance: allowance, money: settings.money)
                }
            }
            EarningsHint(jobID: settings.primaryJob.id)
        }

        if !isEmptyPeriod {
            if scope == .month {
                payslipCheck
            }
            if scope == .year {
                monthByMonth
            }
            jobBreakdown
            breakdown
        }
    }

    private var isEmptyPeriod: Bool { summary.isEmpty && summary.expectedMinutes == 0 }

    // MARK: - The figure

    /// "168 h  of 176 h", large, and the hours a day under it, both on the
    /// background rather than in a card.
    private var figureSection: some View {
        Section {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Metrics.small))
            layout {
                Text(duration.string(summary.workedMinutes))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if showsExpected {
                    Text("of \(duration.string(summary.expectedMinutes))")
                        .font(.body)
                        .monospacedDigit()
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("insights-worked")
            .listRowInsets(EdgeInsets(top: 0, leading: Metrics.large + Metrics.tiny, bottom: Metrics.tiny, trailing: Metrics.large))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if showsChart {
                DailyHoursChart(
                    days: days,
                    calendar: calendar,
                    referenceHours: referenceHours
                )
                .listRowInsets(EdgeInsets(top: Metrics.small, leading: Metrics.large + Metrics.tiny, bottom: Metrics.small, trailing: Metrics.large))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private var showsExpected: Bool {
        settings.features.trackExpectedHours && summary.expectedMinutes > 0
    }

    /// The bars for a week or a month; a year has its months lower down.
    private var showsChart: Bool {
        switch scope {
        case .week, .month: return !isEmptyPeriod
        case .today, .year: return false
        }
    }

    // MARK: - The figures

    /// Overtime, Days worked, Sick, Vacation, then any other day type the
    /// period had.
    private var figuresSection: some View {
        Section {
            if settings.features.showsBalance {
                InsightsRow(title: String(localized: "Overtime")) {
                    Text(duration.signedString(summary.balanceMinutes))
                        .foregroundStyle(Color.hoursBalance(summary.balanceMinutes))
                }
            } else if settings.features.trackExpectedHours {
                InsightsRow(title: String(localized: "Expected"), value: duration.string(summary.expectedMinutes))
            }
            InsightsRow(title: String(localized: "Days worked"), value: "\(summary.daysWorked)")
            ForEach(dayTypeCounts) { entry in
                InsightsRow(
                    title: entry.definition.displayName(),
                    value: String(inflected: "^[\(entry.count) day](inflect: true)")
                )
            }
        } footer: {
            if showsExpected && summary.creditedMinutes > 0 {
                Text(verbatim: paidFractionLabel)
            }
        }
    }

    /// Sick and vacation always, as the board has them; every other day
    /// type only when the period had one.
    private var dayTypeCounts: [DayTypeCount] {
        let always: Set<DayTypeID> = [.sick, .vacation]
        let catalog = settings.dayTypeCatalog
        let fixed = [DayTypeID.sick, .vacation].map { id in
            DayTypeCount(definition: catalog.definition(for: id), count: summary.count(of: id))
        }
        let others = catalog.all.compactMap { definition -> DayTypeCount? in
            guard !always.contains(definition.id) else { return nil }
            let count = summary.count(of: definition.id)
            return count > 0 ? DayTypeCount(definition: definition, count: count) : nil
        }
        return fixed + others
    }

    /// Said only when paid absence makes the figure and its "of" differ:
    /// "102% of expected, including 24h paid absence".
    private var paidFractionLabel: String {
        // With no expected hours this is 0/0, which is nan, and `Int(nan)`
        // traps: guarded here as well as at the call site.
        guard summary.expectedMinutes > 0 else {
            return String(localized: "No expected hours set for this period")
        }
        // Formatted before the lookup rather than inside it. A literal % next
        // to a placeholder makes the catalogue key ambiguous — % or %% — and a
        // key one character wrong returns the English and says nothing.
        let percent = Int((Double(summary.paidMinutes) / Double(summary.expectedMinutes) * 100).rounded())
        let share = percent.formatted(.percent.scale(1))
        guard summary.creditedMinutes > 0 else {
            return String(localized: "\(share) of expected")
        }
        let credited = duration.string(summary.creditedMinutes)
        return String(localized: "\(share) of expected, including \(credited) paid absence")
    }

    // MARK: - Detail

    /// The less used figures, lower down.
    private var breakdown: some View {
        Section {
            if settings.features.trackExpectedHours {
                InsightsRow(title: String(localized: "Scheduled working days"), value: "\(summary.scheduledWorkingDays)")
            }
            InsightsRow(
                title: String(localized: "Average per day worked"),
                value: duration.string(summary.averageWorkedMinutesPerWorkedDay)
            )
            if settings.features.showsBalance && (summary.overtimeMinutes > 0 || summary.deficitMinutes > 0) {
                InsightsRow(title: String(localized: "Overtime")) {
                    Text(duration.string(summary.overtimeMinutes))
                        .foregroundStyle(summary.overtimeMinutes > 0 ? Color.hoursPositive : Color.secondary)
                }
                InsightsRow(title: String(localized: "Short")) {
                    Text(duration.string(summary.deficitMinutes))
                        .foregroundStyle(summary.deficitMinutes > 0 ? Color.hoursMissing : Color.secondary)
                }
            }
            if settings.features.trackBreaks && summary.breakMinutes > 0 {
                InsightsRow(title: String(localized: "Breaks"), value: duration.string(summary.breakMinutes))
            }
            if summary.creditedMinutes > 0 {
                InsightsRow(title: String(localized: "Paid absence"), value: duration.string(summary.creditedMinutes))
            }
        } header: {
            Text("Details")
        }
    }

    // MARK: - Month by month

    /// The year's months: the balance chart, then "October  168h · +4h 10m"
    /// for each month so far, with earnings when pay is set.
    private var monthByMonth: some View {
        let points = monthlyPoints
        let money = Dictionary(uniqueKeysWithValues: (earnings?.months ?? []).map { ($0.month, $0.totalCents) })
        return Section {
            MonthlyBalanceChart(
                points: points,
                formatting: formatting,
                showsCumulative: settings.features.showsBalance
            )
            .padding(.vertical, Metrics.small)
            .accessibilityIdentifier("insights-month-by-month")
            ForEach(points.reversed()) { point in
                InsightsRow(
                    title: formatting.monthName(point.month),
                    value: monthLine(point, cents: money[point.month])
                )
            }
        } header: {
            Text("Month by month")
        }
    }

    /// Two parts at most: the hours and the balance, or the hours and the
    /// money when the balance is not shown.
    private func monthLine(_ point: MonthlyBalancePoint, cents: Int?) -> String {
        var parts = [duration.string(point.workedMinutes)]
        if settings.features.showsBalance {
            parts.append(duration.signedString(point.balanceMinutes))
        } else if let cents, settings.showsEarnings {
            parts.append(settings.money.string(cents, showsCents: false))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Payslip

    private var month: YearMonth { range.start.yearMonth }

    /// The month as Insights shows it, for the payslip to be checked against.
    private var payslipFigures: PayslipFigures {
        PayslipFigures(
            days: days,
            summary: summary,
            earnings: earnings,
            settings: settings,
            month: month,
            calendar: calendar,
            countingThrough: CalendarDate.today(in: calendar)
        )
    }

    private var payslipCheck: some View {
        let stored = settings.payslipEntry(for: month)
        let figures = payslipFigures
        return Section {
            PayslipCheckRow(
                comparison: stored.map { PayslipComparison(entry: $0, figures: figures) },
                monthName: formatting.monthName(month),
                open: { checksPayslip = true }
            )
            .sheet(isPresented: $checksPayslip) {
                PayslipCheckSheet(
                    month: month,
                    monthTitle: formatting.monthTitle(month),
                    figures: figures,
                    stored: stored
                )
            }
        }
    }

    // MARK: - Charts

    private var referenceHours: Double? {
        guard settings.features.trackExpectedHours else { return nil }
        let scheduled = days.filter { $0.isScheduledWorkingDay }
        guard !scheduled.isEmpty else { return nil }
        let total = scheduled.reduce(0) { $0 + $1.expectedMinutes }
        return Double(total) / Double(scheduled.count) / 60.0
    }

    private var monthlyPoints: [MonthlyBalancePoint] {
        // The carried figure only, not the whole origin.
        //
        // This chart has always started from zero rather than from the opening
        // balance — it shows the shape of a period, not an all-time total —
        // and that is a separate decision from carry-over, so it stays. What
        // changes is that a closed year now hands its carried amount to the
        // months that follow it, which is the one thing that would otherwise
        // make the chart's last point and the running balance beside it
        // disagree by exactly the carried amount, both looking plausible.
        let carriedIn = days.first.flatMap { first in
            CarryOver.latest(in: settings.yearCloses.filter { $0.year < first.date.year })
        }
        return BalanceLedger.monthlySeries(
            over: days,
            openingMinutes: carriedIn?.carriedMinutes ?? 0,
            startDate: settings.balanceOrigin(for: days.first?.date ?? CalendarDate.today(in: calendar)).startDate,
            countingThrough: CalendarDate.today(in: calendar)
        )
    }

    // MARK: - Jobs

    /// Only appears once there is more than one job — with one, it would just
    /// restate the totals above.
    @ViewBuilder
    private var jobBreakdown: some View {
        if settings.tracksMultipleJobs {
            let totals = engine
                .jobTotals(for: days, countingThrough: CalendarDate.today(in: calendar))
            if !totals.isEmpty {
                Section {
                    ForEach(totals) { total in
                        HStack(spacing: Metrics.medium) {
                            Circle()
                                .fill(total.job.tint.color)
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(total.job.displayName())
                                Text(verbatim: "\(duration.string(total.workedMinutes)) · \(String(localized: "of \(duration.string(total.expectedMinutes))"))")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(.hoursSecondaryText)
                            }
                            Spacer(minLength: Metrics.small)
                            if settings.features.showsBalance {
                                BalanceText(
                                    minutes: total.balanceMinutes,
                                    formatting: duration,
                                    font: .body.monospacedDigit()
                                )
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("By job")
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

/// A row of Insights: the noun on the left, the figure in grey on the
/// right, or in its own colour when it has one.
struct InsightsRow<Value: View>: View {
    let title: String
    @ViewBuilder let value: Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
            Text(verbatim: title)
                .foregroundStyle(.primary)
            Spacer(minLength: Metrics.small)
            value
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
    }
}

extension InsightsRow where Value == AnyView {
    /// A figure in grey.
    init(title: String, value: String) {
        self.title = title
        self.value = AnyView(
            Text(verbatim: value)
                .foregroundStyle(.hoursSecondaryText)
        )
    }
}

/// Insights › By site: your hours on each site in the period, from the
/// shifts the site days wrote. Nothing while no site was worked.
private struct SiteHoursSection: View {
    let totals: [SiteHours.Total]
    let duration: DurationFormatting

    @Query private var sites: [SiteEntry]

    var body: some View {
        if !totals.isEmpty {
            let names = Dictionary(sites.map { ($0.site.id, $0.site.name) }, uniquingKeysWith: { first, _ in first })
            Section {
                ForEach(totals, id: \.siteID) { total in
                    InsightsRow(
                        title: names[total.siteID] ?? String(localized: "A deleted site"),
                        value: duration.string(total.workedMinutes)
                    )
                }
            } header: {
                Text("By site")
                    .accessibilityIdentifier("insights-by-site")
            }
        }
    }
}
