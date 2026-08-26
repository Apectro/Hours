import Foundation

extension String {
    /// A localized string with `^[…](inflect: true)` actually applied.
    ///
    /// `String(localized:)` does not inflect here, and the reason is worth
    /// writing down because it is not obvious. Automatic grammar agreement is
    /// resolved during the bundle lookup, and this app has no table to look in:
    /// `Localizable.xcstrings` is committed empty, an empty catalog compiles to
    /// nothing, and so there is no `en.lproj`, no `Localizable.strings` and no
    /// `Localizable.stringsdict` in the built product. Every lookup returns its
    /// own key, markup and all — which is how "^[16 day](inflect: true) worked"
    /// reached the calendar and stayed there through 252 unit tests.
    ///
    /// `AttributedString(localized:)` applies morphology whether or not the
    /// lookup found anything, so it gives "16 days worked" today and keeps
    /// giving it once the catalog is populated.
    ///
    /// One cost, stated plainly: Xcode's string extraction recognises
    /// `String(localized:)` and `AttributedString(localized:)` by name, and
    /// will not see literals passed through here. That matters the day someone
    /// translates this app — and it costs nothing today, because extraction
    /// currently produces an empty catalog either way. Populating the catalog
    /// is the fix that would let the call sites go back to `String(localized:)`;
    /// this is the fix that makes the app read correctly in the meantime.
    init(inflected value: String.LocalizationValue) {
        self = String(AttributedString(localized: value).characters)
    }
}
