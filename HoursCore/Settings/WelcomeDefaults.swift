import Foundation

/// What the welcome preselects once you have said where you work: the
/// language of the sheets for your boss and the currency you are paid in.
///
/// A preselection, never a decision — both are shown on their own step and
/// can be changed there or later in Settings. Nothing here guesses a country;
/// without one, the settings stay as they are.
extension HolidayCountry {
    /// The language a sheet handed to a boss here is usually written in.
    ///
    /// Switzerland follows the canton where it is clear: French in Geneva,
    /// Vaud, Neuchâtel and Jura, Italian in Ticino, German everywhere else —
    /// bilingual Valais/Wallis and "other" included, as most cantons are
    /// German-speaking.
    func reportLanguage(region: String?) -> ExportLanguage {
        switch self {
        case .de, .at: return .german
        case .ch:
            switch region {
            case "GE", "VD", "NE", "JU": return .french
            case "TI": return .italian
            default: return .german
            }
        case .hr: return .croatian
        case .si: return .slovenian
        case .it: return .italian
        case .fr: return .french
        case .es: return .spanish
        case .pt: return .portuguese
        case .nl: return .dutch
        case .pl: return .polish
        }
    }

    /// The ISO 4217 code of the money wages are paid in here.
    var currencyCode: String {
        switch self {
        case .ch: return "CHF"
        case .pl: return "PLN"
        case .de, .at, .hr, .si, .it, .fr, .es, .pt, .nl: return "EUR"
        }
    }
}

extension ExportLanguage {
    /// The country's language, or `fallback` — the setting as it stands,
    /// which on a fresh install is `.device`: the app's own language when the
    /// export speaks it, English otherwise.
    static func suggested(for country: HolidayCountry?, region: String?, otherwise fallback: ExportLanguage) -> ExportLanguage {
        country?.reportLanguage(region: region) ?? fallback
    }
}
