import Foundation

/// Counted words on an exported page: "3 people", "21 days on site".
///
/// The app's own screens get this from automatic grammatical agreement, which
/// is a Foundation-on-Apple feature and not something the engine can lean on —
/// it is built on Linux too. So the plural rules are written out here, once,
/// for the ten languages the export speaks. They are CLDR's integer rules,
/// which is all a count of people or days ever needs.
extension ExportLanguage {
    /// The plural forms a language distinguishes for a whole number.
    enum PluralCategory: Hashable, Sendable {
        case one, two, few, many, other
    }

    func pluralCategory(_ count: Int) -> PluralCategory {
        let n = abs(count)
        let lastDigit = n % 10
        let lastTwo = n % 100
        switch resolved {
        case .croatian:
            if lastDigit == 1 && lastTwo != 11 { return .one }
            if (2...4).contains(lastDigit) && !(12...14).contains(lastTwo) { return .few }
            return .other
        case .slovenian:
            switch lastTwo {
            case 1: return .one
            case 2: return .two
            case 3, 4: return .few
            default: return .other
            }
        case .polish:
            if n == 1 { return .one }
            if (2...4).contains(lastDigit) && !(12...14).contains(lastTwo) { return .few }
            return .many
        case .french:
            // French counts nought with one: "0 personne".
            return n <= 1 ? .one : .other
        default:
            return n == 1 ? .one : .other
        }
    }

    /// "1 person", "5 people".
    func people(_ count: Int) -> String {
        let noun: String
        switch pluralCategory(count) {
        case .one:
            noun = pick(en: "person", de: "Person", hr: "osoba", sl: "oseba", it: "persona", fr: "personne",
                        es: "persona", pt: "pessoa", nl: "persoon", pl: "osoba")
        case .two:
            noun = pick(en: "people", de: "Personen", hr: "osobe", sl: "osebi", it: "persone", fr: "personnes",
                        es: "personas", pt: "pessoas", nl: "personen", pl: "osoby")
        case .few:
            noun = pick(en: "people", de: "Personen", hr: "osobe", sl: "osebe", it: "persone", fr: "personnes",
                        es: "personas", pt: "pessoas", nl: "personen", pl: "osoby")
        case .many, .other:
            noun = pick(en: "people", de: "Personen", hr: "osoba", sl: "oseb", it: "persone", fr: "personnes",
                        es: "personas", pt: "pessoas", nl: "personen", pl: "osób")
        }
        return "\(count) \(noun)"
    }

    /// "1 day on site", "21 days on site".
    func daysOnSite(_ count: Int) -> String {
        let phrase: String
        switch pluralCategory(count) {
        case .one:
            phrase = pick(en: "day on site", de: "Tag auf der Baustelle", hr: "dan na gradilištu",
                          sl: "dan na gradbišču", it: "giorno in cantiere", fr: "jour sur le chantier",
                          es: "día en obra", pt: "dia em obra", nl: "dag op de bouwplaats", pl: "dzień na budowie")
        case .two:
            phrase = pick(en: "days on site", de: "Tage auf der Baustelle", hr: "dana na gradilištu",
                          sl: "dneva na gradbišču", it: "giorni in cantiere", fr: "jours sur le chantier",
                          es: "días en obra", pt: "dias em obra", nl: "dagen op de bouwplaats", pl: "dni na budowie")
        case .few:
            phrase = pick(en: "days on site", de: "Tage auf der Baustelle", hr: "dana na gradilištu",
                          sl: "dnevi na gradbišču", it: "giorni in cantiere", fr: "jours sur le chantier",
                          es: "días en obra", pt: "dias em obra", nl: "dagen op de bouwplaats", pl: "dni na budowie")
        case .many, .other:
            phrase = pick(en: "days on site", de: "Tage auf der Baustelle", hr: "dana na gradilištu",
                          sl: "dni na gradbišču", it: "giorni in cantiere", fr: "jours sur le chantier",
                          es: "días en obra", pt: "dias em obra", nl: "dagen op de bouwplaats", pl: "dni na budowie")
        }
        return "\(count) \(phrase)"
    }

    /// "page 2 of 3". Every language here puts the words in that order, so
    /// one shape serves them all.
    func pageOf(_ page: Int, _ count: Int) -> String {
        [self(.page), String(page), self(.of), String(count)].joined(separator: " ")
    }

    /// "People 1–5 of 9", over a part of a site sheet split across pages;
    /// "People 9 of 9" for a part of one.
    func peopleOnPage(_ people: ClosedRange<Int>, of total: Int) -> String {
        let range = people.count == 1 ? String(people.lowerBound) : "\(people.lowerBound)–\(people.upperBound)"
        return self(.peopleOnPage)
            .replacingOccurrences(of: "{range}", with: range)
            .replacingOccurrences(of: "{total}", with: String(total))
    }

    /// "+2 more", after the first site names of a sheet's title.
    func moreSites(_ count: Int) -> String {
        self(.moreSites).replacingOccurrences(of: "{count}", with: String(count))
    }

    /// The sites a sheet covers, in the order they were first worked:
    /// "Hauptstraße 12 · Trg Pravde"; up to three by name, and beyond that
    /// the first two and "+2 more", so the eyebrow stays one line. Blank
    /// names are left out and a name given twice counts once.
    func combinedSiteNames(_ names: [String]) -> String {
        var seen = Set<String>()
        let unique = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard unique.count > 3 else { return unique.joined(separator: " · ") }
        return unique.prefix(2).joined(separator: " · ") + " " + moreSites(unique.count - 2)
    }

    /// A heading as it reads inside a longer one — "Ana hours" rather than
    /// "Ana Hours". German keeps its capital: nearly every heading is a noun,
    /// and a German noun in lower case is a spelling mistake.
    func inline(_ heading: String) -> String {
        guard resolved != .german, let first = heading.first else { return heading }
        return first.lowercased() + heading.dropFirst()
    }
}
