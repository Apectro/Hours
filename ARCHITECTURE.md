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
Core/        pure Swift + Foundation. No SwiftUI, no SwiftData, no UIKit.
Data/        SwiftData models, repository, settings store.
Features/    SwiftUI screens, one folder per feature.
```

`Core` is import-clean by rule, not by convention — it is the entire
calculation engine, and it is the only part of the app that has to be right.
It could be lifted into a Swift package unchanged; it lives in the app target
so the test bundle can reach it with `@testable import Hours` and the project
stays a single, openable Xcode project.

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

Worked time and credited absence are reported separately everywhere, so a
month reads "worked 152 h, paid absence 16 h, expected 168 h, balance 0" rather
than silently inflating hours nobody worked.

Day type precedence when nothing is set explicitly: holiday rule → weekly
schedule (0 contracted hours means weekend) → ordinary working day. An explicit
choice on the day always wins.

## Holidays

The app ships with **no** holidays and never guesses a country. Public holidays
differ by nation, region, employer and year; a wrong guess is worse than an
empty list. Rules are user-created and can recur:

- `once` — a single date
- `annual` — same month and day every year, optionally bounded by year
- `nthWeekday` — e.g. the fourth Thursday in November, or the last Monday in May

A 29 February rule simply does not occur in common years rather than being
silently moved. A holiday can be marked "counts as a normal working day", in
which case it keeps its contracted hours and only its name is carried through.

## Persistence

- **SwiftData** for entities: `DayEntry` (unique on `dateKey`) and
  `HolidayRecord`. These are records the user creates, queries and exports.
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

**Validation** happens on the way in (a break can never be negative, times are
clamped to a real time of day, a range that is entered backwards is corrected)
and, where a value is legitimate but suspicious, is surfaced as a non-blocking
`DayWarning` — a half-typed day is a normal state, not an error.

## Navigation

Three tabs: **Calendar**, **Insights**, **Settings**. The calendar is the
primary surface and opens on the current month; tapping a day reveals an inline
summary beneath the grid, and opening it presents the editor as a sheet so the
month never leaves the screen. Export is reachable from the calendar toolbar
and from Settings.

## Export

One `ReportBuilder` produces a `ReportTable` — columns, formatted rows,
totals — and CSV, XLSX and PDF are three renderings of that single table, so
the formats cannot drift apart. Columns are filtered by the feature toggles: a
column for a feature that is switched off is never offered and never emitted.

CSV is RFC 4180 quoted, UTF-8 with an optional BOM (Excel on Windows needs it),
with a configurable field separator, decimal separator, date format and
duration style. XLSX is written directly as an OOXML package with inline
strings — no third-party dependency. PDF is drawn with `UIGraphicsPDFRenderer`
as a real table with a header block and a totals footer.

## Privacy

Everything is on the device. There is no network code in the app at all: no
URLSession, no analytics SDK, no crash reporter, no remote configuration. The
only data that leaves is a file the user explicitly exports through the system
share sheet. iCloud sync is deliberately not enabled; the model is designed so
it could be added later as an opt-in, and the app works identically without it.
