/**
 * What the page needs that is not words.
 *
 * Everything user-visible lives in src/copy/, one module per language. This
 * file holds the facts that are the same in both: image dimensions, which
 * languages the timesheet proof has pictures for, and the App Store link.
 */

/**
 * The captures are 1320x2868 because that is the simulator's window. The
 * markup declares those numbers so the browser reserves the right shape
 * before an image lands, and `shot` is a base name rather than a path because
 * each one is served at several widths — see scripts/images.mjs.
 */
export const shotSize = { width: 1320, height: 2868 } as const;

export const languages = [
  "English", "Deutsch", "Hrvatski", "Slovenščina", "Italiano",
  "Français", "Español", "Português", "Nederlands", "Polski",
] as const;

/**
 * The evidence for the section that claims ten languages: four real exports
 * the capture suite renders on every run, not mock-ups. Each is a different
 * month name, a different date format and a different word for a weekend. In
 * all four the note is still in English, because somebody typed that sentence
 * and the app doesn't translate those.
 *
 * Only these four are rendered by the capture suite today. The other six are
 * covered by tests rather than pictures, which is why the caption says so
 * instead of implying the set is complete.
 */
export const timesheetProof = {
  width: 1570,
  height: 520,
  languages: [
    {
      code: "de",
      english: "German",
      label: "Deutsch",
      alt:
        "A German timesheet: the columns read Datum, Tag, Art, Beginn, Ende, Pause, " +
        "Gearbeitet, Soll, Überstunden and Notizen; the day types read Wochenende and Arbeit",
    },
    {
      code: "fr",
      english: "French",
      label: "Français",
      alt:
        "A French timesheet: the columns read Date, Jour, Type, Début, Fin, Pause, " +
        "Heures travaillées, Heures prévues, Heures supp. and Notes; the day types read " +
        "Week-end and Travail",
    },
    {
      code: "hr",
      english: "Croatian",
      label: "Hrvatski",
      alt:
        "A Croatian timesheet: the columns read Datum, Dan, Vrsta, Početak, Kraj, Pauza, " +
        "Odrađeno, Planirano, Prekovremeni and Bilješke; the day types read Vikend and Rad",
    },
    {
      code: "pl",
      english: "Polish",
      label: "Polski",
      alt:
        "A Polish timesheet: the columns read Data, Dzień, Typ, Początek, Koniec, Przerwa, " +
        "Przepracowane, Wymagane, Nadgodziny and Notatki; the day types read Weekend and Praca",
    },
  ],
} as const;

/**
 * The App Store link, once there is one. The hero promotes it to the primary
 * action the moment this is a URL, and says there isn't one until then.
 * Changing this line is the whole launch.
 */
export const appStore: string | null = null;

/**
 * Whether a German set of screenshots has been captured yet.
 *
 * Set by the build from whether web/shots-src/de/ exists, so the flag cannot
 * claim images the site does not have — see vite.config.ts.
 */
export const hasGermanShots = import.meta.env.VITE_GERMAN_SHOTS === "1";
