import brand from "./brand.json";

/**
 * Everything the page says, in one file, so the words can be argued with
 * without going through JSX.
 *
 * It is drawn from `docs/app-store-listing.md`, which was written from what
 * the app actually does. Where the two disagree the listing wins, because
 * that is the one Apple reads.
 */

/*
 * The headline and the balance line live in brand.json rather than here,
 * because the social card needs them too and it is a Node script that cannot
 * import TypeScript. They drifted apart once already: the card kept rendering
 * a headline the page had stopped using, in a palette the page had stopped
 * having, and nothing noticed. One file, two readers.
 */
export const headline = brand.headline;
export const headlineLines = brand.headlineLines;

/** The one line the whole app comes down to. */
export const balance = brand.equation.map(([text, kind]) => ({ text, kind }));

/**
 * The cases that make the line above worth having. Every one is a question a
 * timesheet app has to answer, and these are the answers the engine is tested
 * against, so the page and the code cannot drift apart quietly.
 */
export const cases = [
  {
    day: "Eight hours on an eight-hour day",
    result: "0",
    sign: "zero",
    why: "You worked what you were meant to. Nobody owes anybody.",
  },
  {
    day: "Vacation on a Tuesday",
    result: "0",
    sign: "zero",
    why: "The day gets credited with what it expected, so taking leave doesn't show up as falling behind.",
  },
  {
    day: "Vacation on a Saturday",
    result: "0",
    sign: "zero",
    why: "Nothing was expected of a Saturday, so nothing is credited. Booking leave on a day you weren't working anyway shouldn't cost you one.",
  },
  {
    day: "Two hours on a public holiday",
    result: "+2h",
    sign: "plus",
    why: "The holiday expected nothing and you worked two hours anyway.",
  },
  {
    day: "Five and a half hours on an eight-hour day",
    result: "−2h 30m",
    sign: "minus",
    why: "It shows in orange. Being behind is a thing to notice, and an app that paints it red all month is just nagging you.",
  },
  {
    day: "Overtime paid out",
    result: "−7h",
    sign: "minus",
    why: "Once you've been paid for the hours they have to come off the balance somewhere. Recording it as a payout means you can see where seven hours went.",
  },
] as const;

export const howItWorks = [
  {
    label: "The month",
    title: "A calendar you can read at a glance",
    body: "The main screen is a month, washed with colour by day type, totals sitting underneath. A working day that's already gone by with nothing on it gets a dashed outline, so you spot the gap while scrolling past it rather than on the last day of the month.",
  },
  {
    label: "The day",
    title: "Hours the way yours actually work",
    body: "Start and end times, or just type the hours. If the end is before the start it's a night shift and gets measured as one. Breaks go in as a length or as clock times. Split shifts work too, where the gap in the middle is neither worked nor a break.",
  },
  {
    label: "The week",
    title: "A contracted week, per weekday",
    body: "Not one number stretched across five days. A 6/6/6/6/8 week is ordinary here, and so is a four-day one. If your contract just says 37½ hours, that overrides the individual days.",
  },
  {
    label: "The record",
    title: "Dates, never timestamps",
    body: "Flying somewhere or a clock change can't quietly reshape what you entered, because days are stored as dates. There is one real question on a clock-change day: was that shift eight hours or nine? You pick which answer you want, once, in settings.",
  },
] as const;

/**
 * The captures are 1320x2868 because that is the simulator's window. The
 * markup declares those numbers so the browser reserves the right shape
 * before an image lands, and `shot` is a base name rather than a path because
 * each one is served at several widths — see scripts/images.mjs.
 */
export const shotSize = { width: 1320, height: 2868 } as const;

export const shots = [
  {
    shot: "01-calendar",
    alt: "The month view, with days washed by type and the period's totals beneath",
    title: "The month",
    caption: "Coloured by day type, totals underneath, gaps outlined.",
  },
  {
    shot: "02-day-editor",
    alt: "The day editor, showing start and end times, a break and a note",
    title: "A day",
    caption: "Times, breaks, notes, and only the fields you switched on.",
  },
  {
    shot: "03-insights",
    alt: "The insights screen showing worked, expected and balance figures",
    title: "Insights",
    caption: "Today, the week, the month, the year, and a running balance.",
  },
  {
    shot: "04-settings",
    alt: "The settings screen, listing the working schedule, jobs, fields, day types and reminders",
    title: "Settings",
    caption: "Which fields exist, how a day is measured, what a day type means.",
  },
  {
    shot: "10-export",
    alt: "The export screen showing a range, a format and a preview of the timesheet",
    title: "Timesheets",
    caption: "The preview is the file. What you see is what gets shared.",
  },
] as const;

export const languages = [
  "English",
  "Deutsch",
  "Hrvatski",
  "Slovenščina",
  "Italiano",
  "Français",
  "Español",
  "Português",
  "Nederlands",
  "Polski",
] as const;

/**
 * Each promise paired with the thing in the code you could go and read. A
 * privacy claim nobody can check is a claim nobody should believe.
 */
export const privacyClaims = [
  { claim: "No account, no sign-up", evidence: "there is no auth layer anywhere in the app" },
  { claim: "No analytics, no tracking", evidence: "Package.swift declares no external packages" },
  { claim: "Nothing leaves the device", evidence: "unless you export a file or switch on iCloud" },
  { claim: "iCloud is your own", evidence: "CloudKit private database, off by default" },
  { claim: "It never asks where you are", evidence: "no CoreLocation import; the field is a text box" },
  { claim: "Reminders are local", evidence: "UNCalendarNotificationTrigger, scheduled on the device" },
] as const;

export const plans = [
  {
    name: "Free, and staying that way",
    price: "Nothing to sign up for",
    highlight: false,
    items: [
      "The calendar, the day editor and every field",
      "Breaks, overtime, adjustments and the balance",
      "Insights for the day, week, month and year",
      "A nudge when a working day has no hours on it",
      "A JSON backup holding every day you ever entered",
    ],
  },
  {
    name: "Hours Pro",
    price: "Monthly, yearly, or bought outright once",
    highlight: true,
    items: [
      "Timesheets as CSV, Excel or PDF, in ten languages",
      "Home Screen and Lock Screen widgets",
      "A second job, with its own contracted week",
      "Editing a whole range of days in one pass",
      "iCloud sync between your own devices",
    ],
  },
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
