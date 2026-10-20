# Baustelle (job sites) — design

Status: draft for approval · 2026-10-20

## Why

The person using Zeitkonto is sent to a construction site (a *Baustelle*) where
they act as the supervisor. Besides their own hours they write down the hours of
every coworker on that site. At the start of the next month the director asks
for those hours and pays everyone from them.

Today the app only knows one person: you. Everything for a site — the crew, the
daily times, the monthly sheet — happens on paper or somewhere else, and the
supervisor's own hours get typed twice.

Success: the supervisor writes a whole crew's day in a few seconds, and at the
start of the month hands the director one sheet per site with every person's
daily times and monthly total, without retyping anything.

Mockups (agreed with the user): https://claude.ai/artifact/EeWFcyrveYmq5EwBBt3DKv

## What it is

A new top-level area, **Sites** (German "Baustellen"; the word is translated in
every language the app ships), where the user creates one or more sites and
does everything for a site there.

### Sites

- The user creates, renames and archives sites. An archived site keeps its
  history and stops appearing in the list of active sites.
- The site list shows each active site with its crew size, the number of days
  recorded this month, and the crew's total hours this month (mockup screen 1).

### Crew

- **Each site has its own crew list.** A coworker who works on two sites is added
  separately to each — the user decided this explicitly. Crew members are just
  names in the app; they do not install anything or sign in.
- **You** (the user) are on every site implicitly and cannot be removed from it.
- A crew member can be **removed from the daily list without losing hours**:
  they are hidden from new days, and every day already recorded for them stays,
  on screen and on exports.

### Writing a day (mockup screen 2)

- A site day has **one start time, one end time and one break** for the site.
  On a normal day the whole crew arrives and leaves together, so these apply to
  everyone.
- Below them is the crew list. **The user ticks who was there that day.** The
  crew changes from day to day (Ivan may be on this site Monday and elsewhere
  Tuesday), so presence is chosen per day. Someone not ticked was not on this
  site that day and gets no hours here.
- **Exceptions are per person.** If someone came late or left early, the user
  changes just that person's start and/or end time (and break, if needed).
  Everyone else keeps the site times. A person with changed times is visibly
  marked on the day.
- A crew total for the day is shown.
- **"Same as last day"** fills the day from the most recent earlier recorded day
  on that site: the site times, the break, and who was there (not per-person
  exceptions). *(My call, suggested by me and accepted by the user.)*
- An optional **note** per site day ("rain, stopped at 13:00"), printed on the
  director's sheet. *(My call, accepted.)*
- Navigation between days: previous / next day arrows and a date picker.

### Your own hours go into your calendar

The user's own hours on a site **also appear in their personal calendar**, so
nothing is typed twice. The user decided this.

How (my call): the site day is the source of truth. When "You" is ticked on a
site day, the user's day in the calendar gets a shift for it carrying the
user's site times, marked as coming from that site. Editing the site day
updates that shift; unticking "You" or deleting the site day removes it. In the
personal day editor such a shift is shown read-only with a way to open it on
the site, so the two can never disagree. A day can hold site shifts from more
than one site and ordinary shifts side by side, as days already can with jobs.

These shifts count toward the user's own balance, totals, exports and widget
exactly like any other shift, under the primary job unless the site is set to
a different job (sites get an optional job when more than one job exists).

### The director's sheet (mockup screen 3)

- Exported per site, per month (any range is acceptable to the builder, month
  is the default).
- **One row per day, one column per person** (everyone who was on that site at
  least once in the range, including you). Each cell shows start–end and hours
  after break; "—" when that person was not there. The user confirmed this
  layout works for the director.
- At the bottom: each person's **month total** and **days worked**.
- The day's note, when present, appears on that day's row.
- Same three formats the app already exports: **PDF, Excel (XLSX) and CSV**,
  with the same preview-before-sharing the current export screen has.

### Locking and reminders *(my calls, accepted)*

- **Month lock** uses the app's existing `MonthLock`: one lock per month covers
  personal days and site days alike. A locked month refuses site edits with the
  same refusal the personal calendar gives.
- **Reminder**: the existing reminder system gains an evening reminder when a
  site was worked recently but today's site day is missing. It follows the
  existing reminder settings rather than adding a separate system.

### Free and Pro *(my recommendation; the user asked for it)*

- **One site is free**, with its full crew, daily recording, the calendar link
  and reminders. A second active site needs Pro. This mirrors jobs, where one is
  free and more are Pro: a supervisor can use the whole feature on their real
  site before paying.
- **Exporting the director's sheet needs Pro**, under the existing
  `.fileExport` gate. The preview stays free, as it does for today's export.
- If Pro lapses, nothing is lost. Every site stays viewable, and the JSON backup
  still holds all of it. Extra sites become read-only until Pro returns or they
  are archived down to one active site.
- New `ProFeature` case: `multipleSites`, with paywall copy in all ten
  languages. `alwaysFree` gains no new line: recording hours and reading them
  back already covers this.

### Decisions settled after review *(all my calls)*

- **Your name on the sheet.** The app has no user name today. Settings gains a
  "Your name" field (lenient decoding, in the backup and synced settings). The
  sheet's header and your column use it; if it is empty at export time, the
  export screen asks for it once and saves it. On screen the app keeps saying
  "You".
- **Evening reminder mechanics.** Reminder settings gain one field: a site
  reminder time (default 18:00) with its own toggle. For each site worked on in
  the last 14 days, the app schedules a local notification for the next 7 days,
  only on weekdays that site was worked. Saving a site day cancels that day's
  notification, and opening the app reschedules. If a site day is recorded on
  another device, a reminder may still fire on this one; that is acceptable.
- **Restore.** A backup holds sites, crews and site days. Restoring a file that
  has them replaces them along with days and holidays, as restore already does.
  Restoring an older file without any site data leaves existing sites, crews
  and site days untouched. After every restore, the calendar shifts that come
  from sites are rebuilt from the site days, so the two always agree. A
  site-derived shift whose site is not present is dropped.
- **When the calendar would not count a site shift.** Some days don't count
  shifts as worked hours: worked hours entered by hand
  (`autoCalculateWorkedHours` off), an absence day type, or a day excluded from
  totals. On those days ticking "You" is still allowed, because the site sheet
  must stay true. Both the site day and the personal day show a non-blocking
  warning that says why your calendar is not counting these hours, using the
  existing `DayWarning` mechanism. Nothing changes the personal day's own
  settings automatically.
- **Job per site day is frozen.** The job a site day's shift belongs to is
  saved on the site day when it is written. Changing or archiving a site's job
  affects only days written afterwards, so already-reported hours never move
  between jobs, and locked months stay locked.

## Goals

- Recording a normal crew day takes seconds; exceptions take a tap per person.
- One sheet per site per month that the director can pay from.
- The supervisor's own site hours land in their calendar automatically.

## Non-goals

- Coworkers having their own app, accounts, or sign-off.
- Sharing a site between several supervisors' phones.
- Pay rates, wages, or money of any kind.
- Contracted hours, expected hours or balances for coworkers — coworkers only
  have hours worked.
- Clocking in by location / GPS.

## Anti-goals (would be a failure even if it "works")

- The user's own hours disagreeing between the site and the calendar.
- A coworker's past hours disappearing because they left the crew or a site was
  archived.
- A save that silently does nothing (e.g. into a locked month) — refuse loudly,
  as the app already does.
- Site data missing from the backup file, or from iCloud sync when that is on.

## Constraints from the existing app

- `HoursCore` stays pure Swift with no Apple-only imports and builds on Linux;
  all arithmetic (a person's hours for a day, totals, the sheet's table) lives
  there with tests, and views only show resolved values (ARCHITECTURE.md).
- Times are wall-clock `TimeOfDay`, days are `CalendarDate`; a site day's
  duration follows the user's `DurationPolicy` and rounding setting, like
  shifts. An end before the start is an overnight shift, as elsewhere.
- Persistence: SwiftData models with primitive properties only, no unique
  constraints (CloudKit), one site day per (site, date) enforced and reconciled
  by the repository the way `WorkdayRepository` does for days; new models are
  added through the versioned schema with a migration test.
- The JSON backup (`BackupArchive`) carries sites, crews and site days, and
  restoring it restores them. Older backups without them still restore.
- Every user-facing string goes through the String Catalog in all ten shipped
  languages (en, de, es, fr, hr, it, nl, pl, pt, sl).
- Export reuses the existing CSV / XLSX / PDF writers; the sheet is a new
  `ReportTable`-shaped table rather than a fourth writer.
- Privacy promises in ARCHITECTURE.md hold: nothing leaves the device except
  through the user's own export or their own iCloud.

## Left to the builder

- Exact SwiftData model shapes and how per-person exceptions are encoded.
- How the site-to-calendar shift link is stored (e.g. a `siteID` on `Shift`).
- Whether the sheet extends `ReportTable` / `ReportBuilder` or adds a sibling
  builder feeding the same writers.
- Screen details beyond the mockups; editing UI for times follows the existing
  day editor's controls.
- Tab order and icon for **Sites**.
