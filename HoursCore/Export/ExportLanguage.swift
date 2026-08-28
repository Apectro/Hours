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
        // The two-letter prefix rather than `Locale.language`, which is not
        // available on every platform the engine is built for.
        let phone = String(Locale.current.identifier.prefix(2))
        return ExportLanguage.allCases.first { $0 != .device && $0.identity.code == phone } ?? .english
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
        }
    }

    private func pick(
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
    case overtime, balance, runningBalance, holiday, location, tags, notes

    case work, weekend, publicHoliday, vacation, sickLeave, personalDay, dayOff
    case otherDayType

    case correction, paidOut, timeOffInLieu

    case totalWorked, totalPaid, totalExpected, short, carriedForward, daysWorked
    case scheduledDays, daysOff, totalBreaks

    case summary, total, name, page, generated, hours, weekOf
}
