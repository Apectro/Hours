import XCTest

/// The tab bar, without depending on what the tabs are called.
///
/// The labels are translated into ten languages and the screenshot suite runs
/// in two of them, so a query by label works in one and hangs in the other.
/// An accessibility identifier is no use either: on a `TabView` it lands on
/// the tab's content, not on the button. Position is the one property that is
/// both stable and language-independent, and this enum keeps the ordering in
/// one place rather than leaving bare indices at eleven call sites.
enum Tab: Int {
    case calendar = 0
    case insights = 1
    case settings = 2
}

extension XCUIApplication {
    func tab(_ tab: Tab) -> XCUIElement {
        tabBars.buttons.element(boundBy: tab.rawValue)
    }
}


extension XCUIApplication {
    /// A screen, by the identifier its root carries.
    ///
    /// Queried across every element type rather than as a `navigationBar` or
    /// an `otherElement`, because which type SwiftUI surfaces an identifier as
    /// is not worth guessing from a CI log fifteen minutes at a time.
    func screen(_ identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier]
    }
}
