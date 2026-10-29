import Foundation

/// The language an exported timesheet is written in.
///
/// Separate from the language the app is in, and deliberately so: the person
/// reading a timesheet is often not the person who recorded it. Someone
/// working in Germany may keep their phone in English and still need to hand
/// payroll a sheet that says *Gesamt gearbeitet*.
///
/// Only what the app itself writes is translated — column titles, the built-in
/// day types, the summary labels, and the words that hold the document
/// together. Anything the user typed is theirs: a note, a location, a tag, a
/// job name and a day type they invented all come out exactly as entered,
/// because translating somebody's own words would be a fabrication.
///
/// Adding a language is two edits: a row in `identity` below, and an argument
/// on every arm of the word list — which the compiler insists on, so a
/// language cannot ship half-written.
enum ExportLanguage: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// Whatever the phone is set to, falling back to English for languages
    /// the export does not speak.
    case device
    case english
    case german
    case croatian
    case slovenian
    case italian
    case french
    case spanish
    case portuguese
    case dutch
    case polish

    var id: String { rawValue }

    // MARK: - Which language, and where its dates come from

    /// Everything about a language except its words: the two-letter code that
    /// matches it to a phone, the locale that names its months and weekdays,
    /// and what it calls itself in a picker.
    ///
    /// One table rather than the three switches this used to be. The compiler
    /// only ever insisted on the words, so a language could be added and
    /// arrive with its own column titles, the picker naming it correctly, and
    /// its month names still in English.
    private var identity: (code: String, locale: String, name: String) {
        switch self {
        case .device:      return ("", "", "Same as the phone")
        case .english:     return ("en", "en_GB", "English")
        case .german:      return ("de", "de_DE", "Deutsch")
        case .croatian:    return ("hr", "hr_HR", "Hrvatski")
        case .slovenian:   return ("sl", "sl_SI", "Slovenščina")
        case .italian:     return ("it", "it_IT", "Italiano")
        case .french:      return ("fr", "fr_FR", "Français")
        case .spanish:     return ("es", "es_ES", "Español")
        case .portuguese:  return ("pt", "pt_PT", "Português")
        case .dutch:       return ("nl", "nl_NL", "Nederlands")
        case .polish:      return ("pl", "pl_PL", "Polski")
        }
    }

    /// Named in the language itself, as a language picker should be.
    var title: String { identity.name }

    /// Which vocabulary actually gets used. `device` resolves by looking at
    /// the phone, and lands on English when it is set to something this list
    /// has no words for.
    var resolved: ExportLanguage {
        guard self == .device else { return self }
        return ExportLanguage.speaking(Locale.preferredLanguages)
    }

    /// The first language in an ordered preference list this table has words
    /// for, or English.
    ///
    /// The ordered list rather than `Locale.current`, which is the formatting
    /// locale and answers a different question. Someone whose preferences run
    /// Czech, then German, is shown a German app — there is no Czech
    /// localisation for iOS to pick — while `Locale.current` still says Czech.
    /// Reading that one field gave them German screens with English labels on
    /// the parts that come from here.
    ///
    /// Walking the list works because this table holds exactly the ten
    /// languages the app is localised into, so the first preference with
    /// words here is the first preference iOS could have displayed.
    ///
    /// Pure, and takes the list rather than reading it, so the resolution can
    /// be tested against phones other than the one running the tests.
    static func speaking(_ preferences: [String]) -> ExportLanguage {
        for tag in preferences {
            // The two-letter prefix rather than `Locale.language`, which is
            // not available on every platform the engine is built for. It also
            // does the right thing with a tag carrying a script or a region:
            // pt-BR and zh-Hans both reduce to what this table keys on.
            let code = String(tag.prefix(2)).lowercased()
            if let match = allCases.first(where: { $0 != .device && $0.identity.code == code }) {
                return match
            }
        }
        return .english
    }

    /// The locale that names months and weekdays.
    ///
    /// `device` keeps the phone's own locale when the phone speaks a language
    /// the export has words for — so a German phone set to Austria still
    /// writes Jänner rather than Januar, which `de_DE` would have taken away.
    ///
    /// When it does not, the fallback's locale comes with the fallback's
    /// words. A phone in a language this list has none for gets English column
    /// titles, and English titles over foreign month names is the
    /// half-translated document this setting exists to prevent: worse than
    /// either language on its own, because a reader cannot tell which parts
    /// were meant.
    var locale: Locale {
        guard self == .device else { return Locale(identifier: identity.locale) }
        let phone = Locale.current
        return phone.identifier.hasPrefix(resolved.identity.code) ? phone : resolved.locale
    }

    // MARK: - Words

    /// One switch rather than one per language, so every term shows its
    /// translations together and a missing one is a build error rather than a
    /// cell that quietly comes out in English.
    func callAsFunction(_ term: ExportTerm) -> String {
        switch term {

        // Columns
        case .date:           return pick(en: "Date", de: "Datum", hr: "Datum", sl: "Datum", it: "Data",
                                          fr: "Date", es: "Fecha", pt: "Data", nl: "Datum", pl: "Data")
        case .weekday:        return pick(en: "Day", de: "Tag", hr: "Dan", sl: "Dan", it: "Giorno", fr: "Jour",
                                          es: "Día", pt: "Dia", nl: "Dag", pl: "Dzień")
        case .dayType:        return pick(en: "Type", de: "Art", hr: "Vrsta", sl: "Vrsta", it: "Tipo", fr: "Type",
                                          es: "Tipo", pt: "Tipo", nl: "Type", pl: "Typ")
        case .job:            return pick(en: "Job", de: "Tätigkeit", hr: "Posao", sl: "Delo", it: "Lavoro",
                                          fr: "Poste", es: "Trabajo", pt: "Trabalho", nl: "Functie", pl: "Praca")
        case .start:          return pick(en: "Start", de: "Beginn", hr: "Početak", sl: "Začetek", it: "Inizio",
                                          fr: "Début", es: "Inicio", pt: "Início", nl: "Begin", pl: "Początek")
        case .end:            return pick(en: "End", de: "Ende", hr: "Kraj", sl: "Konec", it: "Fine", fr: "Fin",
                                          es: "Fin", pt: "Fim", nl: "Einde", pl: "Koniec")
        case .breakTime:      return pick(en: "Break", de: "Pause", hr: "Pauza", sl: "Odmor", it: "Pausa",
                                          fr: "Pause", es: "Pausa", pt: "Pausa", nl: "Pauze", pl: "Przerwa")
        case .worked:         return pick(en: "Worked", de: "Gearbeitet", hr: "Odrađeno", sl: "Opravljeno",
                                          it: "Ore lavorate", fr: "Heures travaillées", es: "Horas trabajadas",
                                          pt: "Horas trabalhadas", nl: "Gewerkte uren", pl: "Przepracowane")
        case .paidAbsence:    return pick(en: "Paid absence", de: "Bezahlte Abwesenheit", hr: "Plaćeni izostanak",
                                          sl: "Plačana odsotnost", it: "Assenza retribuita", fr: "Absence payée",
                                          es: "Ausencia retribuida", pt: "Ausência paga", nl: "Betaald verlof",
                                          pl: "Nieobecność płatna")
        case .expected:       return pick(en: "Expected", de: "Soll", hr: "Planirano", sl: "Predvideno",
                                          it: "Ore previste", fr: "Heures prévues", es: "Horas previstas",
                                          pt: "Horas previstas", nl: "Verwachte uren", pl: "Wymagane")
        case .overtime:       return pick(en: "Overtime", de: "Überstunden", hr: "Prekovremeni", sl: "Nadure",
                                          it: "Straordinari", fr: "Heures supp.", es: "Horas extra",
                                          pt: "Horas extra", nl: "Overuren", pl: "Nadgodziny")
        case .balance:        return pick(en: "Balance", de: "Saldo", hr: "Saldo", sl: "Saldo", it: "Saldo",
                                          fr: "Solde", es: "Saldo", pt: "Saldo", nl: "Saldo", pl: "Saldo")
        case .runningBalance: return pick(en: "Running balance", de: "Laufender Saldo", hr: "Tekući saldo",
                                          sl: "Tekoče stanje", it: "Saldo progressivo", fr: "Solde cumulé",
                                          es: "Saldo acumulado", pt: "Saldo acumulado", nl: "Doorlopend saldo",
                                          pl: "Saldo narastająco")
        case .holiday:        return pick(en: "Holiday", de: "Feiertag", hr: "Praznik", sl: "Praznik",
                                          it: "Festività", fr: "Jour férié", es: "Festivo", pt: "Feriado",
                                          nl: "Feestdag", pl: "Święto")
        case .location:       return pick(en: "Location", de: "Ort", hr: "Mjesto", sl: "Kraj", it: "Luogo",
                                          fr: "Lieu", es: "Lugar", pt: "Local", nl: "Locatie", pl: "Miejsce")
        case .tags:           return pick(en: "Tags", de: "Schlagwörter", hr: "Oznake", sl: "Oznake",
                                          it: "Etichette", fr: "Étiquettes", es: "Etiquetas", pt: "Etiquetas",
                                          nl: "Labels", pl: "Etykiety")
        case .notes:          return pick(en: "Notes", de: "Notizen", hr: "Bilješke", sl: "Opombe", it: "Note",
                                          fr: "Notes", es: "Notas", pt: "Notas", nl: "Notities", pl: "Notatki")
        case .earnings:       return pick(en: "Earnings", de: "Verdienst", hr: "Zarada", sl: "Zaslužek",
                                          it: "Compenso", fr: "Rémunération", es: "Remuneración",
                                          pt: "Remuneração", nl: "Verdiensten", pl: "Zarobek")

        // The day types that ship with the app. A type the user made is not
        // in here, and is written as they named it.
        case .work:           return pick(en: "Work", de: "Arbeit", hr: "Rad", sl: "Delo", it: "Lavoro",
                                          fr: "Travail", es: "Trabajo", pt: "Trabalho", nl: "Werk", pl: "Praca")
        case .weekend:        return pick(en: "Weekend", de: "Wochenende", hr: "Vikend", sl: "Vikend",
                                          it: "Fine settimana", fr: "Week-end", es: "Fin de semana",
                                          pt: "Fim de semana", nl: "Weekend", pl: "Weekend")
        case .publicHoliday:  return pick(en: "Public holiday", de: "Feiertag", hr: "Državni praznik",
                                          sl: "Državni praznik", it: "Festività nazionale", fr: "Jour férié",
                                          es: "Día festivo", pt: "Feriado", nl: "Feestdag", pl: "Święto państwowe")
        case .vacation:       return pick(en: "Vacation", de: "Urlaub", hr: "Godišnji odmor", sl: "Dopust",
                                          it: "Ferie", fr: "Congés", es: "Vacaciones", pt: "Férias",
                                          nl: "Vakantie", pl: "Urlop")
        case .sickLeave:      return pick(en: "Sick leave", de: "Krankheit", hr: "Bolovanje", sl: "Bolniška",
                                          it: "Malattia", fr: "Arrêt maladie", es: "Baja por enfermedad",
                                          pt: "Baixa médica", nl: "Ziekteverlof", pl: "Zwolnienie lekarskie")
        case .personalDay:    return pick(en: "Personal day", de: "Persönlicher Tag", hr: "Osobni dan",
                                          sl: "Osebni dan", it: "Permesso personale", fr: "Congé personnel",
                                          es: "Día personal", pt: "Dia pessoal", nl: "Persoonlijke dag",
                                          pl: "Dzień osobisty")
        case .dayOff:         return pick(en: "Day off", de: "Freier Tag", hr: "Slobodan dan", sl: "Prost dan",
                                          it: "Giorno libero", fr: "Jour de repos", es: "Día libre",
                                          pt: "Dia de folga", nl: "Vrije dag", pl: "Dzień wolny")
        // The day type, one day of it. Not `timeOffInLieu` below, which is
        // the reason for an adjustment and in several languages a plural
        // ("Zamjenski slobodni dani"); German uses the Austrian word here,
        // as the day is called on an Austrian site.
        case .timeOffInLieuDay: return pick(en: "Time off in lieu", de: "Zeitausgleich",
                                          hr: "Slobodan dan za prekovremene", sl: "Prosti dan za nadure",
                                          it: "Giorno di recupero", fr: "Jour de récupération",
                                          es: "Día de compensación", pt: "Folga compensatória",
                                          nl: "Compensatiedag", pl: "Dzień wolny za nadgodziny")
        case .badWeather:     return pick(en: "Bad weather", de: "Schlechtwetter", hr: "Loše vrijeme",
                                          sl: "Slabo vreme", it: "Maltempo", fr: "Intempéries", es: "Mal tiempo",
                                          pt: "Mau tempo", nl: "Slecht weer", pl: "Niepogoda")
        case .otherDayType:   return pick(en: "Other", de: "Sonstiges", hr: "Ostalo", sl: "Drugo", it: "Altro",
                                          fr: "Autre", es: "Otro", pt: "Outro", nl: "Overig", pl: "Inne")

        // Why a balance moved without hours moving with it.
        case .correction:     return pick(en: "Correction", de: "Korrektur", hr: "Ispravak", sl: "Popravek",
                                          it: "Correzione", fr: "Correction", es: "Corrección", pt: "Correção",
                                          nl: "Correctie", pl: "Korekta")
        case .paidOut:        return pick(en: "Paid out", de: "Ausbezahlt", hr: "Isplaćeno", sl: "Izplačano",
                                          it: "Liquidato", fr: "Payé", es: "Pagado", pt: "Pago", nl: "Uitbetaald",
                                          pl: "Wypłacono")
        case .timeOffInLieu:  return pick(en: "Time off in lieu", de: "Freizeitausgleich",
                                          hr: "Zamjenski slobodni dani", sl: "Nadomestni prosti dnevi",
                                          it: "Recupero ore", fr: "Récupération", es: "Días de compensación",
                                          pt: "Banco de horas", nl: "Compensatieverlof", pl: "Odbiór godzin")

        // The summary block
        case .totalWorked:    return pick(en: "Total worked", de: "Gesamt gearbeitet", hr: "Ukupno odrađeno",
                                          sl: "Skupaj opravljeno", it: "Totale ore lavorate",
                                          fr: "Total travaillé", es: "Total trabajado", pt: "Total trabalhado",
                                          nl: "Totaal gewerkt", pl: "Łącznie przepracowane")
        case .totalPaid:      return pick(en: "Total paid", de: "Gesamt bezahlt", hr: "Ukupno plaćeno",
                                          sl: "Skupaj plačano", it: "Totale retribuito", fr: "Total payé",
                                          es: "Total retribuido", pt: "Total pago", nl: "Totaal betaald",
                                          pl: "Łącznie płatne")
        case .totalExpected:  return pick(en: "Total expected", de: "Gesamt Soll", hr: "Ukupno planirano",
                                          sl: "Skupaj predvideno", it: "Totale ore previste", fr: "Total prévu",
                                          es: "Total previsto", pt: "Total previsto", nl: "Totaal verwacht",
                                          pl: "Łącznie wymagane")
        case .short:          return pick(en: "Short", de: "Fehlzeit", hr: "Manjak", sl: "Manjko",
                                          it: "Ore mancanti", fr: "Déficit", es: "Déficit", pt: "Horas em falta",
                                          nl: "Tekort", pl: "Niedobór")
        case .carriedForward: return pick(en: "Balance carried forward", de: "Saldo Übertrag",
                                          hr: "Preneseni saldo", sl: "Prenesen saldo", it: "Saldo riportato",
                                          fr: "Solde reporté", es: "Saldo anterior", pt: "Saldo transitado",
                                          nl: "Overgedragen saldo", pl: "Saldo z przeniesienia")
        case .daysWorked:     return pick(en: "Days worked", de: "Arbeitstage", hr: "Radni dani",
                                          sl: "Opravljeni dnevi", it: "Giorni lavorati", fr: "Jours travaillés",
                                          es: "Días trabajados", pt: "Dias trabalhados", nl: "Gewerkte dagen",
                                          pl: "Dni przepracowane")
        case .scheduledDays:  return pick(en: "Scheduled working days", de: "Sollarbeitstage",
                                          hr: "Planirani radni dani", sl: "Predvideni delovni dnevi",
                                          it: "Giorni previsti", fr: "Jours prévus", es: "Días previstos",
                                          pt: "Dias previstos", nl: "Geplande werkdagen", pl: "Dni planowane")
        case .daysOff:        return pick(en: "Days off", de: "Freie Tage", hr: "Neradni dani", sl: "Prosti dnevi",
                                          it: "Giorni liberi", fr: "Jours de repos", es: "Días libres",
                                          pt: "Dias de folga", nl: "Vrije dagen", pl: "Dni wolne")
        case .totalBreaks:    return pick(en: "Total breaks", de: "Gesamt Pausen", hr: "Ukupno pauze",
                                          sl: "Skupaj odmori", it: "Totale pause", fr: "Total pauses",
                                          es: "Total pausas", pt: "Total de pausas", nl: "Totaal pauzes",
                                          pl: "Łącznie przerwy")

        // The words that hold the document together
        case .summary:        return pick(en: "Summary", de: "Zusammenfassung", hr: "Sažetak", sl: "Povzetek",
                                          it: "Riepilogo", fr: "Récapitulatif", es: "Resumen", pt: "Resumo",
                                          nl: "Samenvatting", pl: "Podsumowanie")
        case .total:          return pick(en: "Total", de: "Summe", hr: "Ukupno", sl: "Skupaj", it: "Totale",
                                          fr: "Total", es: "Total", pt: "Total", nl: "Totaal", pl: "Razem")
        case .name:           return pick(en: "Name", de: "Name", hr: "Ime", sl: "Ime", it: "Nome", fr: "Nom",
                                          es: "Nombre", pt: "Nome", nl: "Naam", pl: "Imię i nazwisko")
        case .page:           return pick(en: "page", de: "Seite", hr: "stranica", sl: "stran", it: "pagina",
                                          fr: "page", es: "página", pt: "página", nl: "pagina", pl: "strona")
        case .generated:      return pick(en: "generated", de: "erstellt", hr: "izrađeno", sl: "ustvarjeno",
                                          it: "generato", fr: "généré", es: "generado", pt: "gerado",
                                          nl: "gemaakt", pl: "wygenerowano")
        case .hours:          return pick(en: "Hours", de: "Stunden", hr: "Sati", sl: "Ure", it: "Ore",
                                          fr: "Heures", es: "Horas", pt: "Horas", nl: "Uren", pl: "Godziny")
        case .weekOf:         return pick(en: "week of", de: "Woche vom", hr: "tjedan od", sl: "teden od",
                                          it: "settimana del", fr: "semaine du", es: "semana del", pt: "semana de",
                                          nl: "week van", pl: "tydzień od")

        // The director's sheet
        case .day:            return pick(en: "Day", de: "Tag", hr: "Dan", sl: "Dan", it: "Giorno", fr: "Jour",
                                          es: "Día", pt: "Dia", nl: "Dag", pl: "Dzień")
        case .monthTotal:     return pick(en: "Month total", de: "Monatssumme", hr: "Ukupno za mjesec",
                                          sl: "Skupaj za mesec", it: "Totale del mese", fr: "Total du mois",
                                          es: "Total del mes", pt: "Total do mês", nl: "Maandtotaal",
                                          pl: "Suma miesiąca")
        case .you:            return pick(en: "You", de: "Du", hr: "Ti", sl: "Ti", it: "Tu", fr: "Vous",
                                          es: "Tú", pt: "Você", nl: "Jij", pl: "Ty")
        case .fromTo:         return pick(en: "From–to", de: "Von–bis", hr: "Od–do", sl: "Od–do", it: "Dalle–alle",
                                          fr: "De–à", es: "De–a", pt: "Das–às", nl: "Van–tot", pl: "Od–do")
        case .siteHours:      return pick(en: "Site hours", de: "Baustellenstunden", hr: "Sati na gradilištu",
                                          sl: "Ure na gradbišču", it: "Ore in cantiere", fr: "Heures de chantier",
                                          es: "Horas de obra", pt: "Horas de obra", nl: "Bouwplaatsuren",
                                          pl: "Godziny na budowie")
        case .recordedBy:     return pick(en: "Recorded by", de: "Erfasst von", hr: "Evidenciju vodi",
                                          sl: "Evidenco vodi", it: "Registrato da", fr: "Saisi par",
                                          es: "Registrado por", pt: "Registado por", nl: "Bijgehouden door",
                                          pl: "Prowadzone przez")
        case .daysOnSite:     return pick(en: "Days on site", de: "Tage auf der Baustelle", hr: "Dani na gradilištu",
                                          sl: "Dnevi na gradbišču", it: "Giorni in cantiere",
                                          fr: "Jours sur le chantier", es: "Días en obra", pt: "Dias em obra",
                                          nl: "Dagen op de bouwplaats", pl: "Dni na budowie")
        case .crewHours:      return pick(en: "Crew hours", de: "Stunden der Mannschaft", hr: "Sati ekipe",
                                          sl: "Ure ekipe", it: "Ore della squadra", fr: "Heures de l’équipe",
                                          es: "Horas de la cuadrilla", pt: "Horas da equipa",
                                          nl: "Uren van de ploeg", pl: "Godziny ekipy")
        case .people:         return pick(en: "People", de: "Personen", hr: "Osobe", sl: "Osebe", it: "Persone",
                                          fr: "Personnes", es: "Personas", pt: "Pessoas", nl: "Personen",
                                          pl: "Osoby")
        case .peopleOnPage:   return pick(en: "People {range} of {total}", de: "Personen {range} von {total}",
                                          hr: "Osobe {range} od {total}", sl: "Osebe {range} od {total}",
                                          it: "Persone {range} di {total}", fr: "Personnes {range} sur {total}",
                                          es: "Personas {range} de {total}", pt: "Pessoas {range} de {total}",
                                          nl: "Personen {range} van {total}", pl: "Osoby {range} z {total}")
        case .siteLegend:     return pick(
            en: "Each person: on site – off site, then hours after the break. Orange = came late or left early. "
                + "— = not on this site that day.",
            de: "Je Person: Ankunft – Abfahrt, dann die Stunden nach Abzug der Pause. Orange = später gekommen "
                + "oder früher gegangen. — = an diesem Tag nicht auf dieser Baustelle.",
            hr: "Za svaku osobu: dolazak – odlazak, zatim sati nakon pauze. Narančasto = došao kasnije ili otišao "
                + "ranije. — = taj dan nije bio na ovom gradilištu.",
            sl: "Za vsako osebo: prihod – odhod, nato ure po odmoru. Oranžno = prišel pozneje ali odšel prej. "
                + "— = ta dan ni bil na tem gradbišču.",
            it: "Per ogni persona: arrivo – uscita, poi le ore al netto della pausa. Arancione = arrivato tardi o "
                + "uscito prima. — = quel giorno non era in questo cantiere.",
            fr: "Pour chaque personne : arrivée – départ, puis les heures après la pause. Orange = arrivé en retard "
                + "ou parti plus tôt. — = pas sur ce chantier ce jour-là.",
            es: "Para cada persona: llegada – salida y después las horas descontada la pausa. Naranja = llegó tarde "
                + "o se fue antes. — = no estuvo en esta obra ese día.",
            pt: "Para cada pessoa: chegada – saída e depois as horas descontada a pausa. Laranja = chegou mais tarde "
                + "ou saiu mais cedo. — = não esteve nesta obra nesse dia.",
            nl: "Per persoon: aankomst – vertrek, daarna de uren na de pauze. Oranje = later gekomen of eerder "
                + "vertrokken. — = die dag niet op deze bouwplaats.",
            pl: "Dla każdej osoby: przyjście – wyjście, potem godziny po odjęciu przerwy. Pomarańczowy = przyszedł "
                + "później lub wyszedł wcześniej. — = tego dnia nie było go na tej budowie."
        )

        // The same legend for a site whose job pays its breaks, and for a
        // month that has days of both kinds (the site moved jobs mid-month).
        case .siteLegendPaidBreaks: return pick(
            en: "Each person: on site – off site, then hours worked, paid break included. Orange = came late or "
                + "left early. — = not on this site that day.",
            de: "Je Person: Ankunft – Abfahrt, dann die Arbeitsstunden, bezahlte Pause inbegriffen. Orange = später "
                + "gekommen oder früher gegangen. — = an diesem Tag nicht auf dieser Baustelle.",
            hr: "Za svaku osobu: dolazak – odlazak, zatim radni sati, plaćena pauza uključena. Narančasto = došao "
                + "kasnije ili otišao ranije. — = taj dan nije bio na ovom gradilištu.",
            sl: "Za vsako osebo: prihod – odhod, nato delovne ure, plačan odmor vključen. Oranžno = prišel pozneje "
                + "ali odšel prej. — = ta dan ni bil na tem gradbišču.",
            it: "Per ogni persona: arrivo – uscita, poi le ore lavorate, pausa retribuita inclusa. Arancione = "
                + "arrivato tardi o uscito prima. — = quel giorno non era in questo cantiere.",
            fr: "Pour chaque personne : arrivée – départ, puis les heures travaillées, pause payée comprise. "
                + "Orange = arrivé en retard ou parti plus tôt. — = pas sur ce chantier ce jour-là.",
            es: "Para cada persona: llegada – salida y después las horas trabajadas, pausa pagada incluida. "
                + "Naranja = llegó tarde o se fue antes. — = no estuvo en esta obra ese día.",
            pt: "Para cada pessoa: chegada – saída e depois as horas trabalhadas, pausa paga incluída. Laranja = "
                + "chegou mais tarde ou saiu mais cedo. — = não esteve nesta obra nesse dia.",
            nl: "Per persoon: aankomst – vertrek, daarna de gewerkte uren, betaalde pauze inbegrepen. Oranje = "
                + "later gekomen of eerder vertrokken. — = die dag niet op deze bouwplaats.",
            pl: "Dla każdej osoby: przyjście – wyjście, potem przepracowane godziny, z płatną przerwą. "
                + "Pomarańczowy = przyszedł później lub wyszedł wcześniej. — = tego dnia nie było go na tej budowie."
        )
        case .siteLegendMixedBreaks: return pick(
            en: "Each person: on site – off site, then hours worked. Orange = came late or left early. "
                + "— = not on this site that day.",
            de: "Je Person: Ankunft – Abfahrt, dann die Arbeitsstunden. Orange = später gekommen oder früher "
                + "gegangen. — = an diesem Tag nicht auf dieser Baustelle.",
            hr: "Za svaku osobu: dolazak – odlazak, zatim radni sati. Narančasto = došao kasnije ili otišao ranije. "
                + "— = taj dan nije bio na ovom gradilištu.",
            sl: "Za vsako osebo: prihod – odhod, nato delovne ure. Oranžno = prišel pozneje ali odšel prej. "
                + "— = ta dan ni bil na tem gradbišču.",
            it: "Per ogni persona: arrivo – uscita, poi le ore lavorate. Arancione = arrivato tardi o uscito prima. "
                + "— = quel giorno non era in questo cantiere.",
            fr: "Pour chaque personne : arrivée – départ, puis les heures travaillées. Orange = arrivé en retard "
                + "ou parti plus tôt. — = pas sur ce chantier ce jour-là.",
            es: "Para cada persona: llegada – salida y después las horas trabajadas. Naranja = llegó tarde o se "
                + "fue antes. — = no estuvo en esta obra ese día.",
            pt: "Para cada pessoa: chegada – saída e depois as horas trabalhadas. Laranja = chegou mais tarde ou "
                + "saiu mais cedo. — = não esteve nesta obra nesse dia.",
            nl: "Per persoon: aankomst – vertrek, daarna de gewerkte uren. Oranje = later gekomen of eerder "
                + "vertrokken. — = die dag niet op deze bouwplaats.",
            pl: "Dla każdej osoby: przyjście – wyjście, potem przepracowane godziny. Pomarańczowy = przyszedł "
                + "później lub wyszedł wcześniej. — = tego dnia nie było go na tej budowie."
        )

        case .badWeatherDays: return pick(en: "Bad-weather days", de: "Schlechtwettertage",
                                          hr: "Dani lošeg vremena", sl: "Dnevi slabega vremena",
                                          it: "Giorni di maltempo", fr: "Jours d’intempéries",
                                          es: "Días de mal tiempo", pt: "Dias de mau tempo",
                                          nl: "Slechtweerdagen", pl: "Dni niepogody")

        // Under a site sheet's totals: each person's days away, by why.
        case .sickDays:       return pick(en: "Sick days", de: "Krankheitstage", hr: "Dani bolovanja",
                                          sl: "Dnevi bolniške", it: "Giorni di malattia", fr: "Jours de maladie",
                                          es: "Días de baja", pt: "Dias de baixa", nl: "Ziektedagen",
                                          pl: "Dni choroby")
        case .otherSite:      return pick(en: "Other site", de: "Andere Baustelle", hr: "Drugo gradilište",
                                          sl: "Drugo gradbišče", it: "Altro cantiere", fr: "Autre chantier",
                                          es: "Otra obra", pt: "Outra obra", nl: "Andere bouwplaats",
                                          pl: "Inna budowa")
        case .leaveDays:      return pick(en: "Leave days", de: "Urlaubstage", hr: "Dani dopusta",
                                          sl: "Dnevi dopusta", it: "Giorni di ferie", fr: "Jours de congé",
                                          es: "Días de permiso", pt: "Dias de licença", nl: "Verlofdagen",
                                          pl: "Dni urlopu")

        // Field allowance, kilometres and travel (1.2): columns and summary
        // lines on a timesheet, closing lines on a site sheet.
        case .allowance:      return pick(en: "Allowance", de: "Auslöse", hr: "Terenski dodatak",
                                          sl: "Terenski dodatek", it: "Trasferta", fr: "Indemnité",
                                          es: "Dieta", pt: "Ajudas de custo", nl: "Toelage", pl: "Dieta")
        case .kilometresShort: return pick(en: "km", de: "km", hr: "km", sl: "km", it: "km", fr: "km",
                                           es: "km", pt: "km", nl: "km", pl: "km")
        case .travel:         return pick(en: "Travel", de: "Fahrzeit", hr: "Putovanje", sl: "Potovanje",
                                          it: "Viaggio", fr: "Trajet", es: "Viaje", pt: "Viagem",
                                          nl: "Reistijd", pl: "Podróż")
        case .allowanceDays:  return pick(en: "Allowance days", de: "Auslösetage", hr: "Dani terenskog dodatka",
                                          sl: "Dnevi terenskega dodatka", it: "Giorni di trasferta",
                                          fr: "Jours d’indemnité", es: "Días de dieta",
                                          pt: "Dias de ajudas de custo", nl: "Toelagedagen", pl: "Dni diet")
        case .kilometres:     return pick(en: "Kilometres", de: "Kilometer", hr: "Kilometri", sl: "Kilometri",
                                          it: "Chilometri", fr: "Kilomètres", es: "Kilómetros",
                                          pt: "Quilómetros", nl: "Kilometers", pl: "Kilometry")
        case .mileage:        return pick(en: "Mileage", de: "Kilometergeld", hr: "Naknada za kilometre",
                                          sl: "Kilometrina", it: "Rimborso chilometrico",
                                          fr: "Indemnités kilométriques", es: "Kilometraje",
                                          pt: "Quilometragem", nl: "Kilometervergoeding", pl: "Kilometrówka")

        // A crew member's own sheet (1.2)
        case .site:           return pick(en: "Site", de: "Baustelle", hr: "Gradilište", sl: "Gradbišče",
                                          it: "Cantiere", fr: "Chantier", es: "Obra", pt: "Obra",
                                          nl: "Bouwplaats", pl: "Budowa")
        case .address:        return pick(en: "Address", de: "Adresse", hr: "Adresa", sl: "Naslov",
                                          it: "Indirizzo", fr: "Adresse", es: "Dirección", pt: "Morada",
                                          nl: "Adres", pl: "Adres")
        // Two sites in one day (1.2): the summary's block per site, the
        // header tile, and "+2 more" after the first site names of a title.
        case .bySite:         return pick(en: "By site", de: "Nach Baustelle", hr: "Po gradilištu",
                                          sl: "Po gradbišču", it: "Per cantiere", fr: "Par chantier",
                                          es: "Por obra", pt: "Por obra", nl: "Per bouwplaats", pl: "Według budowy")
        case .sites:          return pick(en: "Sites", de: "Baustellen", hr: "Gradilišta", sl: "Gradbišča",
                                          it: "Cantieri", fr: "Chantiers", es: "Obras", pt: "Obras",
                                          nl: "Bouwplaatsen", pl: "Budowy")
        case .moreSites:      return pick(en: "+{count} more", de: "+{count} weitere", hr: "+ još {count}",
                                          sl: "+ še {count}", it: "+ altri {count}", fr: "+ {count} autres",
                                          es: "+ {count} más", pt: "+ mais {count}", nl: "+ nog {count}",
                                          pl: "+ {count} więcej")
        // One sheet for several sites (1.2): drawn sign-offs stay on each
        // site's own sheet.
        case .signOffOnSiteSheets:
            return pick(en: "Crew sign-offs are on each site's own sheet.",
                        de: "Die Unterschriften der Mannschaft stehen auf dem Blatt der jeweiligen Baustelle.",
                        hr: "Potpisi ekipe nalaze se na listu svakog gradilišta.",
                        sl: "Podpisi ekipe so na listu posameznega gradbišča.",
                        it: "Le firme della squadra sono sul foglio di ciascun cantiere.",
                        fr: "Les signatures de l’équipe figurent sur la feuille de chaque chantier.",
                        es: "Las firmas de la cuadrilla están en la hoja de cada obra.",
                        pt: "As assinaturas da equipa estão na folha de cada obra.",
                        nl: "De handtekeningen van de ploeg staan op het blad van elke bouwplaats.",
                        pl: "Podpisy ekipy są na arkuszu każdej budowy.")
        case .reason:         return pick(en: "Reason", de: "Grund", hr: "Razlog", sl: "Razlog", it: "Motivo",
                                          fr: "Motif", es: "Motivo", pt: "Motivo", nl: "Reden", pl: "Powód")

        // The site diary
        case .siteDiary:      return pick(en: "Site diary", de: "Bautagebuch", hr: "Građevinski dnevnik",
                                          sl: "Gradbeni dnevnik", it: "Giornale dei lavori",
                                          fr: "Journal de chantier", es: "Diario de obra", pt: "Diário de obra",
                                          nl: "Bouwdagboek", pl: "Dziennik budowy")
        case .weather:        return pick(en: "Weather", de: "Wetter", hr: "Vrijeme", sl: "Vreme", it: "Meteo",
                                          fr: "Météo", es: "Tiempo", pt: "Tempo", nl: "Weer", pl: "Pogoda")
        case .diaryWorkDone:  return pick(en: "Work done", de: "Ausgeführte Arbeiten", hr: "Izvedeni radovi",
                                          sl: "Opravljena dela", it: "Lavori eseguiti", fr: "Travaux réalisés",
                                          es: "Trabajos realizados", pt: "Trabalhos realizados",
                                          nl: "Uitgevoerd werk", pl: "Wykonane prace")
        case .diaryDeliveries: return pick(en: "Deliveries", de: "Lieferungen", hr: "Isporuke", sl: "Dobave",
                                           it: "Forniture", fr: "Livraisons", es: "Entregas", pt: "Entregas",
                                           nl: "Leveringen", pl: "Dostawy")
        case .diaryProblems:  return pick(en: "Problems / delays", de: "Behinderungen / Verzögerungen",
                                          hr: "Problemi / kašnjenja", sl: "Težave / zamude",
                                          it: "Problemi / ritardi", fr: "Problèmes / retards",
                                          es: "Problemas / retrasos", pt: "Problemas / atrasos",
                                          nl: "Problemen / vertraging", pl: "Problemy / opóźnienia")
        case .diaryVisitors:  return pick(en: "Visitors", de: "Besucher", hr: "Posjetitelji", sl: "Obiskovalci",
                                          it: "Visitatori", fr: "Visiteurs", es: "Visitas", pt: "Visitas",
                                          nl: "Bezoekers", pl: "Odwiedzający")
        case .weatherSunny:   return pick(en: "Sunny", de: "Sonnig", hr: "Sunčano", sl: "Sončno", it: "Soleggiato",
                                          fr: "Ensoleillé", es: "Soleado", pt: "Sol", nl: "Zonnig", pl: "Słonecznie")
        case .weatherCloudy:  return pick(en: "Cloudy", de: "Bewölkt", hr: "Oblačno", sl: "Oblačno", it: "Nuvoloso",
                                          fr: "Nuageux", es: "Nublado", pt: "Nublado", nl: "Bewolkt", pl: "Pochmurno")
        case .weatherRain:    return pick(en: "Rain", de: "Regen", hr: "Kiša", sl: "Dež", it: "Pioggia",
                                          fr: "Pluie", es: "Lluvia", pt: "Chuva", nl: "Regen", pl: "Deszcz")
        case .weatherSnow:    return pick(en: "Snow", de: "Schnee", hr: "Snijeg", sl: "Sneg", it: "Neve",
                                          fr: "Neige", es: "Nieve", pt: "Neve", nl: "Sneeuw", pl: "Śnieg")
        case .weatherFrost:   return pick(en: "Frost", de: "Frost", hr: "Mraz", sl: "Mraz", it: "Gelo",
                                          fr: "Gel", es: "Helada", pt: "Geada", nl: "Vorst", pl: "Mróz")
        case .weatherWind:    return pick(en: "Wind", de: "Wind", hr: "Vjetar", sl: "Veter", it: "Vento",
                                          fr: "Vent", es: "Viento", pt: "Vento", nl: "Wind", pl: "Wiatr")
        case .weatherHeat:    return pick(en: "Heat", de: "Hitze", hr: "Vrućina", sl: "Vročina", it: "Caldo",
                                          fr: "Chaleur", es: "Calor", pt: "Calor", nl: "Hitte", pl: "Upał")

        // Crew sign-off
        case .signOff:        return pick(en: "Sign-off", de: "Bestätigung der Stunden", hr: "Potvrda sati",
                                          sl: "Potrditev ur", it: "Conferma delle ore", fr: "Validation des heures",
                                          es: "Conformidad de horas", pt: "Confirmação das horas",
                                          nl: "Akkoord uren", pl: "Potwierdzenie godzin")
        case .signedOn:       return pick(en: "signed", de: "unterschrieben am", hr: "potpisano", sl: "podpisano",
                                          it: "firmato il", fr: "signé le", es: "firmado el", pt: "assinado em",
                                          nl: "ondertekend op", pl: "podpisano")
        case .changedAfterSigning:
            return pick(en: "changed after signing", de: "nach der Unterschrift geändert",
                        hr: "promijenjeno nakon potpisa", sl: "spremenjeno po podpisu",
                        it: "modificato dopo la firma", fr: "modifié après signature",
                        es: "modificado después de firmar", pt: "alterado depois da assinatura",
                        nl: "gewijzigd na ondertekening", pl: "zmieniono po podpisaniu")

        // The printed page around the table
        case .timesheet:      return pick(en: "Timesheet", de: "Stundenzettel", hr: "Evidencija radnog vremena",
                                          sl: "Evidenca delovnega časa", it: "Foglio ore", fr: "Feuille de temps",
                                          es: "Hoja de horas", pt: "Folha de horas", nl: "Urenstaat",
                                          pl: "Karta czasu pracy")
        case .employeeSignature:
            return pick(en: "Employee · date, signature", de: "Arbeitnehmer · Datum, Unterschrift",
                        hr: "Zaposlenik · datum, potpis", sl: "Zaposleni · datum, podpis",
                        it: "Dipendente · data, firma", fr: "Salarié · date, signature",
                        es: "Empleado · fecha, firma", pt: "Trabalhador · data, assinatura",
                        nl: "Werknemer · datum, handtekening", pl: "Pracownik · data, podpis")
        case .employerSignature:
            return pick(en: "Employer · date, signature", de: "Arbeitgeber · Datum, Unterschrift",
                        hr: "Poslodavac · datum, potpis", sl: "Delodajalec · datum, podpis",
                        it: "Datore di lavoro · data, firma", fr: "Employeur · date, signature",
                        es: "Empleador · fecha, firma", pt: "Empregador · data, assinatura",
                        nl: "Werkgever · datum, handtekening", pl: "Pracodawca · data, podpis")
        case .checkedSignature:
            return pick(en: "Checked · date, signature", de: "Geprüft · Datum, Unterschrift",
                        hr: "Provjereno · datum, potpis", sl: "Preverjeno · datum, podpis",
                        it: "Verificato · data, firma", fr: "Vérifié · date, signature",
                        es: "Revisado · fecha, firma", pt: "Verificado · data, assinatura",
                        nl: "Gecontroleerd · datum, handtekening", pl: "Sprawdzono · data, podpis")
        case .of:             return pick(en: "of", de: "von", hr: "od", sl: "od", it: "di", fr: "sur", es: "de",
                                          pt: "de", nl: "van", pl: "z")
        }
    }

    /// Not private: `AppVocabulary.swift` holds the app's own word table and
    /// picks from it the same way. Two files, because the vocabulary of a
    /// document and the vocabulary of a screen are different things that
    /// happen to share a mechanism.
    func pick(
        en: String,
        de: String,
        hr: String,
        sl: String,
        it: String,
        fr: String,
        es: String,
        pt: String,
        nl: String,
        pl: String
    ) -> String {
        switch resolved {
        case .german: return de
        case .croatian: return hr
        case .slovenian: return sl
        case .italian: return it
        case .french: return fr
        case .spanish: return es
        case .portuguese: return pt
        case .dutch: return nl
        case .polish: return pl
        default: return en
        }
    }

    // MARK: - What is deliberately not translated
    //
    // Durations keep their English units in every language: 8h 30m, never
    // "8 Std 30 Min" or "8 h 30 min". They were translated for a while and it
    // was the wrong call — h and m are read as symbols rather than words
    // wherever a timesheet is filled in, the longer forms pushed every
    // duration column wider than the page wanted, and the workbook's number
    // format has to spell the same units out, so the two could drift.
    //
    // A word somebody has to look up would be worth that. A unit nobody does
    // is not. This paragraph is here so the absence reads as a decision.
}

/// Everything the app itself writes into an exported timesheet.
///
/// An enum rather than a string table: a term added here without translations
/// stops the build, which is the only reliable way to keep this many languages
/// in step. Anything the user typed is deliberately absent.
enum ExportTerm: String, CaseIterable, Hashable, Sendable {
    case date, weekday, dayType, job, start, end, breakTime, worked, paidAbsence, expected
    case overtime, balance, runningBalance, holiday, location, tags, notes, earnings

    case work, weekend, publicHoliday, vacation, sickLeave, personalDay, dayOff
    case otherDayType, timeOffInLieuDay, badWeather

    case correction, paidOut, timeOffInLieu

    case totalWorked, totalPaid, totalExpected, short, carriedForward, daysWorked
    case scheduledDays, daysOff, totalBreaks

    case summary, total, name, page, generated, hours, weekOf

    /// The director's sheet for a site.
    case day, monthTotal, you, fromTo, siteHours, recordedBy, daysOnSite, crewHours, people, siteLegend
    /// Over each part of a sheet split across pages: "People 1–5 of 9", a
    /// pattern filled in by `ExportLanguage.peopleOnPage(_:of:)`.
    case peopleOnPage
    case siteLegendPaidBreaks, siteLegendMixedBreaks, badWeatherDays
    /// Under the site sheet's totals, per person: days away sick, and on leave.
    case sickDays, leaveDays
    /// An absent person's cell: working on another site.
    case otherSite
    /// A crew member's own sheet: which site a day was on, and why they were
    /// not there.
    case site, reason
    /// A site's address, in the workbook and the CSV (1.2).
    case address
    /// Two sites in one day (1.2): the summary's block per site, the header
    /// tile, and the "+2 more" a long list of site names ends with
    /// (`ExportLanguage.moreSites(_:)`).
    case bySite, sites, moreSites
    /// Under a sheet for several sites' month, after the legend, when a
    /// sign-off was left out of it (1.2).
    case signOffOnSiteSheets

    /// Field allowance, kilometres and travel (1.2). `kilometresShort` is the
    /// unit, "km" everywhere; `kilometres` the word, for a line's label.
    case allowance, kilometresShort, travel, allowanceDays, kilometres, mileage

    /// The site diary.
    case siteDiary, weather, diaryWorkDone, diaryDeliveries, diaryProblems, diaryVisitors
    case weatherSunny, weatherCloudy, weatherRain, weatherSnow, weatherFrost, weatherWind, weatherHeat

    /// Crew sign-off on the director's sheet.
    case signOff, signedOn, changedAfterSigning

    /// The printed page around the table.
    case timesheet, employeeSignature, employerSignature, checkedSignature, of
}
