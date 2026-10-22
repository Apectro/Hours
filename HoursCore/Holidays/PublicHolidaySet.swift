import Foundation

/// A country the app can offer public holidays for: the countries whose
/// languages the app speaks, plus Austria and Switzerland.
///
/// Nothing here is ever chosen for the person. "Never guess a country" still
/// holds; what changed is that picking one is a tap instead of an afternoon.
enum HolidayCountry: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case de, at, ch, hr, si, it, fr, es, pt, nl, pl

    var id: String { rawValue }

    /// ISO 3166 code, for the system to name the country in the phone's
    /// language.
    var regionCode: String { rawValue.uppercased() }

    /// The states or cantons, where the holidays depend on them. Empty means
    /// the national list is the whole answer.
    var regions: [HolidayRegion] {
        switch self {
        case .de: return HolidayRegion.germanStates
        case .ch: return HolidayRegion.swissCantons
        default: return []
        }
    }

    /// The Swiss cantons not in the table yet, which get the holidays every
    /// canton shares and a note to add the rest.
    static let otherSwissCanton = "other"
}

/// A German state or Swiss canton, named as it names itself.
struct HolidayRegion: Hashable, Sendable, Identifiable {
    var code: String
    var name: String

    var id: String { code }
}

/// Why a holiday is offered but not ticked.
enum PublicHolidayNote: String, Codable, Hashable, Sendable {
    /// A public holiday only in part of the state or canton (some
    /// municipalities, one city).
    case partOfRegion
    /// Widely a day off, but by custom or agreement, not by law.
    case customary
    /// Off for many, depending on the collective agreement (CAO/KV/GAV).
    case collectiveAgreement
}

/// Something worth saying under a list, about days that are not on it.
enum PublicHolidayTip: String, Codable, Hashable, Sendable {
    /// 24 and 31 December are often off by collective agreement (Austria).
    case christmasEveAndNewYearsEve
    /// The canton is not in the table: only the holidays every canton shares.
    case cantonalHolidaysMissing
    /// Regional or municipal holidays exist and are not included.
    case regionalHolidaysNotIncluded
    /// A holiday on a Sunday may be moved to the Monday by the region (Spain).
    case sundayMovedToMonday
}

/// One public holiday in a set.
struct PublicHoliday: Hashable, Sendable, Identifiable {
    /// Stable within a set, and shared between sets for the same feast
    /// (`christmas`, `easterMonday`), so tests and the UI can name it.
    var id: String
    /// In the set's language: what it is called on the site's calendar.
    var localName: String
    var englishName: String
    var recurrence: HolidayRecurrence
    /// Offered in the preview but not ticked; `note` says why.
    var note: PublicHolidayNote?

    var isOptional: Bool { note != nil }

    /// The local name when the phone speaks the set's language, the English
    /// one on an English phone, and otherwise the local name — which is the
    /// one printed on the employer's calendar and the payslip.
    func name(in language: ExportLanguage, setLanguage: ExportLanguage) -> String {
        let language = language.resolved
        if language == setLanguage { return localName }
        if language == .english { return englishName }
        return localName
    }
}

/// A country's, or a region's, public holidays.
struct PublicHolidaySet: Hashable, Sendable, Identifiable {
    /// `DE-BY`, `AT`, `CH-ZH`, `CH-other`.
    var id: String
    var country: HolidayCountry
    var region: HolidayRegion?
    /// The language the local names are in.
    var language: ExportLanguage
    /// The year the table was last checked against the official list.
    var checkedFor: Int
    /// Where it was checked: the law or official list.
    var source: String
    var holidays: [PublicHoliday]
    var tips: [PublicHolidayTip]

    /// The rules adding the ticked holidays would create, named for the
    /// phone. Each a normal `HolidayRule`: paid absence, editable,
    /// disable-able, deletable.
    func rules(for selection: Set<String>, language phoneLanguage: ExportLanguage) -> [HolidayRule] {
        holidays
            .filter { selection.contains($0.id) }
            .map { HolidayRule(name: $0.name(in: phoneLanguage, setLanguage: language), recurrence: $0.recurrence) }
    }

    /// What the preview ticks to begin with: everything but the optional.
    var defaultSelection: Set<String> {
        Set(holidays.filter { !$0.isOptional }.map(\.id))
    }
}

enum PublicHolidayCatalog {
    static func set(country: HolidayCountry, region: String?) -> PublicHolidaySet? {
        switch country {
        case .de: return region.flatMap(PublicHolidayCatalog.germany)
        case .ch: return region.flatMap(PublicHolidayCatalog.switzerland)
        default:
            return region == nil ? PublicHolidayCatalog.national(country) : nil
        }
    }

    static func set(id: String) -> PublicHolidaySet? {
        allSets.first { $0.id == id }
    }

    static var allSets: [PublicHolidaySet] {
        HolidayCountry.allCases.flatMap { country -> [PublicHolidaySet] in
            if country.regions.isEmpty {
                return set(country: country, region: nil).map { [$0] } ?? []
            }
            return country.regions.compactMap { set(country: country, region: $0.code) }
        }
    }
}

// MARK: - Building the tables

extension PublicHolidayCatalog {
    /// A holiday in a table. Short, because the tables are long.
    static func h(
        _ id: String,
        _ localName: String,
        _ englishName: String,
        _ recurrence: HolidayRecurrence,
        from startYear: Int? = nil,
        note: PublicHolidayNote? = nil
    ) -> PublicHoliday {
        var recurrence = recurrence
        recurrence.startYear = startYear
        return PublicHoliday(id: id, localName: localName, englishName: englishName, recurrence: recurrence, note: note)
    }

    /// A fixed date, day first as the tables' sources write it.
    static func on(_ day: Int, _ month: Int) -> HolidayRecurrence {
        .annual(month: month, day: day)
    }

    /// A set, its holidays in the order they fall in the year it was checked
    /// for, which is the order the preview lists them in.
    static func makeSet(
        id: String,
        country: HolidayCountry,
        region: HolidayRegion? = nil,
        language: ExportLanguage,
        checkedFor: Int = 2026,
        source: String,
        holidays: [PublicHoliday],
        tips: [PublicHolidayTip] = []
    ) -> PublicHolidaySet {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        func key(_ holiday: PublicHoliday) -> Int {
            // A rule that starts later than the checked year still sorts by
            // where it falls.
            var recurrence = holiday.recurrence
            recurrence.startYear = nil
            return recurrence.occurrence(inYear: checkedFor, calendar: calendar)?.key ?? Int.max
        }
        return PublicHolidaySet(
            id: id, country: country, region: region, language: language, checkedFor: checkedFor,
            source: source, holidays: holidays.sorted { key($0) < key($1) }, tips: tips
        )
    }

    /// Days from Easter Sunday.
    static func easter(_ offset: Int) -> HolidayRecurrence {
        .easter(offset: offset)
    }
}
