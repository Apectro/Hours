import Foundation

/// Field allowance and travel (1.2): the money question on a construction
/// crew after the hours — the daily field allowance (HR *terenski dodatak*,
/// DE/AT *Auslöse*, *Taggeld*), kilometres driven in your own car, and the
/// time spent getting there.
///
/// Off by default, so the app stays as simple as it was for everyone who does
/// not need it. Switched off, nothing shows and nothing counts, but what was
/// recorded on the days stays, for when it is switched on again.
///
/// Amounts are whole cents in the app's currency, as pay is. What the rates
/// should be, and what is tax-free, depends on the contract and the country;
/// the app takes them as given.
struct AllowancePreferences: Hashable, Codable, Sendable {
    var isEnabled: Bool
    /// What one day with the field allowance pays.
    var dailyAllowanceCents: Int
    /// What one kilometre in your own car pays.
    var centsPerKilometre: Int
    /// Whether travel time is worked time — added to the day's worked hours,
    /// its balance and its pay — or only recorded and shown.
    var travelCountsAsWork: Bool

    init(
        isEnabled: Bool = false,
        dailyAllowanceCents: Int = 0,
        centsPerKilometre: Int = 0,
        travelCountsAsWork: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.dailyAllowanceCents = max(0, dailyAllowanceCents)
        self.centsPerKilometre = max(0, centsPerKilometre)
        self.travelCountsAsWork = travelCountsAsWork
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, dailyAllowanceCents, centsPerKilometre, travelCountsAsWork
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AllowancePreferences()
        self.init(
            isEnabled: container.lenient(.isEnabled, defaults.isEnabled),
            dailyAllowanceCents: container.lenient(.dailyAllowanceCents, defaults.dailyAllowanceCents),
            centsPerKilometre: container.lenient(.centsPerKilometre, defaults.centsPerKilometre),
            travelCountsAsWork: container.lenient(.travelCountsAsWork, defaults.travelCountsAsWork)
        )
    }
}
