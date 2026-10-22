import Foundation

// Germany: the nine nationwide holidays and each state's own.
//
// Checked for 2026 against the states' Feiertagsgesetze (summarised by the
// Bundesministerium des Innern's "Gesetzliche Feiertage" list). Holidays that
// apply only in part of a state are offered unticked rather than left out:
// - Bavaria, Mariä Himmelfahrt: only in municipalities with a predominantly
//   Catholic population (most of them; the state statistics office lists
//   them). Augsburger Hohes Friedensfest: only in the city of Augsburg.
// - Saxony and Thuringia, Fronleichnam: only in some Catholic municipalities
//   (Sorbian Lusatia; Eichsfeld and others).
// Dates that came later carry their first year: Reformationstag in the north
// (2018), Frauentag in Berlin (2019) and Mecklenburg-Vorpommern (2023),
// Weltkindertag in Thuringia (2019).

extension HolidayRegion {
    static let germanStates: [HolidayRegion] = [
        HolidayRegion(code: "BW", name: "Baden-Württemberg"),
        HolidayRegion(code: "BY", name: "Bayern"),
        HolidayRegion(code: "BE", name: "Berlin"),
        HolidayRegion(code: "BB", name: "Brandenburg"),
        HolidayRegion(code: "HB", name: "Bremen"),
        HolidayRegion(code: "HH", name: "Hamburg"),
        HolidayRegion(code: "HE", name: "Hessen"),
        HolidayRegion(code: "MV", name: "Mecklenburg-Vorpommern"),
        HolidayRegion(code: "NI", name: "Niedersachsen"),
        HolidayRegion(code: "NW", name: "Nordrhein-Westfalen"),
        HolidayRegion(code: "RP", name: "Rheinland-Pfalz"),
        HolidayRegion(code: "SL", name: "Saarland"),
        HolidayRegion(code: "SN", name: "Sachsen"),
        HolidayRegion(code: "ST", name: "Sachsen-Anhalt"),
        HolidayRegion(code: "SH", name: "Schleswig-Holstein"),
        HolidayRegion(code: "TH", name: "Thüringen"),
    ]
}

extension PublicHolidayCatalog {
    private static let germanNationwide: [PublicHoliday] = [
        h("newYear", "Neujahr", "New Year's Day", on(1, 1)),
        h("goodFriday", "Karfreitag", "Good Friday", easter(-2)),
        h("easterMonday", "Ostermontag", "Easter Monday", easter(1)),
        h("labourDay", "Tag der Arbeit", "Labour Day", on(1, 5)),
        h("ascension", "Christi Himmelfahrt", "Ascension Day", easter(39)),
        h("whitMonday", "Pfingstmontag", "Whit Monday", easter(50)),
        h("germanUnity", "Tag der Deutschen Einheit", "German Unity Day", on(3, 10)),
        h("christmas", "1. Weihnachtstag", "Christmas Day", on(25, 12)),
        h("stStephen", "2. Weihnachtstag", "St Stephen's Day", on(26, 12)),
    ]

    private static let epiphany = h("epiphany", "Heilige Drei Könige", "Epiphany", on(6, 1))
    private static let corpusChristi = h("corpusChristi", "Fronleichnam", "Corpus Christi", easter(60))
    private static let assumption = h("assumption", "Mariä Himmelfahrt", "Assumption Day", on(15, 8))
    private static let allSaints = h("allSaints", "Allerheiligen", "All Saints' Day", on(1, 11))
    private static let reformation = h("reformationDay", "Reformationstag", "Reformation Day", on(31, 10))
    private static let reformationSince2018 = h(
        "reformationDay", "Reformationstag", "Reformation Day", on(31, 10), from: 2018
    )

    private static func germanExtras(_ state: String) -> [PublicHoliday]? {
        switch state {
        case "BW": return [epiphany, corpusChristi, allSaints]
        case "BY":
            return [
                epiphany, corpusChristi, allSaints,
                h("assumption", "Mariä Himmelfahrt", "Assumption Day", on(15, 8), note: .partOfRegion),
                h("augsburgPeace", "Augsburger Hohes Friedensfest", "Augsburg Peace Festival", on(8, 8),
                  note: .partOfRegion),
            ]
        case "BE":
            return [h("womensDay", "Internationaler Frauentag", "International Women's Day", on(8, 3), from: 2019)]
        case "BB":
            return [
                h("easterSunday", "Ostersonntag", "Easter Sunday", easter(0)),
                h("whitSunday", "Pfingstsonntag", "Whit Sunday", easter(49)),
                reformation,
            ]
        case "HB", "HH", "NI", "SH": return [reformationSince2018]
        case "HE": return [corpusChristi]
        case "MV":
            return [
                h("womensDay", "Internationaler Frauentag", "International Women's Day", on(8, 3), from: 2023),
                reformation,
            ]
        case "NW", "RP": return [corpusChristi, allSaints]
        case "SL": return [corpusChristi, assumption, allSaints]
        case "SN":
            return [
                reformation,
                h("repentanceDay", "Buß- und Bettag", "Day of Repentance and Prayer",
                  .weekdayOnOrAfter(month: 11, day: 16, weekday: 4)),
                h("corpusChristi", "Fronleichnam", "Corpus Christi", easter(60), note: .partOfRegion),
            ]
        case "ST": return [epiphany, reformation]
        case "TH":
            return [
                h("childrensDay", "Weltkindertag", "World Children's Day", on(20, 9), from: 2019),
                reformation,
                h("corpusChristi", "Fronleichnam", "Corpus Christi", easter(60), note: .partOfRegion),
            ]
        default: return nil
        }
    }

    static func germany(_ state: String) -> PublicHolidaySet? {
        guard let region = HolidayRegion.germanStates.first(where: { $0.code == state }),
              let extras = germanExtras(state) else { return nil }
        return makeSet(
            id: "DE-\(state)",
            country: .de,
            region: region,
            language: .german,
            source: "Feiertagsgesetze der Länder; BMI, Übersicht der gesetzlichen Feiertage",
            holidays: germanNationwide + extras
        )
    }
}
