import Foundation

/// What happens to a balance above the carry-over cap at the end of a year.
enum YearEndSurplus: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// Nothing was above the cap. Not a choice — the outcome of a close that
    /// had no surplus to dispose of.
    case none
    /// Exchanged for money, the way an overtime payout is during the year.
    case paidOut
    /// Lapsed. Common in contracts that cap the account and say so.
    case forfeited

    var id: String { rawValue }

    var title: String { label(in: .device) }

    func label(in language: ExportLanguage) -> String {
        switch self {
        case .none: return language(.surplusNone)
        case .paidOut: return language(.surplusPaidOut)
        case .forfeited: return language(.surplusForfeited)
        }
    }
}

/// How a year's closing balance is carried into the next one.
struct CarryOverPolicy: Codable, Hashable, Sendable {
    /// Off by default. An app that silently starts zeroing balances every
    /// December is worse than one that never had the feature.
    var isEnabled: Bool
    /// The most that may carry into the next year. Nil is uncapped, which is
    /// what a Zeitkonto without a ceiling looks like.
    var capMinutes: Int?
    /// What becomes of anything above the cap.
    var surplusAbove: YearEndSurplus

    init(isEnabled: Bool = false, capMinutes: Int? = nil, surplusAbove: YearEndSurplus = .paidOut) {
        self.isEnabled = isEnabled
        self.capMinutes = capMinutes
        self.surplusAbove = surplusAbove
    }
}

/// A year that has been closed off, and what it handed to the next one.
///
/// Recorded rather than recomputed. The point of closing a year is that the
/// figure is agreed and does not move afterwards: editing a Tuesday in March
/// two years later must not silently change what was carried into the
/// following January, or the record stops being a record.
struct YearClose: Codable, Hashable, Sendable, Identifiable {
    /// The year that was closed. The balance runs through 31 December of it.
    var year: Int
    /// The balance as it stood at the close, before any cap.
    var closingMinutes: Int
    /// What actually carried into `year + 1`.
    var carriedMinutes: Int
    /// What happened to the difference.
    var surplus: YearEndSurplus

    var id: Int { year }

    /// The balance that did not carry. Zero when nothing was capped.
    var surplusMinutes: Int { closingMinutes - carriedMinutes }
}

/// Closing a year, and knowing where a running balance starts.
///
/// The app is named after a Zeitkonto and did not model the construct's
/// defining rule: German working-time accounts have a year boundary, the
/// balance carries into the new year, and a great many contracts cap what may
/// carry. Before this there was one opening figure that ran forever.
enum CarryOver {
    /// What closing `year` at `balance` carries into the next one.
    ///
    /// A cap applies to credit and never to a deficit. This is the rule most
    /// worth stating: a cap on a working-time account is a ceiling on hours
    /// owed *to* you, and applying it to a shortfall would quietly forgive
    /// hours you still owe — the app inventing time that was never worked,
    /// which is precisely what the rest of the engine refuses to do.
    static func close(year: Int, balance: Int, policy: CarryOverPolicy) -> YearClose {
        guard policy.isEnabled, let cap = policy.capMinutes, cap >= 0, balance > cap else {
            return YearClose(
                year: year,
                closingMinutes: balance,
                carriedMinutes: balance,
                surplus: .none
            )
        }
        return YearClose(
            year: year,
            closingMinutes: balance,
            carriedMinutes: cap,
            surplus: policy.surplusAbove
        )
    }

    /// Where the running balance for `date` starts counting.
    ///
    /// A closed year behaves exactly like the opening balance already did:
    /// a figure, and a date before which days are ignored. Reusing that rather
    /// than adding a second mechanism means the chart, the statistics screen
    /// and the export all pick this up without knowing carry-over exists.
    ///
    /// The close that applies to a date is the most recent one *strictly
    /// before* its year — closing 2026 governs 2027 onwards, not 2026 itself,
    /// which is the year that close was computed from.
    static func origin(
        for date: CalendarDate,
        closes: [YearClose],
        openingMinutes: Int,
        balanceStartDate: CalendarDate?
    ) -> (openingMinutes: Int, startDate: CalendarDate?) {
        let applicable = closes.filter { $0.year < date.year }
        guard let latestYear = applicable.map(\.year).max(),
              // A year closed twice keeps the last answer recorded for it.
              let latest = applicable.last(where: { $0.year == latestYear })
        else {
            return (openingMinutes, balanceStartDate)
        }

        let january = CalendarDate(year: latest.year + 1, month: 1, day: 1)
        // A start date after the close still applies: somebody who set both
        // means the later of the two, and taking the earlier would count days
        // they had deliberately excluded.
        let start = balanceStartDate.map { Swift.max($0, january) } ?? january
        return (latest.carriedMinutes, start)
    }

    /// The most recent close, if the years have been closed at all.
    static func latest(in closes: [YearClose]) -> YearClose? {
        closes.max { $0.year < $1.year }
    }
}

extension AppSettings {
    /// Where the running balance for `date` starts, taking any closed year
    /// into account.
    ///
    /// One accessor rather than the same three arguments assembled at each
    /// call site. `BalanceLedger` carries a comment about what happened last
    /// time that rule existed in two copies: the running total on the
    /// statistics screen stopped agreeing with the last point of the chart
    /// printed beside it, and both numbers looked perfectly plausible alone.
    func balanceOrigin(for date: CalendarDate) -> (openingMinutes: Int, startDate: CalendarDate?) {
        CarryOver.origin(
            for: date,
            closes: yearCloses,
            openingMinutes: openingBalanceMinutes,
            balanceStartDate: balanceStartDate
        )
    }
}
