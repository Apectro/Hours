import Foundation

/// The places a widget, a control, a shortcut or a notification can open
/// the app at.
///
/// A widget runs in its own process and cannot write the app's store — the
/// store lives in the app's own container, not the one the two share — so a
/// widget button that changes something is a link that asks the app to do it.
/// The widget builds the URL and the app reads it back through this one type,
/// so the two can never spell a link differently.
///
/// The scheme is registered in `Hours-Info.plist`.
enum AppLink: Hashable, Sendable {
    /// The Sites tab, for the site widget when there is no site to show.
    case sites
    /// A site, on today.
    case site(UUID)
    /// A site on today, filled from its last written day — the site screen's
    /// own "Same as last day", which still declines a day that is written or
    /// a month that is closed.
    case siteSameAsLastDay(UUID)
    /// A site's sheet for one month, as the director gets it. The monthly
    /// reminder opens this on the month that has just ended.
    case siteExport(UUID, YearMonth)
    /// Today's day editor, on the calendar: the Write today control and
    /// shortcut. Today is the phone's today when the link is followed, not
    /// when it was made, so the link carries no date.
    case writeToday

    static let scheme = "zeitkonto"

    private static let sameAsLast = "same-as-last"
    private static let export = "export"
    private static let monthQuery = "month"

    var url: URL {
        let parts: [String]
        var query = ""
        switch self {
        case .sites:
            parts = ["sites"]
        case .writeToday:
            parts = ["today"]
        case let .site(id):
            parts = ["site", id.uuidString]
        case let .siteSameAsLastDay(id):
            parts = ["site", id.uuidString, Self.sameAsLast]
        case let .siteExport(id, month):
            parts = ["site", id.uuidString, Self.export]
            query = "?" + Self.monthQuery + "=" + Self.monthString(month)
        }
        // Built from parts that are all known to be valid, so this cannot fail.
        return URL(string: Self.scheme + "://" + parts.joined(separator: "/") + query)!
    }

    /// Nil for anything that is not exactly one of the links above. A link
    /// can be typed by anyone into anything, so an unknown one opens the app
    /// where it was rather than being guessed at.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }

        switch (host, parts.count) {
        case ("sites", 0):
            self = .sites
        case ("today", 0):
            self = .writeToday
        case ("site", 1):
            guard let id = UUID(uuidString: parts[0]) else { return nil }
            self = .site(id)
        case ("site", 2):
            guard let id = UUID(uuidString: parts[0]) else { return nil }
            switch parts[1] {
            case Self.sameAsLast:
                self = .siteSameAsLastDay(id)
            case Self.export:
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                guard
                    let value = items.first(where: { $0.name == Self.monthQuery })?.value,
                    let month = Self.month(from: value)
                else { return nil }
                self = .siteExport(id, month)
            default:
                return nil
            }
        default:
            return nil
        }
    }

    /// What the Same as yesterday control opens: the site on the site card —
    /// the most recent active one — filled from its last written day, or
    /// the Sites tab when there is no site to fill, where one can be added.
    /// A control cannot ask the store which site that is, so it reads the
    /// snapshot the widgets read.
    static func sameAsYesterday(from snapshot: WidgetSnapshot?) -> AppLink {
        guard let site = snapshot?.site else { return .sites }
        return .siteSameAsLastDay(site.id)
    }

    /// `2026-03`: the same spelling a file name uses, and one that sorts.
    private static func monthString(_ month: YearMonth) -> String {
        String(format: "%04d-%02d", month.year, month.month)
    }

    /// Only exactly `yyyy-MM` with a real month. `YearMonth` would quietly
    /// turn a thirteenth month into January of the next year, which is a
    /// guess, and a link is not something to guess about.
    private static func month(from string: String) -> YearMonth? {
        let pieces = string.split(separator: "-", omittingEmptySubsequences: false)
        guard
            pieces.count == 2, pieces[0].count == 4, pieces[1].count == 2,
            let year = Int(pieces[0]), let month = Int(pieces[1]),
            (1...12).contains(month)
        else { return nil }
        return YearMonth(year: year, month: month)
    }
}
