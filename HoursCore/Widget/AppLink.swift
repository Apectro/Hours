import Foundation

/// The places a widget can open the app at.
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

    static let scheme = "zeitkonto"

    private static let sameAsLast = "same-as-last"

    var url: URL {
        let parts: [String]
        switch self {
        case .sites:
            parts = ["sites"]
        case let .site(id):
            parts = ["site", id.uuidString]
        case let .siteSameAsLastDay(id):
            parts = ["site", id.uuidString, Self.sameAsLast]
        }
        // Built from parts that are all known to be valid, so this cannot fail.
        return URL(string: Self.scheme + "://" + parts.joined(separator: "/"))!
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
        case ("site", 1):
            guard let id = UUID(uuidString: parts[0]) else { return nil }
            self = .site(id)
        case ("site", 2):
            guard let id = UUID(uuidString: parts[0]), parts[1] == Self.sameAsLast else { return nil }
            self = .siteSameAsLastDay(id)
        default:
            return nil
        }
    }
}
