# Hours

A private work-hours calendar for iOS. Everything stays on the device: no
account, no server, no analytics, no third-party code, and no networking of any
kind in the app.

- **Requirements:** Xcode 16 or later, iOS 18 or later.
- **Open:** `ios/Hours/Hours.xcodeproj`
- **Run:** select the *Hours* scheme and press ⌘R.
- **Test:** ⌘U runs the unit tests.

The project uses Xcode's synchronized folder groups, so the file list *is* the
directory tree — adding a Swift file to `Hours/` is all it takes for it to build,
and the project file never drifts out of step with the repository.

Before running on a device, set your own bundle identifier and signing team in
the target's Signing & Capabilities tab. The placeholder is `com.hours.app`.

## What it does

**Calendar** — the main screen. A month or week grid, colour-washed by day type,
with the totals for the period underneath and the selected day summarised inline.
A working day in the past with nothing recorded gets a quiet dashed outline, so
gaps are obvious when you scan a month.

**Day editor** — start and end times (an end before the start is an overnight
shift), breaks as a length or as clock times, per-day expected hours, a manual
adjustment that moves the balance without touching the hours, notes, location and
tags. Every field is behind a setting; anything you switch off disappears rather
than sitting greyed out.

**Insights** — today, this week, this month, this year: worked, expected,
balance, averages, day counts, and a running balance that is always recomputed
from the days rather than stored.

**Settings** — the contracted week (hours per weekday, not one number for all of
them), calculation rules, which fields exist, day types, holidays, calendar
appearance, theme, export options, and backup.

**Export** — CSV, XLSX and PDF, for a day, week, month, year or any custom range,
with a preview of the exact table before you share it. Columns are configurable
and reorderable.

## How the numbers work

Every day type carries a policy that says how it counts, which makes the balance
a single line that is correct in every case:

```
balance = (worked + credited) − expected + adjustment
```

- 8 h worked on an 8 h day → 0
- 08:00–18:00 less a 30 min break on an 8 h day → +1 h 30 m
- Vacation on a Tuesday → 8 h credited against 8 h expected → 0
- Vacation on a Saturday → nothing expected, nothing credited → 0
- Two hours worked on a public holiday → +2 h

Worked time and credited paid absence are always reported separately, so a month
reads "worked 152 h, paid absence 16 h, expected 168 h, balance 0" rather than
quietly inflating hours nobody worked.

Days are stored as `yyyyMMdd` integers and times as minutes since local midnight,
never as `Date`s. Crossing a time zone, a daylight-saving change, or editing a day
from three years ago therefore cannot move or reshape stored data. The one thing
that *does* need an answer on clock-change days — how long a shift lasted — is a
setting: wall clock (the default) or actual elapsed time.

Totals for a period in progress stop at today, so the days still to come in this
month do not read as a growing deficit. A future day you deliberately recorded —
booked leave, a shift entered in advance — still counts.

`ARCHITECTURE.md` covers the layering, the data model, the migration strategy and
the reasoning behind each decision.

## Layout

```
Hours/
  App/         entry point and the tab structure
  Core/        pure Swift + Foundation: the entire calculation engine
  Data/        SwiftData models, repository, settings store
  Features/    one folder per screen
HoursTests/    unit tests for the engine, holidays, DST and the exports
```

`Core` imports nothing but Foundation. No view calculates anything; screens read
values that are already resolved.

## Backups

Nothing is synced anywhere, so a backup file is the only copy that survives
losing the device. Settings › Backup and data writes plain, readable JSON
containing every day, every holiday and all your settings, and restores it.
