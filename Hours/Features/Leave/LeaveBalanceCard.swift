import SwiftUI

/// The leave year as a list section: "18 days left of 24", a bar of what
/// is taken, and what is booked and carried (design v2: no card, one
/// section, the system's own progress bar). On Insights and Settings › Leave.
///
/// The leave year is fetched on its own, since it rarely lines up with the
/// period on screen: a leave year from April, looked at in a month view of
/// February, is last April to this March. Goes inside a `List` or `Form`.
struct LeaveBalanceCard: View {
    /// A day in the leave year to show.
    let date: CalendarDate
    let settings: AppSettings
    let calendar: Calendar
    /// Settings › Leave shows the year even before anything is taken.
    var alwaysShows = false
    /// Insights' identifier; nil where the section is not that one.
    var identifier: String? = "insights-leave"
    /// "Leave" over the section, where the screen's title does not say it.
    var showsHeader = true

    var body: some View {
        PeriodDataProvider(range: range) { data in
            LeaveBalanceCardContent(
                balance: balance(data),
                settings: settings,
                alwaysShows: alwaysShows,
                identifier: identifier,
                showsHeader: showsHeader,
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
    let showsHeader: Bool
    let formatting: CalendarFormatting

    var body: some View {
        // Nothing to say to someone who has never mentioned leave: no policy
        // changed, nothing taken, nothing booked, nothing carried.
        if alwaysShows || settings.leave.isCustomized || balance.used > .zero || balance.planned > .zero || balance.carried > .zero {
            Section {
                VStack(alignment: .leading, spacing: Metrics.small) {
                    Text(String(
                        localized: "\(balance.remaining.localized) days left of \(available.localized)",
                        comment: "Vacation days still to book, of those the year gives; e.g. 8 days left of 24"
                    ))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(balance.remaining < .zero ? Color.hoursMissing : .primary)

                    ProgressView(value: fraction(balance.used + balance.planned))
                        .tint(vacationType.tint.color)
                        .accessibilityHidden(true)

                    ForEach(details, id: \.self) { line in
                        Text(verbatim: line)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.hoursSecondaryText)
                    }
                }
                .padding(.vertical, Metrics.tiny)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(identifier ?? "leave-year")
            } header: {
                if showsHeader {
                    Text("Leave")
                }
            } footer: {
                Text(verbatim: yearSpan)
            }
        }
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

    /// "4 taken · 2 planned", then a line each for what was carried, what
    /// expires and what has.
    private var details: [String] {
        var lines = [[
            String(localized: "\(balance.used.localized) taken", comment: "Vacation days already taken this leave year"),
            String(localized: "\(balance.planned.localized) planned", comment: "Vacation days booked after today")
        ].joined(separator: " · ")]
        if balance.carried > .zero {
            lines.append(String(localized: "Carried over: \(balance.carried.localized)", comment: "Vacation days from last leave year"))
        }
        if balance.carryOverAtRisk > .zero, let expiry = balance.carryOverExpiry {
            lines.append(String(
                localized: "Expiring on \(formatting.shortDate(expiry)): \(balance.carryOverAtRisk.localized)",
                comment: "Carried-over vacation days that are lost unless taken by this date"
            ))
        }
        if balance.expired > .zero {
            lines.append(String(localized: "Expired: \(balance.expired.localized)", comment: "Carried-over vacation days lost"))
        }
        return lines
    }
}
