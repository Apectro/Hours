import brand from "../brand.json";
import type { Copy } from "./en";

/**
 * Alles, was die deutsche Seite sagt.
 *
 * Typed as `Copy`, so the compiler refuses a build where a section exists in
 * English and not here.
 *
 * Terminology follows the app and its exports: Saldo, Soll, Pause, Feiertag.
 * The register is "du" throughout, which is what Apple's own German uses and
 * what suits an app one person wrote.
 */
export const de: Copy = {
  lang: "de",
  htmlTitle: "Hours — ein Stundenkalender, der auf dem Telefon bleibt",
  htmlDescription:
    "Erfasse deine Stunden in einem Kalender, sieh deinen Saldo, und gib der Lohnbuchhaltung einen Stundenzettel in ihrer Sprache. Kein Konto, kein Server, nichts wird gesammelt.",
  ogDescription:
    "Ein Stundenkalender, der deine Stunden auf dem Telefon lässt. Kein Konto, kein Server, nichts wird gesammelt.",
  otherLanguage: "English",
  skip: "Zum Inhalt springen",

  nav: {
    balance: "Der Saldo",
    app: "Die App",
    timesheets: "Stundenzettel",
    privacy: "Datenschutz",
    pricing: "Preis",
    sections: "Abschnitte",
    elsewhere: "Anderswo",
    theme: "Farbschema",
  },
  theme: { auto: "Auto", light: "Hell", dark: "Dunkel" },

  hero: {
    headlineLines: brand.de.headlineLines,
    lede: "Tag antippen, Stunden eintragen, und der Monat rechnet sich selbst zusammen. Wenn die Lohnbuchhaltung einen Stundenzettel will, exportierst du einen — in der Sprache, die sie liest. Es gibt kein Konto anzulegen und nirgendwo, wohin etwas davon ginge.",
    appStoreAction: "Im App Store laden",
    costAction: "Was es kostet",
    sourceAction: "Quellcode lesen",
    notYet: "Noch nicht im App Store. ",
    note: "Stunden zu erfassen ist kostenlos und bleibt es. Braucht iOS 17.",
    shotAlt: "Hours auf einem iPhone: ein Monat, dessen Tage nach Art eingefärbt sind, mit den Summen darunter",
  },

  equation: {
    label: "Am Ende ist es eine Zeile",
    parts: brand.de.equation,
    figureLabel: "Wie der Saldo berechnet wird",
    foot: "Jede Tagesart trägt eine Regel, wie sie zählt. Deshalb stimmt dieselbe Zeile, ob du gearbeitet hast, im Urlaub warst oder krank. Arbeitszeit und bezahlte Abwesenheit werden immer getrennt ausgewiesen. Sie zusammenzuzählen ist der Weg zu einer Zahl, die niemand erklären kann.",
  },

  balance: {
    heading: "Sechs Tage, die ein Stundenzettel richtig treffen muss",
    lede: "Stunden zu addieren ist der leichte Teil. Schwierig sind die Tage, die nicht einfach gearbeitet oder nicht gearbeitet sind, und davon gibt es mehr, als man denkt. Einen davon falsch, und jemandem fehlt ein Tag.",
    caption: "Ein Acht-Stunden-Tag laut Vertrag, Montag bis Freitag.",
    columns: { day: "Der Tag", balance: "Saldo", why: "Warum" },
    cases: [
      { day: "Acht Stunden an einem Acht-Stunden-Tag", result: "0", sign: "zero",
        why: "Gearbeitet wurde, was vorgesehen war. Niemand schuldet jemandem etwas." },
      { day: "Urlaub an einem Dienstag", result: "0", sign: "zero",
        why: "Dem Tag wird gutgeschrieben, was er erwartet hat. Urlaub erscheint also nicht als Rückstand." },
      { day: "Urlaub an einem Samstag", result: "0", sign: "zero",
        why: "Von einem Samstag wurde nichts erwartet, also wird nichts gutgeschrieben. Urlaub an einem Tag, an dem du ohnehin nicht gearbeitet hättest, darf keinen Urlaubstag kosten." },
      { day: "Zwei Stunden an einem Feiertag", result: "+2h", sign: "plus",
        why: "Der Feiertag hat nichts erwartet, und du hast trotzdem zwei Stunden gearbeitet." },
      { day: "Fünfeinhalb Stunden an einem Acht-Stunden-Tag", result: "−2h 30m", sign: "minus",
        why: "Steht in Orange da. Im Minus zu sein ist etwas, das man sehen soll — und eine App, die das einen Monat lang rot anmalt, nörgelt bloß." },
      { day: "Überstunden ausgezahlt", result: "−7h", sign: "minus",
        why: "Sind die Stunden einmal bezahlt, müssen sie irgendwo vom Saldo herunter. Als Auszahlung erfasst, sieht man, wo die sieben Stunden geblieben sind." },
    ],
  },

  app: {
    heading: "Zuerst ein Kalender, und bis auf die Knochen einstellbar",
    lede: "Jedes Feld hängt an einem Schalter, und was du ausschaltest, verschwindet, statt ausgegraut herumzustehen. Eine App, die acht Stunden am Tag erfasst, sollte dich nicht an neun Feldern vorbeiscrollen lassen, die du nie brauchst.",
    rows: [
      { label: "Der Monat", title: "Ein Kalender, den man auf einen Blick liest",
        body: "Der Hauptbildschirm ist ein Monat, nach Tagesart eingefärbt, die Summen darunter. Ein vergangener Arbeitstag, auf dem nichts steht, bekommt einen gestrichelten Rahmen — die Lücke fällt dir beim Scrollen auf und nicht erst am Monatsletzten." },
      { label: "Der Tag", title: "Stunden so, wie deine tatsächlich laufen",
        body: "Beginn und Ende, oder einfach die Stunden eintippen. Liegt das Ende vor dem Beginn, ist es eine Nachtschicht und wird auch so gemessen. Pausen gehen als Dauer oder als Uhrzeiten hinein. Geteilte Schichten ebenso, bei denen die Lücke dazwischen weder Arbeitszeit noch Pause ist." },
      { label: "Die Woche", title: "Eine Vertragswoche, pro Wochentag",
        body: "Nicht eine Zahl über fünf Tage gespannt. Eine 6/6/6/6/8-Woche ist hier normal, eine Vier-Tage-Woche auch. Steht im Vertrag nur 37½ Stunden, überschreibt das die einzelnen Tage." },
      { label: "Der Eintrag", title: "Daten, niemals Zeitstempel",
        body: "Ein Flug oder eine Zeitumstellung kann nicht stillschweigend verändern, was du eingetragen hast, weil Tage als Datum gespeichert werden. An einem Umstellungstag gibt es genau eine echte Frage: waren das acht Stunden oder neun? Welche Antwort du willst, entscheidest du einmal in den Einstellungen." },
    ],
  },

  gallery: {
    heading: "Wie es tatsächlich aussieht",
    lede: "Jedes dieser Bilder entsteht bei jedem Build aus der Testsuite der App selbst. Sie können sich also nicht unbemerkt von dem entfernen, was du installieren würdest.",
    shots: [
      { shot: "01-calendar", title: "Der Monat",
        alt: "Die Monatsansicht mit nach Art eingefärbten Tagen und den Summen des Zeitraums darunter",
        caption: "Nach Tagesart eingefärbt, Summen darunter, Lücken umrandet." },
      { shot: "02-day-editor", title: "Ein Tag",
        alt: "Der Tageseditor mit Beginn und Ende, einer Pause und einer Notiz",
        caption: "Zeiten, Pausen, Notizen — und nur die Felder, die du eingeschaltet hast." },
      { shot: "03-insights", title: "Auswertung",
        alt: "Die Auswertung mit gearbeiteten Stunden, Sollstunden und Saldo",
        caption: "Heute, die Woche, der Monat, das Jahr und ein laufender Saldo." },
      { shot: "04-settings", title: "Einstellungen",
        alt: "Die Einstellungen mit Arbeitszeiten, Tätigkeiten, Feldern, Tagesarten und Erinnerungen",
        caption: "Welche Felder es gibt, wie ein Tag gemessen wird, was eine Tagesart bedeutet." },
      { shot: "10-export", title: "Stundenzettel",
        alt: "Der Exportbildschirm mit Zeitraum, Format und einer Vorschau des Stundenzettels",
        caption: "Die Vorschau ist die Datei. Was du siehst, wird geteilt." },
    ],
  },

  timesheets: {
    heading: "Ein Stundenzettel in der Sprache dessen, der ihn liest",
    lede: "Nimm einen beliebigen Zeitraum — eine Woche, einen Monat, oder den 3. bis zum 19. — und exportiere ihn als CSV, Excel oder PDF. Du wählst die Spalten und ihre Reihenfolge, dein Name steht oben, und die Datei benennst du selbst. Die Excel-Datei hält hinter der Stunden-und-Minuten-Formatierung echte Dauern, damit die Spalte sich weiterhin summieren lässt.",
    tablistLabel: "Sprache des Stundenzettels",
    proofLead: (language: string) => `Ein echter Export, auf ${language}.`,
    proofRest: " Jede Überschrift, jeder Wochentag, jede Tagesart und jedes Datumsformat ist übersetzt. Die Notiz nicht, denn das sind Wörter, die du getippt hast. Diese vier entstehen bei jedem Build; die anderen sechs deckt die Testsuite ab.",
    proofLanguages: { de: "Deutsch", fr: "Französisch", hr: "Kroatisch", pl: "Polnisch" },
    rows: {
      settable: { label: "Eigene Einstellung", title: "Zehn Sprachen",
        bodyBefore: "Die Sprache der Datei ist eine eigene Einstellung, denn wer einen Stundenzettel liest, ist meist nicht die Person, die ihn ausgefüllt hat. Lass dein Telefon auf Englisch und gib der Lohnbuchhaltung einen Zettel, auf dem ",
        bodyEm: "Gesamt gearbeitet", bodyAfter: " steht." },
      untouched: { label: "Bleibt unberührt", title: "Nur die Wörter der App",
        body: "Spaltentitel, die mitgelieferten Tagesarten und die Beschriftungen der Zusammenfassung werden übersetzt. Eine Notiz, die du getippt hast, eine Tätigkeit, die du benannt hast, eine Tagesart, die du erfunden hast: die kommen genau so heraus, wie du sie geschrieben hast. Fremde Wörter zu übersetzen hieße, sie zu erfinden." },
    },
  },

  privacy: {
    heading: "Jedes Versprechen hier, und wo es zu prüfen ist",
    lede: "Die App ist eine Datei auf deinem Telefon. Es gibt kein Konto anzulegen und keinen Server, an den etwas ginge, und der Quellcode ist offen — du musst also nichts davon glauben.",
    claims: [
      { claim: "Kein Konto, keine Anmeldung", evidence: "in der ganzen App gibt es keine Anmeldeschicht" },
      { claim: "Keine Analyse, kein Tracking", evidence: "Package.swift führt keine externen Pakete" },
      { claim: "Nichts verlässt das Gerät", evidence: "außer du exportierst eine Datei oder schaltest iCloud ein" },
      { claim: "iCloud ist deins", evidence: "private CloudKit-Datenbank, standardmäßig aus" },
      { claim: "Fragt nie, wo du bist", evidence: "kein CoreLocation-Import; das Feld ist ein Textfeld" },
      { claim: "Erinnerungen sind lokal", evidence: "UNCalendarNotificationTrigger, auf dem Gerät geplant" },
    ],
  },

  pricing: {
    heading: "Erfassen ist kostenlos. Bezahlt wird für Dokumente.",
    lede: "Nichts, was du erfasst hast, wird je weggesperrt. Läuft ein Abo aus, steht jede Zahl weiterhin da und die Sicherung wird weiterhin geschrieben. Bezahlt wird dafür, daraus eine Datei zu machen, die jemand anderes lesen kann.",
    plans: [
      { name: "Kostenlos, und bleibt es", price: "Nichts, wofür man sich anmelden müsste", highlight: false,
        items: [
          "Der Kalender, der Tageseditor und jedes Feld",
          "Pausen, Überstunden, Korrekturen und der Saldo",
          "Auswertung für Tag, Woche, Monat und Jahr",
          "Ein Hinweis, wenn an einem Arbeitstag keine Stunden stehen",
          "Eine JSON-Sicherung mit jedem Tag, den du je eingetragen hast",
        ] },
      { name: "Hours Pro", price: "Monatlich, jährlich, oder einmalig gekauft", highlight: true,
        items: [
          "Stundenzettel als CSV, Excel oder PDF, in zehn Sprachen",
          "Widgets für Home- und Sperrbildschirm",
          "Eine zweite Tätigkeit mit eigener Vertragswoche",
          "Einen ganzen Zeitraum in einem Zug bearbeiten",
          "iCloud-Sync zwischen deinen eigenen Geräten",
        ] },
    ],
  },

  footer: {
    line: "Hours ist von einer einzelnen Person gemacht. Keine Firma dahinter, und nichts darin, das nach Hause telefoniert.",
    privacy: "Datenschutz",
    source: "Quellcode",
    support: "Support",
  },
};
