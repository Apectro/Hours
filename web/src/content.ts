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

export const shots = [
  {
    src: "shots/01-calendar.png",
    alt: "The month view, with days washed by type and the period's totals beneath",
    title: "The month",
    caption: "Colour-washed by day type, totals underneath, gaps outlined.",
  },
  {
    src: "shots/02-day-editor.png",
    alt: "The day editor, showing start and end times, a break and a note",
    title: "A day",
    caption: "Times, breaks, notes — and only the fields you switched on.",
  },
  {
    src: "shots/03-insights.png",
    alt: "The insights screen showing worked, expected and balance figures",
    title: "Insights",
    caption: "Today, the week, the month, the year, and a running balance.",
  },
  {
    src: "shots/04-settings.png",
    alt: "The settings screen, listing the working schedule, jobs, fields, day types and reminders",
    title: "Settings",
    caption: "Which fields exist, how a day is measured, what a day type means.",
  },
  {
    src: "shots/10-export.png",
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
