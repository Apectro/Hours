import Foundation

/// Why a day's balance was adjusted by hand.
///
/// Without this the balance only ever grows, and taking time off in lieu or
/// being paid out shows up as an unexplained negative correction. Naming the
/// reason lets a report say "10 h paid out" instead, which is the difference
/// between a record you can hand to someone and one you have to remember the
/// story behind.
enum AdjustmentReason: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// A correction to the hours themselves — agreed rounding, a fixed mistake.
    case correction
    /// Accrued overtime exchanged for money. The hours leave the balance and
    /// do not come back as time.
    case payout
    /// Accrued overtime taken as time off instead of being worked.
    case timeOffInLieu

    var id: String { rawValue }

    /// The app's own screens follow the phone. This used to be pinned to
    /// English, so a German user entered a figure on a screen saying "Payout"
    /// and then read "Auszahlung" against it in the timesheet they exported —
    /// the same concept, two answers, in one product.
    var title: String { label(in: .device) }

    /// The label an exported summary gives this adjustment.
    func label(in language: ExportLanguage) -> String {
        switch self {
        case .correction: return language(.correction)
        case .payout: return language(.paidOut)
        case .timeOffInLieu: return language(.timeOffInLieu)
        }
    }

    var explanation: String { explanation(in: .device) }

    func explanation(in language: ExportLanguage) -> String {
        switch self {
        case .correction: return language(.adjustmentCorrectionExplained)
        case .payout: return language(.adjustmentPayoutExplained)
        case .timeOffInLieu: return language(.adjustmentTimeOffExplained)
        }
    }

    var symbolName: String {
        switch self {
        case .correction: return "slider.horizontal.3"
        case .payout: return "banknote"
        case .timeOffInLieu: return "figure.walk.departure"
        }
    }

    /// Whether this reason normally moves the balance down. Used only to
    /// suggest a sign in the editor; the user's figure always wins.
    var suggestsDeduction: Bool {
        switch self {
        case .correction: return false
        case .payout, .timeOffInLieu: return true
        }
    }
}
