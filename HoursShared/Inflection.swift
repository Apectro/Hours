import Foundation

extension String {
    /// A localized string with `^[…](inflect: true)` actually applied.
    ///
    /// Automatic grammar agreement is resolved during the bundle lookup, so a
    /// key the catalog does not carry comes back with its markup intact. That
    /// is how "^[16 day](inflect: true) worked" reached the calendar and stayed
    /// there through 252 unit tests: `Localizable.xcstrings` was committed
    /// empty, an empty catalog compiles to nothing at all, and every lookup
    /// returned its own key.
    ///
    /// The catalog now carries these strings, so `String(localized:)` would
    /// work too. This stays because it is correct either way — the lookup
    /// finds a plural-varied value, or `AttributedString` inflects the key —
    /// and a new inflected string is therefore right on the day it is written
    /// rather than on the day someone remembers to add a catalog entry for it.
    /// `InflectionTests` enforces the choice, and separately checks that the
    /// catalog is still reaching the bundle.
    ///
    /// One cost, stated plainly: Xcode's extraction recognises
    /// `String(localized:)` and `AttributedString(localized:)` by name and will
    /// not see literals passed through here, so entries for these keys are
    /// maintained by `Scripts/build-catalog.py` instead.
    init(inflected value: String.LocalizationValue) {
        self = String(AttributedString(localized: value).characters)
    }
}
