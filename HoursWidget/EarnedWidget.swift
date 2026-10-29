import SwiftUI
import WidgetKit

/// What the month has earned so far, and what it is made of: the hours, the
/// field allowance, the kilometres. New in 1.2.
///
/// Shown whenever a rate is set, whichever figure the app leads with —
/// placing this widget is the choice. Money never reaches the site widget.
struct EarnedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursEarned", provider: HoursProvider()) { entry in
            EarnedWidgetView(entry: entry)
                .widgetSurface(onHomeScreen: true)
        }
        .configurationDisplayName("Earned")
        .description("What this month has earned so far: hours, allowance and kilometres.")
        .supportedFamilies([.systemMedium])
    }
}

struct EarnedWidgetView: View {
    let entry: HoursEntry
    private let calendar = Calendar.current

    private var earned: WidgetMonthEarned? { entry.snapshot.monthEarned(at: entry.date, calendar: calendar) }

    var body: some View {
        HStack(alignment: .top, spacing: 17) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(
                    title: String(localized: "Earned", comment: "Widget header, what the month has earned"),
                    systemImage: symbol
                )
                if !entry.hasData {
                    Spacer(minLength: 0)
                    EmptyStateView(state: entry.state).frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                } else if let earned {
                    BigFigure(text: money(earned).string(earned.totalCents, showsCents: false)).padding(.top, 11)
                    SecondaryLine(text: String(
                        localized: "\(WidgetText.monthName(entry.date)) so far",
                        comment: "Earned widget, under the month's earnings, e.g. October so far"
                    ))
                    .padding(.top, 5)
                    Spacer(minLength: 0)
                } else {
                    QuietNote(text: String(
                        localized: "Set your hourly rate in Zeitkonto to see what you earn.",
                        comment: "Earned widget, before an hourly rate is set"
                    ))
                    .padding(.top, 11)
                }
            }
            .frame(width: 125, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            if entry.hasData, let earned, !earned.rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(earned.rows, id: \.self) { row in
                        EarnedRowView(row: row, money: money(earned), formatting: entry.snapshot.formatting)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func money(_ earned: WidgetMonthEarned) -> MoneyFormatting {
        MoneyFormatting(currencyCode: earned.currencyCode)
    }

    /// The currency's own sign where SF Symbols has one.
    private var symbol: String {
        switch earned?.currencyCode ?? entry.snapshot.earnings?.currencyCode {
        case "EUR": return "eurosign.circle"
        case "CHF": return "francsign.circle"
        case "GBP": return "sterlingsign.circle"
        case "USD": return "dollarsign.circle"
        default: return "banknote"
        }
    }
}

/// "106 h   980 €".
struct EarnedRowView: View {
    let row: WidgetEarnedRow
    let money: MoneyFormatting
    let formatting: DurationFormatting

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(WidgetTheme.rule).frame(height: 0.75)
            HStack {
                Text(verbatim: label).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: money.string(row.cents, showsCents: false)).lineLimit(1)
            }
            .font(.system(size: 12).monospacedDigit())
            .frame(height: 25)
        }
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch row.kind {
        case let .hours(minutes): return WidgetText.wholeHours(minutes)
        case let .allowance(days): return String(inflected: "Field allowance · ^[\(days) day](inflect: true)")
        case let .kilometres(km): return String(localized: "\(km) km")
        }
    }
}
