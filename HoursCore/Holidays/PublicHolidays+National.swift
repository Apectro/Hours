import Foundation

// The countries with one national list. Each checked for 2026 against the
// source named on its set. National holidays only: regional and municipal
// ones (a city's patron saint, a Spanish community's own days, Alsace-
// Moselle's Good Friday and 26 December) are not included, and the preview
// says so.
//
// Left out because they could not be confirmed:
// - Italy: San Francesco d'Assisi (4 October), reported as restored as a
//   national holiday from 2026. Not added until confirmed in the Gazzetta
//   Ufficiale; a person can add it by hand.
// - Slovenia: any newer work-free day beyond the list in the Zakon o
//   praznikih in dela prostih dnevih as known here.

extension PublicHolidayCatalog {
    static func national(_ country: HolidayCountry) -> PublicHolidaySet? {
        switch country {
        case .at: return austria
        case .hr: return croatia
        case .si: return slovenia
        case .it: return italy
        case .fr: return france
        case .es: return spain
        case .pt: return portugal
        case .nl: return netherlands
        case .pl: return poland
        case .de, .ch: return nil
        }
    }

    /// Arbeitsruhegesetz § 7 (2). Good Friday stopped being a holiday for
    /// anyone in 2019 (it became the "persönlicher Feiertag").
    private static var austria: PublicHolidaySet {
        makeSet(
            id: "AT", country: .at, language: .german,
            source: "Arbeitsruhegesetz (ARG) § 7 Abs. 2",
            holidays: [
                h("newYear", "Neujahr", "New Year's Day", on(1, 1)),
                h("epiphany", "Heilige Drei Könige", "Epiphany", on(6, 1)),
                h("easterMonday", "Ostermontag", "Easter Monday", easter(1)),
                h("labourDay", "Staatsfeiertag", "Labour Day", on(1, 5)),
                h("ascension", "Christi Himmelfahrt", "Ascension Day", easter(39)),
                h("whitMonday", "Pfingstmontag", "Whit Monday", easter(50)),
                h("corpusChristi", "Fronleichnam", "Corpus Christi", easter(60)),
                h("assumption", "Mariä Himmelfahrt", "Assumption Day", on(15, 8)),
                h("nationalDay", "Nationalfeiertag", "National Day", on(26, 10)),
                h("allSaints", "Allerheiligen", "All Saints' Day", on(1, 11)),
                h("immaculateConception", "Mariä Empfängnis", "Immaculate Conception", on(8, 12)),
                h("christmas", "Christtag", "Christmas Day", on(25, 12)),
                h("stStephen", "Stefanitag", "St Stephen's Day", on(26, 12)),
            ],
            tips: [.christmasEveAndNewYearsEve]
        )
    }

    /// Zakon o blagdanima, spomendanima i neradnim danima (NN 110/19), in
    /// force since 2020: Statehood Day moved to 30 May and Remembrance Day
    /// (18 November) was added.
    private static var croatia: PublicHolidaySet {
        makeSet(
            id: "HR", country: .hr, language: .croatian,
            source: "Zakon o blagdanima, spomendanima i neradnim danima u Republici Hrvatskoj (NN 110/19)",
            holidays: [
                h("newYear", "Nova godina", "New Year's Day", on(1, 1)),
                h("epiphany", "Bogojavljenje ili Sveta tri kralja", "Epiphany", on(6, 1)),
                h("easterSunday", "Uskrs", "Easter Sunday", easter(0)),
                h("easterMonday", "Uskrsni ponedjeljak", "Easter Monday", easter(1)),
                h("labourDay", "Praznik rada", "Labour Day", on(1, 5)),
                h("statehoodDay", "Dan državnosti", "Statehood Day", on(30, 5), from: 2020),
                h("corpusChristi", "Tijelovo", "Corpus Christi", easter(60)),
                h("antiFascistDay", "Dan antifašističke borbe", "Anti-Fascist Struggle Day", on(22, 6)),
                h("victoryDay", "Dan pobjede i domovinske zahvalnosti i Dan hrvatskih branitelja",
                  "Victory and Homeland Thanksgiving Day", on(5, 8)),
                h("assumption", "Velika Gospa", "Assumption Day", on(15, 8)),
                h("allSaints", "Svi sveti", "All Saints' Day", on(1, 11)),
                h("remembranceDay",
                  "Dan sjećanja na žrtve Domovinskog rata i Dan sjećanja na žrtvu Vukovara i Škabrnje",
                  "Remembrance Day", on(18, 11), from: 2020),
                h("christmas", "Božić", "Christmas Day", on(25, 12)),
                h("stStephen", "Sveti Stjepan", "St Stephen's Day", on(26, 12)),
            ]
        )
    }

    /// Zakon o praznikih in dela prostih dnevih: the work-free days only, not
    /// the holidays that are worked. 2 January is back since 2017.
    private static var slovenia: PublicHolidaySet {
        makeSet(
            id: "SI", country: .si, language: .slovenian,
            source: "Zakon o praznikih in dela prostih dnevih v Republiki Sloveniji",
            holidays: [
                h("newYear", "Novo leto", "New Year's Day", on(1, 1)),
                h("newYear2", "Novo leto (2. januar)", "New Year (2 January)", on(2, 1), from: 2017),
                h("presernDay", "Prešernov dan, slovenski kulturni praznik", "Prešeren Day", on(8, 2)),
                h("easterSunday", "Velikonočna nedelja", "Easter Sunday", easter(0)),
                h("easterMonday", "Velikonočni ponedeljek", "Easter Monday", easter(1)),
                h("resistanceDay", "Dan upora proti okupatorju", "Day of Uprising Against Occupation", on(27, 4)),
                h("labourDay", "Praznik dela", "Labour Day", on(1, 5)),
                h("labourDay2", "Praznik dela (2. maj)", "Labour Day (2 May)", on(2, 5)),
                h("whitSunday", "Binkoštna nedelja", "Whit Sunday", easter(49)),
                h("statehoodDay", "Dan državnosti", "Statehood Day", on(25, 6)),
                h("assumption", "Marijino vnebovzetje", "Assumption Day", on(15, 8)),
                h("reformationDay", "Dan reformacije", "Reformation Day", on(31, 10)),
                h("allSaints", "Dan spomina na mrtve", "Remembrance Day", on(1, 11)),
                h("christmas", "Božič", "Christmas Day", on(25, 12)),
                h("independenceDay", "Dan samostojnosti in enotnosti", "Independence and Unity Day", on(26, 12)),
            ]
        )
    }

    /// Legge 260/1949 as amended (Epiphany restored 1985).
    private static var italy: PublicHolidaySet {
        makeSet(
            id: "IT", country: .it, language: .italian,
            source: "Legge 27 maggio 1949, n. 260, e successive modifiche",
            holidays: [
                h("newYear", "Capodanno", "New Year's Day", on(1, 1)),
                h("epiphany", "Epifania", "Epiphany", on(6, 1)),
                h("easterSunday", "Pasqua", "Easter Sunday", easter(0)),
                h("easterMonday", "Lunedì dell'Angelo", "Easter Monday", easter(1)),
                h("liberationDay", "Festa della Liberazione", "Liberation Day", on(25, 4)),
                h("labourDay", "Festa del Lavoro", "Labour Day", on(1, 5)),
                h("republicDay", "Festa della Repubblica", "Republic Day", on(2, 6)),
                h("assumption", "Ferragosto", "Assumption Day", on(15, 8)),
                h("allSaints", "Ognissanti", "All Saints' Day", on(1, 11)),
                h("immaculateConception", "Immacolata Concezione", "Immaculate Conception", on(8, 12)),
                h("christmas", "Natale", "Christmas Day", on(25, 12)),
                h("stStephen", "Santo Stefano", "St Stephen's Day", on(26, 12)),
            ],
            tips: [.regionalHolidaysNotIncluded]
        )
    }

    /// Code du travail, article L3133-1.
    private static var france: PublicHolidaySet {
        makeSet(
            id: "FR", country: .fr, language: .french,
            source: "Code du travail, article L3133-1",
            holidays: [
                h("newYear", "Jour de l'an", "New Year's Day", on(1, 1)),
                h("easterMonday", "Lundi de Pâques", "Easter Monday", easter(1)),
                h("labourDay", "Fête du Travail", "Labour Day", on(1, 5)),
                h("victoryDay", "Victoire 1945", "Victory in Europe Day", on(8, 5)),
                h("ascension", "Ascension", "Ascension Day", easter(39)),
                h("whitMonday", "Lundi de Pentecôte", "Whit Monday", easter(50)),
                h("nationalDay", "Fête nationale", "Bastille Day", on(14, 7)),
                h("assumption", "Assomption", "Assumption Day", on(15, 8)),
                h("allSaints", "Toussaint", "All Saints' Day", on(1, 11)),
                h("armistice", "Armistice 1918", "Armistice Day", on(11, 11)),
                h("christmas", "Noël", "Christmas Day", on(25, 12)),
            ],
            tips: [.regionalHolidaysNotIncluded]
        )
    }

    /// The national holidays of the Estatuto de los Trabajadores, art. 37.2,
    /// as the yearly BOE resolution lists them for every community. Maundy
    /// Thursday, 19 March, Easter Monday and the communities' own days are
    /// regional.
    private static var spain: PublicHolidaySet {
        makeSet(
            id: "ES", country: .es, language: .spanish,
            source: "Estatuto de los Trabajadores, art. 37.2; Resolución anual de fiestas laborales (BOE)",
            holidays: [
                h("newYear", "Año Nuevo", "New Year's Day", on(1, 1)),
                h("epiphany", "Epifanía del Señor", "Epiphany", on(6, 1)),
                h("goodFriday", "Viernes Santo", "Good Friday", easter(-2)),
                h("labourDay", "Fiesta del Trabajo", "Labour Day", on(1, 5)),
                h("assumption", "Asunción de la Virgen", "Assumption Day", on(15, 8)),
                h("nationalDay", "Fiesta Nacional de España", "National Day", on(12, 10)),
                h("allSaints", "Todos los Santos", "All Saints' Day", on(1, 11)),
                h("constitutionDay", "Día de la Constitución Española", "Constitution Day", on(6, 12)),
                h("immaculateConception", "Inmaculada Concepción", "Immaculate Conception", on(8, 12)),
                h("christmas", "Natividad del Señor", "Christmas Day", on(25, 12)),
            ],
            tips: [.regionalHolidaysNotIncluded, .sundayMovedToMonday]
        )
    }

    /// Código do Trabalho, artigo 234.º. Four holidays were suspended in
    /// 2013–2015 and restored in 2016.
    private static var portugal: PublicHolidaySet {
        makeSet(
            id: "PT", country: .pt, language: .portuguese,
            source: "Código do Trabalho, artigo 234.º",
            holidays: [
                h("newYear", "Ano Novo", "New Year's Day", on(1, 1)),
                h("goodFriday", "Sexta-feira Santa", "Good Friday", easter(-2)),
                h("easterSunday", "Páscoa", "Easter Sunday", easter(0)),
                h("libertyDay", "Dia da Liberdade", "Freedom Day", on(25, 4)),
                h("labourDay", "Dia do Trabalhador", "Labour Day", on(1, 5)),
                h("corpusChristi", "Corpo de Deus", "Corpus Christi", easter(60), from: 2016),
                h("portugalDay", "Dia de Portugal, de Camões e das Comunidades Portuguesas", "Portugal Day",
                  on(10, 6)),
                h("assumption", "Assunção de Nossa Senhora", "Assumption Day", on(15, 8)),
                h("republicDay", "Implantação da República", "Republic Day", on(5, 10), from: 2016),
                h("allSaints", "Dia de Todos os Santos", "All Saints' Day", on(1, 11), from: 2016),
                h("restorationDay", "Restauração da Independência", "Restoration of Independence", on(1, 12),
                  from: 2016),
                h("immaculateConception", "Imaculada Conceição", "Immaculate Conception", on(8, 12)),
                h("christmas", "Natal", "Christmas Day", on(25, 12)),
            ],
            tips: [.regionalHolidaysNotIncluded]
        )
    }

    /// Algemene termijnenwet, art. 3. Whether a holiday is a paid day off is
    /// the collective agreement's (CAO) call; Good Friday and Liberation Day
    /// (off for many only every fifth year) are offered unticked.
    private static var netherlands: PublicHolidaySet {
        makeSet(
            id: "NL", country: .nl, language: .dutch,
            source: "Algemene termijnenwet, artikel 3",
            holidays: [
                h("newYear", "Nieuwjaarsdag", "New Year's Day", on(1, 1)),
                h("goodFriday", "Goede Vrijdag", "Good Friday", easter(-2), note: .collectiveAgreement),
                h("easterSunday", "Eerste Paasdag", "Easter Sunday", easter(0)),
                h("easterMonday", "Tweede Paasdag", "Easter Monday", easter(1)),
                // 27 April, or the 26th when the 27th is a Sunday.
                h("kingsDay", "Koningsdag", "King's Day",
                  .annualOffSunday(month: 4, day: 27, sundayOffset: -1), from: 2014),
                h("liberationDay", "Bevrijdingsdag", "Liberation Day", on(5, 5), note: .collectiveAgreement),
                h("ascension", "Hemelvaartsdag", "Ascension Day", easter(39)),
                h("whitSunday", "Eerste Pinksterdag", "Whit Sunday", easter(49)),
                h("whitMonday", "Tweede Pinksterdag", "Whit Monday", easter(50)),
                h("christmas", "Eerste Kerstdag", "Christmas Day", on(25, 12)),
                h("stStephen", "Tweede Kerstdag", "Boxing Day", on(26, 12)),
            ]
        )
    }

    /// Ustawa o dniach wolnych od pracy (1951, as amended): Epiphany since
    /// 2011, Christmas Eve since 2025.
    private static var poland: PublicHolidaySet {
        makeSet(
            id: "PL", country: .pl, language: .polish,
            source: "Ustawa z dnia 18 stycznia 1951 r. o dniach wolnych od pracy",
            holidays: [
                h("newYear", "Nowy Rok", "New Year's Day", on(1, 1)),
                h("epiphany", "Święto Trzech Króli", "Epiphany", on(6, 1), from: 2011),
                h("easterSunday", "Wielkanoc", "Easter Sunday", easter(0)),
                h("easterMonday", "Poniedziałek Wielkanocny", "Easter Monday", easter(1)),
                h("labourDay", "Święto Pracy", "Labour Day", on(1, 5)),
                h("constitutionDay", "Święto Narodowe Trzeciego Maja", "Constitution Day", on(3, 5)),
                h("whitSunday", "Zielone Świątki", "Whit Sunday", easter(49)),
                h("corpusChristi", "Boże Ciało", "Corpus Christi", easter(60)),
                h("assumption", "Wniebowzięcie Najświętszej Maryi Panny", "Assumption Day", on(15, 8)),
                h("allSaints", "Wszystkich Świętych", "All Saints' Day", on(1, 11)),
                h("independenceDay", "Narodowe Święto Niepodległości", "Independence Day", on(11, 11)),
                h("christmasEve", "Wigilia Bożego Narodzenia", "Christmas Eve", on(24, 12), from: 2025),
                h("christmas", "Boże Narodzenie (pierwszy dzień)", "Christmas Day", on(25, 12)),
                h("stStephen", "Boże Narodzenie (drugi dzień)", "Second Day of Christmas", on(26, 12)),
            ]
        )
    }
}
