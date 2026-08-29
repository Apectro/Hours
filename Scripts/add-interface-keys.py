"""Add the interface keys the code looks up and the catalogue never had.

Order matches translations.json's own: de hr sl it fr es pt nl pl.
%lld where the value is an Int, %@ where it is a String. Getting that wrong
means the lookup misses and English comes back, silently — which is the whole
defect being fixed here, so the types were read off the call sites rather than
guessed.
"""
import collections
import json

PATH = "/home/user/hours/Scripts/translations.json"

NEW = {
 "%@ has no hours recorded.": [
  "Für %@ sind keine Stunden erfasst.", "Za %@ nema evidentiranih sati.",
  "Za %@ ni zabeleženih ur.", "Per %@ non ci sono ore registrate.",
  "Aucune heure enregistrée pour le %@.", "No hay horas registradas para el %@.",
  "Não há horas registadas para %@.", "Voor %@ zijn geen uren vastgelegd.",
  "Dla %@ nie zapisano godzin."],
 "%@ and %@ have no hours recorded.": [
  "Für %@ und %@ sind keine Stunden erfasst.", "Za %@ i %@ nema evidentiranih sati.",
  "Za %@ in %@ ni zabeleženih ur.", "Per %@ e %@ non ci sono ore registrate.",
  "Aucune heure enregistrée pour le %@ et le %@.",
  "No hay horas registradas para el %@ ni el %@.",
  "Não há horas registadas para %@ e %@.", "Voor %@ en %@ zijn geen uren vastgelegd.",
  "Dla %@ i %@ nie zapisano godzin."],
 "%lld left alone": [
  "%lld unverändert", "%lld nepromijenjeno", "%lld nespremenjenih",
  "%lld invariati", "%lld inchangés", "%lld sin cambios",
  "%lld inalterados", "%lld ongewijzigd", "%lld bez zmian"],
 "%lld skipped": [
  "%lld übersprungen", "%lld preskočeno", "%lld preskočenih",
  "%lld saltati", "%lld ignorés", "%lld omitidos",
  "%lld ignorados", "%lld overgeslagen", "%lld pominięto"],
 "Marks each day as %@. Any hours on those days are removed if the type does not use times.": [
  "Markiert jeden Tag als %@. Stunden an diesen Tagen werden entfernt, wenn die Art keine Zeiten verwendet.",
  "Označava svaki dan kao %@. Sati na tim danima uklanjaju se ako vrsta ne koristi vremena.",
  "Označi vsak dan kot %@. Ure na teh dnevih se odstranijo, če vrsta ne uporablja časov.",
  "Segna ogni giorno come %@. Le ore su quei giorni vengono rimosse se il tipo non usa gli orari.",
  "Marque chaque jour comme %@. Les heures de ces jours sont supprimées si le type n'utilise pas d'horaires.",
  "Marca cada día como %@. Las horas de esos días se eliminan si el tipo no usa horarios.",
  "Marca cada dia como %@. As horas desses dias são removidas se o tipo não usar horários.",
  "Markeert elke dag als %@. Uren op die dagen worden verwijderd als het type geen tijden gebruikt.",
  "Oznacza każdy dzień jako %@. Godziny w tych dniach są usuwane, jeśli typ nie używa godzin."],
 "%@ over": ["%@ mehr", "%@ više", "%@ več", "%@ in più", "%@ de plus",
             "%@ de más", "%@ a mais", "%@ meer", "%@ więcej"],
 "%@ short": ["%@ weniger", "%@ manje", "%@ manj", "%@ in meno", "%@ de moins",
              "%@ de menos", "%@ a menos", "%@ minder", "%@ mniej"],
 "%@ under": ["%@ weniger", "%@ manje", "%@ manj", "%@ in meno", "%@ de moins",
              "%@ de menos", "%@ a menos", "%@ minder", "%@ mniej"],
 "%@  ·  %@ credited": [
  "%@  ·  %@ angerechnet", "%@  ·  %@ priznato", "%@  ·  %@ priznano",
  "%@  ·  %@ accreditate", "%@  ·  %@ crédité", "%@  ·  %@ acreditadas",
  "%@  ·  %@ creditadas", "%@  ·  %@ toegekend", "%@  ·  %@ zaliczone"],
 "Started %@%@": ["Begonnen um %@%@", "Počelo u %@%@", "Začelo ob %@%@",
                  "Iniziato alle %@%@", "Commencé à %@%@", "Iniciado a las %@%@",
                  "Iniciado às %@%@", "Gestart om %@%@", "Rozpoczęto o %@%@"],
 "Clocked in for %@": [
  "Seit %@ eingestempelt", "Prijavljeni %@", "Prijavljeni %@",
  "In servizio da %@", "Pointé depuis %@", "Fichado desde hace %@",
  "Com entrada registada há %@", "%@ ingeklokt", "Zalogowany od %@"],
 "Block %lld": ["Block %lld", "Blok %lld", "Blok %lld", "Blocco %lld",
                "Bloc %lld", "Bloque %lld", "Bloco %lld", "Blok %lld", "Blok %lld"],
 "Nothing recorded yet. %@ expected.": [
  "Noch nichts erfasst. %@ erwartet.", "Još ništa nije evidentirano. Očekuje se %@.",
  "Še nič zabeleženo. Pričakovano %@.", "Ancora nulla registrato. Previste %@.",
  "Rien d'enregistré. %@ attendues.", "Aún no hay nada registrado. Se esperan %@.",
  "Ainda nada registado. Esperadas %@.", "Nog niets vastgelegd. %@ verwacht.",
  "Jeszcze nic nie zapisano. Oczekiwane %@."],
 "%lld scheduled": ["%lld geplant", "%lld planirano", "%lld načrtovanih",
                    "%lld pianificati", "%lld prévus", "%lld previstos",
                    "%lld previstos", "%lld gepland", "%lld zaplanowanych"],
 "%lld off": ["%lld frei", "%lld slobodno", "%lld prostih", "%lld liberi",
              "%lld de repos", "%lld libres", "%lld de folga", "%lld vrij",
              "%lld wolnych"],
 "%@ credited as paid %@": [
  "%@ als bezahlter %@ angerechnet", "%@ priznato kao plaćeni %@",
  "%@ priznano kot plačan %@", "%@ accreditate come %@ retribuito",
  "%@ crédité comme %@ payé", "%@ acreditadas como %@ pagado",
  "%@ creditadas como %@ pago", "%@ toegekend als betaald %@",
  "%@ zaliczone jako płatny %@"],
 "Clear %@": ["%@ löschen", "Očisti %@", "Počisti %@", "Cancella %@",
              "Effacer %@", "Borrar %@", "Limpar %@", "%@ wissen", "Wyczyść %@"],
 "%@ · automatic": ["%@ · automatisch", "%@ · automatski", "%@ · samodejno",
                    "%@ · automatico", "%@ · automatique", "%@ · automático",
                    "%@ · automático", "%@ · automatisch", "%@ · automatycznie"],
 "From your weekly schedule for %@.": [
  "Aus Ihrem Wochenplan für %@.", "Iz vašeg tjednog rasporeda za %@.",
  "Iz vašega tedenskega urnika za %@.", "Dal tuo orario settimanale per %@.",
  "D'après votre planning hebdomadaire du %@.", "De tu horario semanal para el %@.",
  "Do seu horário semanal de %@.", "Uit je weekrooster voor %@.",
  "Z tygodniowego grafiku na %@."],
 "Export preview, %lld rows": [
  "Exportvorschau, %lld Zeilen", "Pregled izvoza, %lld redaka",
  "Predogled izvoza, %lld vrstic", "Anteprima esportazione, %lld righe",
  "Aperçu de l'export, %lld lignes", "Vista previa de exportación, %lld filas",
  "Pré-visualização da exportação, %lld linhas", "Exportvoorbeeld, %lld rijen",
  "Podgląd eksportu, %lld wierszy"],
 "Showing the first 12 of %lld rows.": [
  "Es werden die ersten 12 von %lld Zeilen gezeigt.",
  "Prikazano je prvih 12 od %lld redaka.", "Prikazanih je prvih 12 od %lld vrstic.",
  "Vengono mostrate le prime 12 righe di %lld.",
  "Affichage des 12 premières lignes sur %lld.",
  "Se muestran las primeras 12 de %lld filas.",
  "A mostrar as primeiras 12 de %lld linhas.",
  "De eerste 12 van %lld rijen worden getoond.",
  "Pokazano pierwszych 12 z %lld wierszy."],
 "Share %@": ["%@ teilen", "Podijeli %@", "Deli %@", "Condividi %@",
              "Partager %@", "Compartir %@", "Partilhar %@", "%@ delen",
              "Udostępnij %@"],
 "%lld with hours recorded": [
  "%lld mit erfassten Stunden", "%lld s evidentiranim satima",
  "%lld z zabeleženimi urami", "%lld con ore registrate",
  "%lld avec des heures saisies", "%lld con horas registradas",
  "%lld com horas registadas", "%lld met vastgelegde uren",
  "%lld z zapisanymi godzinami"],
 "The file could not be prepared. %@": [
  "Die Datei konnte nicht erstellt werden. %@",
  "Datoteku nije bilo moguće pripremiti. %@",
  "Datoteke ni bilo mogoče pripraviti. %@",
  "Non è stato possibile preparare il file. %@",
  "Le fichier n'a pas pu être préparé. %@",
  "No se pudo preparar el archivo. %@",
  "Não foi possível preparar o ficheiro. %@",
  "Het bestand kon niet worden voorbereid. %@",
  "Nie udało się przygotować pliku. %@"],
 "Your hours are kept on this device and in your own private iCloud storage, which only your devices can read. %@ %@": [
  "Ihre Stunden bleiben auf diesem Gerät und in Ihrem eigenen privaten iCloud-Speicher, den nur Ihre Geräte lesen können. %@ %@",
  "Vaši sati ostaju na ovom uređaju i u vašoj privatnoj iCloud pohrani, koju mogu čitati samo vaši uređaji. %@ %@",
  "Vaše ure ostanejo v tej napravi in v vaši zasebni shrambi iCloud, ki jo lahko berejo le vaše naprave. %@ %@",
  "Le tue ore restano su questo dispositivo e nel tuo spazio iCloud privato, leggibile solo dai tuoi dispositivi. %@ %@",
  "Vos heures restent sur cet appareil et dans votre propre stockage iCloud privé, que seuls vos appareils peuvent lire. %@ %@",
  "Tus horas se quedan en este dispositivo y en tu propio almacenamiento privado de iCloud, que solo pueden leer tus dispositivos. %@ %@",
  "As suas horas ficam neste dispositivo e no seu próprio armazenamento privado do iCloud, que só os seus dispositivos podem ler. %@ %@",
  "Je uren blijven op dit apparaat en in je eigen privé-iCloudopslag, die alleen jouw apparaten kunnen lezen. %@ %@",
  "Twoje godziny pozostają na tym urządzeniu i w Twojej prywatnej przestrzeni iCloud, którą mogą odczytać tylko Twoje urządzenia. %@ %@"],
 "Your hours are stored locally and nowhere else. %@ %@": [
  "Ihre Stunden werden lokal gespeichert und sonst nirgends. %@ %@",
  "Vaši se sati pohranjuju lokalno i nigdje drugdje. %@ %@",
  "Vaše ure so shranjene lokalno in nikjer drugje. %@ %@",
  "Le tue ore sono salvate solo in locale. %@ %@",
  "Vos heures sont stockées en local et nulle part ailleurs. %@ %@",
  "Tus horas se guardan localmente y en ningún otro sitio. %@ %@",
  "As suas horas são guardadas localmente e em mais lado nenhum. %@ %@",
  "Je uren worden lokaal opgeslagen en nergens anders. %@ %@",
  "Twoje godziny są przechowywane lokalnie i nigdzie indziej. %@ %@"],
 "There is no account to make, no server of ours, no analytics, no advertising and no third-party code.": [
  "Es gibt kein Konto anzulegen, keinen Server von uns, keine Analyse, keine Werbung und keinen Fremdcode.",
  "Nema računa za otvoriti, nema našeg poslužitelja, nema analitike, nema oglasa i nema tuđeg koda.",
  "Ni računa za ustvariti, ni našega strežnika, ni analitike, ni oglasov in ni tuje kode.",
  "Non c'è alcun account da creare, nessun nostro server, nessuna analisi, nessuna pubblicità e nessun codice di terze parti.",
  "Il n'y a aucun compte à créer, aucun serveur à nous, aucune analyse, aucune publicité et aucun code tiers.",
  "No hay cuenta que crear, ningún servidor nuestro, ninguna analítica, ninguna publicidad y ningún código de terceros.",
  "Não há conta para criar, nenhum servidor nosso, nenhuma análise, nenhuma publicidade e nenhum código de terceiros.",
  "Er is geen account aan te maken, geen server van ons, geen analytics, geen advertenties en geen code van derden.",
  "Nie ma konta do założenia, żadnego naszego serwera, analityki, reklam ani cudzego kodu."],
 "The one thing it asks the network is whether Zeitkonto Pro has been paid for, which it asks the App Store; no part of your hours goes with the question.": [
  "Das Einzige, was es im Netz abfragt, ist, ob Zeitkonto Pro bezahlt wurde, und zwar beim App Store; von Ihren Stunden geht dabei nichts mit.",
  "Jedino što pita mrežu jest je li Zeitkonto Pro plaćen, a to pita App Store; ništa od vaših sati ne ide uz to pitanje.",
  "Edino, kar vpraša omrežje, je, ali je Zeitkonto Pro plačan, in to vpraša App Store; z vprašanjem ne gre nič od vaših ur.",
  "L'unica cosa che chiede alla rete è se Zeitkonto Pro è stato pagato, e lo chiede all'App Store; nessuna parte delle tue ore parte con la domanda.",
  "La seule chose qu'il demande au réseau, c'est si Zeitkonto Pro a été payé, et il le demande à l'App Store ; aucune partie de vos heures n'accompagne la question.",
  "Lo único que pregunta a la red es si se ha pagado Zeitkonto Pro, y se lo pregunta a la App Store; ninguna parte de tus horas viaja con la pregunta.",
  "A única coisa que pergunta à rede é se o Zeitkonto Pro foi pago, e pergunta-o à App Store; nenhuma parte das suas horas segue com a pergunta.",
  "Het enige wat het aan het netwerk vraagt is of Zeitkonto Pro betaald is, en dat vraagt het de App Store; geen deel van je uren gaat mee met die vraag.",
  "Jedyne, o co pyta sieć, to czy opłacono Zeitkonto Pro — pyta o to App Store; żadna część Twoich godzin nie idzie razem z pytaniem."],
 "That file could not be read as a backup. %@": [
  "Diese Datei konnte nicht als Sicherung gelesen werden. %@",
  "Tu datoteku nije bilo moguće pročitati kao kopiju. %@",
  "Te datoteke ni bilo mogoče prebrati kot kopijo. %@",
  "Non è stato possibile leggere il file come backup. %@",
  "Ce fichier n'a pas pu être lu comme une sauvegarde. %@",
  "No se pudo leer ese archivo como copia de seguridad. %@",
  "Não foi possível ler esse ficheiro como cópia de segurança. %@",
  "Dat bestand kon niet als back-up worden gelezen. %@",
  "Nie udało się odczytać tego pliku jako kopii zapasowej. %@"],
 "The file could not be opened. %@": [
  "Die Datei konnte nicht geöffnet werden. %@",
  "Datoteku nije bilo moguće otvoriti. %@",
  "Datoteke ni bilo mogoče odpreti. %@",
  "Non è stato possibile aprire il file. %@",
  "Le fichier n'a pas pu être ouvert. %@",
  "No se pudo abrir el archivo. %@",
  "Não foi possível abrir o ficheiro. %@",
  "Het bestand kon niet worden geopend. %@",
  "Nie udało się otworzyć pliku. %@"],
 "%@ and %lld more": [
  "%@ und %lld weitere", "%@ i još %lld", "%@ in še %lld",
  "%@ e altri %lld", "%@ et %lld de plus", "%@ y %lld más",
  "%@ e mais %lld", "%@ en nog %lld", "%@ i jeszcze %lld"],
 "Day %lld": ["Tag %lld", "Dan %lld", "Dan %lld", "Giorno %lld", "Jour %lld",
              "Día %lld", "Dia %lld", "Dag %lld", "Dzień %lld"],
 "From %@": ["Ab %@", "Od %@", "Od %@", "Da %@", "À partir de %@", "Desde %@",
             "A partir de %@", "Vanaf %@", "Od %@"],
 "Through %@": ["Bis %@", "Do %@", "Do %@", "Fino a %@", "Jusqu'à %@",
                "Hasta %@", "Até %@", "Tot en met %@", "Do %@"],
 "Hours already recorded against this job stay, and count towards %@.": [
  "Bereits auf diese Tätigkeit erfasste Stunden bleiben und zählen zu %@.",
  "Već evidentirani sati na ovom poslu ostaju i broje se u %@.",
  "Že zabeležene ure pri tem delu ostanejo in se štejejo k %@.",
  "Le ore già registrate su questo lavoro restano e contano per %@.",
  "Les heures déjà saisies sur ce poste restent et comptent pour %@.",
  "Las horas ya registradas en este trabajo se mantienen y cuentan para %@.",
  "As horas já registadas neste trabalho mantêm-se e contam para %@.",
  "Al vastgelegde uren op deze functie blijven staan en tellen mee voor %@.",
  "Godziny zapisane już przy tej pracy pozostają i liczą się do %@."],
 "Look back %lld days": [
  "%lld Tage zurückblicken", "Pogledaj %lld dana unatrag",
  "Poglej %lld dni nazaj", "Guarda indietro di %lld giorni",
  "Remonter de %lld jours", "Revisar %lld días atrás",
  "Recuar %lld dias", "%lld dagen terugkijken", "Sprawdź %lld dni wstecz"],
 "These pre-fill the editor when you add hours to a working day. That comes to %@ worked.": [
  "Diese füllen den Editor vor, wenn Sie an einem Arbeitstag Stunden eintragen. Das ergibt %@ Arbeitszeit.",
  "Ovo unaprijed ispunjava uređivač kad dodajete sate na radni dan. To iznosi %@ rada.",
  "To vnaprej izpolni urejevalnik, ko dodate ure na delovni dan. To znese %@ dela.",
  "Precompilano l'editor quando aggiungi ore a un giorno lavorativo. Fanno %@ di lavoro.",
  "Ils préremplissent l'éditeur quand vous ajoutez des heures à un jour travaillé. Cela fait %@ de travail.",
  "Rellenan el editor cuando añades horas a un día laborable. Eso son %@ de trabajo.",
  "Preenchem o editor quando adiciona horas a um dia de trabalho. Dá %@ de trabalho.",
  "Deze vullen de editor alvast in als je uren toevoegt aan een werkdag. Dat komt neer op %@ gewerkt.",
  "Wstępnie wypełniają edytor przy dodawaniu godzin w dniu roboczym. Daje to %@ pracy."],
 "Since %@, through %@.": [
  "Seit %@, bis %@.", "Od %@, do %@.", "Od %@ do %@.",
  "Dal %@, fino al %@.", "Depuis le %@, jusqu'au %@.",
  "Desde el %@, hasta el %@.", "Desde %@, até %@.",
  "Vanaf %@, tot en met %@.", "Od %@ do %@."],
 "Everything recorded through %@.": [
  "Alles erfasst bis %@.", "Sve evidentirano do %@.",
  "Vse zabeleženo do %@.", "Tutto ciò che è registrato fino al %@.",
  "Tout ce qui est enregistré jusqu'au %@.", "Todo lo registrado hasta el %@.",
  "Tudo o que está registado até %@.", "Alles vastgelegd tot en met %@.",
  "Wszystko zapisane do %@."],
 "%lld%% of expected": [
  "%lld %% des Solls", "%lld %% od očekivanog", "%lld %% pričakovanega",
  "%lld%% del previsto", "%lld %% du prévu", "%lld%% de lo previsto",
  "%lld%% do previsto", "%lld%% van verwacht", "%lld%% oczekiwanego"],
 "%lld%% of expected, including %@ paid absence": [
  "%lld %% des Solls, davon %@ bezahlte Abwesenheit",
  "%lld %% od očekivanog, uključujući %@ plaćenog izostanka",
  "%lld %% pričakovanega, vključno z %@ plačane odsotnosti",
  "%lld%% del previsto, incluse %@ di assenza retribuita",
  "%lld %% du prévu, dont %@ d'absence payée",
  "%lld%% de lo previsto, incluidas %@ de ausencia pagada",
  "%lld%% do previsto, incluindo %@ de ausência paga",
  "%lld%% van verwacht, inclusief %@ betaald verzuim",
  "%lld%% oczekiwanego, w tym %@ płatnej nieobecności"],
 "Previous %@": ["Vorheriger %@", "Prethodni %@", "Prejšnji %@",
                 "%@ precedente", "%@ précédent", "%@ anterior",
                 "%@ anterior", "Vorige %@", "Poprzedni %@"],
 "Next %@": ["Nächster %@", "Sljedeći %@", "Naslednji %@", "%@ successivo",
             "%@ suivant", "%@ siguiente", "%@ seguinte", "Volgende %@",
             "Następny %@"],
 "of %@": ["von %@", "od %@", "od %@", "di %@", "sur %@", "de %@", "de %@",
           "van %@", "z %@"],
 "%@ this month": [
  "%@ diesen Monat", "%@ ovaj mjesec", "%@ ta mesec", "%@ questo mese",
  "%@ ce mois-ci", "%@ este mes", "%@ este mês", "%@ deze maand",
  "%@ w tym miesiącu"],
}


def main() -> None:
    data = json.load(open(PATH, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    langs = data["languages"]
    added = 0
    for key, values in NEW.items():
        assert len(values) == len(langs), f"{key}: {len(values)} for {len(langs)} languages"
        if key in data["interface"]:
            continue
        data["interface"][key] = values
        added += 1
    data["interface"] = collections.OrderedDict(sorted(data["interface"].items()))
    with open(PATH, "w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
    print(f"added {added}; interface now {len(data['interface'])}")


if __name__ == "__main__":
    main()
