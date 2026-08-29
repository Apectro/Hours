import Foundation

/// The words the app shows on its own screens that live in the engine.
///
/// Separate from `ExportTerm`, which is the vocabulary of a *document*, and
/// separate on purpose: the export language is a setting — someone working in
/// Germany may keep the app in German and still hand payroll an English
/// timesheet — while these follow the phone and nothing else. Filing "Dark"
/// under the words a timesheet is written in would have made that distinction
/// impossible to keep.
///
/// Why any of this exists: `HoursCore` also builds on Linux, where the
/// localisation APIs are not reliably present, so `String(localized:)` is not
/// available to it. The app's own layer uses that; the engine uses this. Both
/// end up covering the same ten languages, and `Scripts/check-localizations.py`
/// is what says so.
///
/// Adding a term is one case here and one arm below, and the compiler insists
/// on all ten arguments — so a term cannot ship with a language missing, which
/// is exactly how "Expected" and "Fields" once reached a German screenshot.
enum UITerm: String, CaseIterable, Hashable, Sendable {
    // How a day's length is measured
    case wallClock, elapsedReal, wallClockExplained, elapsedRealExplained
    // Rounding
    case roundingExact, roundingFiveMinutes, roundingQuarterHour
    // Appearance
    case appearanceSystem, appearanceLight, appearanceDark
    // What a calendar cell shows
    case badgeNothing, badgeWorkedHours, badgeBalance
    // Periods
    case periodDay, periodWeek, periodMonth, periodYear, periodCustom
    // How a holiday repeats
    case holidayOnce, holidayAnnual, holidayNthWeekday
    // Separators
    case separatorComma, separatorSemicolon, separatorTab, separatorPoint
    // Why a balance was adjusted by hand
    case adjustmentCorrectionExplained, adjustmentPayoutExplained,
    case adjustmentTimeOffExplained
    // What Pro unlocks
    case proTimesheets, proWidgets, proMultipleJobs, proRangeEditing, proICloudSync,
    case proTimesheetsExplained, proWidgetsExplained, proMultipleJobsExplained,
    case proRangeEditingExplained, proICloudSyncExplained
}

extension ExportLanguage {
    /// One switch rather than one per language, so every term shows its
    /// translations together and a missing one is a build error rather than a
    /// label that quietly comes out in English.
    func callAsFunction(_ term: UITerm) -> String {
        switch term {

        // How a day's length is measured
        case .wallClock:
            return pick(en: "Wall clock", de: "Uhrzeit", hr: "Vrijeme po satu", sl: "Urni čas",
                              it: "Ora dell'orologio", fr: "Heure de l'horloge",
                              es: "Hora del reloj", pt: "Hora do relógio", nl: "Kloktijd",
                              pl: "Czas zegarowy")
        case .elapsedReal:
            return pick(en: "Actual elapsed", de: "Tatsächlich vergangen", hr: "Stvarno proteklo",
                              sl: "Dejansko preteklo", it: "Tempo effettivo",
                              fr: "Temps réellement écoulé", es: "Tiempo real transcurrido",
                              pt: "Tempo real decorrido", nl: "Werkelijk verstreken",
                              pl: "Rzeczywisty upływ")
        case .wallClockExplained:
            return pick(en: "08:00–16:00 counts as 8 h on every day of the year, including clock-change days.",
                              de: "08:00–16:00 zählt an jedem Tag des Jahres als 8 Std., auch an Tagen der Zeitumstellung.",
                              hr: "08:00–16:00 računa se kao 8 h svaki dan u godini, uključujući dane pomicanja sata.",
                              sl: "08:00–16:00 se šteje kot 8 h vsak dan v letu, tudi na dneve premika ure.",
                              it: "08:00–16:00 conta come 8 h ogni giorno dell'anno, anche quando cambia l'ora.",
                              fr: "08:00–16:00 compte pour 8 h tous les jours de l'année, y compris lors du changement d'heure.",
                              es: "08:00–16:00 cuenta como 8 h todos los días del año, incluidos los del cambio de hora.",
                              pt: "08:00–16:00 conta como 8 h todos os dias do ano, incluindo os da mudança da hora.",
                              nl: "08:00–16:00 telt elke dag van het jaar als 8 u, ook op dagen dat de klok verspringt.",
                              pl: "08:00–16:00 liczy się jako 8 godz. każdego dnia roku, także przy zmianie czasu.")
        case .elapsedRealExplained:
            return pick(en: "Shifts crossing a daylight-saving change count the time that actually passed.",
                              de: "Schichten über eine Zeitumstellung hinweg zählen die tatsächlich vergangene Zeit.",
                              hr: "Smjene koje prelaze pomicanje sata broje stvarno proteklo vrijeme.",
                              sl: "Izmene čez premik ure štejejo dejansko pretečeni čas.",
                              it: "I turni a cavallo del cambio dell'ora contano il tempo realmente trascorso.",
                              fr: "Les postes à cheval sur un changement d'heure comptent le temps réellement écoulé.",
                              es: "Los turnos que cruzan un cambio de hora cuentan el tiempo realmente transcurrido.",
                              pt: "Os turnos que atravessam a mudança da hora contam o tempo realmente decorrido.",
                              nl: "Diensten over een klokverzetting tellen de tijd die werkelijk verstreken is.",
                              pl: "Zmiany obejmujące zmianę czasu liczą czas, który faktycznie upłynął.")

        // Rounding
        case .roundingExact:
            return pick(en: "Exact", de: "Genau", hr: "Točno", sl: "Natančno", it: "Esatto",
                              fr: "Exact", es: "Exacto", pt: "Exato", nl: "Exact", pl: "Dokładnie")
        case .roundingFiveMinutes:
            return pick(en: "Nearest 5 min", de: "Auf 5 Min.", hr: "Na 5 min", sl: "Na 5 min",
                              it: "Ai 5 min", fr: "Aux 5 min", es: "A 5 min", pt: "Aos 5 min",
                              nl: "Op 5 min", pl: "Do 5 min")
        case .roundingQuarterHour:
            return pick(en: "Nearest 15 min", de: "Auf 15 Min.", hr: "Na 15 min", sl: "Na 15 min",
                              it: "Ai 15 min", fr: "Aux 15 min", es: "A 15 min", pt: "Aos 15 min",
                              nl: "Op 15 min", pl: "Do 15 min")

        // Appearance
        case .appearanceSystem:
            return pick(en: "System", de: "System", hr: "Sustav", sl: "Sistem", it: "Sistema",
                              fr: "Système", es: "Sistema", pt: "Sistema", nl: "Systeem",
                              pl: "Systemowy")
        case .appearanceLight:
            return pick(en: "Light", de: "Hell", hr: "Svijetlo", sl: "Svetlo", it: "Chiaro",
                              fr: "Clair", es: "Claro", pt: "Claro", nl: "Licht", pl: "Jasny")
        case .appearanceDark:
            return pick(en: "Dark", de: "Dunkel", hr: "Tamno", sl: "Temno", it: "Scuro",
                              fr: "Sombre", es: "Oscuro", pt: "Escuro", nl: "Donker", pl: "Ciemny")

        // What a calendar cell shows
        case .badgeNothing:
            return pick(en: "Nothing", de: "Nichts", hr: "Ništa", sl: "Nič", it: "Niente",
                              fr: "Rien", es: "Nada", pt: "Nada", nl: "Niets", pl: "Nic")
        case .badgeWorkedHours:
            return pick(en: "Worked hours", de: "Gearbeitete Stunden", hr: "Odrađeni sati",
                              sl: "Opravljene ure", it: "Ore lavorate", fr: "Heures travaillées",
                              es: "Horas trabajadas", pt: "Horas trabalhadas", nl: "Gewerkte uren",
                              pl: "Przepracowane godziny")
        case .badgeBalance:
            return pick(en: "Balance", de: "Saldo", hr: "Saldo", sl: "Saldo", it: "Saldo",
                              fr: "Solde", es: "Saldo", pt: "Saldo", nl: "Saldo", pl: "Saldo")

        // Periods
        case .periodDay:
            return pick(en: "Day", de: "Tag", hr: "Dan", sl: "Dan", it: "Giorno", fr: "Jour",
                              es: "Día", pt: "Dia", nl: "Dag", pl: "Dzień")
        case .periodWeek:
            return pick(en: "Week", de: "Woche", hr: "Tjedan", sl: "Teden", it: "Settimana",
                              fr: "Semaine", es: "Semana", pt: "Semana", nl: "Week", pl: "Tydzień")
        case .periodMonth:
            return pick(en: "Month", de: "Monat", hr: "Mjesec", sl: "Mesec", it: "Mese", fr: "Mois",
                              es: "Mes", pt: "Mês", nl: "Maand", pl: "Miesiąc")
        case .periodYear:
            return pick(en: "Year", de: "Jahr", hr: "Godina", sl: "Leto", it: "Anno", fr: "Année",
                              es: "Año", pt: "Ano", nl: "Jaar", pl: "Rok")
        case .periodCustom:
            return pick(en: "Custom", de: "Eigener Zeitraum", hr: "Prilagođeno", sl: "Po meri",
                              it: "Personalizzato", fr: "Personnalisé", es: "Personalizado",
                              pt: "Personalizado", nl: "Aangepast", pl: "Własny")

        // How a holiday repeats
        case .holidayOnce:
            return pick(en: "One-off date", de: "Einmaliges Datum", hr: "Jednokratni datum",
                              sl: "Enkratni datum", it: "Data singola", fr: "Date unique",
                              es: "Fecha única", pt: "Data única", nl: "Eenmalige datum",
                              pl: "Data jednorazowa")
        case .holidayAnnual:
            return pick(en: "Every year, same date", de: "Jedes Jahr, gleiches Datum",
                              hr: "Svake godine, isti datum", sl: "Vsako leto, isti datum",
                              it: "Ogni anno, stessa data", fr: "Chaque année, même date",
                              es: "Cada año, misma fecha", pt: "Todos os anos, mesma data",
                              nl: "Elk jaar, dezelfde datum", pl: "Co roku, ta sama data")
        case .holidayNthWeekday:
            return pick(en: "Every year, n-th weekday", de: "Jedes Jahr, n-ter Wochentag",
                              hr: "Svake godine, n-ti dan u tjednu",
                              sl: "Vsako leto, n-ti dan v tednu",
                              it: "Ogni anno, n-esimo giorno della settimana",
                              fr: "Chaque année, n-ième jour de la semaine",
                              es: "Cada año, n-ésimo día de la semana",
                              pt: "Todos os anos, n-ésimo dia da semana",
                              nl: "Elk jaar, n-de weekdag", pl: "Co roku, n-ty dzień tygodnia")

        // Separators
        case .separatorComma:
            return pick(en: "Comma", de: "Komma", hr: "Zarez", sl: "Vejica", it: "Virgola",
                              fr: "Virgule", es: "Coma", pt: "Vírgula", nl: "Komma",
                              pl: "Przecinek")
        case .separatorSemicolon:
            return pick(en: "Semicolon", de: "Semikolon", hr: "Točka-zarez", sl: "Podpičje",
                              it: "Punto e virgola", fr: "Point-virgule", es: "Punto y coma",
                              pt: "Ponto e vírgula", nl: "Puntkomma", pl: "Średnik")
        case .separatorTab:
            return pick(en: "Tab", de: "Tabulator", hr: "Tabulator", sl: "Tabulator",
                              it: "Tabulazione", fr: "Tabulation", es: "Tabulación",
                              pt: "Tabulação", nl: "Tab", pl: "Tabulator")
        case .separatorPoint:
            return pick(en: "Point", de: "Punkt", hr: "Točka", sl: "Pika", it: "Punto", fr: "Point",
                              es: "Punto", pt: "Ponto", nl: "Punt", pl: "Kropka")

        // Why a balance was adjusted by hand
        case .adjustmentCorrectionExplained:
            return pick(en: "Adjusts the balance without changing the hours you worked.",
                              de: "Ändert den Saldo, ohne die gearbeiteten Stunden zu verändern.",
                              hr: "Mijenja saldo bez promjene odrađenih sati.",
                              sl: "Spremeni saldo, ne da bi spremenil opravljene ure.",
                              it: "Modifica il saldo senza cambiare le ore lavorate.",
                              fr: "Ajuste le solde sans modifier les heures travaillées.",
                              es: "Ajusta el saldo sin cambiar las horas trabajadas.",
                              pt: "Ajusta o saldo sem alterar as horas trabalhadas.",
                              nl: "Past het saldo aan zonder de gewerkte uren te wijzigen.",
                              pl: "Zmienia saldo bez zmiany przepracowanych godzin.")
        case .adjustmentPayoutExplained:
            return pick(en: "Overtime exchanged for money. It leaves the balance and does not come back as time.",
                              de: "Überstunden gegen Geld. Sie verlassen den Saldo und kommen nicht als Zeit zurück.",
                              hr: "Prekovremeni sati zamijenjeni za novac. Odlaze iz salda i ne vraćaju se kao vrijeme.",
                              sl: "Nadure, zamenjane za denar. Zapustijo saldo in se ne vrnejo kot čas.",
                              it: "Straordinari convertiti in denaro. Escono dal saldo e non tornano come tempo.",
                              fr: "Heures supplémentaires payées. Elles quittent le solde et ne reviennent pas en temps.",
                              es: "Horas extra pagadas. Salen del saldo y no vuelven como tiempo.",
                              pt: "Horas extra pagas. Saem do saldo e não voltam como tempo.",
                              nl: "Overuren uitbetaald. Ze verlaten het saldo en komen niet terug als tijd.",
                              pl: "Nadgodziny wymienione na pieniądze. Opuszczają saldo i nie wracają jako czas.")
        case .adjustmentTimeOffExplained:
            return pick(en: "Overtime taken as time off. Use a negative figure for the hours drawn down.",
                              de: "Überstunden als Freizeit genommen. Für die abgebauten Stunden einen negativen Wert eingeben.",
                              hr: "Prekovremeni sati uzeti kao slobodno vrijeme. Za iskorištene sate upišite negativan broj.",
                              sl: "Nadure, vzete kot prosti čas. Za porabljene ure vnesite negativno število.",
                              it: "Straordinari presi come permesso. Usa un valore negativo per le ore consumate.",
                              fr: "Heures supplémentaires prises en repos. Indiquez un nombre négatif pour les heures utilisées.",
                              es: "Horas extra tomadas como tiempo libre. Usa un número negativo para las horas consumidas.",
                              pt: "Horas extra tiradas como folga. Use um número negativo para as horas utilizadas.",
                              nl: "Overuren opgenomen als vrije tijd. Gebruik een negatief getal voor de opgenomen uren.",
                              pl: "Nadgodziny odebrane jako wolne. Wpisz liczbę ujemną dla wykorzystanych godzin.")

        // What Pro unlocks
        case .proTimesheets:
            return pick(en: "Timesheets", de: "Stundenzettel", hr: "Evidencija radnog vremena",
                              sl: "Evidenca delovnega časa", it: "Fogli ore",
                              fr: "Feuilles d'heures", es: "Hojas de horas", pt: "Folhas de horas",
                              nl: "Urenstaten", pl: "Karty czasu pracy")
        case .proWidgets:
            return pick(en: "Widgets", de: "Widgets", hr: "Widgeti", sl: "Pripomočki", it: "Widget",
                              fr: "Widgets", es: "Widgets", pt: "Widgets", nl: "Widgets",
                              pl: "Widżety")
        case .proMultipleJobs:
            return pick(en: "More than one job", de: "Mehr als eine Tätigkeit",
                              hr: "Više od jednog posla", sl: "Več kot eno delo",
                              it: "Più di un lavoro", fr: "Plusieurs postes",
                              es: "Más de un trabajo", pt: "Mais do que um trabalho",
                              nl: "Meer dan één functie", pl: "Więcej niż jedna praca")
        case .proRangeEditing:
            return pick(en: "Edit a range at once", de: "Zeitraum auf einmal bearbeiten",
                              hr: "Uređivanje raspona odjednom", sl: "Urejanje obdobja naenkrat",
                              it: "Modifica un intervallo in una volta",
                              fr: "Modifier une période en une fois",
                              es: "Editar un intervalo de una vez",
                              pt: "Editar um intervalo de uma vez",
                              nl: "Een periode in één keer bewerken", pl: "Edycja zakresu naraz")
        case .proICloudSync:
            return pick(en: "iCloud sync", de: "iCloud-Sync", hr: "iCloud sinkronizacija",
                              sl: "Sinhronizacija iCloud", it: "Sincronizzazione iCloud",
                              fr: "Synchronisation iCloud", es: "Sincronización con iCloud",
                              pt: "Sincronização com iCloud", nl: "iCloud-synchronisatie",
                              pl: "Synchronizacja iCloud")
        case .proTimesheetsExplained:
            return pick(en: "Hand your hours to payroll as a spreadsheet or a PDF, laid out the way you choose.",
                              de: "Geben Sie Ihre Stunden als Tabelle oder PDF an die Lohnbuchhaltung, im Layout Ihrer Wahl.",
                              hr: "Predajte svoje sate obračunu plaća kao tablicu ili PDF, složene onako kako želite.",
                              sl: "Oddajte svoje ure obračunu plač kot preglednico ali PDF, urejene po vaši izbiri.",
                              it: "Consegna le tue ore alle paghe come foglio di calcolo o PDF, impaginato come vuoi.",
                              fr: "Remettez vos heures à la paie en tableur ou en PDF, mis en page comme vous le voulez.",
                              es: "Entrega tus horas a nóminas como hoja de cálculo o PDF, con el diseño que elijas.",
                              pt: "Entregue as suas horas ao processamento salarial em folha de cálculo ou PDF, como preferir.",
                              nl: "Lever je uren aan de salarisadministratie als spreadsheet of pdf, ingedeeld zoals jij wilt.",
                              pl: "Przekaż godziny do kadr jako arkusz lub PDF, w wybranym przez siebie układzie.")
        case .proWidgetsExplained:
            return pick(en: "Today's hours and the month's balance on your Home Screen and Lock Screen.",
                              de: "Die heutigen Stunden und der Monatssaldo auf Home- und Sperrbildschirm.",
                              hr: "Današnji sati i mjesečni saldo na početnom i zaključanom zaslonu.",
                              sl: "Današnje ure in mesečni saldo na začetnem in zaklenjenem zaslonu.",
                              it: "Le ore di oggi e il saldo del mese sulla schermata Home e sul blocco schermo.",
                              fr: "Les heures du jour et le solde du mois sur l'écran d'accueil et l'écran verrouillé.",
                              es: "Las horas de hoy y el saldo del mes en la pantalla de inicio y la de bloqueo.",
                              pt: "As horas de hoje e o saldo do mês no ecrã principal e no ecrã bloqueado.",
                              nl: "De uren van vandaag en het maandsaldo op je beginscherm en toegangsscherm.",
                              pl: "Dzisiejsze godziny i saldo miesiąca na ekranie początkowym i blokady.")
        case .proMultipleJobsExplained:
            return pick(en: "Two jobs on the same Tuesday, each with its own contracted week.",
                              de: "Zwei Tätigkeiten am selben Dienstag, jede mit ihrer eigenen Vertragswoche.",
                              hr: "Dva posla u isti utorak, svaki sa svojim ugovorenim tjednom.",
                              sl: "Dve deli isti torek, vsako s svojim pogodbenim tednom.",
                              it: "Due lavori nello stesso martedì, ciascuno con la propria settimana contrattuale.",
                              fr: "Deux postes le même mardi, chacun avec sa semaine contractuelle.",
                              es: "Dos trabajos el mismo martes, cada uno con su propia semana contratada.",
                              pt: "Dois trabalhos na mesma terça-feira, cada um com a sua semana contratada.",
                              nl: "Twee functies op dezelfde dinsdag, elk met een eigen contractweek.",
                              pl: "Dwie prace tego samego wtorku, każda z własnym tygodniem umownym.")
        case .proRangeEditingExplained:
            return pick(en: "Book a fortnight of leave in one pass instead of ten trips through the editor.",
                              de: "Zwei Wochen Urlaub in einem Zug eintragen statt zehnmal durch den Editor.",
                              hr: "Unesite dva tjedna godišnjeg odjednom umjesto deset prolazaka kroz uređivač.",
                              sl: "Vnesite dva tedna dopusta naenkrat namesto desetih obiskov urejevalnika.",
                              it: "Registra due settimane di ferie in una volta invece di dieci passaggi nell'editor.",
                              fr: "Saisissez deux semaines de congés en une fois au lieu de dix passages dans l'éditeur.",
                              es: "Registra dos semanas de vacaciones de una vez en lugar de diez pasos por el editor.",
                              pt: "Registe duas semanas de férias de uma vez em vez de dez passagens pelo editor.",
                              nl: "Boek twee weken verlof in één keer in plaats van tien rondjes door de editor.",
                              pl: "Wpisz dwa tygodnie urlopu za jednym razem zamiast dziesięciu wizyt w edytorze.")
        case .proICloudSyncExplained:
            return pick(en: "The same hours on your phone and your iPad, through your own iCloud.",
                              de: "Dieselben Stunden auf iPhone und iPad, über Ihre eigene iCloud.",
                              hr: "Isti sati na telefonu i iPadu, preko vlastitog iClouda.",
                              sl: "Iste ure na telefonu in iPadu, prek lastnega iClouda.",
                              it: "Le stesse ore su iPhone e iPad, tramite il tuo iCloud.",
                              fr: "Les mêmes heures sur votre iPhone et votre iPad, via votre propre iCloud.",
                              es: "Las mismas horas en tu iPhone y tu iPad, a través de tu propio iCloud.",
                              pt: "As mesmas horas no seu iPhone e iPad, através do seu próprio iCloud.",
                              nl: "Dezelfde uren op je iPhone en je iPad, via je eigen iCloud.",
                              pl: "Te same godziny na iPhonie i iPadzie, przez własny iCloud.")
        }
    }
}
