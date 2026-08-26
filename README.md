# Hours

[![Build and test](https://github.com/Apectro/Hours/actions/workflows/ci.yml/badge.svg)](https://github.com/Apectro/Hours/actions/workflows/ci.yml)

A private work-hours calendar for iOS. Your hours stay on the device: no
account, no server of ours, no analytics, no third-party code. The only network
call the app makes is to the App Store, to ask whether Hours Pro has been paid
for — and to your own iCloud, if you switch sync on.

- **Requirements:** Xcode 16 or later, iOS 18 or later.
- **Open:** `Hours.xcodeproj`
- **Run:** select the *Hours* scheme and press ⌘R.
- **Test:** ⌘U runs the unit tests and the UI tests.

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
HoursCore/     pure Swift + Foundation: the entire calculation engine
Hours/
  App/         entry point and the tab structure
  Data/        SwiftData models, repository, settings store
  Features/    one folder per screen
HoursShared/   Apple-platform code the app and the widget both need
HoursWidget/   the Home Screen and Lock Screen widgets
HoursTests/    unit tests for the engine, holidays, DST and the exports
HoursUITests/  launch and end-to-end tests, and the App Store screenshots
```

`HoursCore` imports nothing but Foundation. No view calculates anything; screens
read values that are already resolved. `Package.swift` builds that same folder
as a Swift package so CI can compile and test it on Linux — where there is no
UIKit, SwiftUI or SwiftData to accidentally import.

## Widgets

Two of them, in every size iOS offers: **Today** (worked so far, against what
was expected, with the running clock counting up live) and **This month**
(worked against expected, and the balance). Both work on the Lock Screen as
well as the Home Screen.

A widget runs in its own process and cannot open the app's database, so the app
writes a small JSON snapshot into a shared container and the widget reads that.
It is refreshed whenever anything it shows changes — a day saved, the clock
started or stopped, the app closed.

**The shared container needs an App Group, and App Groups need a paid Apple
Developer account.** Nothing else in the app does, so the widgets are the one
part a free account cannot use. They are not wired up by default, precisely so
that a free-account build still installs:

1. Open the project, select the **Hours** target, then Signing & Capabilities.
2. Add the **App Groups** capability and create `group.com.hours.app`.
3. Do the same for the **HoursWidgetExtension** target, ticking the same group.

Nothing else to change; the identifier is already in the code
(`WidgetSnapshotStore.appGroupIdentifier`, if you would rather use a different
one). Until that is done the app behaves exactly as it does now — it notices
the container is missing and writes nothing — and the widgets say so instead of
showing a convincing screenful of zeroes.

Tapping a widget opens the app. There are no buttons on it: an interactive
widget runs its action inside the widget's own process, which cannot reach the
database either, so a "clock in" button there could only pretend to work. Siri
and the Shortcuts app can start and stop the clock instead, and those run in
the app.

## iCloud

Off by default, and the app is designed to be complete without it. Turn it on
in Settings › iCloud and your days and holidays go into **your own** private
iCloud storage, which only your devices can read — no account to make, no
server of ours, nothing that any third party sees. Your settings travel with
them, through iCloud's key-value storage, because a second device computing
expected hours from a different contracted week would produce wrong figures
rather than merely different ones.

A store's iCloud setting is fixed at the moment it opens, so the switch takes
effect the next time the app is opened, and says so rather than pretending
otherwise.

Two devices can each record the same Tuesday while offline, and CloudKit has no
idea the two rows mean the same day — it merges both in. The last one edited
wins and the other is removed the moment the day is next read. Hours are not
meaningfully mergeable: a start time from one device and an end time from
another would invent a shift nobody worked.

**iCloud needs a paid Apple Developer account**, like the widgets. It is not
wired into the entitlements for the same reason, so a free-account build still
installs. To enable it: select the **Hours** target, Signing & Capabilities,
add **iCloud**, tick **CloudKit** and **Key-value storage**, and create the
container `iCloud.com.hours.app`. If the switch is on but the entitlement is
missing, the app opens its local store instead and says so; it never refuses to
start.

Sync is not a backup. A day you delete is deleted everywhere.

## Hours Pro

Recording your hours is free and stays free: the calendar, the day editor,
breaks, overtime, the balance, reminders, and the backup file that holds every
day you ever entered. **Nothing you have recorded is ever held behind a
payment** — if a subscription lapses, every figure is still there and the
backup still writes.

What is paid for is producing and creating: timesheets as CSV, XLSX or PDF; the
widgets; a second job; editing a range in one pass; and iCloud sync. Sold as a
monthly or yearly subscription, or bought outright once — an app with no server
behind it shouldn't only be rentable.

There is **no account and no login**. A purchase belongs to your Apple ID, so it
is already on your other devices; the Restore button exists because the App
Store asks for one, not because you should need it. Payment is handled by the
App Store, and the app is told exactly one thing in return: whether it has been
paid for.

`Hours.storekit` lets the whole thing be exercised in the simulator with no App
Store Connect account and no network — the scheme already points at it, so Buy,
cancel, expire and refund all work locally.

## Putting it on the App Store

Everything here needs an Apple account, so none of it can be done from a
repository. It is written down so that the sequence is not something to work
out under pressure.

**Screenshots are already made for you, at both sizes.** `ScreenshotTests`
drives the app in a simulator with a month of sample data and captures the
calendar, a day, the insights, settings, the privacy screen and the export
sheet. It runs twice — on the largest iPhone the runner has, and again on a
smaller one — and the two sets land in a folder each, named after the
simulator. The larger is the 6.9-inch set App Store Connect asks for; the
smaller is a second size to choose from, not a required one. A true 6.5-inch
device (an iPhone 11 Pro Max) is not installed on the runner image, so if you
specifically need that size it has to be taken by hand. They are attached to the run
as `app-store-screenshots` and pushed to the `screenshots` branch.
The branch is usually the easier one to reach for: artifacts are served from a
storage host that some networks cannot get to at all.

That happens in the full simulator job, which does **not** run on every push:
macOS minutes bill at ten times the Linux rate, so it runs on pull requests and
on demand — Actions › Build and test › Run workflow.

A push runs the Linux engine job, in about a minute, and — only when it touched
something outside `HoursCore`, `Scripts` or the prose — a build-only macOS job
that compiles the app and the test bundles without running them. That second
job exists because moving the full one off pushes left nothing compiling the
app target at all: app-only changes reached `main` green, having never been
through a compiler. Roughly a quarter of the cost of the full job, and skipped
entirely on the engine-only pushes that make up most of the history.

**The rest, in order:**

1. **Apple Developer Program** — $99 a year, at developer.apple.com. Nothing
   below is possible without it, and the widgets and iCloud sync need it too.
2. **Bundle identifier** — replace the `com.hours.app` placeholder with one you
   own, in the Hours target and in `com.hours.app.widget`.
3. **Capabilities** — App Groups (`group.com.hours.app`) on both targets for
   the widgets; iCloud with CloudKit and Key-value storage, and a container, for
   sync. Both are optional: without them the app runs and says so.
4. **Paid Applications agreement** — App Store Connect › Business. Until this is
   signed and your bank and tax details are accepted, purchases fail with no
   useful error, which is a confusing afternoon if you have not been warned.
5. **The three products**, matching `SubscriptionStore.ProductID` exactly:
   - `com.hours.app.pro.monthly` — auto-renewable, group `hours.pro`
   - `com.hours.app.pro.yearly` — auto-renewable, same group
   - `com.hours.app.pro.lifetime` — non-consumable

   Each needs a display name, a description and a price. `Hours.storekit`
   carries placeholders; the real ones live only in App Store Connect.
6. **Privacy nutrition label** — "Data Not Collected", every category. That is
   unusually easy to fill in here because it is true: no analytics, no
   third-party code, no account, and nothing sent anywhere but the user's own
   iCloud if they ask for it.
7. **App Review notes** — say that Hours Pro can be exercised with a sandbox
   account, and that the app is fully functional unpaid. Reviewers reject
   paywalls they cannot get behind.

**One thing worth deciding before you submit:** the prices in `Hours.storekit`
(£1.99 monthly, £12.99 yearly, £24.99 outright) are placeholders chosen to make
the paywall render, not a recommendation.

## Backups

Nothing is synced anywhere, so a backup file is the only copy that survives
losing the device. Settings › Backup and data writes plain, readable JSON
containing every day, every holiday and all your settings, and restores it.
