import Foundation

/// Writes an amount of whole cents as text.
///
/// The engine counts money in cents and nothing else; this is the one place
/// they become a currency, so the app, the widgets and the exports cannot
/// write the same amount three ways. The currency is the one chosen in
/// settings, the shape of the number is the locale's: euros on an English
/// phone are still euros.
struct MoneyFormatting: Hashable, Sendable {
    var currencyCode: String
    var locale: Locale

    init(currencyCode: String, locale: Locale = .current) {
        self.currencyCode = currencyCode
        self.locale = locale
    }

    /// "€2,340.50", or "€2,341" without the cents for a figure meant to be
    /// read at a glance. Leaving the cents out rounds half a unit up, in
    /// whole cents, before anything is formatted.
    func string(_ cents: Int, showsCents: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode
        let shown: Int
        if showsCents {
            shown = cents
        } else {
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
            let sign = cents < 0 ? -1 : 1
            shown = sign * ((abs(cents) + 50) / 100) * 100
        }
        // Decimal, not Double: a hundredth is exact in one and not the other.
        let amount = NSDecimalNumber(decimal: Decimal(shown) / 100)
        return formatter.string(from: amount) ?? MoneyFormatting.plain(cents, decimalSeparator: ".") + " " + currencyCode
    }

    /// "2340.50": the amount alone, for a cell a spreadsheet should read as a
    /// number. The currency goes in the column's heading instead.
    static func plain(_ cents: Int, decimalSeparator: String) -> String {
        let sign = cents < 0 ? "-" : ""
        let magnitude = abs(cents)
        return sign + "\(magnitude / 100)" + decimalSeparator + String(format: "%02d", magnitude % 100)
    }
}
