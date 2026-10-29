# Hours — architecture

A private, offline work-hours calendar for iOS. No account, no server, no
analytics, no third-party code.

## Deployment target: iOS 18.0

SwiftData's first release (iOS 17) shipped with predicate and migration
limitations that would show up exactly where this app leans hardest — range
queries over historical data. iOS 18 also gives `@Observable` throughout,
mature Swift Charts, and `ShareLink` behaviour that no longer needs
workarounds. By 2026 iOS 18 is on effectively every device that can install
new apps, so nothing is lost by requiring it.

The Swift *language mode* is 5, not 6. The app uses async/await and
`@MainActor` where they help, but full strict-concurrency checking would add
noise without adding safety to a single-user, main-actor app.

## Layers

```
HoursCore/      pure Swift + Foundation. No SwiftUI, no SwiftData, no UIKit,
                and no Apple-only API: it is built on Linux too.
HoursShared/    Apple-platform code the app and the widget both need.
Hours/Data/     SwiftData models, repository, settings store.
Hours/Features/ SwiftUI screens, one folder per feature.
HoursWidget/    the widget extension: widgets, the Live Activity, controls.
HoursWatch/     the Apple Watch app; HoursWatchWidget/ its complications;
                HoursWatchShared/ what those two share.
```

`HoursShared` exists because "shared between the app and the extension" and
"portable" are two different things, and one folder cannot be both. Finding the
app group is shared but not portable, so it goes there; the snapshot it writes
is arithmetic and Codable, so it stays in the engine where the tests reach it.

`HoursCore` is import-clean by rule, not by convention — it is the entire
calculation engine, and it is the only part of the app that has to be right.

That rule is now enforced by a machine rather than by review. `Package.swift`
describes the same folder as a Swift package, and CI builds and tests it on
Linux, where UIKit, SwiftUI and SwiftData do not exist: one stray import and
the job stops compiling. It is also the fast half of the feedback loop, since
the engine's tests run there in about a minute instead of five.

Two builds of the same files, then, and no duplication: the Xcode app target
compiles `HoursCore/` directly rather than depending on the package, so there
is nothing to keep in step and no `public` scattered through the engine to
satisfy a module boundary that only one of the two builds has. The package
module is deliberately named `Hours`, the same as the app module, so the test
files say `@testable import Hours` and either build compiles them unchanged.

It sits beside the app folder rather than inside it because an Xcode
synchronized folder group can belong to more than one target, but a folder
nested inside another target's group cannot — so this is the shape an app
extension can share.

Business logic never appears in a view. Views read `DayComputation` and
`PeriodSummary` values that are already fully resolved.

## The one modelling decision worth reading twice

**Days are calendar days, and times are wall-clock times.**

A `CalendarDate` is `(year, month, day)`, persisted as the integer `yyyyMMdd`.
A `TimeOfDay` is minutes since local midnight. Neither is a `Date`.

This is what makes the awkward cases fall out for free:

- Travelling across time zones cannot move an entry to a different day.
- A DST transition cannot shift a stored time.
- Editing a day recorded three years ago behaves identically to editing today.
- One entry per date is a rule the repository keeps (see *Uniqueness is a
  rule* under Persistence), so it holds across synced devices too.

The cost is that "how long was the shift" needs an explicit answer on the two
clock-change days a year, so it is a setting: `DurationPolicy.wallClock`
(default — 08:00–16:00 is eight hours on every day of the year, which is what
salaried timesheets do) or `.elapsedReal` (the time that actually passed, for
hours that are billed or paid by elapsed time).

## Expected hours, credited absence, and the balance

Every day type carries an `ExpectationPolicy`:

| Policy            | Expected hours     | Effect                                    |
|-------------------|--------------------|-------------------------------------------|
| `scheduled`       | contracted for that weekday | ordinary working day             |
| `zero`            | 0                  | not a working day; not working it is free |
| `creditedAbsence` | contracted         | contracted hours are *credited* as paid    |

The balance is then one line, and it is correct in every case:

```
balance = (worked + credited) - expected + adjustment
```

- 8 h worked on an 8 h day → 0
- 08:00–18:00 less 30 m break on an 8 h day → +1 h 30 m
- Vacation on a Tuesday → credited 8 h, expected 8 h → 0
- Vacation on a Saturday → credited 0, expected 0 → 0
- Public holiday during vacation → one day, one type, no double count
- Worked 2 h on a public holiday → credited 8 h + worked 2 h − expected 8 h → +2 h
- Time off in lieu on a Tuesday → nothing worked, nothing credited, expected 8 h → −8 h

**Worked time** is measured per shift in `WorkdayCalculator` and then added
up: the shift's length less its breaks, unless the shift's job pays for breaks
(`Job.breaksArePaid`), in which case it is the whole length. A paid break is
still recorded and reported as a break — the break column and totals do not
change — it is only not taken off. The rule is the job's because employers
differ, and it is decided per shift because one day can hold two of them. A
shift with no job, or a job since deleted, follows the primary job; an
archived job keeps its rule for its history. While there is only one job its
rule lives beside the top-level `schedules`, as `primaryBreaksArePaid`.

Nothing else subtracts a break. The day editor's preview, the time clock, bulk
edits, site days and every total read worked minutes from that one place, so
they follow the rule without knowing it exists. A site day decides by its
frozen `SiteDay.jobID` for everyone on it — the crew work for the same employer
there — which is the same job your own calendar shift from that site carries.
The one figure computed outside the calculator, the "that comes to … worked"
under the default start and end, is `WorkSchedule.defaultShiftMinutes`, which
takes the job's rule as an argument.

Worked time and credited absence are reported separately everywhere, so a
month reads "worked 152 h, paid absence 16 h, expected 168 h, balance 0" rather
than silently inflating hours nobody worked.

**The balance starts on your first day.** Someone who installs the app on
19 October did not spend 1 to 16 October eight hours short every day. The
balance starts at `AppSettings.balanceStartDate` when one is set — in either
direction: earlier than the first entry says the days in between were owed,
later says the days before it are settled — and otherwise at the first day
anything was recorded, a calendar day or a site day. `PeriodEngine` takes that
first day as an input (`firstRecorded`, read by the repository with two
one-row sorted fetches) and marks every day before the start
`precedesBalanceStart`. Such a day does not count (`counts(through:)`) and is
not a gap (`isUnrecordedWorkingDay`), so the month, the statistics, the
exports, the running balance, closing a year, the reminder, the calendar's
dashed outlines and the widget all start in the same place without knowing the
rule exists. With nothing recorded and no start date, nothing counts: the
balance is zero and nothing is missing. A day with something on it is never
before the start, even if the first recorded day was read a moment before it
was written. The engine the day editor uses resolves one day at a time and is
not told, because a single day's figures do not depend on where the balance
starts.

**A schedule changes from a date onward.** A contract that becomes a
four-day week in November must not rewrite October, which was worked — and
perhaps handed in — under the old one. So each job's week, and the top-level
`schedules` of the one-job case, is a `ScheduleHistory`: versions of
`WorkSchedule`, each with the day it took effect, the first one "since
always". Everything that reads a schedule for a date reads the version in
force on that date — the latest that had started — through
`schedule(on:)`: expected hours and the day type in `WorkdayCalculator`, each
job's share in `jobTotals`, a new day's pre-filled times, a bulk fill, the
widget's "off at". A weekly override belongs to its version. What is not about
a date — the summary row in Settings, the week the editor opens on — uses
today's version. Saving a changed week asks when it starts: from today, from
a date (which replaces any version starting on or after it), or "it was
always like this", which is the old behaviour and leaves a single version.
The dialog names any closed month the answer would rewrite, and the screen
lists the changes so one can be taken back, letting the week before it run on.

Settings written before versions existed have only `schedule`, and read as
one version since always. Both are written: the history under
`scheduleVersions`, and the newest week under `schedule`, where an older
version of the app reads it and applies it to all of history as it always
did. When the two disagree on reading, an older app edited the week after a
newer one wrote the list; that edit lands on the newest version.

Day type precedence when nothing is set explicitly: holiday rule → the weekly
schedule in force that day (0 contracted hours means weekend) → ordinary
working day. An explicit choice on the day always wins.

The history is a `DatedHistory`, generic over what it dates, because pay
changes the same way (below). `ScheduleHistory` is its week, stored exactly
as before.

## Earnings

**Pay belongs to a job and changes from a date.** Each job carries an optional
`PayHistory` — `DatedHistory<PayRules>` — and, while there is one job, it lives
beside the top-level schedule as `primaryPay`, the way `primaryBreaksArePaid`
does. A raise asks when it starts, with the same prompt as the week; the first
rate a job is given applies since always, since nothing earned anything before
it. No pay at all means earnings are not set up, which is what every older
settings file and backup reads as, and then everything shows the hours balance
as before. `AppSettings.mainFigure` chooses between the two once a rate is set;
`showsEarnings` is the one question the screens ask.

**Money is whole cents; percentages are whole percents.** `EarningsCalculator`
works from days `PeriodEngine` has already resolved and never measures a shift
again. It places each shift's worked minutes on the clock — unpaid timed breaks
where they were, an untimed break out of the middle of the shift, a paid break
left in — and then makes them agree with the worked minutes the day already
has, putting any difference from rounding or a typed-in figure on the end of
the day. Each minute pays the rate, and every surcharge covering it adds its
percentage of the rate: Saturday, Sunday or public holiday (judged by the
calendar day the minute falls on, so a Saturday night shift turns into Sunday
at midnight; a holiday on a Saturday pays the holiday rate alone), night (the
window may cross midnight), and overtime. Because the surcharges simply add,
which minutes are overtime only decides which day they belong to. Credited
paid absence earns its credited hours at the rate times its day type's
**Paid at** (`DayTypeDefinition.paidPercent`, 0–100, 100 unless changed;
Settings › Day types, for paid-absence types), with no surcharge — sick leave
in Croatia is 70%. Only money changes: the hours credited and the balance are
the same at any percentage. With several jobs each shift is paid by its own
job, and credited hours split as `jobTotals` splits them.

**The employer's first 42 days.** A type with `employerPaysFirst42Days` (Sick,
on for Croatia) earns nothing from the 43rd calendar day of a run: consecutive
dates of that type, a weekend or public holiday left as it is inside the run
counting as a day of it (`EarningsCalculator.runPositions`). From then the
health insurer pays (HZZO in Croatia); the day is marked
`isPaidByHealthInsurance` and the day editor says "Paid by health insurance"
("Plaća HZZO"), and Insights notes such days and any reduced percentage under
the money. A month needs the 42 days before it to know, so
`earningsRange(covering:)` reaches back eight weeks while any type has the
rule. `SickPay.applyCountryDefault` sets the built-in Sick type to 70% with the
rule when Croatia's public holidays are added — the first-run country step or
Settings › Holidays — unless Sick was already edited; nothing else changes a
percentage. The app uses the hourly rate, not the six-month average the law
uses, and the Sick editor says so.

Overtime after the normal day is the minutes past the day's threshold — the
week in force that day expects, unless one is set by hand. Overtime after the
week counts minutes in date order from the first day of the user's week;
credited hours fill the threshold first but are never overtime themselves. So
a week cut in half by the start of a month still puts its overtime on the
same days: `PeriodEngine.earnings` widens any range to whole weeks
(`earningsRange(covering:)`, which is also what the callers fetch), works the
weeks out whole, and only then cuts them to the range.

A day is worked out exactly — in hundredths of a cent-minute — and rounded to
the cent once, half up. Its parts are rounded through a running total, as
`WorkSchedule` spreads a weekly target, so they add up to the day's total to
the cent, and an `EarningsSummary` is a sum of days, so a month is exactly what
its days say. Days before the balance starts and excluded days earn nothing,
and a day after today earns nothing yet, even with something recorded on it:
booked leave is owed hours, but it is not money earned.

The currency is a code in settings, nil until chosen, which follows the
phone's region; the engine stores the code and the cents and nothing else.
`MoneyFormatting` is the one place cents become text, for the app, the widgets
and the exports.

**Field allowance, kilometres and travel (1.2).** `AllowancePreferences`
in settings — off by default, decoded leniently, so every older file reads
as off with no rates — holds a daily allowance, a rate per kilometre (both
whole cents in the app's currency) and whether travel time counts as work.
A day carries `hasFieldAllowance`, `kilometres` and `travelMinutes`;
`WorkdayCalculator` resolves them onto `DayComputation`, all zero while the
switch is off (the record keeps them for when it is switched on again).
Travel that counts as work is added to worked minutes after rounding — the
rule rounds clock times, and travel has none — so the balance and the pay
follow it without knowing; `EarningsCalculator` places the extra minutes on
the end of the day like any typed-in figure. `AllowanceSummary` counts
allowance days, kilometres and travel over resolved days by the money rule
(`EarningsSummary.counts`), and needs no hourly rate. With a rate,
`EarningsBreakdown` has `allowanceCents` and `mileageCents` of its own:
they are in `totalCents`, never in a surcharge, and every screen and
export names them on their own lines. The amounts and what is tax-free
depend on the contract and the country; the settings footer says so and
the app takes the rates as given.

**Money never reaches anyone else.** The site screens, the site widget card,
the director's sheet and the crew lists are built without it — the site
sheet's builder is never handed earnings, and the earnings column is never
offered among the columns to choose. A personal timesheet carries an earnings
column, tile and total only when Export options says so, which it does not by
default.

## Leave, time off in lieu, and the year in review

**Time off in lieu** (Zeitausgleich) is a built-in day type, id
`timeOffInLieu`, with the `scheduled` policy: exactly an ordinary working day
with nothing worked, so it takes the day's contracted hours — from the week in
force — off the balance and nothing else. Because it is chosen on the day, the
day has an entry and is never a gap; the widget leaves it out of the month's
squares and does not say when it ends, as it does for leave. A new built-in
needs nothing written: the catalogue merges built-ins with the stored custom
types at read time, custom types have UUID ids, and an older version reading a
day of this type shows it as Unknown. Its export term (`timeOffInLieuDay`) is
separate from the adjustment reason `timeOffInLieu`, which is a plural in some
languages; German uses the Austrian *Zeitausgleich* for the day.

**Leave** is `AppSettings.leave`, a `LeavePolicy` for the primary job:
allowance in days (halves allowed), the day the leave year starts, days carried
over *into a named leave year* — so last year's figure is not quietly carried
into every year after — and an optional expiry for the carry-over. It decodes
leniently, so 1.0 settings and backups read as the defaults (25 days from
1 January), and it travels in a backup with the rest of the settings.

`LeaveCalculator` counts days `PeriodEngine` has already resolved, in
`HalfDays` so nothing is ever 17.4999. Only the built-in Vacation type takes
leave, and only on a day something is contracted; an excluded day takes none.
There is no half-day type, but a vacation day can have its expected hours set
lower by hand, which credits fewer hours: up to half the day's contracted hours
is half a day of leave, more is a day, nothing credited is nothing taken. Used
is through today, planned is after it, and remaining subtracts both. Carried
days are spent first, in date order, so leave taken or booked by the expiry
keeps the carry-over it uses and whatever is left after the expiry is lost.
Insights shows the leave year containing the period on screen (fetched on its
own, since a leave year from April does not line up with a month), once the
policy has been changed or any leave is taken, booked or carried; the day
editor shows what would be left while the day is a vacation day.

**Overtime available** reads a positive running balance as days off:
`OvertimeAvailable` divides it by the average working day of the weeks every
active job has in force, rounded to the nearest half day.

**The year in review** is `YearReview`, made from `PeriodEngine`,
`PeriodAggregator`, `BalanceLedger` and `LeaveCalculator` — the calculators
Insights reads — and nothing else. It stops at today, as earnings do, rather
than counting days already entered for later. Days on sites come from the site
shifts in your own calendar (`ShiftPeriod.siteID`), so nothing about anyone
else's hours is an input, and money appears only with a rate. A bad-weather
card appears only when a type with id `badWeather` exists — built in or
custom — and has days, so the review works with or without that type. The
screen is a full-screen cover from Insights, never a push; the late-December
invitation is a card on Insights from the 20th, put away for the year once
opened or dismissed (`@AppStorage`, a convenience of the installation). Share
renders the summary with `ImageRenderer` and hands the picture to the share
sheet; nothing leaves the phone otherwise.

## Checking a payslip (1.2)

The reason most people track their hours is to see they were paid right, so
Insights' month has a "Check your payslip" row that opens a sheet. The user types
what the payslip says — hours worked, overtime, sick and leave (hours or days),
gross pay — and only what is typed is compared. `PayslipComparison` (engine)
does no new arithmetic: `PayslipFigures` is read from the same resolved days,
summary and earnings Insights shows for the month, counted through today —
Worked, Overtime (the summary's), the hours credited on Sick and on Vacation
days, and the month's earnings. A line the app has no answer to is not asked
for: overtime while the balance or "Calculate overtime" is off, money without a
rate. Days are read by the average working day of the week in force
(`averageWorkingDayMinutes`, as *Overtime available* reads them). A line
matches within a quarter of an hour, or one unit of money, either way; beyond
that it is "more" or "less on the payslip", never an error. The sheet says
payroll may count differently (cut-off dates, averages), and its note for
payroll is plain text in the export language (`PayslipTerm`, the figures named
with the timesheet's own `ExportTerm`s), shared with a `ShareLink` or copied.

What was typed is kept per month in `AppSettings.payslipChecks`, keyed
`"yyyy-MM"` — no schema change. It decodes month by month (an unreadable month
is dropped, the rest kept), is written only once something is in it, travels
in a backup with the settings, and the 1.0 and 1.1 decoders skip the key. The
row compares the stored figures with the hours as they are now, so editing a
day afterwards changes "Checked" to "1 difference" by itself.

## Holidays

The app ships with **no** holidays and never guesses a country. Public holidays
differ by nation, region, employer and year; a wrong guess is worse than an
empty list. Rules are user-created and can recur:

- `once` — a single date
- `annual` — same month and day every year, optionally bounded by year
- `nthWeekday` — e.g. the fourth Thursday in November, or the last Monday in May
- `easter` (1.1) — days from Easter Sunday in `offset` (Good Friday −2, Easter
  Monday +1, Ascension +39, Whit Monday +50, Corpus Christi +60), by the
  anonymous Gregorian computus
- `weekdayOnOrAfter` (1.1) — the first weekday on or after a date: Buß- und
  Bettag (Wednesday on or after 16 Nov), the Swiss fast Monday (Monday on or
  after 16 Sep), the Jeûne genevois (Thursday on or after 5 Sep)
- `annualOffSunday` (1.1) — a date moved by `offset` when it is a Sunday:
  Dutch King's Day

The last three are not built by hand (`Kind.handMade` is what the editor
offers); they come from a country's list.

A 29 February rule simply does not occur in common years rather than being
silently moved. A holiday can be marked "counts as a normal working day", in
which case it keeps its contracted hours and only its name is carried through.

**1.0 reading 1.1's movable rules.** 1.0 decodes `kind` strictly in a backup —
an unknown kind fails the list of holidays and with it the whole restore — and
in the store reads an unknown kind string as `annual` on the stored month and
day. So a movable rule is written as an annual **31 February**, which no year
has, with its real shape beside it where 1.0 does not look: a `movable` object
in the backup JSON, and in the store the kind string itself
(`easter:1:1:2:39` — kind, month, day, weekday, offset; no new column, so no
schema version). The worst 1.0 does with one is list it without a date; it
never puts a holiday on a wrong day. 1.1 in turn reads a kind it does not know
(from a later version) as a rule that never occurs rather than failing the
file. See `HolidayRecurrence+Coding.swift`.

**Public holidays by country (1.1).** `PublicHolidayCatalog` holds pure Swift
tables, one `PublicHolidaySet` per country or per German state / Swiss canton,
each with the year it was checked for and its source. A holiday that applies
only in part of a region, or by custom or collective agreement, carries a
`note` and is offered unticked; a day that could not be confirmed is left out
and named in the table's comment. Picking is one tap — Settings › Holidays ›
Add public holidays, the first-run "Where do you work?" step, or a one-time
card on the calendar for someone with no holidays — but still never automatic.
`PublicHolidayImport` turns the ticked holidays into ordinary `HolidayRule`s,
skipping any an existing rule (enabled or not) already covers on every date of
the next five years; `AppSettings.publicHolidays` remembers the set and the
rule ids it created, for "Remove these holidays", and whether the card was
answered. The stored name is the one for the phone's language: local on a phone
in the set's language, English on an English phone, otherwise the local name
(which is what the employer's calendar and the payslip say).

**Working a public holiday.** The day stays a holiday: its contracted hours are
credited and every hour worked comes on top (`balance = worked + credited −
expected`), and those hours earn the Sunday & holiday surcharge — the usual
arrangement in Germany and Austria (Feiertagsentgelt plus pay for the work).
"I worked" therefore prefills the week's times without setting the day type
(`PeriodEngine.draftRecord(…, working: true)`); choosing Work explicitly would
drop the credit. `DayComputation.isWorkedPublicHoliday` marks the calendar cell.
A site's month does not outline a public holiday as unwritten, and the evening
site reminders skip it (`SiteUnwrittenDay`, `SiteReminderPlan`).

## Persistence

- **SwiftData** for entities: `DayEntry` (one per `dateKey`) and
  `HolidayRecord`, and for job sites `SiteEntry`, `CrewMemberEntry` and
  `SiteDayEntry` (one per site and `dateKey`), and since 1.1 the site diary:
  `SiteDiaryEntry` (one per site and `dateKey`), `SiteDiaryPhotoEntry` and
  `CrewSignatureEntry` (one per site, person and month), and extra work:
  `ExtraWorkJobEntry`, `ExtraWorkPhotoEntry`, `ExtraWorkReportEntry` (a report
  that was sent) and `ExtraWorkItemEntry` (the remembered items). These are
  records the user creates, queries and exports.
- **UserDefaults (Codable JSON)** for `AppSettings`. Preferences are a
  singleton read on nearly every view update and passed into every pure
  calculation; a value type is the right shape for that, and it keeps the
  calculation engine free of any storage dependency.

Custom day types live in settings rather than SwiftData because they are
configuration that must be available wherever a day is rendered.

**Migration.** SwiftData models store primitives only — no enums, no
associated values, no `Date`s — so adding a property is an additive,
lightweight migration. Settings decode leniently: every field falls back to its
default when absent, so a new preference in a future version cannot invalidate
a stored blob. `AppSettings.schemaVersion` exists for the day a real
transformation is needed.

**Schema versions.** `HoursMigrationPlan` walks V1 → V2 → V3 → V4 → V5 → V6 → V7
→ V8 → V9, every stage lightweight. The live classes are always the newest version; the moment
a new version is added, the previous one gets frozen copies of the classes
column for column (V2 and V3 hold theirs), because a version must keep
describing exactly what stores written by it hold. V4 (1.1) adds
`SiteDayEntry.isBadWeatherStop` with a default, and the three diary entities
with a default on every property. Diary photos are `@Attribute(.externalStorage)`
JPEGs: the database file stays small, a fetch of the rows (the month grid's
marks) never reads an image, and with sync on they travel as CloudKit assets.
V5 (1.1) adds the four extra-work entities and freezes V4's eight classes. V6
(1.1) adds whether an extra-work job is finished — `isDone` and an optional
`doneAt` — and freezes V5's twelve classes. `isDone` is stored with the default
`true` on purpose: a lightweight stage fills an added column with its default,
and every job a V5 store holds was written as finished work, before a job could
be in progress; the app writes `false` itself for a new job. V7 (1.1) adds
`SiteDayEntry.absenceData`, optional, JSON `[CrewAbsence]` beside
`presentData` — why people not ticked were away — and freezes V6's twelve
classes. It is a column of its own rather than more JSON in `presentData`
because every older build decodes that column as `[Attendance]`, leniently,
and would read an absence as one more person present. V8 (1.2) freezes V7's
twelve classes and adds the day's `hasFieldAllowance`, `kilometres` and
`travelMinutes` (defaults false, 0, 0), the site's `allowanceByDefault`
(false) and, for the opt-in arrival reminder, `latitude` and `longitude`
(optional), `arrivalRadius` (150) and `remindsOnArrival` (false) — on
`Site` too, so `SiteEntry.site` and `apply` carry them and a restore keeps
them — and on
the site day `allowanceData` (optional JSON `[UUID]`, who gets the
allowance) and `kilometres` (0). `allowanceData` is a column of its own for
`absenceData`'s reason: a field inside each attendance in `presentData`
would be dropped by any older build that wrote the day again. V9 (1.2)
freezes V8's twelve classes — TestFlight installs already hold V8 stores, so
V8 is never changed in place — and adds the site's `address` (optional text,
nil and empty both none). Every
new entity keeps the rules a CloudKit-mirrored store sets: every attribute has a
default or is optional, nothing is `.unique`, and there are no relationships —
rows refer to each other by id strings, as the diary's do. `MigrationTests`
checks every entity of the live schema against those rules.

**Uniqueness is a rule, not a constraint.** `dateKey` used to carry
`@Attribute(.unique)`. It does not any more, for two reasons that arrive
together: CloudKit refuses a store with a unique constraint on it, and even with
one, two devices editing the same Tuesday offline produce two rows that CloudKit
merges in without knowing they mean the same day. So `WorkdayRepository` owns
the rule instead — every read that could see duplicates collapses them, keeping
the most recently edited row and deleting the rest, and `reconcileDuplicates()`
runs on every return to the app. A tie on the last edit breaks on creation
date, and rows that still cannot be told apart are all kept until the next edit
stamps one, since two devices breaking that tie differently would each delete
the row the other kept.

Last edit wins rather than a merge. Hours are not meaningfully mergeable: a
start time from one device and an end time from another would invent a shift
nobody worked.

Every synced record has a natural key both devices agree on, or an id only one
device ever makes: a day by `dateKey`; a site day and a diary by site and
`dateKey`; a signature by site, person and month; sites, crew members and
photos by their ids. Holiday rules are the exception — the same "Christmas Day"
added on two phones before they synced has two ids — so after the id collapse
`HolidayDuplicates` removes rules that say exactly what an older rule says
(recurrence, name ignoring case, working day, enabled, notes). There the tie
*can* break on the id, because the id travels with the rule and every device
picks the same survivor. Sites and crew made separately on two devices are not
merged: attendances point at their ids, and two sites with one name may be two
sites.

`SiteRepository` holds the same rule for sites, crew members and site days.
It also writes your own calendar day in the same save as the site day, through
`WorkdayRepository` and under the same month lock, and when duplicate site days
collapse it rewrites the calendar day for that date, so the site and your
calendar never keep different hours.

**The diary is not under the month lock.** `SiteDiaryRepository` writes the
diary, its photos and the crew's signatures without consulting `MonthLock`.
The lock keeps a closed month's hours as they were handed in, and none of this
is hours: a diary written up the next morning or a crew signing their month —
which happens after the month ends, usually after it is closed — must still be
possible. Its methods avoid the names `save` and `delete` so
`check-repository-lock.py` does not take them for the hours' writes. A rained-off
stop *is* hours, so it goes through `SiteRepository` and the lock like any
other change to a site day.

**Backups.** The diary, its photos and the signatures are three optional lists
in the backup JSON (`diaries`, `diaryPhotos`, `signatures`), and extra work four
more (`extraWorkJobs`, `extraWorkPhotos`, `extraWorkReports`, `extraWorkItems`),
set after `init` so the initialiser stays as it was. Quantities are written as
text ("12.5"), exact on every platform. A job's `isDone` and `doneAt` are
optional keys: missing, the job is done (it was written before a job could be
in progress); a decoder from before them skips them, and the status written is
still only "open" or "sent". The allowance (1.2) is keys in the same way: the
settings' `allowance`, a day's `hasFieldAllowance`, `kilometres` and
`travelMinutes`, a site's `allowanceByDefault` and its arrival reminder's
`latitude`, `longitude`, `arrivalRadius` (written when not 150) and
`remindsOnArrival`, and its `address`, a site day's
`allowanceMemberIDs` and `kilometres`, and a site shift's `fieldAllowance`
and `kilometres` — each written only when set, missing reads as none, and
nothing new goes inside an attendance, which every older decoder reads as
one more person present. A site day's `absences` and a day type's
`paidPercent` and `employerPaysFirst42Days` are keys in the same way: missing
reads as none, 100% and off, and 1.0's decoders skip them. The format version
stays 1: they are additions 1.0 skips without complaint, where a new version
number would make 1.0 refuse the whole file. Photos go in as base64 inside the
one file, so a backup is still a single file through a single door. The price
is size: a stored photo is about 200–500 KB, a third more as base64, so a month
with three photos on twenty days adds roughly 15–30 MB. A file that carries the
lists replaces what is on the device; a file from before them keeps the
device's diary for the sites it restores and drops it for sites it removes
(`BackupArchive.restoredItems`). Extra work restores by the same rule; the
remembered items belong to no site, so an older file keeps the device's.
Deleting everything takes the diary and extra work with the sites.

**iCloud sync.** Off by default, per installation, and the same store file
with or without it: `HoursModelContainer.make` changes only `cloudKitDatabase`,
so turning sync on mirrors every row already there (CloudKit mirroring exports
a store's existing rows the first time it is set up on it) and turning it off
keeps everything. `Scripts/check-cloudkit-models.py` holds the newest schema
version to what CloudKit accepts — every attribute optional or defaulted, no
unique constraint, relationships optional with an inverse and no `.deny` — on
every push; V4 passed as it stood, so no V5 was needed. `CloudKitSchema`
initialises the live version's models; each version that adds a column (V6,
V7, V8 and V9 do) has to be initialised and deployed to Production again.

*No build may crash at launch because of sync.* 1.0 in TestFlight did, at every
launch: it opened a syncing store without being signed for iCloud, CloudKit
raised an Objective-C exception Swift cannot catch, and the remembered choice
did it again next time. `SyncLaunch.plan` (engine, tested exhaustively) now
decides each launch's store from the UI-test flag, the preference, the
`ICLOUD_SYNC` flag, the entitlement and a mark:

1. **The signature.** iOS has no public "do I have this entitlement" call, but
   `codesign` writes the entitlements plist into the code signature at the end
   of the executable. `CodeSignatureEntitlements` reads the app's own
   (memory-mapped; Mach-O, `LC_CODE_SIGNATURE`, SuperBlob slot 5, every offset
   bounds-checked) and `ICloudEntitlement` says whether CloudKit in
   `iCloud.app.zeitkonto` is allowed. Not allowed, or unreadable: the local
   store, sync switched off, and the reason. That is the 1.0 crash, prevented
   before anything opens.
2. **The mark.** A file (`SyncLaunchMark`, written before the iCloud store
   opens, because a `UserDefaults` write may not reach the disk before a kill)
   is cleared by `SyncMonitor` when CloudKit reports its setup finished, after
   20 seconds alive, or on going to the background. A launch that finds it
   still there opens locally and switches sync off: one crash, never a loop.
3. **The fallback.** A store that throws opens locally, sync off.

Whatever stops it, `SyncPreference.problem` remembers why and Settings › iCloud
says "Sync couldn't start: …" until it is turned on again; a build compiled with
sync but not signed for it shows the switch disabled with the reason. UI tests
(`-hours-ui-testing`) always get the in-memory store and never read, touch or
change any of this. The preference moved to a new key in 1.1, so the choice
saved by the 1.0 builds that crashed does not start uploading by itself.

`SyncMonitor` also collapses duplicates as soon as an import lands, and the
screen shows a missing or restricted iCloud account (asked of CloudKit only
while syncing, i.e. only once the build is proven to be allowed) and
CloudKit's last error.

*Settings* go through `NSUbiquitousKeyValueStore`, decided by `SettingsSync`
(engine): iCloud's copy, last write wins, except when a device first joins it,
when its own custom day types (its days carry their ids) and its rule ids for
the same country's public holidays are kept beside iCloud's and written back.
The first device uploads its settings at launch rather than at its next change.
Restoring a backup on a syncing device replaces the settings and the data on
every device; Backup and data says so.

*Entitlements and builds.* `Hours.entitlements` carries the container, CloudKit,
push (`aps-environment`; mirroring is told of changes by silent pushes, with
`remote-notification` in `Hours-Info.plist`) and the key-value store.
`aps-environment` and the CloudKit environment are build settings
(`ZEITKONTO_APS_ENVIRONMENT`, `ZEITKONTO_CLOUDKIT_ENVIRONMENT`): development /
Development in Debug, production / Production in Release, which this project
only signs for distribution. Simulator CI builds (`CODE_SIGNING_ALLOWED=NO`)
carry no entitlements and say so.

*The CloudKit schema.* TestFlight and App Store builds use the Production
environment, which cannot create record types on the fly; until the schema is
deployed there, sync opens and uploads nothing. `CloudKitSchema` runs
`initializeCloudKitSchema` on a scratch store with the same models (Apple's
route for SwiftData): from the launch argument
`-hours-initialize-cloudkit-schema` in Debug, or from a button in Settings ›
iCloud in a TestFlight build made with the workflow's *CloudKit development*
switch (`CLOUDKIT_SCHEMA_TOOLS`, Development environment — never one to submit).
The schema is then deployed to Production in the CloudKit Console. The steps,
including the container and the App ID, are in README.md, *iCloud*, and the
TestFlight lane prints them; its preflight switches on the iCloud and Push
capabilities with the API key, and the beta lane stops before building if the
signing profile lacks the container, CloudKit or production push — the parts
the API cannot do.

**Validation** happens on the way in (a break can never be negative, times are
clamped to a real time of day, a range that is entered backwards is corrected)
and, where a value is legitimate but suspicious, is surfaced as a non-blocking
`DayWarning` — a half-typed day is a normal state, not an error.

## Navigation

Four tabs: **Calendar**, **Sites**, **Insights**, **Settings**. The calendar is the
primary surface and opens on the current month; tapping a day reveals an inline
summary beneath the grid, and opening it presents the editor as a sheet so the
month never leaves the screen. Sites lists each active job site with its crew
and this month's figures, and leads to the site and its crew list; while
today is unwritten a card also offers "Same as last day", which pushes the
same `SiteRoute(appliesSameAsLastDay:)` the site widget does. The site screen
puts the selected day first: the day's week (the whole month on request),
the day's crew, bad weather, extra work, the diary, and the month's figures
last. At accessibility text sizes a day cell of the site's week or month
shows one mark under its number (the crew count, else rain, else one dot for a
diary or extra work) instead of three; VoiceOver still names every one. Export is reachable from the calendar toolbar and from Settings.

**The calendar, top to bottom (1.1).** The grid, then the selected day's card
(its Write hours / Edit day button must be on screen when a day is tapped),
then the period's totals with their own Export button, then the week list in
week view. A clearly sideways swipe on the grid pages the period, as the
toolbar arrows do; it is a simultaneous gesture, so scrolling and cell taps are
untouched. Export has its own toolbar button; ⋯ keeps the view, Edit a range,
and **Close / Reopen** for the month on screen (`MonthLock.offer(for:today:)`:
only a finished month can be closed, any closed month can be reopened, the
reopen asks once more). A closed month shows a notice above the grid with
Reopen. Settings › Balance & rounding keeps a Closed months row that opens the full
list (`ClosedMonthsScreen`). The day editor's and the bulk edit's "this month is
closed" alerts reopen the month in place; the edit stays on screen and Save
works afterwards. The site day does the same: its closed-month notice has
Reopen (asking first), and its refusal alert offers Reopen for that month.

**Photo viewer.** One sheet (`Shared/PhotoViewerSheet`) shows a photo large for
the site diary and the extra-work editor alike: Done top right, a confirmed
bin top left when the photo can be removed.

**Export's range steps.** Day, week, month and year each have ‹ › that move a
whole period (`ExportRangeKind.step`, `canStepForward` — never into a period
that has not started). `PeriodStepper` is the one stepper control; a site's
sheet uses it for its month.

**The day editor keeps edits.** Swipe-down is disabled while the draft differs
from what it opened with (site shifts excluded: they follow the site day), and
Cancel asks "Discard changes?". Expected hours, corrections and "Count this day"
sit under one "More" row at the bottom, opened whenever any of them is in use.

## Widgets and the Live Activity

A widget runs in its own process with a hard memory limit, so it never opens
the store. The app writes a small `WidgetSnapshot` into the App Group's
container whenever something it shows could have changed, and the widget reads
that. Every figure in it comes from the engine: `WidgetSnapshotWriter` only
fetches, `PeriodEngine` resolves the days, and `WidgetSnapshotBuilder` turns
them into the week's bars, the month's squares and the site card. A square's
state is read from the day's own balance and a bar counts exactly when the day
counts towards the app's own week total, so the widget cannot show a different
answer from the calendar. All of it is tested on Linux with the rest of the
engine.

The file outlives the moment it was written. Glanced at after midnight it
still describes yesterday, so each figure has an accessor that takes the
instant being drawn: yesterday's total is not shown as today's, last week's
bars are not shown under THIS WEEK, and yesterday's "written" is not today's.
It decodes leniently, as settings do, so a widget updated before the app has
run once reads the old file and leaves the new parts out.

Earnings travel the same way: the writer runs `PeriodEngine.earnings` for the
month and the week and writes today's, the week's and the month's cents with
the currency code, and only while earnings are the main figure — so the
block's presence is that choice, and an older file reads as hours. Each figure
lapses with its day, week or month like the hours beside it. The running clock
is not added to them: what its minutes pay depends on surcharges only the app
works out, so the figure moves when the shift is saved.

**The 1.2 widgets** (Clock, Balance, Leave and Earned beside the four
kinds that were already placed) read more of the same file: the week day by
day (`WidgetWeekDay`: from–to, worked, credited, balance, the day's kind and
type name, when work usually starts), a dot per day of the month, the
running balance and what it is in days off, the leave year (only once leave
is in use — the Insights card's rule), the month's earnings split into hours,
allowance and kilometres (whenever a rate is set), the site card's crew row
by row with the reason each person is away, and whether the clock is
switched on. `WidgetFigures.swift` decides all of it — bar heights and the
target line, dot kinds, "≈ 1½ days off", the next stretch of leave across a
weekend, which face Today shows — and each figure lapses with its day, week
or month as the older ones do; past midnight the week still knows whether
the new day is a working day. Names that reach the widget (day types, "You",
another site) are resolved by the writer in the phone's language through the
export word table, so the extension looks nothing up in settings. Today's
**Clock in** and **Clock out** are real buttons: `ToggleClockIntent` set to
on, and `StopClockIntent`, run in the app's process like the control's. The
look is the system's widget background with one accent from the extension's
asset catalogue; a timeline entry a minute while the clock runs keeps the
minutes moving, and the seconds are system timers.

**A widget cannot write, so its buttons are links.** The store lives in the
app's own container, not the shared one. "Same as yesterday" on the site
widget is `zeitkonto://site/<id>/same-as-last`; the app follows it by pushing a
`SiteRoute` value onto the Sites tab's path, and the site screen then does what
its own "Same as last day" button does, only where that button is offered.
`AppLink` in the engine is the one spelling of these links for both sides. The
scheme and the `remote-notification` background mode CloudKit needs are the
only things in `Hours-Info.plist`, because neither has a build-setting form and
the rest of the app's Info.plist is generated.

**The Live Activity follows the snapshot.** Five paths start or stop the clock
— the clock card, discarding, Siri, Shortcuts and the Live Activity's own stop
button — and every one already refreshes the widget, so the refresh is where
`ClockActivityController` brings the activity in line: a running clock that has
been paid for has exactly one, and anything else has none. That also ends a
stale one on the next launch. The stop button is a `LiveActivityIntent`, which
iOS runs in the app's process; the widget extension compiles the same type, in
`HoursShared`, only to put it on the button, and its `perform` is compiled out
there by the `WIDGET_EXTENSION` condition only that target sets.

**Controls are widgets that act.** Clock in and out is a `ControlWidgetToggle`
whose state is the snapshot's running clock and whose intent,
`ToggleClockIntent`, is built exactly as the stop button is: a
`LiveActivityIntent` (and a `SetValueIntent`, for the state it was flipped to)
in `HoursShared`, run in the app's process, compiled out of the extension.
Clocking in from Control Center therefore starts the Live Activity from the
background, which only such an intent may do. Same as yesterday and Write
today are `OpenURLIntent` buttons on `AppLink`; which site Same as yesterday
opens is `AppLink.sameAsYesterday(from:)`, the site card's site. The snapshot
writer reloads the controls with the widgets. The App Shortcuts that open the
app — Same as yesterday, Write today — leave their link in
`HoursStack.notificationLinks`, as a tapped notification does, and the root
follows it: Write today onto the calendar with today's editor over it.

## The Apple Watch app

The watch is a second, smaller screen for the same snapshot. It cannot read
the phone's App Group and must never open the store, so `PhoneWatchLink` sends
it the widgets' `WidgetSnapshot` as the WatchConnectivity application context
— which keeps only the latest, exactly right for a snapshot — from the same
`refresh` that writes the file, so the watch hears of every change the widgets
do. It activates in the app's `init`, because a message from the watch wakes
the app in the background, where no view appears.

A tap on the watch is a `WatchCommand` with its own id and the instant it was
tapped: `sendMessage` while the phone is in reach, `transferUserInfo`
otherwise (delivered in order when the two meet), and both when a message
fails, since a lost reply is indistinguishable from a lost message. The phone
decides with `WatchCommandLedger`, in the engine: a command is obeyed once,
at the time it was tapped — two hours queued in a pocket were still worked —
never in the future, and a clock-out older than the running clock is refused,
because it ended a shift the phone has already ended. It then runs the same
`TimeClock` as everything else and refreshes, which answers the watch. A Live
Activity cannot be started from that background wake; it appears the next
time the app comes forward.

The watch shows `WatchFace`, also in the engine: the snapshot's own accessors
(so yesterday's total is not today's on the wrist either) with the taps the
phone has not reported handled laid over them, so the button responds at once
with the phone in the van. The context carries the ids the phone has seen;
the watch drops those, and anything unanswered after a day. Complications read
the same two things from the watch's own App Group and draw the same face.

The watch app has its own targets and scheme, `HoursWatch`, and is embedded
in the iPhone app ("Embed Watch Content"), so the iPhone scheme builds it for
the watchOS simulator and the archive carries it. The engine
folder is compiled into them as into the widget; `HoursShared` is not, since
ActivityKit is not on watchOS. Its strings are a third catalogue,
`HoursWatchShared/Localizable.xcstrings`, generated like the others from the
`watchInterface` list. No Pro gate: it is free, as everything is at launch.

**Sample data for the App Store shots.** A watch simulator has no phone, so
behind `-hours-sample-data` (the phone sample's own argument) the watch app
shows `WatchSample`, in the engine: the sample site, a shift since seven or
a written day, the month in euros in proportion to the date. It then starts
no WatchConnectivity session and ignores taps, so nothing replaces the
figures and nothing is written to the App Group. CI launches it once per
line of `fastlane/watch-screenshots.txt` and saves the screen with `simctl`.

## Reminders and the links they open

Four kinds of scheduled local notification (and, since 1.2, the arrival
question below, posted when it happens), each planned in the engine and scheduled by
`ReminderScheduler`, under its own identifier prefix so each can be replaced
without touching the others: the weekly gap reminder (`GapFinder`), the evening
site reminder (`SiteReminderPlan`), the note on the 1st that a site sheet
is ready for the boss (`MonthlySheetReminderPlan`), and the weekly note
that finished extra work has not been sent to the boss
(`ExtraWorkReminderPlan`). None of them asks for permission until its switch is
turned on; the two site ones are on by default and simply schedule nothing
while notifications are not allowed, and the extra-work one is off by default.

**Arriving at a site (1.2).** The fifth kind is not scheduled at all:
`ArrivalReminders` posts it the moment iOS reports that the phone crossed
the edge of a site it watches. Off unless turned on in a site's settings
(`SiteArrivalSection`), where turning it on explains first and only then
asks: When In Use for one fix (`CLLocationManager.requestLocation`) saved as
the site's `place`, notifications, then Always, which region events while
the app is closed need. Without Always or Precise Location the switch stays
on and the section says it cannot work, with a way to Settings.

`ArrivalLocation` is the app's only CoreLocation code. It watches one
`CLCircularRegion` per site with the reminder on, a place and not archived
(`Site.monitorsArrival`), entry and exit, at most 20 in the Sites tab's
order (`ArrivalReminderPolicy.plan`; the section says when a site is past
them), and none without Always. Region monitoring rather than `CLMonitor`:
both are on iOS 18, and the delegate of a `CLLocationManager` made in the
app's `init` hears the event on the background relaunch iOS makes for it,
with no monitor to reopen by name, no event stream to be iterating in time
and no service session to hold. No `location` background mode. The regions
are brought in line on launch, on every return to the app, when a site is
saved, after a restore or Delete everything, and when the access changes.

Whether a crossing asks is `ArrivalReminderPolicy.decide`, in the engine:
arriving asks to start the clock only with none running and not on a day
off (`isDayOff`: a public holiday, paid absence, time off in lieu, a day off
of the user's own — never Work, Other or the weekend, since someone at the
site on a Saturday is there to work); leaving asks to stop it only while it
runs, any day; and the same site is not asked the same way twice within two
hours (`ArrivalReminderLog`, this phone's `UserDefaults`, never in settings
or a backup).

**Leaving with nothing written (1.2).** Leaving with no clock running asks
"Left <site> — write today's hours?" instead (`.askToWrite`) when the site
has no day for today — written means any site day stored for that site and
date, the evening site reminder's rule (`SiteReminderPlan.isWritten`) — and
today is not a day off; it shares leaving's two hours. The body gives the
last day's times ("07:00–15:30 like last time"). With a last day that copies
to something (`SiteRepository.sameAsLastDay`, not blank) the notification has
Same as last day and Not now: Same as last day saves exactly what the site
screen's button would, from the delegate without opening the app, under the
month lock — a closed month is told in a notification of its own, as the
stop is — then refreshes the widget, the evening and the monthly reminders.
Without one there are no buttons. A tap on the notification itself follows
its `AppLink.site` link to the site on today, as any notification link is
followed. It does not double up with the evening site reminder: the log
remembers which sites were asked today, and `SiteReminderPlan.dates` leaves
those sites out of today (`askedWhenLeavingToday`), so the evening one is
only for sites nobody asked about; the refresh runs as the question is
posted. The notification has a category per question, with Start clock /
Stop clock / Same as last day and Not now, answered by `NotificationTapDelegate` without
opening the app: `TimeClock.clockIn(at:jobID:)` with the site's job, or
`clockOut(at:)`, at the moment you arrived or left when that is within
twelve hours and after the clock started (`clockInstant`), then the widget
refresh. As with a tap on the watch, the Live Activity of a clock started
this way appears when the app next comes forward. The delegate shows these
categories as banners while the app is open; the other reminders are
still not shown then.

UI tests never make a `CLLocationManager`: `ArrivalLocation` is a fake that
hands out a fixed place and the access `-hours-location-always`,
`-hours-location-denied` or `-hours-location-no-always` asks for.

**Extra work not sent.** A day of the week and a time (Friday 15:00 by
default), one repeating weekly request (`unsent-extra-work`). A notification
cannot look at the store when it fires, so its words are fixed when it is
scheduled: `ExtraWorkReminderRefresher` asks the plan again and replaces the
request — or removes it when nothing is waiting — on launch, on every return to
the app, when a job is saved, deleted, ticked or sent, when a site is archived,
and from its settings. Nothing changes the answer without the app being open,
except a sync from another device or a restore, which wait for the next return
to the app. Waiting means the report's "Not sent yet" (`awaitsReport`) on a
finished job of an active site. One site: "Trg Pravde: 3 extra jobs not sent
yet", linking to that site's report (`zeitkonto://site/<id>/extra-work`,
`AppLink.siteExtraWork`, which the site screen opens as a sheet, as it opens the
export); several: the total, "3 extra jobs not sent to your boss yet", linking
to the Sites tab. Counts are inflected (`String(inflected:)`, the
`extraJobs` noun). The preference keys say "unsent work" so a backup without
extra work still has no `extraWork` key in it.

The monthly note only ever plans the next 1st — the one after depends on days
not written yet — so it is redone on launch, on every return to the app, when a
site day appears or goes, when a site is renamed or archived, and from its
settings. It carries an `AppLink` (`zeitkonto://site/<id>/export?month=2026-10`)
in its `userInfo`. A tap reaches `NotificationTapDelegate`, set in the app's
`init` so a tap that launches the app is not missed, which leaves the link in
`HoursStack.notificationLinks`; `RootView` follows it exactly as it follows a
widget's `onOpenURL`, by value onto the Sites tab, where the site screen opens
the export as a sheet. The delegate handles taps only: a notification arriving
while the app is open is still not shown, as before.

## First run

A fresh install asks its questions once (`FirstRunSetupView`): a name for the
sheets, the working week, whether breaks are paid, where you work (the
country's public holidays), the language of the reports for the boss, whether
you lead a crew, and an optional hourly rate with its currency. Each answer is
written as you continue past it, through the same helpers the settings screens
use (`changePrimarySchedule`, `setPrimaryBreaksArePaid`, `changePay`, the export
language and currency fields), so skipping half-way keeps what was answered,
and continuing without changing anything leaves the defaults exactly as they
were (`FirstRunAnswers`, tested on Linux).

**Preselected from the country (1.1).** Leaving the country step preselects the
report language and the currency (`HolidayCountry.reportLanguage(region:)` —
Switzerland by canton — and `currencyCode`) unless either was already picked by
hand; with no country both stay as the settings had them, which for the
language is "Same as the phone": the app's language when the export speaks it,
English otherwise. The phone's own currency is stored as none, as Settings ›
Pay does. A rate becomes the primary job's first pay since always; no rate sets
nothing up and stores no currency, and a job that already has pay keeps it. The
rate is typed as text and read by `MoneyInput` on every keystroke, since a
formatted number field only commits when it loses focus and the decimal keypad
has no Return. The pay step says where money can appear: never on a site's
sheet, and on a personal timesheet only if Export options adds it.

**Leading a crew** is `AppSettings.leadsCrew`, decoded leniently (1.0 settings
and backups read as no; 1.0 skips the key). It only decides what the last screen
offers — Create a site is for a crew lead — and what the tour's Sites stop says.
It never hides a tab.

## Ratings and feedback

The app asks for an App Store rating with the system prompt (`requestReview`),
and only right after a sheet has really been shared — the export's or the
extra-work report's share sheet ending in `.completed` (`ShareSheetPresenter`;
the export no longer uses a `ShareLink`, which does not say). `ReviewPrompt`
(engine, tested) decides: not in the first fourteen days after the first launch,
and once per app version; the system then decides whether to show it and caps it
at three a year. Nothing asks "do you like it?" first, which the App Store rules
forbid. `ReviewPromptStore` keeps the first launch and the last version asked in
`UserDefaults` on this device only, and never asks under UI tests.

Settings › Rate Zeitkonto opens the App Store's write-a-review page
(app id 6825054128); Send feedback opens a mail to the developer with the app
version, the system and the phone model in its footer, nothing of the hours, and
shows the address to copy when no mail account is set up.

## The guided tour

"Show me around" on the setup's last screen, or Settings › Show the tour again,
starts six stops (`GuidedTour`, `TourStop` in the engine): a welcome in the
middle, today's cell, the month's totals, Sites, Insights, and Export options
naming the report language. Skip on any setup step ends the setup without it,
and it is never started on its own; UI tests see it only when `-hours-tour`
asks.

Views mark what the tour points at with `.tourTarget(_:)`. They report their
frame in window coordinates to a `TourCoordinator` in the environment rather
than as anchor preferences, because the targets sit inside the `TabView`'s tabs,
navigation stacks and lists, and a preference set there does not reliably reach
a view outside the `TabView`. `RootView` owns the coordinator, switches tabs
through its own `selection` as the stops move, and ends on the calendar.
`TourOverlay` dims the screen (black at 55%), cuts a rounded, animated hole
around the target and puts the card above or below it; it waits about a second
for a target after a tab switch, and a target that never appears (the month
summary switched off, a row scrolled away) shows the card centred with nothing
lit, so the tour cannot get stuck. Taps outside the card do nothing. The card
is modal to VoiceOver and takes focus at every stop, the dimming is hidden from
it, and Reduce Motion drops the movement.

Telling a fresh install from an update is `FirstRunSetup.decide`: any stored
day, holiday or site, sync being on, or any setting off its default means
someone has been using the app, so they are not asked and that is remembered.
The flag lives in its own `UserDefaults` key, like the sync preference, because
it belongs to the installation rather than to the data. UI tests start from what
a fresh install looks like, so they see it only when `-hours-first-run` asks.

## Sites: bad weather, the diary and sign-off

**Bad weather** (Schlechtwetter) is a built-in day type, `.badWeather`, paid
like a holiday by default and editable like the other built-ins. Being built in,
it appears for everyone who updates with nothing stored or migrated; a custom
type with the same id overrides it, as with every built-in. A site day can be
stopped for the whole crew (`SiteDay.stoppedForBadWeather(at:)`): with no time,
nobody worked and the times go but who was there stays; with a time ("stopped at
11:00") the hours up to it stand. A full stop gives your own day the Bad weather
type when nothing else is on it — no type you chose, no other hours. A partial
stop does not: the type credits the contracted day, and on top of the hours
already worked that would count them twice, so that day stays hours worked.
`SiteCalendarSync.merged` is told the site days as they stood before the change,
which is how lifting, unticking or deleting a stop takes the type it put on back
off without touching a Bad weather day you chose yourself. Bad-weather days are
counted on the site's month header and as a tile on the director's sheet, whose
note column leads with "Bad weather" on those days.

**The site diary** (Bautagebuch) is one `SiteDiary` per site and day — weather,
a temperature typed by hand, and four texts — plus up to six `DiaryPhoto`s. It
is independent of the hours: it can exist with none, and deleting the hours
leaves it. A blank diary is not stored. The weather is picked, never fetched.
On the day screen each part (weather, the four texts, photos) is a row that
opens in place, closed with a one-line preview of what it holds
(`SiteDiary.weatherPreview`, `SiteDiary.preview(of:)`); the editor of an
extra-work job opens its Material, Time, Photos and Signature sections the same
way (`DisclosureHeader`).

**Why someone was not there.** On a site day, someone not ticked can be given
a reason: a `CrewAbsence` (person and day type) in `SiteDay.absences`, chosen
from `DayTypeCatalog.absenceReasons` — Sick, Vacation, Personal day, Time off
in lieu, Day off and the user's own non-working types; never Work, Weekend,
Public holiday, Bad weather or Other. The 44-point button where a ticked
person's clock would be opens the reasons and "No reason"; the row then shows
the type's colour and name, and the long press offers the same. A reason
unticks; ticking clears it; "Same as last day" never copies one, since people
are sick a day at a time. You away with a reason gives your own calendar day
that type through `SiteCalendarSync.merged`, by the bad-weather rule: only over
a day with nothing on it and no type you chose, and taken back only when the
reason that put it there goes or changes. On the site sheet an absent person's
cells read the reason's export name — the timesheet's word for the type — and
"Sick days" and "Leave days" (Vacation, personal days, the user's own types)
are rows under the totals only when someone has one. Nothing about money: a
site sheet never has any.

**On another site** is a reason too, first in the menu, but not a day type:
`AbsenceReason.otherSite(siteID?)`, one of your other active sites or "Another
site" with no name. It never reaches your calendar (your hours there come from
that site), counts as neither sick nor leave, and prints the site's name, or
"Other site" in the export language. It is stored as `kind: "otherSite"` with
no `dayTypeID`, so a reader that knows only day types fails on the entry
rather than guessing one, and every reader treats a list it cannot read as no
reasons; this version reads lists entry by entry and leaves out only what it
cannot read. When someone not ticked here was ticked on another of your sites
that day — you by your id, anyone else by the name "Add from other sites"
matches (`CrewCandidates.key`), and only when one site matches —
`SiteElsewhere` gives a greyed "At <site>" hint; a tap on the reason button
confirms it, a long press offers the rest. A hint is never stored on its own.

**Field allowance on a site (1.2).** While the allowance is tracked, a
site can give it by default (`Site.allowanceByDefault`), and a site day
freezes who got it in `SiteDay.allowanceMemberIDs`: ticking someone in on
such a site adds them (`togglingPresence(of:allowanceByDefault:)`), the
crew row's long-press menu takes it off or gives it to one person
(`settingAllowance`), and unticking or a reason for being away takes it.
Only someone ticked present has it (`hasAllowance(for:)`), so a stray entry
counts for nothing. The day also has the vehicle's `kilometres`, one number
for the day. "Same as last day" carries both, the allowance for those it
carries over. Your own share reaches your calendar on the site shift
(`Shift.fieldAllowance`, `Shift.kilometres`), rebuilt with it by
`SiteCalendarSync` like the hours, so it never touches the allowance or
kilometres you typed on the day yourself; the day has the allowance if
either gives it, and your kilometres and every site's add up. A site shift
carrying only those — a full bad-weather stop — is still `isEmpty` for the
hours, so the stop still types the day, but is stored for what it carries.
The site sheet has an "Allowance days" closing row per person, only when
anyone has one, and a "Kilometres" row with the month's total in the notes
column, which every split part keeps; never an amount.

**Two sites in one day (1.2).** "Moved to another site…" records that some
of the crew left a site mid-day for another of your sites. `SiteMoving.apply`
(engine) works on the two site days: each person who went keeps their start
here and ends at the time they left; on the other site's day for the date —
made when there is none, freezing that site's job as any new day does — they
are ticked from when they started until their original end here. The break
goes here, there or half on each (`BreakPlacement`); unless chosen it goes
where it falls in time — an untimed break sits in the middle of the shift, as
`EarningsCalculator` places one — and to the other site when the move cuts it.
People are matched to the other site's crew by name (`CrewCandidates.key`),
someone hidden there is shown again and someone missing is added. Nobody who
stays changes, a reason someone is away is never moved, the allowance is not
given twice for one day, and a closed month refuses. The result is a
`SiteMove` on the day they left (`SiteDay.moves`) holding each person's
attendance on both days before, so `SiteMoving.undo` restores both exactly,
and takes away a day the move made unless something was written on it since.
`SiteRepository.applyMove` and `undoMove` write both site days, the new crew
and your calendar day in one save under the lock, so when you went your day
gets two site shifts through `SiteCalendarSync` like any two site days.

The moves are stored without a schema version: V9 is on TestFlight, and a
new column means V10, a migration stage and a CloudKit schema to deploy
again for an undo record. They ride in `absenceData` as entries of their own
kind, `{"memberID": <move id>, "kind": "move", "move": …}`
(`SiteDayStorage`). Every reader since 1.1 decodes that list entry by entry
and leaves out an entry whose kind it does not know, so an older 1.2 build
reads the day's reasons exactly as before; the worst it can do is write the
day again without the move, which loses the banner and Undo, never hours. A
backup carries them as the site day's `moves` key, written only when there
are some, which 1.0 and 1.1 skip.

Your calendar day on two sites (`DaySiteSplit`) shows a thin bar with a colour
per site and a gap where neither was worked, a row per site — "Trg Pravde ·
12:00 – 16:00 · 3h 30m" — the break with the site it was taken on, and a
button to each site's day, pushed by value on the calendar's own stack. The
day's Worked and balance are the day's, counted once; the month cell is
unchanged.

**Crew sign-off.** Each person reads their month on your phone and signs with a
finger. A `CrewSignature` stores the strokes as points (sharp at any size, and a
few hundred numbers in a backup) and a fingerprint of that person's hours at the
moment of signing (`SignatureFingerprint`, FNV-1a over their days' start, end,
break and minutes — Linux-safe and stable across devices). When the hours change
afterwards the fingerprint no longer matches and the sign-off and the sheet say
"changed after signing". Signing again replaces the old signature.

Signing is optional. The site export has a **Signatures** switch (remembered in
`@AppStorage("export.siteSignatures")`, on by default); off, `SiteSheetBuilder`
leaves out both the line to sign on and the sign-off boxes, and the export's
sign-off row stays, greyed, saying it is turned off for that sheet. Signatures
already given stay stored. The sign-off is also in the site's own menu, as a
sheet with a month stepper that opens on `SignOff.defaultMonth` (last month
during the first ten days, this month after). Removing a signature asks first.

**A sheet for each person (1.2).** At month end each worker wants their own
hours to check against their payslip, and the supervisor wants to hand each of
them a page. `CrewMemberSheetBuilder` (engine) makes one person's month across
every site they appear on. A person is a `CrewSheetPerson`: you by your id, anyone
else by their name folded as "Add from other sites" folds it (`CrewCandidates.key`),
since each site keeps its own crew. It is a `.timesheet` `ReportTable` with the
person's name as `ownerName`, so the PDF, the workbook and the CSV print it
through the personal timesheet's own code and look, headline and tiles
included; the sites go in the eyebrow and the title. A row per day they were
ticked present (two on a day they were on two sites) and per day a reason was
given for them not being there, one a day and none on a day they worked
elsewhere; a day with neither is no row, which is also how it treats weekends
and holidays, as the site sheet does. The site column appears only for more than
one site, the reason and note columns only when a row has one; a note is the site
day's, led by "Bad weather" as on the site sheet. Totals: hours and days on site,
sick and leave days only when non-zero, counted by the site sheet's rule
(`SiteSheetBuilder.absenceKind`). With the Signatures switch on it carries the
timesheet's employee line and the site sheet's "checked" line; no drawn
signatures, which belong to the site sheet. The site export's "One sheet per
person" shares one file per person in the chosen format, all in one share
(`ShareSheetPresenter.present(_ urls:)`), named "<Name> – <Month Year>"
(`ExportNaming.crewSheetFileName`, then the file writer's sanitising). The crew
list's share button opens `CrewMemberSheetScreen`, one person's sheet for this
month with a month stepper. Nothing is stored: the sheets are made from the site
days each time.

## Extra work

**Extra work** (Zusatzarbeiten, dodatni radovi) is what a crew did beyond the
contract, written down so the boss knows what is done. An `ExtraWorkJob` belongs
to a site and a day: what was done, material lines (`ExtraWorkItem`: the user's
own name, a `Decimal` quantity, an `ExtraWorkUnit` — pcs, m, m², m³, kg, h, set,
or a unit typed in and kept as typed), optionally how long the job took and who
was on it, up to six photos (the diary's `DiaryPhotoProcessor`, so no metadata), and the client's
optional signature (the crew sign-off's `SignaturePoint`s and canvas). **There
is no money anywhere in it**, it is never on the personal timesheet, and the
report is a progress report, not a bill: no invoice step, no invoicing words in
any language (`ExtraWorkExportTests` checks), no empty lines to sign on.

**Time on a job** is one time for the job, not hours per person: "it took us an
hour" with two people is a one-hour job. The editor has one quarter-hour
stepper (tap the number to type "1:30" or "1,5", `ExtraWorkTime`) and the day's
crew as chips, all of the day's ticked crew chosen when the time is added.
Saving stores each chosen person with that same time in the job's existing
`[ExtraWorkHours]` (`ExtraWorkJob.settingTime`), so neither the schema nor the
backup changed. `ExtraWorkJob.duration` is that shared time — for a job written
before, whose people can have different minutes, the largest — and `people`
who has time on it; everywhere a job is shown it reads "1h · Marijo Mikša, Dusko
Bajlović" (`timeLine`). **Nothing adds hours up across jobs** — no tile, no
summary, no total row: each job says how long it took.

Two things are tracked, separately. **Is the work finished?** A job can run over
several days, so `isDone` starts false and is ticked by the user — the 44-point
checkmark beside the job (and a long-press item, since the day's rows are not a
`List` and have no swipe), or "Work finished" in the editor; `doneAt` records
when. A job decoded without the field — a V5 store, a backup from before — is
done, since it was written as finished work. **Does the boss have it?** Its
status is open → sent; sent is set by one rule, `ExtraWorkSending.marked`: only
when the share sheet reports a completed share (`ShareSheetPresenter` uses
`UIActivityViewController`, since `ShareLink` does not say), and then for every
job in the report, recorded with an `ExtraWorkReportRecord`; a cancelled share
changes nothing, and sharing a CSV marks nothing, since it is data rather than
the report. Builds of 1.1 before it shipped had a third status, invoiced; a
stored "invoiced" reads as sent. A job sent while in progress and finished since
(`doneAt` after `sentAt`) is `awaitsReport` again: the boss heard it was under
way, not that it is done. A job shows at most two chips — In progress / Finished,
then Sent or Signed (grey) — through `ExtraWorkChips` everywhere, the report
included.

The report (`ExtraWorkReport`, pure) is one site's finished jobs — not sent yet
(every finished job the boss does not have, whatever its date), this week, or
picked dates — and those still in progress only when "Include jobs still in
progress" is on; `ExtraWorkReport` keeps them apart (`done`, `inProgress`).
Material is summed per item and unit over both: case, accents and spacing do not
make a new item (`ExtraWorkCatalog.key`), and a line is named as it was most
recently written. The report screen ("Extra-work report") puts the site and
what it carries first, then the range, then the jobs; every job on the site
still in progress, whatever the range, is one line under the title that opens
in place to a list with checkmarks. A new job starts in progress, so a report
left empty only by jobs in progress (`ExtraWorkRange.leftInProgress`) says how
many, with "Include them" (turns the switch on) and "Mark finished…" (lists
them with their checkmarks) instead of "Nothing to report". One button sends
the PDF ("Send to boss · PDF"); the picture, Excel and CSV are in a "More
formats" menu beside it.
`ExtraWorkDocument` turns a report into the export language's words — "Extra
work done · dates", the work done day by day with its photos first, then a
"Still in progress" section if any, then the material used as a summary; tiles
for jobs done, in progress and photos, each only where it has something
to say (never hours). A job's material is one line per item, "4 × P7" over
"2 × P6", in the PDF and on the day's card alike. A signature the client gave
is printed as "Confirmed on site by <name>, <date>" with the drawing, on its job or under the report, and nothing is
printed where there is none. Four renderings: the PDF (`ExtraWorkPDFRenderer`,
A4 portrait in the director's sheet's type and colours, jobs running on over
pages), the same report as one tall picture for a chat
(`ExtraWorkPictureRenderer`; see below), a workbook with Jobs and Material sheets in that order
(`XLSXWriter.data(sheets:)`, quantities as numbers through `ReportRow.numbers`,
a job's items one per line in a wrapped cell), and a CSV of job lines with each
job's time and who on its first line only; where any job has its time noted,
both carry an Hours column (the job's duration) and a Who column; a Status
column appears in both only when jobs in progress are included, and a
"Confirmed on site" column only when somebody confirmed. Its words are
`ExtraWorkTerm`s, kept beside `ExportTerm` in their own file with the same
one-switch rule.

**The picture.** WhatsApp opens an A4 PDF zoomed in and cut off, so "Send as
picture" shares the report as one image: 1080 pixels wide, drawn a point to a
pixel with the table's text at about 30 pixels, as tall as the report, never
paginated, with "Zeitkonto" in the footer instead of a page count. It is not a
second layout: `ExtraWorkReportLayout` measures and draws every block (header
and tiles, the jobs, "Still in progress", the material, the closing with the
legend and signature) for both, and differs only in its `Metrics` — page width,
margins, columns, and a type scale that multiplies every font, rule and
vertical distance (1 for the PDF, whose output is unchanged). The PDF renderer
only cuts the blocks into pages; the picture renderer draws them one under
another into a `UIGraphicsImageRenderer`. Photos are the PDF's small
thumbnails, two to a row, until the picture would pass 16,000 pixels; then they
are left out and the text kept (the PDF still has them). The bytes are a PNG or
a JPEG at 0.85, whichever is smaller; the file is named as the PDF is, with
`.png` or `.jpg`. Sharing it marks the jobs sent exactly as the PDF does, only
once the share sheet reports a completed share.

The remembered items ("Used before") are one list for the user, not per site:
saving a job records its items, most recently used offered first.

**Not under the month lock.** `ExtraWorkRepository` writes without
`MonthLock`, for the diary's reason: none of it is anyone's hours, and the
30th's extra work is finished and sent after the month is closed. The
checkmark writes through `storeProgress(of:)`, which touches `isDone` and
`doneAt` alone. Its methods avoid `save`, `delete` and `replaceAll`.

## Export

One `ReportBuilder` produces a `ReportTable` — columns, formatted rows,
totals — and CSV, XLSX and PDF are three renderings of that single table, so
the formats cannot drift apart. Columns are filtered by the feature toggles: a
column for a feature that is switched off is never offered and never emitted.

A personal timesheet adds Allowance, km and Travel before the notes, each
only while the allowance is tracked and some day in the range has one —
never chosen, like the earnings column — and lines for allowance days,
kilometres and travel under the totals, an allowance-days tile, and, when
it carries earnings, what the allowance and the kilometres came to.

A director's sheet (`SiteSheetBuilder`) opens with the timesheet's own Date
and Day columns — the same `ReportBuilder.dateText`/`weekdayText`, so the date
follows Settings › Export date style, and the same headings in every export
language — each a column group of one, so the two-row heading of the workbook
and the PDF names both. People's groups start at group 2 (`mergedGroups`);
the closing rows keep their label in the date column with the day empty.

A big crew does not fit across A4 landscape: every person is two columns
that may never be cut short ("07:00–16:00" and their hours), and the page
holds five or six. The PDF then prints the month once per group of people
rather than squeezing the times. `SiteSheetBuilder.split(_:peoplePerPage:)`
(engine, tested on Linux) cuts the table into consecutive, balanced groups —
seven at five a page is four and three — each a complete table: Date and Day,
that group's people, Notes, and that group's closing rows (a sick or leave
row only where someone in the group had one), with flags and merged groups
moved along with their person and a "People 1–5 of 9" line
(`ExportTerm.peopleOnPage`) printed under the header block, which every part
repeats. How many fit is measured by the app (`PDFReportLayout.printedParts`:
the largest group size at which every part's measured minimum widths fit).
A sheet everyone fits on comes back unchanged and prints exactly as before.
A day row is 14 points tall, or as little as 12 when that keeps every day of
the table and its closing rows on the first page (`PDFReportLayout.dayRowHeight`):
14 points fit 30 days, so a 31-day month used to send its last day over to a
page of its own with the total. When the days and the total fit but the summary
does not, the total stays under the days (`PDFPagePlan.drawsTotal`) and the
summary and the lines to sign on go on to the next page. The header tiles are as
wide as their figure needs, never narrower than 88 points. The page count runs across all parts, and the sign-off and diary follow the
last part once. Only the PDF is split: the workbook keeps one wide sheet and
the CSV one table.

A director's sheet can carry the site diary and the crew's sign-off. In the PDF
they are pages of their own after the table (`PDFAppendix`), laid out before
drawing so the footer's page count includes them; with nobody signed and no
diary included the sheet prints exactly as before. Diary photos are drawn from
small JPEGs (900 px) so the PDF keeps the compressed bytes instead of every
pixel. In the workbook the diary is a second sheet, a row per day. The CSV
stays one table, which is what a CSV importer expects: no diary there.

**A site's address (1.2).** `Site.address` is free text, one or two lines,
typed in the site's settings or filled in from its saved place.
`ReportTable.address` carries it on one line (`SiteAddress.singleLine`) for
the site sheet (every split part keeps it), a crew member's sheet when it
covers exactly one site, and the extra-work report. The PDF prints it as one
line under the byline, in the byline's grey a size smaller; the header block
grows by 11 points, which a 31-day month with its closing rows still fits.
The workbook has a row of its own under the title block ("Address" in the
export language, then the address) and the CSV a line after the name in its
identification block. Nothing else about the sheets changes. A personal
timesheet's Location column, only when it is on, falls back to the address of
the site a day's shift came from when the day has no location of its own
(`ReportBuilder.siteAddresses`); a typed location stays the day's.

**Two sites on a timesheet (1.2).** When the period's shifts come from more
than one site, `ReportBuilder` adds a Site column after the day (never chosen:
`ReportColumn.site`), and a day worked on several sites prints as a row per
site under one date — the date, the day and what is written about the day on
the first, each site's times, break and hours on its own — then a "Day" row
with the day's own figures (`SplitDayRow`): its worked hours, counted once,
and what it owed, its balance and its money. The site rows' hours are figures
in the workbook and the Day row's are text, so its SUM counts each minute
once; the totals and the summary are the period's as always. The PDF shades
the group lightly and rules it once. "By site" (`ReportTable.bySite`: name,
address, hours) stands beside the summary in the PDF and under it in the
workbook and the CSV; a "Sites" tile goes beside Worked only while the header
has fewer than five tiles. The eyebrow and the title name the sites in the
order first worked, "Hauptstraße 12 · Trg Pravde", and beyond three the first
two and "+2 more" in the export language (`ExportLanguage.combinedSiteNames`),
as a crew member's sheet now does too; the PDF cuts the eyebrow with an
ellipsis rather than wrapping it. Export's Sites picker ("All sites" or one)
filters the timesheet to one site's shifts (`DayComputation.restricted`):
that site's hours only, so nothing owed, no balance, no money and no
allowance, titled after the site with its address. Site sheets and crew
members' sheets read the site days, which a move already splits.

CSV is RFC 4180 quoted, UTF-8 with an optional BOM (Excel on Windows needs it),
with a configurable field separator, decimal separator, date format and
duration style. XLSX is written directly as an OOXML package with inline
strings — no third-party dependency. PDF is drawn with `UIGraphicsPDFRenderer`
as a real table with a header block and a totals footer.

## Privacy

Everything is on the device unless the user says otherwise. There is no
URLSession in the app, no analytics SDK, no crash reporter, no remote
configuration and no third-party code of any kind. Two Apple frameworks make
network calls on its behalf and nothing else does: StoreKit, to ask whether Pro
has been paid for, and — only when the user turns it on — CloudKit. Neither
carries a single recorded hour anywhere we can see. (MapKit loads Apple's map
tiles for the small map of a site's place, shown only once a site has one, and
`CLGeocoder` asks Apple Maps for the address of a site's saved place only when
"Fill in from the saved place" is tapped — that one place, nothing else.) The
only data that leaves deliberately is a file the user exports through the
system share sheet.

**Location (1.2): only if you turn on an arrival reminder for a site, and it
never leaves your phone.** Until 1.2 the app did not access location at all.
The arrival reminder reads one fix to save a site's place, and then iOS
watches those sites' areas and wakes the app at their edge; the app keeps no
positions, no history and no track, only each such site's latitude,
longitude and radius, which travel with the site (a backup, the user's own
iCloud) and nowhere else. So the App Store's "Data Not Collected" stays
true; `notes/listing-1.2/privacy.md` has the reasoning and the review notes,
and the privacy policy, the Privacy screen, the website and the README say
the same sentence.

The Apple Watch app does not change that: WatchConnectivity carries the
snapshot from the phone to the user's own paired watch directly, with no
account and no server, and the watch keeps it on the watch.

iCloud sync is off by default and opt-in. When it is on, everything in the
store — days, holidays, sites, crews, the diary with its photos, signatures —
goes through SwiftData's own CloudKit mirroring into the user's private
database, and the settings blob through `NSUbiquitousKeyValueStore` — settings
are not in the SwiftData store, and a second device computing expected hours
from a different contracted week would be wrong rather than merely different.
Both are the user's own iCloud; neither we nor anyone else can read them, so
the App Store's "Data Not Collected" stays true. The privacy policy says so,
and how to delete the iCloud copy.

The preference deliberately lives outside `AppSettings`, in its own
`UserDefaults` key. Settings travel in a backup file, and restoring a backup
taken on a synced device onto a different phone must not quietly start
uploading someone's hours. Sync is a property of an installation, not of the
data.

**The camera and photos.** The diary's photo picker is `PhotosPicker`, which
runs out of process and needs no photo-library permission: the app only ever
sees the pictures chosen. The camera is `UIImagePickerController` and asks for
camera access with a purpose string, the first and only permission the diary
adds. Every photo, picked or taken, is decoded and written again as a new JPEG
with no metadata at all (`DiaryPhotoProcessor`), which is what takes the GPS
coordinates out: the app keeps no location but a site's saved place, and only
for an arrival reminder the user turned on, and a GPS position in a picture
handed to a director would break that by the back door. The weather is picked by
hand; there is no weather service.

The privacy screen is written from `HoursStack.isSyncing` rather than from what
the app intends in general — it reports the store that actually opened. A
screen that says "nothing leaves the device" while the store is syncing is the
one screen in the app it would be worst to be wrong on.

## Being paid for

The entitlement is a value type in the engine — `Entitlement`, with
`ProFeature` naming what is sold — so the rules are tested exhaustively and
off-platform, and StoreKit appears in exactly one file. `SubscriptionStore`
builds one from `Transaction.currentEntitlements`; nothing else may invent one,
and there is no `isPro` boolean written anywhere a user could reach.

**No account, deliberately.** A purchase belongs to the buyer's Apple ID, which
is what puts it on their other devices without anyone logging in. Requiring a
login for an app that works offline would also risk App Review guideline
5.1.1(v), which allows an account only where it is core to the functionality.

Two rules the code is written to keep:

**Pro gates producing and creating, never viewing or keeping.** Someone whose
subscription lapsed opens every day they recorded, sees every total, and still
writes the JSON backup that holds the lot. What they lose is the formatted
timesheet and the ability to set more up. `ProFeature.alwaysFree` lists what
that protects, and a test asserts the sold list has not quietly grown.

**StoreKit's answer is the answer, including when it is no.** An early version
kept a recent paid entitlement when `currentEntitlements` came back empty, on
the theory that empty might mean a device with no signal. That was wrong, and
the StoreKit tests caught it: `currentEntitlements` reads Apple-signed
transactions held on the device and needs no network, so empty means genuinely
nothing. Second-guessing it did not protect anyone offline — StoreKit had
already done that — it only made an expiry or a refund take a fortnight to
take effect.

**TestFlight installs get Pro without paying.** `TesterAccess` unlocks it
when StoreKit's own app transaction says the copy came from TestFlight (the
sandbox environment), so the App Store build can never reach it. A real
purchase always wins, a switch in Settings — shown only in TestFlight — turns
the unlock off so the paywall can be tested, and only the App Store's own
answer is cached, so moving from TestFlight to the App Store version never
starts out unlocked. App Review runs in the same sandbox, so the unlock is
compiled in only when the TestFlight workflow's "Unlock Pro for testers"
switch is on (`TESTER_UNLOCK`); the build submitted for review is made with it
off and contains no unlock at all.

The cached entitlement survives for one purpose: to fill the moment between
launch and StoreKit replying, so a subscriber does not watch their own app sit
locked for a second. It is provisional, the first completed refresh overwrites
it either way, and one older than a fortnight is not shown at all.

Gates sit at the moment of doing the thing, not at the door of the screen. A
person who has not paid can open Export, choose their range and columns, and
read the preview — they are stopped where the file would be written. Hiding the
screen would leave them guessing what they were being sold.

The widget cannot ask StoreKit cheaply from its own short-lived process, so the
answer travels in the snapshot the app already writes. It defaults closed, which
is what makes a file written by an older version read as unpaid rather than as a
free pass.

## Look

`Hours/Features/Shared/DesignSystem.swift` holds the spacing scale (`Metrics`:
tiny 4, small 8, medium 12, large 16, extraLarge 24; corner radii 14 for cards,
10 for smaller tiles, `chipCornerRadius` 8 for status chips) and the semantic
colours. `hoursNegative` and `hoursPositive` are asset colours
(`HoursWarningText`, `HoursPositiveText`) that pass contrast as text in Light
mode — system orange and green on white do not, which matters in sunlight —
and are the system colours in Dark; `hoursNegativeFill` is the bright orange,
for washes only. A scrolling screen that is not a `Form` is `SectionHeading`
over `SurfaceCard`-style surfaces, `Metrics.large` apart; one heading style for
every in-scroll section. Sheets that write something have Cancel on the left
and Save (or a more precise verb, such as Sign) on the right; sheets that only
show or share have Done on the right.

## Text and tests

**Strings the user reads go through a String Catalog.** One per bundle: the app
has its own and the widget extension has its own, since an extension looks up
strings in its own bundle and would otherwise never be translatable at all.
Both start empty and the build extracts the keys, so adding a language later is
a matter of adding a language rather than of first finding the words.

Counts go through automatic grammatical agreement — `^[\(count) day](inflect:
true)` — rather than a hand-picked noun, because "1 day" / "2 days" is the easy
half and the pattern is what a translator needs for a language where the number
changes the word itself.

The distinction that matters in SwiftUI is which type a parameter is declared
as. `Text`, `Label`, `Button`, `Section` and `.navigationTitle` take
`LocalizedStringKey`, so a literal handed to any of them extracts itself. Our
own components take `String` — `StatTile(label:)`, `SettingsRow(title:)`,
`PrivacyPoint(detail:)` — and a literal there is just a literal, invisible to a
translator. Those call sites say `String(localized:)`, as do the summary
strings assembled at runtime.

They keep the `String` parameter rather than becoming `LocalizedStringKey`
because three call sites pass values that are already localised text — a
weekday name from `DateFormatter`, an adjustment reason from the engine — and
handing a runtime string to `LocalizedStringKey` asks it to be looked up as a
key, which is wrong even where it happens to work.

`HoursCore` is the exception. It also builds on Linux, where the localisation
APIs are not reliably present, so the one string it produces — the reminder
body — branches per count instead. Same plural correctness, no dependency.

**UI tests exist for what unit tests cannot see.** Two hundred of them cover
the arithmetic and not one would notice the app crashing on launch, a store
that refuses to open, or a settings screen that traps. `HoursUITests` launches
the app and checks that the tabs are there, that every settings screen opens
and comes back, and that a day can be opened and saved.

They run against an app told to start from nothing: `-hours-ui-testing` gives
it an in-memory store, default settings and no running clock. Read from the
launch arguments rather than compiled behind `#if DEBUG`, because the build
under test should be the build that ships. Without it a test would read
whatever is on the machine running it, and would write to it.

Elements are matched by accessibility identifier, not by label. The labels are
sentences that will be translated; the identifiers are dates and roles that
will not.

**The screen atlas** (`ScreenAtlasTests`) is a picture of every screen and
state for a design review: the sample month in every tab, each sheet and menu,
every Settings screen, the paywall, each first-run step and tour stop, and the
empty states. It is skipped unless the runner's environment has
`HOURS_SCREEN_ATLAS=1`; `HOURS_ATLAS_ARGUMENTS` adds launch arguments to every
launch. CI runs it alone when the `screen_atlas` input is set, in four passes
(light, dark, accessibility text size, Croatian), and keeps the PNGs as the
`screen-atlas` artifact, `<pass>/atlas-NN-<screen>.png`. It never stops at a
missing element: what it could not reach is listed in one failure at the end.
A new screen gets an identifier on its button (never on a container holding
buttons, which hands it down to them) and a line in the atlas.
