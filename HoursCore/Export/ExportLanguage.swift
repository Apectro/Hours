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
enum ExportLanguage: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    /// Whatever the phone is set to, falling back to English for languages
    /// the export does not speak.
    case device
    case english
    case german
    case croatian

    var id: String { rawValue }

    /// Named in the language itself, as a language picker should be.
    var title: String {
        switch self {
        case .device: return "Same as the phone"
        case .english: return "English"
        case .german: return "Deutsch"
        case .croatian: return "Hrvatski"
        }
    }

    /// Which vocabulary actually gets used. `device` resolves by looking at
    /// the phone, and lands on English when it is set to something this list
    /// has no words for.
    var resolved: ExportLanguage {
        guard self == .device else { return self }
        // The two-letter prefix rather than `Locale.language`, which is not
        // available on every platform the engine is built for.
        switch Locale.current.identifier.prefix(2) {
        case "de": return .german
        case "hr": return .croatian
        default: return .english
        }
    }

    /// The locale that names months and weekdays.
    ///
    /// `device` keeps the phone's, so a German phone set to a 24-hour clock
    /// and Monday weeks keeps both.
    var locale: Locale {
        switch self {
        case .device: return .current
        case .english: return Locale(identifier: "en_GB")
        case .german: return Locale(identifier: "de_DE")
        case .croatian: return Locale(identifier: "hr_HR")
        }
    }

    // MARK: - Words

    /// One switch rather than three, so every term shows its translations on
    /// the same line and a missing one is a build error rather than a cell
    /// that quietly comes out in English.
    func callAsFunction(_ term: ExportTerm) -> String {
        switch term {
        // Columns
        case .date:            return pick(en: "Date", de: "Datum", hr: "Datum")
        case .weekday:         return pick(en: "Day", de: "Tag", hr: "Dan")
        case .dayType:         return pick(en: "Type", de: "Art", hr: "Vrsta")
        case .job:             return pick(en: "Job", de: "Tätigkeit", hr: "Posao")
        case .start:           return pick(en: "Start", de: "Beginn", hr: "Početak")
        case .end:             return pick(en: "End", de: "Ende", hr: "Kraj")
        case .breakTime:       return pick(en: "Break", de: "Pause", hr: "Pauza")
        case .worked:          return pick(en: "Worked", de: "Gearbeitet", hr: "Odrađeno")
        case .paidAbsence:     return pick(en: "Paid absence", de: "Bezahlte Abwesenheit", hr: "Plaćeni izostanak")
        case .expected:        return pick(en: "Expected", de: "Soll", hr: "Planirano")
        case .overtime:        return pick(en: "Overtime", de: "Überstunden", hr: "Prekovremeni")
        case .balance:         return pick(en: "Balance", de: "Saldo", hr: "Saldo")
        case .runningBalance:  return pick(en: "Running balance", de: "Laufender Saldo", hr: "Tekući saldo")
        case .holiday:         return pick(en: "Holiday", de: "Feiertag", hr: "Praznik")
        case .location:        return pick(en: "Location", de: "Ort", hr: "Mjesto")
        case .tags:            return pick(en: "Tags", de: "Schlagwörter", hr: "Oznake")
        case .notes:           return pick(en: "Notes", de: "Notizen", hr: "Bilješke")

        // The day types that ship with the app. A type the user made is not
        // in here, and is written as they named it.
        case .work:            return pick(en: "Work", de: "Arbeit", hr: "Rad")
        case .weekend:         return pick(en: "Weekend", de: "Wochenende", hr: "Vikend")
        case .publicHoliday:   return pick(en: "Public holiday", de: "Feiertag", hr: "Državni praznik")
        case .vacation:        return pick(en: "Vacation", de: "Urlaub", hr: "Godišnji odmor")
        case .sickLeave:       return pick(en: "Sick leave", de: "Krankheit", hr: "Bolovanje")
        case .personalDay:     return pick(en: "Personal day", de: "Persönlicher Tag", hr: "Osobni dan")
        case .dayOff:          return pick(en: "Day off", de: "Freier Tag", hr: "Slobodan dan")
        case .otherDayType:    return pick(en: "Other", de: "Sonstiges", hr: "Ostalo")

        // Why a balance moved without hours moving with it.
        case .correction:      return pick(en: "Correction", de: "Korrektur", hr: "Ispravak")
        case .paidOut:         return pick(en: "Paid out", de: "Ausbezahlt", hr: "Isplaćeno")
        case .timeOffInLieu:   return pick(en: "Time off in lieu", de: "Freizeitausgleich", hr: "Zamjenski slobodni dani")

        // The summary block
        case .totalWorked:     return pick(en: "Total worked", de: "Gesamt gearbeitet", hr: "Ukupno odrađeno")
        case .totalPaid:       return pick(en: "Total paid", de: "Gesamt bezahlt", hr: "Ukupno plaćeno")
        case .totalExpected:   return pick(en: "Total expected", de: "Gesamt Soll", hr: "Ukupno planirano")
        case .short:           return pick(en: "Short", de: "Fehlzeit", hr: "Manjak")
        case .carriedForward:  return pick(en: "Balance carried forward", de: "Saldo Übertrag", hr: "Preneseni saldo")
        case .daysWorked:      return pick(en: "Days worked", de: "Arbeitstage", hr: "Radni dani")
        case .scheduledDays:   return pick(en: "Scheduled working days", de: "Sollarbeitstage", hr: "Planirani radni dani")
        case .daysOff:         return pick(en: "Days off", de: "Freie Tage", hr: "Neradni dani")
        case .totalBreaks:     return pick(en: "Total breaks", de: "Gesamt Pausen", hr: "Ukupno pauze")

        // The words that hold the document together
        case .summary:         return pick(en: "Summary", de: "Zusammenfassung", hr: "Sažetak")
        case .total:           return pick(en: "Total", de: "Summe", hr: "Ukupno")
        case .name:            return pick(en: "Name", de: "Name", hr: "Ime")
        case .page:            return pick(en: "page", de: "Seite", hr: "stranica")
        case .generated:       return pick(en: "generated", de: "erstellt", hr: "izrađeno")
        case .hours:           return pick(en: "Hours", de: "Stunden", hr: "Sati")
        case .weekOf:          return pick(en: "week of", de: "Woche vom", hr: "tjedan od")
        }
    }

    private func pick(en: String, de: String, hr: String) -> String {
        switch resolved {
        case .german: return de
        case .croatian: return hr
        default: return en
        }
    }

    // MARK: - Units

    /// What follows the number of hours in "8h 30m".
    var hourUnit: String { pick(en: "h", de: "Std", hr: "h") }

    /// And the minutes.
    var minuteUnit: String { pick(en: "m", de: "Min", hr: "min") }

    /// Whether a space comes between the number and its unit.
    ///
    /// "8h 30m" is idiomatic English and "8Std 30Min" is not German, so the
    /// spacing travels with the language rather than being fixed in the
    /// formatter. It is a separate value because the workbook's number format
    /// has to be built with exactly the same spacing, or the cell and the
    /// column total would disagree about how a duration looks.
    var unitSpacer: String { resolved == .english ? "" : " " }
}

/// Everything the app itself writes into an exported timesheet.
///
/// An enum rather than a string table: a term added here without translations
/// stops the build, which is the only reliable way to keep three languages in
/// step. Anything the user typed is deliberately absent.
enum ExportTerm: String, CaseIterable, Hashable, Sendable {
    case date, weekday, dayType, job, start, end, breakTime, worked
    case paidAbsence, expected, overtime, balance, runningBalance
    case holiday, location, tags, notes

    case work, weekend, publicHoliday, vacation, sickLeave, personalDay, dayOff, otherDayType

    case correction, paidOut, timeOffInLieu

    case totalWorked, totalPaid, totalExpected, short, carriedForward
    case daysWorked, scheduledDays, daysOff, totalBreaks

    case summary, total, name, page, generated, hours, weekOf
}
