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
            ScrollView {
                VStack(spacing: Metrics.large) {
                    if let year = offeredReviewYear, !(scope == .year && year == anchor.year) {
                        YearReviewInvitation(
                            year: year,
                            open: {
                                dismissedReviewYear = year
                                review = ReviewedYear(year: year)
                            },
                            dismiss: { dismissedReviewYear = year }
                        )
                    }

                    Picker("Period", selection: $scope) {
                        ForEach(StatisticsScope.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tourTarget(.insights)

                    periodStepper

                    // The review is the year's best card, so it leads the
                    // year rather than waiting under leave and balance. The
                    // seasonal card above steps aside for the same year, so
                    // it is never offered twice.
                    if scope == .year {
                        YearReviewInvitation(
                            year: anchor.year,
                            open: {
                                if offeredReviewYear == anchor.year { dismissedReviewYear = anchor.year }
                                review = ReviewedYear(year: anchor.year)
                            },
                            dismiss: nil,
                            identifier: "insights-year-review"
                        )
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
                            settings: settingsStore.settings,
                            calendar: calendar
                        )
                    }

                    if scope != .today {
                        LeaveBalanceCard(
                            date: min(range.end, CalendarDate.today(in: calendar)),
                            settings: settingsStore.settings,
                            calendar: calendar
                        )
                    }
                }
                .padding(.horizontal, Metrics.large)
                .padding(.bottom, Metrics.extraLarge)
            }
            .background(Color.hoursCanvas)
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

    private var periodStepper: some View {
        HStack {
            stepButton(
                systemImage: "chevron.left",
                label: String(
                    localized: "Previous \(scope.title.lowercased())",
                    comment: "VoiceOver; the value is a period name such as month or week"
                )
            ) { step(-1) }

            Spacer(minLength: Metrics.small)

            Text(periodTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
                .contentTransition(.identity)

            Spacer(minLength: Metrics.small)

            stepButton(
                systemImage: "chevron.right",
                label: String(
                    localized: "Next \(scope.title.lowercased())",
                    comment: "VoiceOver; the value is a period name such as month or week"
                )
            ) { step(1) }
            .disabled(isAtPresent)
        }
        // Two buttons in one row: without this a tap anywhere in the row
        // presses both.
        .buttonStyle(.borderless)
    }

    /// A full 44pt target, the same chevron the export month stepper uses:
    /// the old bordered circles were about 34pt, small for a gloved thumb.
    private func stepButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
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
