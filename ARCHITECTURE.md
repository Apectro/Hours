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
HoursWidget/    the widget extension.
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

- **SwiftData** for entities: `DayEntry` (one per `dateKey`) and
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

**Uniqueness is a rule, not a constraint.** `dateKey` used to carry
`@Attribute(.unique)`. It does not any more, for two reasons that arrive
together: CloudKit refuses a store with a unique constraint on it, and even with
one, two devices editing the same Tuesday offline produce two rows that CloudKit
merges in without knowing they mean the same day. So `WorkdayRepository` owns
the rule instead — every read that could see duplicates collapses them, keeping
the most recently edited row and deleting the rest, and `reconcileDuplicates()`
runs on every return to the app. Ties break on creation date and then on the
identifier, so every device resolves a tie the same way rather than each
keeping a different row and handing it back to the others forever.

Last edit wins rather than a merge. Hours are not meaningfully mergeable: a
start time from one device and an end time from another would invent a shift
nobody worked.

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

Everything is on the device unless the user says otherwise. There is no
URLSession in the app, no analytics SDK, no crash reporter, no remote
configuration and no third-party code of any kind. Two Apple frameworks make
network calls on its behalf and nothing else does: StoreKit, to ask whether Pro
has been paid for, and — only when the user turns it on — CloudKit. Neither
carries a single recorded hour anywhere we can see. The only data that leaves
deliberately is a file the user exports through the system share sheet.

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

**A cached answer may extend what was paid for, never invent it.** The failure
worth designing against is a paying customer with no signal being told to buy
the app again, so a recent paid entitlement survives a launch that cannot reach
the App Store, for a bounded fortnight. A cached `.free` is worth nothing and is
never consulted.

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

This is groundwork rather than the finished job, and worth being plain about: a
`Text("literal")` localises itself, but the computed summary strings in the
settings screens are `String` values assembled from literals, and each would
need `String(localized:)` before a translator could see it.

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
