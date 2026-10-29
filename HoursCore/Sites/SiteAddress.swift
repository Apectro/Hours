import Foundation

/// A site's address as the sheets print it, and as "Fill in from the saved
/// place" writes it (1.2).
///
/// The address is the user's own words: typed, or filled in once and then
/// theirs to change. Nothing here looks anything up; the app asks Apple Maps
/// for the place's street, number, postcode and city only when that button
/// is tapped, and hands the parts to `compose`.
enum SiteAddress {
    /// One line for the top of a sheet: the typed lines joined with ", ",
    /// blank lines and stray spaces gone, and no comma doubled where a line
    /// already ended with one.
    static func singleLine(_ address: String) -> String {
        address
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                var text = line.trimmingCharacters(in: .whitespaces)
                while text.hasSuffix(",") {
                    text = String(text.dropLast()).trimmingCharacters(in: .whitespaces)
                }
                return text
            }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// Two lines the way an address is written where the app is used:
    /// "Kaiserstraße 12" over "10115 Berlin". A missing part is left out; a
    /// house number without a street says nothing on its own.
    static func compose(street: String?, number: String?, postcode: String?, city: String?) -> String {
        func clean(_ part: String?) -> String { (part ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let streetText = clean(street)
        let first = streetText.isEmpty ? "" : [streetText, clean(number)].filter { !$0.isEmpty }.joined(separator: " ")
        let second = [clean(postcode), clean(city)].filter { !$0.isEmpty }.joined(separator: " ")
        return [first, second].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
