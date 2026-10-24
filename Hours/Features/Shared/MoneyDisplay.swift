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

    /// The currencies a picker offers: the common ones, plus `chosen` when
    /// it is not among them, in code order.
    static func currencyChoices(including chosen: String) -> [String] {
        var codes = Locale.commonISOCurrencyCodes
        if !codes.contains(chosen) { codes.append(chosen) }
        return codes.sorted()
    }

    /// "Euro (EUR)", in the phone's language; the bare code when the system
    /// has no name for it.
    static func currencyName(_ code: String) -> String {
        guard let name = Locale.current.localizedString(forCurrencyCode: code) else { return code }
        return "\(name) (\(code))"
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

/// Kilometres as they are typed: the digits, at most five of them, and none
/// for nothing usable.
enum Kilometres {
    static func parse(_ text: String) -> Int {
        Int(String(text.filter { $0.isASCII && $0.isNumber }.prefix(5))) ?? 0
    }
}
