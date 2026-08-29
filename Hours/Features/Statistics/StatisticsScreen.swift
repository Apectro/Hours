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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.large) {
                    Picker("Period", selection: $scope) {
                        ForEach(StatisticsScope.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    periodStepper

                    PeriodDataProvider(range: range) { data in
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
                }
                .padding(.horizontal, Metrics.large)
                .padding(.bottom, Metrics.extraLarge)
            }
            .background(Color.hoursCanvas)
            .navigationTitle("Insights")
            // A screen the UI tests wait for. The title beside it is translated.
            .accessibilityIdentifier("screen-insights")
        }
    }

    private var calendar: Calendar { settingsStore.workCalendar }
    private var range: CalendarDateRange { scope.range(around: anchor, in: calendar) }

    private var periodStepper: some View {
        HStack {
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(String(
            localized: "Previous \(scope.title.lowercased())",
            comment: "VoiceOver; the value is a period name such as month or week"
        ))

            Spacer()

            Text(periodTitle)
                .font(.headline)
                .contentTransition(.identity)

            Spacer()

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(String(
            localized: "Next \(scope.title.lowercased())",
            comment: "VoiceOver; the value is a period name such as month or week"
        ))
            .disabled(isAtPresent)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
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
