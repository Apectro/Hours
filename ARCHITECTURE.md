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
- `@Attribute(.unique)` on the date key makes duplicate entries impossible at
  the storage layer rather than by convention.

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
paid absence earns its credited hours at the rate, with no surcharge. With
several jobs each shift is paid by its own job, and credited hours split as
`jobTotals` splits them.

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
  `CrewSignatureEntry` (one per site, person and month). These are records
  the user creates, queries and exports.
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

**Schema versions.** `HoursMigrationPlan` walks V1 → V2 → V3 → V4, every
stage lightweight. The live classes are always the newest version; the moment
a new version is added, the previous one gets frozen copies of the classes
column for column (V2 and V3 hold theirs), because a version must keep
describing exactly what stores written by it hold. V4 (1.1) adds
`SiteDayEntry.isBadWeatherStop` with a default, and the three diary entities
with a default on every property. Diary photos are `@Attribute(.externalStorage)`
JPEGs: the database file stays small, a fetch of the rows (the month grid's
marks) never reads an image, and with sync on they travel as CloudKit assets.

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
in the backup JSON (`diaries`, `diaryPhotos`, `signatures`). The format version
stays 1: they are additions 1.0 skips without complaint, where a new version
number would make 1.0 refuse the whole file. Photos go in as base64 inside the
one file, so a backup is still a single file through a single door. The price
is size: a stored photo is about 200–500 KB, a third more as base64, so a month
with three photos on twenty days adds roughly 15–30 MB. A file that carries the
lists replaces what is on the device; a file from before them keeps the
device's diary for the sites it restores and drops it for sites it removes
(`BackupArchive.restoredItems`). Deleting everything takes the diary with the
sites.

**Validation** happens on the way in (a break can never be negative, times are
clamped to a real time of day, a range that is entered backwards is corrected)
and, where a value is legitimate but suspicious, is surfaced as a non-blocking
`DayWarning` — a half-typed day is a normal state, not an error.

## Navigation

Four tabs: **Calendar**, **Sites**, **Insights**, **Settings**. The calendar is the
primary surface and opens on the current month; tapping a day reveals an inline
summary beneath the grid, and opening it presents the editor as a sheet so the
month never leaves the screen. Sites lists each active job site with its crew
and this month's figures, and leads to the site and its crew list. Export is
reachable from the calendar toolbar and from Settings.

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

**A widget cannot write, so its buttons are links.** The store lives in the
app's own container, not the shared one. "Same as yesterday" on the site
widget is `zeitkonto://site/<id>/same-as-last`; the app follows it by pushing a
`SiteRoute` value onto the Sites tab's path, and the site screen then does what
its own "Same as last day" button does, only where that button is offered.
`AppLink` in the engine is the one spelling of these links for both sides. The
scheme is the one thing in `Hours-Info.plist`, because a URL type has no
build-setting form and the rest of the app's Info.plist is generated.

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

## Reminders and the links they open

Three kinds of local notification, each planned in the engine and scheduled by
`ReminderScheduler`, under its own identifier prefix so each can be replaced
without touching the others: the weekly gap reminder (`GapFinder`), the evening
site reminder (`SiteReminderPlan`), and the note on the 1st that a site's sheet
is ready for the director (`MonthlySheetReminderPlan`). None of them asks for
permission until its switch is turned on; the two site ones are on by default
and simply schedule nothing while notifications are not allowed.

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

A fresh install asks three questions once (`FirstRunSetupView`): a name for the
sheets, the working week, whether breaks are paid. Each answer is written as
you continue past it, through the same helpers the settings screens use
(`setPrimarySchedule`, `setPrimaryBreaksArePaid`), so skipping half-way keeps
what was answered, and continuing without changing anything leaves the
defaults exactly as they were.

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

**Crew sign-off.** Each person reads their month on your phone and signs with a
finger. A `CrewSignature` stores the strokes as points (sharp at any size, and a
few hundred numbers in a backup) and a fingerprint of that person's hours at the
moment of signing (`SignatureFingerprint`, FNV-1a over their days' start, end,
break and minutes — Linux-safe and stable across devices). When the hours change
afterwards the fingerprint no longer matches and the sign-off and the sheet say
"changed after signing". Signing again replaces the old signature.

## Export

One `ReportBuilder` produces a `ReportTable` — columns, formatted rows,
totals — and CSV, XLSX and PDF are three renderings of that single table, so
the formats cannot drift apart. Columns are filtered by the feature toggles: a
column for a feature that is switched off is never offered and never emitted.

A director's sheet can carry the site diary and the crew's sign-off. In the PDF
they are pages of their own after the table (`PDFAppendix`), laid out before
drawing so the footer's page count includes them; with nobody signed and no
diary included the sheet prints exactly as before. Diary photos are drawn from
small JPEGs (900 px) so the PDF keeps the compressed bytes instead of every
pixel. In the workbook the diary is a second sheet, a row per day. The CSV
stays one table, which is what a CSV importer expects: no diary there.

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
carries a single recorded hour anywhere we can see. The only data that leaves
deliberately is a file the user exports through the system share sheet.

The Apple Watch app does not change that: WatchConnectivity carries the
snapshot from the phone to the user's own paired watch directly, with no
account and no server, and the watch keeps it on the watch.

iCloud sync is off by default and opt-in. When it is on, the days and holidays
go through SwiftData's own CloudKit mirroring into the user's private database,
and the settings blob through `NSUbiquitousKeyValueStore` — settings are not in
the SwiftData store, and a second device computing expected hours from a
different contracted week would be wrong rather than merely different. Both are
the user's own iCloud; neither we nor anyone else can read them.

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
coordinates out: the app does not access location, and keeping it in a picture
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
