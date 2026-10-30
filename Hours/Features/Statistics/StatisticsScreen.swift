import SwiftUI
import SwiftData

enum StatisticsScope: String, CaseIterable, Identifiable, Hashable {
    case today
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        // These four were bare literals while "Today", "Week", "Month" and
        // "Year" sat correctly translated in the catalogue — the enum simply
        // never asked for them. The segmented control at the top of Insights
        // was English on a German phone with the German beside it.
        case .today: return String(localized: "Today")
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        case .year: return String(localized: "Year")
        }
    }

    /// The periods the picker offers.
    static let shown: [StatisticsScope] = [.week, .month, .year]

    func range(around date: CalendarDate, in calendar: Calendar) -> CalendarDateRange {
        switch self {
        case .today: return CalendarDateRange(single: date)
        case .week: return CalendarDateRange.week(containing: date, in: calendar)
        case .month: return date.yearMonth.range(in: calendar)
        case .year: return CalendarDateRange.year(date.year, in: calendar)
        }
    }
}

/// Figures for a period, with a chart only where one earns its place.
struct StatisticsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    @State private var scope: StatisticsScope = .month
    @State private var anchor = CalendarDate.today(in: .current)
    /// The year whose review is open, full screen.
    @State private var review: ReviewedYear?
    /// The last year the late-December card was opened or put away for. A
    /// convenience of this installation, not data: losing it shows the card
    /// once more.
    @AppStorage("yearReview.dismissedYear") private var dismissedReviewYear = 0

    var body: some View {
        NavigationStack {
            List {
                if let year = offeredReviewYear, year != anchor.year {
                    Section {
                        YearReviewInvitation(
                            year: year,
                            open: {
                                dismissedReviewYear = year
                                review = ReviewedYear(year: year)
                            },
                            dismiss: { dismissedReviewYear = year }
                        )
                    }
                }

                // Week, Month, Year (1.2): today's figures are on the Today
                // tab. Then the period, with the arrows that page it.
                Section {
                    Picker("Period", selection: $scope) {
                        ForEach(StatisticsScope.shown) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("insights-scope")
                    .tourTarget(.insights)
                    .listRowInsets(EdgeInsets(top: Metrics.small, leading: 0, bottom: Metrics.small, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    periodStepper
                        .listRowInsets(EdgeInsets(top: Metrics.small, leading: Metrics.large + Metrics.tiny, bottom: 0, trailing: Metrics.small))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                PeriodDataProvider(range: fetchedRange) { data in
                    StatisticsContent(
                        range: range,
                        scope: scope,
                        data: data,
                        settings: settingsStore.settings,
                        calendar: calendar,
                        formatting: settingsStore.dateFormatting
                    )
                }

                if settingsStore.settings.features.showsBalance {
                    CumulativeBalanceCard(
                        through: range.end,
                        trend: range,
                        settings: settingsStore.settings,
                        calendar: calendar
                    )
                }

                LeaveBalanceCard(
                    date: min(range.end, CalendarDate.today(in: calendar)),
                    settings: settingsStore.settings,
                    calendar: calendar
                )

                // "Your 2026": the year's review, a card at a time.
                Section {
                    InsightsOpenCard(
                        title: String(localized: "Your \(String(anchor.year))", comment: "Opens the year in review; the value is a year"),
                        detail: String(localized: "Your year in numbers"),
                        systemImage: "sparkles",
                        identifier: "insights-year-review"
                    ) {
                        if offeredReviewYear == anchor.year { dismissedReviewYear = anchor.year }
                        review = ReviewedYear(year: anchor.year)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .fullScreenCover(item: $review) { reviewed in
                YearReviewScreen(year: reviewed.year)
            }
            .navigationTitle("Insights")
            // A screen the UI tests wait for. The title beside it is translated.
            .accessibilityIdentifier("screen-insights")
        }
    }

    private var calendar: Calendar { settingsStore.workCalendar }

    private var offeredReviewYear: Int? {
        YearReview.yearToOffer(
            today: CalendarDate.today(in: calendar),
            dismissedYear: dismissedReviewYear == 0 ? nil : dismissedReviewYear
        )
    }

    private var range: CalendarDateRange { scope.range(around: anchor, in: calendar) }

    /// The whole weeks around the period, which earnings need: overtime
    /// after the contracted week is counted from the week's first day.
    private var fetchedRange: CalendarDateRange {
        CalendarDateRange(
            start: CalendarDateRange.week(containing: range.start, in: calendar).start,
            end: CalendarDateRange.week(containing: range.end, in: calendar).end
        )
    }

    /// "October" in grey, as the board has it over the figure, with the
    /// two chevrons in small circles that page it.
    private var periodStepper: some View {
        HStack(spacing: Metrics.small) {
            Text(periodTitle)
                .font(.subheadline)
                .foregroundStyle(.hoursSecondaryText)
                .contentTransition(.identity)
                .frame(maxWidth: .infinity, alignment: .leading)

            stepButton(
                systemImage: "chevron.left",
                label: String(
                    localized: "Previous \(scope.title.lowercased())",
                    comment: "VoiceOver; the value is a period name such as month or week"
                ),
                isEnabled: true
            ) { step(-1) }
            .accessibilityIdentifier("insights-previous")

            stepButton(
                systemImage: "chevron.right",
                label: String(
                    localized: "Next \(scope.title.lowercased())",
                    comment: "VoiceOver; the value is a period name such as month or week"
                ),
                isEnabled: !isAtPresent
            ) { step(1) }
            .disabled(isAtPresent)
            .accessibilityIdentifier("insights-next")
        }
        // Two buttons in one row: without this a tap anywhere in the row
        // presses both.
        .buttonStyle(.borderless)
    }

    /// A chevron in a small grey circle, the export's stepper's, inside a
    /// 44-point target.
    private func stepButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.primary : Color(uiColor: .tertiaryLabel))
                .frame(width: 32, height: 32)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(verbatim: label))
    }

    private var periodTitle: String {
        let formatting = settingsStore.dateFormatting
        switch scope {
        case .today: return formatting.fullDate(anchor)
        case .week: return "\(formatting.shortDate(range.start)) – \(formatting.shortDate(range.end))"
        case .month: return formatting.monthTitle(anchor.yearMonth)
        case .year: return String(anchor.year)
        }
    }

    private var isAtPresent: Bool {
        range.contains(CalendarDate.today(in: calendar))
    }

    private func step(_ direction: Int) {
        withAnimation(.snappy(duration: 0.2)) {
            switch scope {
            case .today:
                anchor = anchor.adding(days: direction, in: calendar)
            case .week:
                anchor = anchor.adding(days: direction * 7, in: calendar)
            case .month:
                let month = anchor.yearMonth.adding(months: direction)
                anchor = CalendarDate(
                    year: month.year,
                    month: month.month,
                    day: min(anchor.day, month.dayCount(in: calendar))
                )
            case .year:
                anchor = CalendarDate(year: anchor.year + direction, month: anchor.month, day: 1)
            }
        }
    }
}

/// A row on Insights that opens something: "Your 2026". The title, a line
/// under it in grey, and a chevron.
struct InsightsOpenCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let identifier: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: Metrics.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .foregroundStyle(.primary)
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Metrics.small)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(identifier)
    }
}
