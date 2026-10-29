import SwiftUI
import WidgetKit

/// The running balance: how far ahead or behind, and what that is in days
/// off. New in 1.2.
struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursBalance", provider: HoursProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Balance")
        .description("Your running balance, and how many days off it comes to.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct BalanceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HoursEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: BalanceCircular(entry: entry)
            default: BalanceSmall(entry: entry)
            }
        }
        .widgetSurface(onHomeScreen: family.isHomeScreen)
    }
}

/// "+12:30 / +3:30 in October / ≈ 1½ days off". With "Calculate overtime"
/// off there is no balance, and the widget says so rather than showing a
/// zero that would read as "exactly even".
struct BalanceSmall: View {
    let entry: HoursEntry
    private let calendar = Calendar.current

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(
                title: String(localized: "Balance", comment: "Widget header, the running balance"),
                systemImage: (snapshot.totalBalanceMinutes ?? 0) < 0 ? "arrow.down" : "arrow.up"
            )
            if !entry.hasData {
                Spacer(minLength: 0)
                EmptyStateView(state: entry.state).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else if !snapshot.showsBalance {
                QuietNote(text: String(
                    localized: "Overtime is switched off in Zeitkonto, so there is no balance to show.",
                    comment: "Balance widget, when Calculate overtime is off"
                ))
                .padding(.top, 11)
            } else if let total = snapshot.totalBalanceMinutes {
                BigFigure(text: snapshot.formatting.signedString(total)).padding(.top, 11)
                SecondaryLine(text: String(
                    localized: "\(snapshot.formatting.signedString(snapshot.monthBalance(at: entry.date, calendar: calendar))) in \(WidgetText.monthName(entry.date))",
                    comment: "Balance widget, the month's balance, e.g. +3:30 in October"
                ))
                .padding(.top, 5)
                Spacer(minLength: 4)
                if let days = snapshot.balanceDaysOff {
                    SecondaryLine(text: WidgetText.daysOff(days))
                }
            } else {
                QuietNote(text: String(localized: "Open Zeitkonto once to fill this in")).padding(.top, 11)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// "OCT / +3:30 / balance", the month's balance as the design draws it.
struct BalanceCircular: View {
    let entry: HoursEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Text(verbatim: WidgetText.monthAbbreviation(entry.date))
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.5)
                    .opacity(0.75)
                Text(verbatim: figure)
                    .font(.lockFigure(size: 19))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
                Text("balance", comment: "Lock Screen circular widget, under the month's balance")
                    .font(.system(size: 8.5))
                    .opacity(0.75)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
        }
        .accessibilityElement(children: .combine)
    }

    private var figure: String {
        guard entry.hasData, entry.snapshot.showsBalance else { return "–" }
        return entry.snapshot.formatting.signedString(entry.snapshot.monthBalance(at: entry.date, calendar: .current))
    }
}
