import SwiftUI

/// "Vacation: 18 of 25 left · 2 planned", on Insights.
///
/// The leave year is fetched on its own, since it rarely lines up with the
/// period on screen: a leave year from April, looked at in a month view of
/// February, is last April to this March.
struct LeaveBalanceCard: View {
    /// A day in the leave year to show.
    let date: CalendarDate
    let settings: AppSettings
    let calendar: Calendar

    var body: some View {
        PeriodDataProvider(range: range) { data in
            LeaveBalanceCardContent(
                balance: balance(data),
                settings: settings,
                formatting: CalendarFormatting(locale: .current, calendar: calendar)
            )
        }
    }

    private var leaveYear: Int { settings.leave.leaveYear(containing: date, calendar: calendar) }
    private var range: CalendarDateRange { settings.leave.range(ofLeaveYear: leaveYear, calendar: calendar) }

    private func balance(_ data: PeriodData) -> LeaveBalance {
        let engine = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: data.firstRecorded)
        return LeaveCalculator.balance(
            leaveYear: leaveYear,
            days: engine.days(in: range, records: data.records, holidays: data.holidays),
            settings: settings,
            calendar: calendar,
            today: CalendarDate.today(in: calendar)
        )
    }
}

private struct LeaveBalanceCardContent: View {
    let balance: LeaveBalance
    let settings: AppSettings
    let formatting: CalendarFormatting

    var body: some View {
        // Nothing to say to someone who has never mentioned leave: no policy
        // changed, nothing taken, nothing booked, nothing carried.
        if settings.leave.isCustomized || balance.used > .zero || balance.planned > .zero || balance.carried > .zero {
            SurfaceCard {
                VStack(alignment: .leading, spacing: Metrics.small) {
                    HStack(spacing: Metrics.small) {
                        DayTypeBadge(definition: vacationType, size: 22)
                        Text(vacationType.displayName())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.4)
                        Spacer(minLength: Metrics.small)
                        Text(yearSpan)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(String(
                        localized: "\(balance.remaining.localized) of \(available.localized) left",
                        comment: "Vacation days still to book, of those the year gives; e.g. 18 of 25 left"
                    ))
                    .font(.hoursFigure(.title2))
                    .foregroundStyle(balance.remaining < .zero ? Color.hoursNegative : .primary)

                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .accessibilityIdentifier("insights-leave")
        }
    }

    private var vacationType: DayTypeDefinition { settings.dayTypeCatalog.definition(for: .vacation) }

    /// The allowance and the carry-over that is still there to take.
    private var available: HalfDays { balance.allowance + balance.carried - balance.expired }

    private var yearSpan: String {
        "\(formatting.shortDate(balance.range.start)) – \(formatting.dateWithYear(balance.range.end))"
    }

    private var details: String {
        var parts = [
            String(localized: "\(balance.used.localized) taken", comment: "Vacation days already taken this leave year"),
            String(localized: "\(balance.planned.localized) planned", comment: "Vacation days booked after today")
        ]
        if balance.carried > .zero {
            parts.append(String(localized: "Carried over: \(balance.carried.localized)", comment: "Vacation days from last leave year"))
        }
        if balance.carryOverAtRisk > .zero, let expiry = balance.carryOverExpiry {
            parts.append(String(
                localized: "Expiring on \(formatting.shortDate(expiry)): \(balance.carryOverAtRisk.localized)",
                comment: "Carried-over vacation days that are lost unless taken by this date"
            ))
        }
        if balance.expired > .zero {
            parts.append(String(localized: "Expired: \(balance.expired.localized)", comment: "Carried-over vacation days lost"))
        }
        return parts.joined(separator: "  ·  ")
    }
}
