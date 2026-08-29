import brand from "../brand.json";

/**
 * Everything the English page says.
 *
 * `Copy` is derived from this object, so German is checked against it by the
 * compiler: a section added here and forgotten there is a build error rather
 * than a paragraph that silently comes out in the wrong language.
 */
export const en = {
  lang: "en",
  htmlTitle: "Zeitkonto — a work-hours calendar that stays on your phone",
  htmlDescription:
    "Record your hours on a calendar, see your balance, and hand payroll a timesheet in ten languages. No account, no server, nothing collected.",
  ogDescription:
    "A work-hours calendar that keeps your hours on your phone. No account, no server, nothing collected.",
  otherLanguage: "Deutsch",
  /** The phone has no room for the full word. */
  otherLanguageShort: "DE",
  skip: "Skip to content",

  nav: {
    balance: "The balance",
    app: "The app",
    timesheets: "Timesheets",
    privacy: "Privacy",
    pricing: "Pricing",
    sections: "Sections",
    elsewhere: "Elsewhere",
    theme: "Colour theme",
  },
  theme: { auto: "Auto", light: "Light", dark: "Dark" },

  hero: {
    headlineLines: brand.en.headlineLines,
    lede: "Tap a day, put your hours in, and the month adds itself up. When payroll wants a timesheet you export one, in whatever language they read. There's no account to make and nowhere for any of it to go.",
    appStoreAction: "Get it on the App Store",
    costAction: "What it costs",
    sourceAction: "Read the source",
    notYet: "It isn't on the App Store yet. ",
    note: "Recording your hours is free and stays free. Needs iOS 18.",
    shotAlt: "Zeitkonto on an iPhone, showing a month of days coloured by type with totals beneath",
  },

  equation: {
    label: "It all comes down to one line",
    parts: brand.en.equation,
    figureLabel: "How the balance is calculated",
    foot: "Each day type carries a policy saying how it counts, which is why the same line works whether you were at work, on leave or off sick. Worked time and paid absence are always reported separately. Adding them together is how you end up with a figure nobody can explain.",
  },

  balance: {
    heading: "Six days a timesheet has to get right",
    lede: "Adding up hours is the easy part. What's hard is the days that aren't simply worked or not worked, and there are more of those than you'd think. Get one of them wrong and somebody is short a day.",
    caption: "An eight-hour contracted day, Monday to Friday.",
    columns: { day: "The day", balance: "Balance", why: "Why" },
    cases: [
      { day: "Eight hours on an eight-hour day", result: "0", sign: "zero",
        why: "You worked what you were meant to. Nobody owes anybody." },
      { day: "Vacation on a Tuesday", result: "0", sign: "zero",
        why: "The day gets credited with what it expected, so taking leave doesn't show up as falling behind." },
      { day: "Vacation on a Saturday", result: "0", sign: "zero",
        why: "Nothing was expected of a Saturday, so nothing is credited. Booking leave on a day you weren't working anyway shouldn't cost you one." },
      { day: "Two hours on a public holiday", result: "+2h", sign: "plus",
        why: "The holiday expected nothing and you worked two hours anyway." },
      { day: "Five and a half hours on an eight-hour day", result: "−2h 30m", sign: "minus",
        why: "It shows in orange. Being behind is a thing to notice, and an app that paints it red all month is just nagging you." },
      { day: "Overtime paid out", result: "−7h", sign: "minus",
        why: "Once you've been paid for the hours they have to come off the balance somewhere. Recording it as a payout means you can see where seven hours went." },
    ],
  },

  app: {
    heading: "A calendar first, and configurable to the bone",
    lede: "Every field sits behind a switch, and anything you switch off disappears instead of sitting there greyed out. An app for recording eight hours a day shouldn't make you scroll past nine fields you never use.",
    rows: [
      { label: "The month", title: "A calendar you can read at a glance",
        body: "The main screen is a month, washed with colour by day type, totals sitting underneath. A working day that's already gone by with nothing on it gets a dashed outline, so you spot the gap while scrolling past it rather than on the last day of the month." },
      { label: "The day", title: "Hours the way yours actually work",
        body: "Start and end times, or just type the hours. If the end is before the start it's a night shift and gets measured as one. Breaks go in as a length or as clock times. Split shifts work too, where the gap in the middle is neither worked nor a break." },
      { label: "The week", title: "A contracted week, per weekday",
        body: "Not one number stretched across five days. A 6/6/6/6/8 week is ordinary here, and so is a four-day one. If your contract just says 37½ hours, that overrides the individual days." },
      { label: "The year", title: "A year that closes, and carries",
        body: "Close a year and the figure it carried is fixed, so a correction made two years later can't move what somebody already agreed. Cap the carry-over if your contract does — paid out or forfeited above it. A shortfall always carries in full; forgiving it would invent hours nobody worked." },
      { label: "The record", title: "Dates, never timestamps",
        body: "Flying somewhere or a clock change can't quietly reshape what you entered, because days are stored as dates. There is one real question on a clock-change day: was that shift eight hours or nine? You pick which answer you want, once, in settings." },
    ],
  },

  gallery: {
    heading: "What it actually looks like",
    lede: "Every one of these comes out of the app's own test suite on each build, so they can't quietly drift from the thing you'd install.",
    shots: [
      { shot: "01-calendar", title: "The month",
        alt: "The month view, with days washed by type and the period's totals beneath",
        caption: "Coloured by day type, totals underneath, gaps outlined." },
      { shot: "02-day-editor", title: "A day",
        alt: "The day editor, showing start and end times, a break and a note",
        caption: "Times, breaks, notes, and only the fields you switched on." },
      { shot: "03-insights", title: "Insights",
        alt: "The insights screen showing worked, expected and balance figures",
        caption: "Today, the week, the month, the year, and a running balance." },
      { shot: "04-settings", title: "Settings",
        alt: "The settings screen, listing the working schedule, jobs, fields, day types and reminders",
        caption: "Which fields exist, how a day is measured, what a day type means." },
      { shot: "10-export", title: "Timesheets",
        alt: "The export screen showing a range, a format and a preview of the timesheet",
        caption: "The preview is the file. What you see is what gets shared." },
    ],
  },

  timesheets: {
    heading: "A timesheet in the language of whoever reads it",
    lede: "Pick any range you like, a week or a month or the 3rd to the 19th, and export it as CSV, Excel or PDF. You choose the columns and their order, your name goes at the top, and you name the file. The Excel version keeps real durations behind the hours-and-minutes formatting, so the column still adds up.",
    tablistLabel: "Timesheet language",
    proofLead: (language: string) => `A real export, in ${language}.`,
    proofRest: " Every heading, weekday, day type and date format is translated. The note isn't, because those are words you typed. These four get rendered on every build; the other six are covered by tests.",
    proofLanguages: { de: "German", fr: "French", hr: "Croatian", pl: "Polish" },
    rows: {
      settable: { label: "Set separately", title: "Ten languages",
        bodyBefore: "The file's language is its own setting, because the person reading a timesheet usually isn't the person who filled it in. Keep your phone in English and hand payroll a sheet that says ",
        bodyEm: "Gesamt gearbeitet", bodyAfter: "." },
      untouched: { label: "Left alone", title: "Only the app's own words",
        body: "Column titles, the day types it ships with and the summary labels all get translated. A note you typed, a job you named, a day type you invented: those come out exactly as you wrote them. Translating somebody's own words would be making things up." },
    },
  },

  privacy: {
    heading: "Every promise here, and where to check it",
    lede: "The app is a file on your phone. There's no account to make and no server to send anything to, and the source is public, so you don't have to take any of this on trust.",
    claims: [
      { claim: "No account, no sign-up", evidence: "there is no auth layer anywhere in the app" },
      { claim: "No analytics, no tracking", evidence: "Package.swift declares no external packages" },
      { claim: "Nothing leaves the device", evidence: "unless you export a file or switch on iCloud" },
      { claim: "iCloud is your own", evidence: "CloudKit private database, off by default" },
      { claim: "It never asks where you are", evidence: "no CoreLocation import; the field is a text box" },
      { claim: "Reminders are local", evidence: "UNCalendarNotificationTrigger, scheduled on the device" },
    ],
  },

  pricing: {
    heading: "Recording is free. You pay to make documents.",
    lede: "Nothing you've recorded ever gets locked up. If a subscription lapses every figure is still there and the backup still writes. What you're paying for is turning it into a file somebody else can read.",
    plans: [
      { name: "Free, and staying that way", price: "Nothing to sign up for", highlight: false,
        items: [
          "The calendar, the day editor and every field",
          "Breaks, overtime, adjustments and the balance",
          "Insights for the day, week, month and year",
          "A nudge when a working day has no hours on it",
          "A JSON backup holding every day you ever entered",
        ] },
      { name: "Zeitkonto Pro", price: "Monthly, yearly, or bought outright once", highlight: true,
        items: [
          "Timesheets as CSV, Excel or PDF, in ten languages",
          "Home Screen and Lock Screen widgets",
          "A second job, with its own contracted week",
          "Editing a whole range of days in one pass",
          "iCloud sync between your own devices",
        ] },
    ],
  },

  footer: {
    line: "Zeitkonto is made by one person. No company behind it, and nothing in it that phones home.",
    privacy: "Privacy",
    source: "Source",
    support: "Support",
  },
};

export type Copy = typeof en;
