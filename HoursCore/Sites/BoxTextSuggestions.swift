import Foundation

/// One line of text the camera read on a box: what it says, how big it is
/// in the picture (any unit, only compared with the others), and how far its
/// middle is from the barcode's.
struct RecognisedLine: Hashable, Sendable {
    let text: String
    let area: Double
    let distanceToCode: Double

    init(text: String, area: Double, distanceToCode: Double) {
        self.text = text
        self.area = area
        self.distanceToCode = distanceToCode
    }
}

/// Reading an item's name off the box (1.3): while a new barcode is read the
/// camera also reads the text around it, and the New item sheet offers what
/// looks like a name ("From the box"). On the phone only; nothing is looked
/// up. Also the Scan text tray, which joins the lines tapped.
enum BoxTextSuggestions {
    /// How many names are offered.
    static let limit = 4
    /// Longer than this is a sentence on the box, not a name.
    static let maximumLength = 40
    /// Fewer letters than this is a code or a unit.
    static let minimumLetters = 3

    /// The lines that look like a name, cleaned and without repeats, the
    /// most prominent first: lines mostly of letters before ones mostly of
    /// numbers, then the largest, then the nearest the barcode.
    static func names(from lines: [RecognisedLine], code: String) -> [String] {
        let candidates = lines.enumerated().compactMap { index, line -> Candidate? in
            let text = cleaned(line.text)
            guard isName(text, code: code) else { return nil }
            return Candidate(text: text, line: line, index: index)
        }
        let ordered = candidates.sorted { a, b in
            if a.mostlyLetters != b.mostlyLetters { return a.mostlyLetters }
            if a.line.area != b.line.area { return a.line.area > b.line.area }
            if a.line.distanceToCode != b.line.distanceToCode { return a.line.distanceToCode < b.line.distanceToCode }
            return a.index < b.index
        }
        var seen = Set<String>()
        var names: [String] = []
        for candidate in ordered where names.count < limit {
            let key = candidate.text.lowercased()
            guard seen.insert(key).inserted else { continue }
            names.append(candidate.text)
        }
        return names
    }

    /// The Scan text tray with one more line tapped: joined with a space,
    /// an empty line adding nothing.
    static func appending(_ line: String, to tray: String) -> String {
        let added = cleaned(line)
        guard !added.isEmpty else { return tray }
        let current = cleaned(tray)
        return current.isEmpty ? added : "\(current) \(added)"
    }

    /// Scan text's "Use" in a field that is a description (What was done):
    /// the text goes after what is already typed, with a space between
    /// unless the field already ends in a space or a new line. A field with
    /// nothing but spaces is empty; nothing scanned leaves it as it is.
    /// Name fields are replaced instead, by their own sheets.
    static func adding(_ scanned: String, to typed: String) -> String {
        let added = cleaned(scanned)
        guard !added.isEmpty else { return typed }
        guard typed.contains(where: { !($0.isWhitespace || $0.isNewline) }) else { return added }
        if let last = typed.last, last.isWhitespace || last.isNewline {
            return typed + added
        }
        return typed + " " + added
    }

    /// Trimmed, with every run of spaces or line breaks one space.
    static func cleaned(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    // MARK: - The rules

    private struct Candidate {
        let text: String
        let line: RecognisedLine
        let index: Int

        var mostlyLetters: Bool {
            let letters = text.filter(\.isLetter).count
            let digits = text.filter(\.isNumber).count
            return letters >= digits
        }
    }

    private static func isName(_ text: String, code: String) -> Bool {
        guard !text.isEmpty, text.count <= maximumLength else { return false }
        guard text.filter(\.isLetter).count >= minimumLetters else { return false }
        guard !containsCode(text, code: code) else { return false }
        guard !matches(pricePattern, text), !matches(addressPattern, text) else { return false }
        return hasWord(text)
    }

    /// The barcode's own number printed under it, with or without spaces.
    private static func containsCode(_ text: String, code: String) -> Bool {
        let codeDigits = code.filter(\.isNumber)
        if codeDigits.count >= 6, text.filter(\.isNumber).contains(codeDigits) { return true }
        let compactCode = code.filter { $0.isLetter || $0.isNumber }.lowercased()
        let compactText = text.filter { $0.isLetter || $0.isNumber }.lowercased()
        return !compactCode.isEmpty && compactText == compactCode
    }

    /// Something that reads as a word: two letters or more and nothing else
    /// (a hyphen or an apostrophe inside it is fine), not a unit ("kg",
    /// "ml", "Hz") and not a code's label ("EAN", "Art. Nr.").
    private static func hasWord(_ text: String) -> Bool {
        text.split(separator: " ").contains { token in
            let trimmed = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            let letters = trimmed.filter { !"-'’.".contains($0) }
            guard letters.count >= 2, letters.allSatisfy(\.isLetter) else { return false }
            let key = letters.lowercased()
            return !units.contains(key) && !labels.contains(key)
        }
    }

    private static let units: Set<String> = [
        "kg", "mg", "mm", "cm", "dm", "km", "ml", "cl", "dl", "kw", "mw", "ma", "mah", "hz", "khz",
        "pcs", "pc", "stk", "st", "pk", "qm", "lfm", "xl", "xxl",
    ]

    private static let labels: Set<String> = [
        "ean", "gtin", "upc", "sku", "ref", "lot", "art", "artnr", "nr", "no", "batch", "charge",
        "pzn", "mfg", "exp", "id",
    ]

    /// "4,99 €", "€ 12.50", "3,20 EUR", "CHF 9.90".
    private static let pricePattern = try? NSRegularExpression(
        pattern: #"[€$£¥]\s*\d|\d\s*[€$£¥]|\d[\d.,]*\s*(eur|chf|usd|gbp|kn|pln|zł)(?![\p{L}])|(eur|chf|usd|gbp|pln)\s*\d"#,
        options: [.caseInsensitive]
    )

    /// "www.example.com", "https://…", "example.de", "info@example.com".
    private static let addressPattern = try? NSRegularExpression(
        pattern: #"://|www\.|@[\p{L}\d-]+\.|[\p{L}\d-]+\.(com|net|org|de|at|ch|hr|si|it|fr|nl|pl|pt|es|eu|info|io|co|uk)(?![\p{L}])"#,
        options: [.caseInsensitive]
    )

    private static func matches(_ pattern: NSRegularExpression?, _ text: String) -> Bool {
        guard let pattern else { return false }
        return pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
