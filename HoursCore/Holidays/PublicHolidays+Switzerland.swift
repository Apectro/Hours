import Foundation

// Switzerland: 1 August is the only federal holiday; everything else is the
// canton's. Checked for 2026 against the cantons' Ruhetags- and
// Feiertagsgesetze (and the SECO/Federal Office of Justice overview of
// cantonal holidays). Accuracy over coverage: a canton not listed gets the
// four days every canton shares (New Year, Ascension, 1 August, Christmas)
// and a note to add its own, and a day that is only customary, or only a
// holiday in some municipalities, is offered unticked.
//
// Left out on purpose, because they are customary or local rather than
// cantonal law, or because the table could not be confirmed:
// - Berchtoldstag (2 Jan) in ZH and LU: widely off, not a statutory holiday
//   there; offered unticked. Not offered in SG and ZG (not confirmed).
// - Valais: Easter Monday, Whit Monday and 26 December are commonly off but
//   not cantonal holidays; not offered.
// - Aargau: the Catholic feasts, Berchtoldstag and St Stephen's Day differ by
//   district and municipality; offered unticked.
// - 1 May in Geneva and Vaud, and local days such as Sechseläuten or
//   Knabenschiessen (Zurich city afternoons): not included.

extension HolidayRegion {
    static let swissCantons: [HolidayRegion] = [
        HolidayRegion(code: "AG", name: "Aargau"),
        HolidayRegion(code: "BL", name: "Basel-Landschaft"),
        HolidayRegion(code: "BS", name: "Basel-Stadt"),
        HolidayRegion(code: "BE", name: "Bern"),
        HolidayRegion(code: "GE", name: "Genève"),
        HolidayRegion(code: "LU", name: "Luzern"),
        HolidayRegion(code: "SG", name: "St. Gallen"),
        HolidayRegion(code: "TI", name: "Ticino"),
        HolidayRegion(code: "VS", name: "Valais/Wallis"),
        HolidayRegion(code: "VD", name: "Vaud"),
        HolidayRegion(code: "ZG", name: "Zug"),
        HolidayRegion(code: "ZH", name: "Zürich"),
        HolidayRegion(code: HolidayCountry.otherSwissCanton, name: "–"),
    ]
}

extension PublicHolidayCatalog {
    // German-speaking cantons.
    private static let chNewYear = h("newYear", "Neujahr", "New Year's Day", on(1, 1))
    private static let chBerchtold = h("berchtold", "Berchtoldstag", "St Berchtold's Day", on(2, 1))
    private static let chGoodFriday = h("goodFriday", "Karfreitag", "Good Friday", easter(-2))
    private static let chEasterMonday = h("easterMonday", "Ostermontag", "Easter Monday", easter(1))
    private static let chLabourDay = h("labourDay", "Tag der Arbeit", "Labour Day", on(1, 5))
    private static let chAscension = h("ascension", "Auffahrt", "Ascension Day", easter(39))
    private static let chWhitMonday = h("whitMonday", "Pfingstmontag", "Whit Monday", easter(50))
    private static let chCorpusChristi = h("corpusChristi", "Fronleichnam", "Corpus Christi", easter(60))
    private static let chNationalDay = h("nationalDay", "Bundesfeier", "Swiss National Day", on(1, 8))
    private static let chAssumption = h("assumption", "Mariä Himmelfahrt", "Assumption Day", on(15, 8))
    private static let chAllSaints = h("allSaints", "Allerheiligen", "All Saints' Day", on(1, 11))
    private static let chImmaculate = h(
        "immaculateConception", "Mariä Empfängnis", "Immaculate Conception", on(8, 12)
    )
    private static let chChristmas = h("christmas", "Weihnachtstag", "Christmas Day", on(25, 12))
    private static let chStStephen = h("stStephen", "Stephanstag", "St Stephen's Day", on(26, 12))

    private static func optional(_ holiday: PublicHoliday, _ note: PublicHolidayNote) -> PublicHoliday {
        var holiday = holiday
        holiday.note = note
        return holiday
    }

    private static func swissHolidays(_ canton: String) -> (ExportLanguage, String, [PublicHoliday])? {
        switch canton {
        case "ZH":
            return (.german, "Ruhetags- und Ladenöffnungsgesetz des Kantons Zürich", [
                chNewYear, optional(chBerchtold, .customary), chGoodFriday, chEasterMonday, chLabourDay,
                chAscension, chWhitMonday, chNationalDay, chChristmas, chStStephen,
            ])
        case "BE":
            return (.german, "Gesetz über die Ruhe an öffentlichen Feiertagen, Kanton Bern", [
                chNewYear, chBerchtold, chGoodFriday, chEasterMonday, chAscension, chWhitMonday,
                chNationalDay, chChristmas, chStStephen,
            ])
        case "LU":
            return (.german, "Ruhetagsgesetz des Kantons Luzern", [
                chNewYear, optional(chBerchtold, .customary), chGoodFriday, chEasterMonday, chAscension,
                chWhitMonday, chCorpusChristi, chNationalDay, chAssumption, chAllSaints, chImmaculate,
                chChristmas, chStStephen,
            ])
        case "BS":
            return (.german, "Ruhetagsgesetz des Kantons Basel-Stadt", [
                chNewYear, chGoodFriday, chEasterMonday, chLabourDay, chAscension, chWhitMonday,
                chNationalDay, chChristmas, chStStephen,
            ])
        case "BL":
            return (.german, "Gesetz über die öffentlichen Ruhetage, Kanton Basel-Landschaft", [
                chNewYear, chGoodFriday, chEasterMonday, chLabourDay, chAscension, chWhitMonday,
                chNationalDay, chChristmas, chStStephen,
            ])
        case "AG":
            return (.german, "Gesetz über die öffentlichen Ruhetage, Kanton Aargau", [
                chNewYear, optional(chBerchtold, .partOfRegion), chGoodFriday, chEasterMonday, chAscension,
                chWhitMonday, optional(chCorpusChristi, .partOfRegion), chNationalDay,
                optional(chAssumption, .partOfRegion), optional(chAllSaints, .partOfRegion),
                optional(chImmaculate, .partOfRegion), chChristmas, optional(chStStephen, .partOfRegion),
            ])
        case "SG":
            return (.german, "Ruhetagsgesetz des Kantons St. Gallen", [
                chNewYear, chGoodFriday, chEasterMonday, chAscension, chWhitMonday, chNationalDay,
                chAllSaints, chChristmas, chStStephen,
            ])
        case "ZG":
            return (.german, "Gesetz über die öffentlichen Ruhetage, Kanton Zug", [
                chNewYear, chGoodFriday, chEasterMonday, chAscension, chWhitMonday, chCorpusChristi,
                chNationalDay, chAssumption, chAllSaints, chImmaculate, chChristmas, chStStephen,
            ])
        case "TI":
            return (.italian, "Legge sul riposo infrasettimanale, Cantone Ticino", [
                h("newYear", "Capodanno", "New Year's Day", on(1, 1)),
                h("epiphany", "Epifania", "Epiphany", on(6, 1)),
                h("stJoseph", "San Giuseppe", "St Joseph's Day", on(19, 3)),
                h("easterMonday", "Lunedì di Pasqua", "Easter Monday", easter(1)),
                h("labourDay", "Festa del lavoro", "Labour Day", on(1, 5)),
                h("ascension", "Ascensione", "Ascension Day", easter(39)),
                h("whitMonday", "Lunedì di Pentecoste", "Whit Monday", easter(50)),
                h("corpusChristi", "Corpus Domini", "Corpus Christi", easter(60)),
                h("stPeterPaul", "Santi Pietro e Paolo", "Saints Peter and Paul", on(29, 6)),
                h("nationalDay", "Festa nazionale", "Swiss National Day", on(1, 8)),
                h("assumption", "Assunzione", "Assumption Day", on(15, 8)),
                h("allSaints", "Ognissanti", "All Saints' Day", on(1, 11)),
                h("immaculateConception", "Immacolata Concezione", "Immaculate Conception", on(8, 12)),
                h("christmas", "Natale", "Christmas Day", on(25, 12)),
                h("stStephen", "Santo Stefano", "St Stephen's Day", on(26, 12)),
            ])
        case "VD":
            return (.french, "Loi sur les jours fériés, Canton de Vaud", [
                h("newYear", "Nouvel An", "New Year's Day", on(1, 1)),
                h("berchtold", "2 janvier", "St Berchtold's Day", on(2, 1)),
                h("goodFriday", "Vendredi saint", "Good Friday", easter(-2)),
                h("easterMonday", "Lundi de Pâques", "Easter Monday", easter(1)),
                h("ascension", "Ascension", "Ascension Day", easter(39)),
                h("whitMonday", "Lundi de Pentecôte", "Whit Monday", easter(50)),
                h("nationalDay", "Fête nationale", "Swiss National Day", on(1, 8)),
                h("fastMonday", "Lundi du Jeûne fédéral", "Federal Fast Monday",
                  .weekdayOnOrAfter(month: 9, day: 16, weekday: 2)),
                h("christmas", "Noël", "Christmas Day", on(25, 12)),
            ])
        case "GE":
            return (.french, "Loi sur les jours fériés, République et canton de Genève", [
                h("newYear", "Nouvel An", "New Year's Day", on(1, 1)),
                h("goodFriday", "Vendredi saint", "Good Friday", easter(-2)),
                h("easterMonday", "Lundi de Pâques", "Easter Monday", easter(1)),
                h("ascension", "Ascension", "Ascension Day", easter(39)),
                h("whitMonday", "Lundi de Pentecôte", "Whit Monday", easter(50)),
                h("nationalDay", "Fête nationale", "Swiss National Day", on(1, 8)),
                // The Thursday after the first Sunday of September.
                h("genevaFast", "Jeûne genevois", "Geneva Fast",
                  .weekdayOnOrAfter(month: 9, day: 5, weekday: 5)),
                h("christmas", "Noël", "Christmas Day", on(25, 12)),
                h("restoration", "Restauration de la République", "Restoration of the Republic", on(31, 12)),
            ])
        case "VS":
            return (.french, "Loi sur le repos dominical et les jours fériés, Canton du Valais", [
                h("newYear", "Nouvel An", "New Year's Day", on(1, 1)),
                h("stJoseph", "Saint-Joseph", "St Joseph's Day", on(19, 3)),
                h("ascension", "Ascension", "Ascension Day", easter(39)),
                h("corpusChristi", "Fête-Dieu", "Corpus Christi", easter(60)),
                h("nationalDay", "Fête nationale", "Swiss National Day", on(1, 8)),
                h("assumption", "Assomption", "Assumption Day", on(15, 8)),
                h("allSaints", "Toussaint", "All Saints' Day", on(1, 11)),
                h("immaculateConception", "Immaculée Conception", "Immaculate Conception", on(8, 12)),
                h("christmas", "Noël", "Christmas Day", on(25, 12)),
            ])
        case HolidayCountry.otherSwissCanton:
            return (.german, "Arbeitsgesetz Art. 20a; Bundesfeiertag (Art. 110 Abs. 3 BV)", [
                chNewYear, chAscension, chNationalDay, chChristmas,
            ])
        default:
            return nil
        }
    }

    static func switzerland(_ canton: String) -> PublicHolidaySet? {
        guard let region = HolidayRegion.swissCantons.first(where: { $0.code == canton }),
              let (language, source, holidays) = swissHolidays(canton) else { return nil }
        let isOther = canton == HolidayCountry.otherSwissCanton
        return makeSet(
            id: "CH-\(canton)",
            country: .ch,
            region: region,
            language: language,
            source: source,
            holidays: holidays,
            tips: isOther ? [.cantonalHolidaysMissing] : [.regionalHolidaysNotIncluded]
        )
    }
}
