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

    var title: String { label(in: .english) }

    /// The label an exported summary gives this adjustment.
    func label(in language: ExportLanguage) -> String {
        switch self {
        case .correction: return language(.correction)
        case .payout: return language(.paidOut)
        case .timeOffInLieu: return language(.timeOffInLieu)
        }
    }

    var explanation: String {
        switch self {
        case .correction:
            return "Adjusts the balance without changing the hours you worked."
        case .payout:
            return "Overtime exchanged for money. It leaves the balance and does not come back as time."
        case .timeOffInLieu:
            return "Overtime taken as time off. Use a negative figure for the hours drawn down."
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
