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
    /// Settings › Leave shows the year even before anything is taken.
    var alwaysShows = false
    /// Insights' identifier; nil where the card is not that one.
    var identifier: String? = "insights-leave"

    var body: some View {
        PeriodDataProvider(range: range) { data in
            LeaveBalanceCardContent(
                balance: balance(data),
                settings: settings,
                alwaysShows: alwaysShows,
                identifier: identifier,
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
    let alwaysShows: Bool
    let identifier: String?
    let formatting: CalendarFormatting

    var body: some View {
        // Nothing to say to someone who has never mentioned leave: no policy
        // changed, nothing taken, nothing booked, nothing carried.
        if alwaysShows || settings.leave.isCustomized || balance.used > .zero || balance.planned > .zero || balance.carried > .zero {
            SurfaceCard {
                VStack(alignment: .leading, spacing: Metrics.small) {
                    HStack(spacing: Metrics.small) {
                        DayTypeBadge(definition: vacationType, size: 22)
                        Text(yearTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.hoursSecondaryText)
                            .textCase(.uppercase)
                            .tracking(0.4)
                        Spacer(minLength: Metrics.small)
                        Text(yearSpan)
                            .font(.caption)
                            .foregroundStyle(.hoursSecondaryText)
                    }

                    Text(String(
                        localized: "\(balance.remaining.localized) days left of \(available.localized)",
                        comment: "Vacation days still to book, of those the year gives; e.g. 8 days left of 24"
                    ))
                    .font(.hoursFigure(.title2))
                    .foregroundStyle(balance.remaining < .zero ? Color.hoursMissing : .primary)

                    LeaveBar(
                        used: fraction(balance.used),
                        planned: fraction(balance.planned),
                        tint: vacationType.tint.color
                    )

                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(.hoursSecondaryText)
                }
                .accessibilityElement(children: .combine)
            }
            .accessibilityIdentifier(identifier ?? "leave-year")
        }
    }

    /// "2026", or "2026/27" for a leave year that does not start in January.
    private var yearTitle: String {
        let start = balance.range.start.year
        let end = balance.range.end.year
        return start == end ? String(start) : "\(start)/\(String(end).suffix(2))"
    }

    private func fraction(_ days: HalfDays) -> Double {
        guard available.halves > 0 else { return 0 }
        return min(max(Double(days.halves) / Double(available.halves), 0), 1)
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

/// The leave year as a bar: taken, then booked, then what is left.
private struct LeaveBar: View {
    let used: Double
    let planned: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(tint)
                    .frame(width: proxy.size.width * used)
                Rectangle()
                    .fill(tint.opacity(0.4))
                    .frame(width: proxy.size.width * min(planned, 1 - used))
                Spacer(minLength: 0)
            }
            .background(Color.hoursSubdued.opacity(0.25))
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
