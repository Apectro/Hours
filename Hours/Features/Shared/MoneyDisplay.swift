import Foundation

extension AppSettings {
    /// How amounts are written on screen: the chosen currency, or the
    /// phone's region's until one is chosen, in the phone's own number shape.
    var money: MoneyFormatting {
        MoneyFormatting(currencyCode: currencyCode(fallback: AppSettings.deviceCurrencyCode))
    }

    /// The currency of the phone's region. Euros when the region has none,
    /// which is where the app's users mostly are.
    static var deviceCurrencyCode: String {
        Locale.current.currency?.identifier ?? "EUR"
    }
}

extension PayRules {
    /// An amount typed as a decimal, in whole cents, rounded to the nearest.
    /// Decimal rather than Double all the way, so 0.1 is 10 cents exactly.
    static func cents(from amount: Decimal) -> Int {
        var exact = amount * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &exact, 0, .plain)
        return max(0, NSDecimalNumber(decimal: rounded).intValue)
    }

    static func amount(fromCents cents: Int) -> Decimal {
        Decimal(cents) / 100
    }
}
