import Foundation

/// The tab a stop of the tour is on. The app maps it onto its own tab
/// selection; the engine only names it.
enum TourTab: String, Hashable, Sendable {
    case calendar, sites, insights, settings
}

/// A control the tour can point at. Views mark themselves with one, and the
/// tour draws its spotlight around whichever is on screen.
enum TourTarget: String, Hashable, Sendable {
    /// Today's cell in the calendar.
    case calendarToday
    /// The month's totals under the calendar.
    case calendarSummary
    /// The first site card, or the empty Sites screen's invitation.
    case sites
    /// The period picker at the top of Insights.
    case insights
    /// Export options in Settings.
    case settingsExport
}

/// One stop of the guided tour, in order.
enum TourStop: String, CaseIterable, Hashable, Sendable {
    case welcome, today, summary, sites, insights, export

    var tab: TourTab {
        switch self {
        case .welcome, .today, .summary: return .calendar
        case .sites: return .sites
        case .insights: return .insights
        case .export: return .settings
        }
    }

    /// Nil: shown in the middle of the screen, pointing at nothing.
    var target: TourTarget? {
        switch self {
        case .welcome: return nil
        case .today: return .calendarToday
        case .summary: return .calendarSummary
        case .sites: return .sites
        case .insights: return .insights
        case .export: return .settingsExport
        }
    }
}

/// Where the tour is. The same six stops for everyone; whether you lead a
/// crew only changes what the Sites stop says, never which tabs exist.
struct GuidedTour: Hashable, Sendable {
    let leadsCrew: Bool
    private(set) var index = 0

    init(leadsCrew: Bool) {
        self.leadsCrew = leadsCrew
    }

    var stop: TourStop { TourStop.allCases[index] }
    /// 1-based, for "2 of 6".
    var number: Int { index + 1 }
    var count: Int { TourStop.allCases.count }
    var isLast: Bool { number == count }

    /// Moves to the next stop. False, and nothing changes, on the last one.
    mutating func advance() -> Bool {
        guard !isLast else { return false }
        index += 1
        return true
    }
}
