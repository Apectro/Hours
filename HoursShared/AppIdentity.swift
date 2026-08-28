import Foundation

/// What the app is called.
///
/// Deliberately not a localized string. The interface is translated into ten
/// languages and the name is in none of them: it is the same word on a Polish
/// phone as on a German one, the way Komoot and Blinkist are. Putting it
/// through the string catalogue would invite exactly the well-meaning
/// translation that turns a brand into a common noun.
///
/// It is a constant rather than read from the bundle so the widget extension,
/// the notification and the app all say the same thing without depending on
/// which target's Info.plist they happen to be reading.
public enum AppIdentity {
    /// The product name, as it appears to somebody using it.
    public static let name = "Zeitkonto"

    /// The paid tier. The suffix is not translated either.
    public static let proName = "Zeitkonto Pro"
}
