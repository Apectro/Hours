import Foundation

/// An amount of money as it is typed: "18,50", "18.5", "1.250,50 €".
///
/// The welcome's rate field is plain text rather than a formatted number
/// field, because a formatted field only hands over its value when it loses
/// focus, and a decimal keypad has no Return to make it — the Continue button
/// would read the rate from before it was typed. So the text is read here, on
/// every keystroke, in whole cents.
enum MoneyInput {
    /// Ten million an hour: more than anyone types, small enough that cents
    /// times minutes stays far inside `Int`.
    static let maximumCents = 1_000_000_000

    /// Whole cents, rounded half up at the third decimal; 0 when nothing
    /// usable was typed. The last comma or point is the decimal mark and any
    /// before it group thousands; everything that is not a digit or a mark —
    /// spaces, a currency sign — is ignored.
    static func cents(from text: String) -> Int {
        let kept = text.filter { $0.isASCII && ($0.isNumber || $0 == "," || $0 == ".") }
        let marks: Set<Character> = [",", "."]
        let whole: Substring
        let fraction: Substring
        if let mark = kept.lastIndex(where: { marks.contains($0) }) {
            whole = kept[..<mark]
            fraction = kept[kept.index(after: mark)...]
        } else {
            whole = Substring(kept)
            fraction = ""
        }
        let wholeDigits = whole.filter(\.isNumber).map { Int(String($0))! }
        let fractionDigits = fraction.filter(\.isNumber).map { Int(String($0))! }

        var cents = 0
        for digit in wholeDigits {
            cents = cents * 10 + digit
            if cents >= maximumCents { return maximumCents }
        }
        cents *= 100
        let padded = fractionDigits + [0, 0, 0]
        cents += padded[0] * 10 + padded[1]
        if padded[2] >= 5 { cents += 1 }
        return min(cents, maximumCents)
    }
}
