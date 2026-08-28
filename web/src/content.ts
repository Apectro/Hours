/**
 * Everything the page says, in one file.
 *
 * The copy is drawn from `docs/app-store-listing.md`, which was written from
 * what the app actually does. Where the two disagree, the listing is the one
 * Apple reads and this file is the one that should change.
 */

/** The one line the whole app is built on. */
export const balance = [
  { text: "worked", kind: "term" },
  { text: "+", kind: "op" },
  { text: "credited", kind: "term" },
  { text: "−", kind: "op" },
  { text: "expected", kind: "term" },
  { text: "+", kind: "op" },
  { text: "adjustment", kind: "term" },
  { text: "=", kind: "op" },
  { text: "balance", kind: "result" },
] as const;

/**
 * The cases that make the line above worth having. Every one of them is a
 * question a timesheet app has to answer, and getting any of them wrong is
 * how somebody loses a day.
 */
export const cases = [
  {
    day: "Eight hours on an eight-hour day",
    result: "0",
    sign: "zero",
    why: "What was expected was worked. Nothing owed either way.",
  },
  {
    day: "Vacation on a Tuesday",
    result: "0",
    sign: "zero",
    why: "The day is credited against what it expected, so leave does not read as a shortfall.",
  },
  {
    day: "Vacation on a Saturday",
    result: "0",
    sign: "zero",
    why: "Nothing was expected, so nothing is credited. A day off in the week is not a day of leave.",
  },
  {
    day: "Two hours on a public holiday",
    result: "+2h",
    sign: "plus",
    why: "The holiday expected nothing and two hours were worked.",
  },
  {
    day: "Five and a half hours on an eight-hour day",
    result: "−2h 30m",
    sign: "minus",
    why: "Shown in orange, not red. Being under your hours is a state to notice, not an error.",
  },
  {
    day: "Overtime paid out",
    result: "−7h",
    sign: "minus",
    why: "Recorded as a payout rather than a mystery correction, so the balance says where it went.",
  },
] as const;

export const howItWorks = [
  {
    tag: "The month",
    title: "A calendar, not a list",
    body: "The main screen is a month, colour-washed by day type, with your totals underneath. A working day in the past with nothing on it gets a dashed outline, so a gap is something you notice while scanning rather than at the end of the month.",
  },
  {
    tag: "The day",
    title: "Hours the way yours work",
    body: "Start and end times or a figure you type. An end before the start is an overnight shift and is measured as one. Breaks as a length or as clock times. Split shifts, where the gap between two blocks is neither worked nor a break.",
  },
  {
    tag: "The week",
    title: "A contracted week, per weekday",
    body: "Not one number for all five days. A 6/6/6/6/8 week and a four-day week are ordinary rather than special cases, and a contract stating 37½ hours can override the days outright.",
  },
  {
    tag: "The record",
    title: "Dates, never timestamps",
    body: "Crossing a time zone or a daylight-saving change cannot move or reshape what you recorded. The one thing that genuinely needs an answer on a clock-change day — how long the shift lasted — is a setting: wall clock, or actual elapsed time.",
  },
] as const;

/**
 * The captures are 1320x2868 because that is the simulator's window. The
 * markup declares those numbers so the browser reserves the right shape
 * before an image arrives, and `shot` is a base name rather than a path
 * because each one is served at several widths — see scripts/images.mjs.
 */
export const shotSize = { width: 1320, height: 2868 } as const;

export const shots = [
  {
    shot: "01-calendar",
    alt: "The month view, with days washed by type and the period's totals beneath",
    title: "The month",
    caption: "Colour-washed by day type, totals underneath, gaps outlined.",
  },
  {
    shot: "02-day-editor",
    alt: "The day editor, showing start and end times, a break and a note",
    title: "A day",
    caption: "Times, breaks, notes — and only the fields you switched on.",
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
 * Each claim paired with the thing in the code that makes it true. A promise
 * nobody can check is a promise nobody should believe.
 */
export const privacyClaims = [
  { claim: "No account, no sign-up", evidence: "there is no auth layer anywhere in the app" },
  { claim: "No analytics, no tracking", evidence: "Package.swift declares no external packages" },
  { claim: "Nothing leaves the device", evidence: "unless you export a file or switch on iCloud" },
  { claim: "iCloud is your own", evidence: "CloudKit private database, off by default" },
  { claim: "It never asks for your location", evidence: "no CoreLocation import; the field is a text box" },
  { claim: "Reminders are local", evidence: "UNCalendarNotificationTrigger, scheduled on the device" },
] as const;

export const plans = [
  {
    name: "Free, and staying free",
    price: "No account, nothing to sign up for",
    highlight: false,
    items: [
      "The calendar, the day editor and every field",
      "Breaks, overtime, adjustments and the balance",
      "Insights for the day, week, month and year",
      "Reminders when a working day has no hours on it",
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
 * The App Store link, once there is one. The hero promotes it to the primary
 * action the moment this is a URL; until then the page does not pretend to
 * have somewhere to send anybody. Changing this line is the whole launch.
 */
export const appStore: string | null = null;

/**
 * The evidence for the section that claims ten languages: four real exports
 * the capture suite renders on every run, not mock-ups. Each one is a
 * different month name, a different date format and a different word for a
 * weekend — and in all four the note is still in English, because that is a
 * sentence somebody typed and the app does not translate those.
 *
 * Only these four are rendered by the capture suite today. The other six
 * languages are covered by tests rather than by pictures, which is why the
 * caption says so rather than implying the set is complete.
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

export type TimesheetLanguage = (typeof timesheetProof.languages)[number];
