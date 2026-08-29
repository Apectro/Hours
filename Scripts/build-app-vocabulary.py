"""Emit HoursCore/Localization/AppVocabulary.swift from a table.

Hand-writing ten arguments on each of thirty-odd switch arms is how a language
ends up shifted by one column, which compiles and is invisible in review.
"""
import pathlib

ORDER = ["en", "de", "hr", "sl", "it", "fr", "es", "pt", "nl", "pl"]

# section -> [(case, {lang: word})]
SECTIONS = [
    ("How a day's length is measured", [
        ("wallClock", dict(
            en="Wall clock", de="Uhrzeit", hr="Vrijeme po satu", sl="Urni čas",
            it="Ora dell'orologio", fr="Heure de l'horloge", es="Hora del reloj",
            pt="Hora do relógio", nl="Kloktijd", pl="Czas zegarowy")),
        ("elapsedReal", dict(
            en="Actual elapsed", de="Tatsächlich vergangen", hr="Stvarno proteklo",
            sl="Dejansko preteklo", it="Tempo effettivo", fr="Temps réellement écoulé",
            es="Tiempo real transcurrido", pt="Tempo real decorrido",
            nl="Werkelijk verstreken", pl="Rzeczywisty upływ")),
        ("wallClockExplained", dict(
            en="08:00–16:00 counts as 8 h on every day of the year, including clock-change days.",
            de="08:00–16:00 zählt an jedem Tag des Jahres als 8 Std., auch an Tagen der Zeitumstellung.",
            hr="08:00–16:00 računa se kao 8 h svaki dan u godini, uključujući dane pomicanja sata.",
            sl="08:00–16:00 se šteje kot 8 h vsak dan v letu, tudi na dneve premika ure.",
            it="08:00–16:00 conta come 8 h ogni giorno dell'anno, anche quando cambia l'ora.",
            fr="08:00–16:00 compte pour 8 h tous les jours de l'année, y compris lors du changement d'heure.",
            es="08:00–16:00 cuenta como 8 h todos los días del año, incluidos los del cambio de hora.",
            pt="08:00–16:00 conta como 8 h todos os dias do ano, incluindo os da mudança da hora.",
            nl="08:00–16:00 telt elke dag van het jaar als 8 u, ook op dagen dat de klok verspringt.",
            pl="08:00–16:00 liczy się jako 8 godz. każdego dnia roku, także przy zmianie czasu.")),
        ("elapsedRealExplained", dict(
            en="Shifts crossing a daylight-saving change count the time that actually passed.",
            de="Schichten über eine Zeitumstellung hinweg zählen die tatsächlich vergangene Zeit.",
            hr="Smjene koje prelaze pomicanje sata broje stvarno proteklo vrijeme.",
            sl="Izmene čez premik ure štejejo dejansko pretečeni čas.",
            it="I turni a cavallo del cambio dell'ora contano il tempo realmente trascorso.",
            fr="Les postes à cheval sur un changement d'heure comptent le temps réellement écoulé.",
            es="Los turnos que cruzan un cambio de hora cuentan el tiempo realmente transcurrido.",
            pt="Os turnos que atravessam a mudança da hora contam o tempo realmente decorrido.",
            nl="Diensten over een klokverzetting tellen de tijd die werkelijk verstreken is.",
            pl="Zmiany obejmujące zmianę czasu liczą czas, który faktycznie upłynął.")),
    ]),
    ("Rounding", [
        ("roundingExact", dict(
            en="Exact", de="Genau", hr="Točno", sl="Natančno", it="Esatto",
            fr="Exact", es="Exacto", pt="Exato", nl="Exact", pl="Dokładnie")),
        ("roundingFiveMinutes", dict(
            en="Nearest 5 min", de="Auf 5 Min.", hr="Na 5 min", sl="Na 5 min",
            it="Ai 5 min", fr="Aux 5 min", es="A 5 min", pt="Aos 5 min",
            nl="Op 5 min", pl="Do 5 min")),
        ("roundingQuarterHour", dict(
            en="Nearest 15 min", de="Auf 15 Min.", hr="Na 15 min", sl="Na 15 min",
            it="Ai 15 min", fr="Aux 15 min", es="A 15 min", pt="Aos 15 min",
            nl="Op 15 min", pl="Do 15 min")),
    ]),
    ("Appearance", [
        ("appearanceSystem", dict(
            en="System", de="System", hr="Sustav", sl="Sistem", it="Sistema",
            fr="Système", es="Sistema", pt="Sistema", nl="Systeem", pl="Systemowy")),
        ("appearanceLight", dict(
            en="Light", de="Hell", hr="Svijetlo", sl="Svetlo", it="Chiaro",
            fr="Clair", es="Claro", pt="Claro", nl="Licht", pl="Jasny")),
        ("appearanceDark", dict(
            en="Dark", de="Dunkel", hr="Tamno", sl="Temno", it="Scuro",
            fr="Sombre", es="Oscuro", pt="Escuro", nl="Donker", pl="Ciemny")),
    ]),
    ("What a calendar cell shows", [
        ("badgeNothing", dict(
            en="Nothing", de="Nichts", hr="Ništa", sl="Nič", it="Niente",
            fr="Rien", es="Nada", pt="Nada", nl="Niets", pl="Nic")),
        ("badgeWorkedHours", dict(
            en="Worked hours", de="Gearbeitete Stunden", hr="Odrađeni sati",
            sl="Opravljene ure", it="Ore lavorate", fr="Heures travaillées",
            es="Horas trabajadas", pt="Horas trabalhadas", nl="Gewerkte uren",
            pl="Przepracowane godziny")),
        ("badgeBalance", dict(
            en="Balance", de="Saldo", hr="Saldo", sl="Saldo", it="Saldo",
            fr="Solde", es="Saldo", pt="Saldo", nl="Saldo", pl="Saldo")),
    ]),
    ("Periods", [
        ("periodDay", dict(
            en="Day", de="Tag", hr="Dan", sl="Dan", it="Giorno", fr="Jour",
            es="Día", pt="Dia", nl="Dag", pl="Dzień")),
        ("periodWeek", dict(
            en="Week", de="Woche", hr="Tjedan", sl="Teden", it="Settimana",
            fr="Semaine", es="Semana", pt="Semana", nl="Week", pl="Tydzień")),
        ("periodMonth", dict(
            en="Month", de="Monat", hr="Mjesec", sl="Mesec", it="Mese",
            fr="Mois", es="Mes", pt="Mês", nl="Maand", pl="Miesiąc")),
        ("periodYear", dict(
            en="Year", de="Jahr", hr="Godina", sl="Leto", it="Anno",
            fr="Année", es="Año", pt="Ano", nl="Jaar", pl="Rok")),
        ("periodCustom", dict(
            en="Custom", de="Eigener Zeitraum", hr="Prilagođeno", sl="Po meri",
            it="Personalizzato", fr="Personnalisé", es="Personalizado",
            pt="Personalizado", nl="Aangepast", pl="Własny")),
    ]),
    ("How a holiday repeats", [
        ("holidayOnce", dict(
            en="One-off date", de="Einmaliges Datum", hr="Jednokratni datum",
            sl="Enkratni datum", it="Data singola", fr="Date unique",
            es="Fecha única", pt="Data única", nl="Eenmalige datum",
            pl="Data jednorazowa")),
        ("holidayAnnual", dict(
            en="Every year, same date", de="Jedes Jahr, gleiches Datum",
            hr="Svake godine, isti datum", sl="Vsako leto, isti datum",
            it="Ogni anno, stessa data", fr="Chaque année, même date",
            es="Cada año, misma fecha", pt="Todos os anos, mesma data",
            nl="Elk jaar, dezelfde datum", pl="Co roku, ta sama data")),
        ("holidayNthWeekday", dict(
            en="Every year, n-th weekday", de="Jedes Jahr, n-ter Wochentag",
            hr="Svake godine, n-ti dan u tjednu", sl="Vsako leto, n-ti dan v tednu",
            it="Ogni anno, n-esimo giorno della settimana",
            fr="Chaque année, n-ième jour de la semaine",
            es="Cada año, n-ésimo día de la semana",
            pt="Todos os anos, n-ésimo dia da semana",
            nl="Elk jaar, n-de weekdag", pl="Co roku, n-ty dzień tygodnia")),
    ]),
    ("Separators", [
        ("separatorComma", dict(
            en="Comma", de="Komma", hr="Zarez", sl="Vejica", it="Virgola",
            fr="Virgule", es="Coma", pt="Vírgula", nl="Komma", pl="Przecinek")),
        ("separatorSemicolon", dict(
            en="Semicolon", de="Semikolon", hr="Točka-zarez", sl="Podpičje",
            it="Punto e virgola", fr="Point-virgule", es="Punto y coma",
            pt="Ponto e vírgula", nl="Puntkomma", pl="Średnik")),
        ("separatorTab", dict(
            en="Tab", de="Tabulator", hr="Tabulator", sl="Tabulator",
            it="Tabulazione", fr="Tabulation", es="Tabulación",
            pt="Tabulação", nl="Tab", pl="Tabulator")),
        ("separatorPoint", dict(
            en="Point", de="Punkt", hr="Točka", sl="Pika", it="Punto",
            fr="Point", es="Punto", pt="Ponto", nl="Punt", pl="Kropka")),
    ]),
    ("When a backup file will not open", [
        ("backupNotABackup", dict(
            en="This file is not a Zeitkonto backup.",
            de="Diese Datei ist keine Zeitkonto-Sicherung.",
            hr="Ova datoteka nije Zeitkonto sigurnosna kopija.",
            sl="Ta datoteka ni varnostna kopija Zeitkonta.",
            it="Questo file non è un backup di Zeitkonto.",
            fr="Ce fichier n'est pas une sauvegarde Zeitkonto.",
            es="Este archivo no es una copia de seguridad de Zeitkonto.",
            pt="Este ficheiro não é uma cópia de segurança do Zeitkonto.",
            nl="Dit bestand is geen Zeitkonto-back-up.",
            pl="Ten plik nie jest kopią zapasową Zeitkonto.")),
        # %lld is the format version the file declares.
        ("backupFromNewerVersion", dict(
            en="This backup was made by a newer version of Zeitkonto (format %lld). Update Zeitkonto and try again.",
            de="Diese Sicherung stammt aus einer neueren Version von Zeitkonto (Format %lld). Bitte Zeitkonto aktualisieren und erneut versuchen.",
            hr="Ova je kopija napravljena novijom verzijom Zeitkonta (format %lld). Ažurirajte Zeitkonto i pokušajte ponovno.",
            sl="Ta kopija je bila ustvarjena z novejšo različico Zeitkonta (format %lld). Posodobite Zeitkonto in poskusite znova.",
            it="Questo backup è stato creato da una versione più recente di Zeitkonto (formato %lld). Aggiorna Zeitkonto e riprova.",
            fr="Cette sauvegarde a été créée par une version plus récente de Zeitkonto (format %lld). Mettez Zeitkonto à jour et réessayez.",
            es="Esta copia se creó con una versión más reciente de Zeitkonto (formato %lld). Actualiza Zeitkonto e inténtalo de nuevo.",
            pt="Esta cópia foi criada por uma versão mais recente do Zeitkonto (formato %lld). Atualize o Zeitkonto e tente novamente.",
            nl="Deze back-up is gemaakt met een nieuwere versie van Zeitkonto (formaat %lld). Werk Zeitkonto bij en probeer het opnieuw.",
            pl="Ta kopia powstała w nowszej wersji Zeitkonto (format %lld). Zaktualizuj Zeitkonto i spróbuj ponownie.")),
        # %@ names the part of the file that would not decode.
        ("backupUnreadable", dict(
            en="This backup is damaged: its %@ could not be read.",
            de="Diese Sicherung ist beschädigt: %@ konnte nicht gelesen werden.",
            hr="Ova je kopija oštećena: %@ nije bilo moguće pročitati.",
            sl="Ta kopija je poškodovana: %@ ni bilo mogoče prebrati.",
            it="Questo backup è danneggiato: non è stato possibile leggere %@.",
            fr="Cette sauvegarde est endommagée : impossible de lire %@.",
            es="Esta copia está dañada: no se pudo leer %@.",
            pt="Esta cópia está danificada: não foi possível ler %@.",
            nl="Deze back-up is beschadigd: %@ kon niet worden gelezen.",
            pl="Ta kopia jest uszkodzona: nie udało się odczytać %@.")),
    ]),
    ("Why a balance was adjusted by hand", [
        ("adjustmentCorrectionExplained", dict(
            en="Adjusts the balance without changing the hours you worked.",
            de="Ändert den Saldo, ohne die gearbeiteten Stunden zu verändern.",
            hr="Mijenja saldo bez promjene odrađenih sati.",
            sl="Spremeni saldo, ne da bi spremenil opravljene ure.",
            it="Modifica il saldo senza cambiare le ore lavorate.",
            fr="Ajuste le solde sans modifier les heures travaillées.",
            es="Ajusta el saldo sin cambiar las horas trabajadas.",
            pt="Ajusta o saldo sem alterar as horas trabalhadas.",
            nl="Past het saldo aan zonder de gewerkte uren te wijzigen.",
            pl="Zmienia saldo bez zmiany przepracowanych godzin.")),
        ("adjustmentPayoutExplained", dict(
            en="Overtime exchanged for money. It leaves the balance and does not come back as time.",
            de="Überstunden gegen Geld. Sie verlassen den Saldo und kommen nicht als Zeit zurück.",
            hr="Prekovremeni sati zamijenjeni za novac. Odlaze iz salda i ne vraćaju se kao vrijeme.",
            sl="Nadure, zamenjane za denar. Zapustijo saldo in se ne vrnejo kot čas.",
            it="Straordinari convertiti in denaro. Escono dal saldo e non tornano come tempo.",
            fr="Heures supplémentaires payées. Elles quittent le solde et ne reviennent pas en temps.",
            es="Horas extra pagadas. Salen del saldo y no vuelven como tiempo.",
            pt="Horas extra pagas. Saem do saldo e não voltam como tempo.",
            nl="Overuren uitbetaald. Ze verlaten het saldo en komen niet terug als tijd.",
            pl="Nadgodziny wymienione na pieniądze. Opuszczają saldo i nie wracają jako czas.")),
        ("adjustmentTimeOffExplained", dict(
            en="Overtime taken as time off. Use a negative figure for the hours drawn down.",
            de="Überstunden als Freizeit genommen. Für die abgebauten Stunden einen negativen Wert eingeben.",
            hr="Prekovremeni sati uzeti kao slobodno vrijeme. Za iskorištene sate upišite negativan broj.",
            sl="Nadure, vzete kot prosti čas. Za porabljene ure vnesite negativno število.",
            it="Straordinari presi come permesso. Usa un valore negativo per le ore consumate.",
            fr="Heures supplémentaires prises en repos. Indiquez un nombre négatif pour les heures utilisées.",
            es="Horas extra tomadas como tiempo libre. Usa un número negativo para las horas consumidas.",
            pt="Horas extra tiradas como folga. Use um número negativo para as horas utilizadas.",
            nl="Overuren opgenomen als vrije tijd. Gebruik een negatief getal voor de opgenomen uren.",
            pl="Nadgodziny odebrane jako wolne. Wpisz liczbę ujemną dla wykorzystanych godzin.")),
    ]),
    ("What Pro unlocks", [
        ("proTimesheets", dict(
            en="Timesheets", de="Stundenzettel", hr="Evidencija radnog vremena",
            sl="Evidenca delovnega časa", it="Fogli ore", fr="Feuilles d'heures",
            es="Hojas de horas", pt="Folhas de horas", nl="Urenstaten",
            pl="Karty czasu pracy")),
        ("proWidgets", dict(
            en="Widgets", de="Widgets", hr="Widgeti", sl="Pripomočki",
            it="Widget", fr="Widgets", es="Widgets", pt="Widgets",
            nl="Widgets", pl="Widżety")),
        ("proMultipleJobs", dict(
            en="More than one job", de="Mehr als eine Tätigkeit",
            hr="Više od jednog posla", sl="Več kot eno delo",
            it="Più di un lavoro", fr="Plusieurs postes",
            es="Más de un trabajo", pt="Mais do que um trabalho",
            nl="Meer dan één functie", pl="Więcej niż jedna praca")),
        ("proRangeEditing", dict(
            en="Edit a range at once", de="Zeitraum auf einmal bearbeiten",
            hr="Uređivanje raspona odjednom", sl="Urejanje obdobja naenkrat",
            it="Modifica un intervallo in una volta",
            fr="Modifier une période en une fois",
            es="Editar un intervalo de una vez",
            pt="Editar um intervalo de uma vez",
            nl="Een periode in één keer bewerken",
            pl="Edycja zakresu naraz")),
        ("proICloudSync", dict(
            en="iCloud sync", de="iCloud-Sync", hr="iCloud sinkronizacija",
            sl="Sinhronizacija iCloud", it="Sincronizzazione iCloud",
            fr="Synchronisation iCloud", es="Sincronización con iCloud",
            pt="Sincronização com iCloud", nl="iCloud-synchronisatie",
            pl="Synchronizacja iCloud")),
        ("proTimesheetsExplained", dict(
            en="Hand your hours to payroll as a spreadsheet or a PDF, laid out the way you choose.",
            de="Geben Sie Ihre Stunden als Tabelle oder PDF an die Lohnbuchhaltung, im Layout Ihrer Wahl.",
            hr="Predajte svoje sate obračunu plaća kao tablicu ili PDF, složene onako kako želite.",
            sl="Oddajte svoje ure obračunu plač kot preglednico ali PDF, urejene po vaši izbiri.",
            it="Consegna le tue ore alle paghe come foglio di calcolo o PDF, impaginato come vuoi.",
            fr="Remettez vos heures à la paie en tableur ou en PDF, mis en page comme vous le voulez.",
            es="Entrega tus horas a nóminas como hoja de cálculo o PDF, con el diseño que elijas.",
            pt="Entregue as suas horas ao processamento salarial em folha de cálculo ou PDF, como preferir.",
            nl="Lever je uren aan de salarisadministratie als spreadsheet of pdf, ingedeeld zoals jij wilt.",
            pl="Przekaż godziny do kadr jako arkusz lub PDF, w wybranym przez siebie układzie.")),
        ("proWidgetsExplained", dict(
            en="Today's hours and the month's balance on your Home Screen and Lock Screen.",
            de="Die heutigen Stunden und der Monatssaldo auf Home- und Sperrbildschirm.",
            hr="Današnji sati i mjesečni saldo na početnom i zaključanom zaslonu.",
            sl="Današnje ure in mesečni saldo na začetnem in zaklenjenem zaslonu.",
            it="Le ore di oggi e il saldo del mese sulla schermata Home e sul blocco schermo.",
            fr="Les heures du jour et le solde du mois sur l'écran d'accueil et l'écran verrouillé.",
            es="Las horas de hoy y el saldo del mes en la pantalla de inicio y la de bloqueo.",
            pt="As horas de hoje e o saldo do mês no ecrã principal e no ecrã bloqueado.",
            nl="De uren van vandaag en het maandsaldo op je beginscherm en toegangsscherm.",
            pl="Dzisiejsze godziny i saldo miesiąca na ekranie początkowym i blokady.")),
        ("proMultipleJobsExplained", dict(
            en="Two jobs on the same Tuesday, each with its own contracted week.",
            de="Zwei Tätigkeiten am selben Dienstag, jede mit ihrer eigenen Vertragswoche.",
            hr="Dva posla u isti utorak, svaki sa svojim ugovorenim tjednom.",
            sl="Dve deli isti torek, vsako s svojim pogodbenim tednom.",
            it="Due lavori nello stesso martedì, ciascuno con la propria settimana contrattuale.",
            fr="Deux postes le même mardi, chacun avec sa semaine contractuelle.",
            es="Dos trabajos el mismo martes, cada uno con su propia semana contratada.",
            pt="Dois trabalhos na mesma terça-feira, cada um com a sua semana contratada.",
            nl="Twee functies op dezelfde dinsdag, elk met een eigen contractweek.",
            pl="Dwie prace tego samego wtorku, każda z własnym tygodniem umownym.")),
        ("proRangeEditingExplained", dict(
            en="Book a fortnight of leave in one pass instead of ten trips through the editor.",
            de="Zwei Wochen Urlaub in einem Zug eintragen statt zehnmal durch den Editor.",
            hr="Unesite dva tjedna godišnjeg odjednom umjesto deset prolazaka kroz uređivač.",
            sl="Vnesite dva tedna dopusta naenkrat namesto desetih obiskov urejevalnika.",
            it="Registra due settimane di ferie in una volta invece di dieci passaggi nell'editor.",
            fr="Saisissez deux semaines de congés en une fois au lieu de dix passages dans l'éditeur.",
            es="Registra dos semanas de vacaciones de una vez en lugar de diez pasos por el editor.",
            pt="Registe duas semanas de férias de uma vez em vez de dez passagens pelo editor.",
            nl="Boek twee weken verlof in één keer in plaats van tien rondjes door de editor.",
            pl="Wpisz dwa tygodnie urlopu za jednym razem zamiast dziesięciu wizyt w edytorze.")),
        ("proICloudSyncExplained", dict(
            en="The same hours on your phone and your iPad, through your own iCloud.",
            de="Dieselben Stunden auf iPhone und iPad, über Ihre eigene iCloud.",
            hr="Isti sati na telefonu i iPadu, preko vlastitog iClouda.",
            sl="Iste ure na telefonu in iPadu, prek lastnega iClouda.",
            it="Le stesse ore su iPhone e iPad, tramite il tuo iCloud.",
            fr="Les mêmes heures sur votre iPhone et votre iPad, via votre propre iCloud.",
            es="Las mismas horas en tu iPhone y tu iPad, a través de tu propio iCloud.",
            pt="As mesmas horas no seu iPhone e iPad, através do seu próprio iCloud.",
            nl="Dezelfde uren op je iPhone en je iPad, via je eigen iCloud.",
            pl="Te same godziny na iPhonie i iPadzie, przez własny iCloud.")),
    ]),
]


def swift_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def wrap_args(case: str, words: dict) -> str:
    """One arm of the switch, wrapped to a readable width."""
    indent = " " * 30
    parts = [f"{lang}: {swift_string(words[lang])}" for lang in ORDER]
    lines, current = [], "            return pick("
    for i, part in enumerate(parts):
        piece = part + ("," if i < len(parts) - 1 else ")")
        if len(current) + len(piece) > 100 and not current.rstrip().endswith("pick("):
            lines.append(current.rstrip())
            current = indent
        current += piece + " "
    lines.append(current.rstrip())
    return f"        case .{case}:\n" + "\n".join(lines)


def wrap_cases(names: list) -> str:
    """`case a, b, c` broken across lines rather than one long one."""
    lines, current = [], "    case "
    for i, n in enumerate(names):
        piece = n + ("," if i < len(names) - 1 else "")
        if len(current) + len(piece) > 88 and current.strip() != "case":
            lines.append(current.rstrip())
            current = "    case "
        current += piece + " "
    lines.append(current.rstrip())
    return "\n".join(lines)


cases = [c for _, entries in SECTIONS for c, _ in entries]

header = '''import Foundation

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
'''

body = header
for name, entries in SECTIONS:
    body += f"    // {name}\n"
    body += wrap_cases([c for c, _ in entries]) + "\n"
body += "}\n\nextension ExportLanguage {\n"
body += '''    /// One switch rather than one per language, so every term shows its
    /// translations together and a missing one is a build error rather than a
    /// label that quietly comes out in English.
    func callAsFunction(_ term: UITerm) -> String {
        switch term {
'''
for i, (name, entries) in enumerate(SECTIONS):
    body += f"\n        // {name}\n"
    for case, words in entries:
        body += wrap_args(case, words) + "\n"
body += "        }\n    }\n}\n"

out = pathlib.Path("/home/user/hours/HoursCore/Localization/AppVocabulary.swift")
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(body, encoding="utf-8")

print(f"{len(cases)} terms x {len(ORDER)} languages = {len(cases) * len(ORDER)} words")
print("longest line:", max(len(l) for l in body.split("\n")))
missing = [(c, l) for _, es in SECTIONS for c, w in es for l in ORDER if not w.get(l)]
print("missing:", missing or "none")
dupes = [c for c in cases if cases.count(c) > 1]
print("duplicate cases:", set(dupes) or "none")
