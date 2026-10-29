# Zeitkonto

[![Build and test](https://github.com/Apectro/Hours/actions/workflows/ci.yml/badge.svg)](https://github.com/Apectro/Hours/actions/workflows/ci.yml)

A private work-hours calendar for iOS. Your hours stay on the device: no
account, no server of ours, no analytics, no third-party code. The only network
call the app makes is to the App Store, to ask whether Zeitkonto Pro has been paid
for — and to your own iCloud, if you switch sync on. Location only if you turn on
an arrival reminder for a site, and it never leaves your phone.

- **Requirements:** Xcode 16 or later, iOS 18 or later.
> **On the two names.** The product is Zeitkonto: that is the display name, the
> bundle identifier, and what every user-facing string says. The Xcode project,
> its targets, the module directories and `Hours.store` still say Hours. Those
> are internal, invisible to anyone using the app, and renaming them means
> churning every file path in the project for no one's benefit. The one that
> would have mattered — the SwiftData store filename — is deliberately
> untouched, because changing it orphans existing data.

- **Open:** `Hours.xcodeproj`
- **Run:** select the *Hours* scheme and press ⌘R.
- **Test:** ⌘U runs the unit tests and the UI tests.

The project uses Xcode's synchronized folder groups, so the file list *is* the
directory tree — adding a Swift file to `Hours/` is all it takes for it to build,
and the project file never drifts out of step with the repository.

Before running on a device, set your signing team in the target's Signing &
Capabilities tab. The bundle identifier is `app.zeitkonto.hours`, and the
widget's is `app.zeitkonto.hours.widget`.

**TestFlight without a Mac.** The *TestFlight* workflow
(`.github/workflows/testflight.yml`, started by hand from the Actions tab)
checks the Apple account first, then signs with fastlane match (certificates
kept encrypted on this repository's `certificates` branch), builds on a
GitHub-hosted Mac and uploads. The build number is the workflow's run number.
It needs the repository secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_CONTENT` and `MATCH_PASSWORD`.

## What it does

**First launch** — three short questions on a fresh install, each skippable:
your name for the sheets you hand in, your working week, and whether your breaks
are paid. Then straight to today's editor or a new site. Anyone updating from an
earlier version is never asked.

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

**Check your payslip** — on Insights' month, type what the payslip says:
hours worked, overtime, sick days and leave (in hours or days), gross pay. Only
what you fill in is compared, each with a ✓ or "Payslip shows 4h less", and a
short note can be shared or copied for payroll in the report language. The row
then says "Checked" or how many figures differ.

**Leave** — set your yearly vacation allowance, when your leave year starts,
and any days carried over (and when they expire) in Settings › Leave. Insights
shows "18 of 25 left · 2 planned", and the day editor says what a vacation day
would leave. A built-in *Time off in lieu* day (Zeitausgleich) spends overtime:
the day's hours come off the balance, and Insights says how many days off the
balance is worth.

**Your year** — from Insights' year view, and once in late December, a
full-screen set of cards: hours, days on sites, the busiest month, the longest
day, the year's balance, leave taken, and earnings when a rate is set. Share
turns it into a picture; nothing about anybody else's hours is in it.

**Sites** — a site's crew is entered once and the day's times once for all of
them. A new site, or a crew screen, offers the people from your other crews to
tick rather than type again. On the 1st, a note per site you worked on last
month says its site sheet is ready for the boss, and opens it.

**Arrival reminder (1.2)** — off unless you turn it on in a site's settings.
After an explanation, it saves where the site is from your current location
(shown as coordinates and a small map, with a radius of 100, 150, 300 or
500 m) and asks for location "Always". Reaching the site with no clock running
then asks "Arrived at Trg Pravde — start the clock?", and leaving it with the
clock running "Left Trg Pravde — stop the clock?"; Start clock and Stop clock
work from the notification, at the time you arrived or left. Never on a day off
or a public holiday, never twice within two hours, at most 20 sites. The
location never leaves the phone.

**Site diary, bad weather and sign-off** — under each site day, a short diary
(Bautagebuch): the weather, a temperature typed by hand, work done, deliveries,
problems and visitors, and up to six photos, stripped of their location. A
"Rained off" button stops the whole crew for bad weather (Schlechtwetter), with
no hours or keeping the hours until the stop, and gives your own day the Bad
weather type. At month end each crew member checks their hours on your phone and
signs with a finger; a signature whose hours change afterwards says so. The
director's sheet can carry the diary and the signatures; in the PDF, a crew too
big for one page is printed a group of people at a time, never with times cut short.

**A sheet for each person (1.2)** — the site export's "One sheet per person"
shares a file per crew member instead of the director's sheet: their own days on
every site they worked that month, in the timesheet's design, with the hours,
days on site and any sick or leave days, and the lines to sign on when Signatures
is on. The share button beside a name on the crew list opens that person's sheet
for this month, to check against a payslip or to sign.

**Extra work** — what the crew did beyond the contract, written down so the
boss knows what is done: "8 emergency lights and 10 lamps". Each job on a site
day has what was done, material with −/+ steppers (or a typed 12.5 m), the items
used before offered as chips, optionally how long the job took and who was on
it ("1h · Marijo, Dusko" — one time for the job, never added up), photos and
the client's optional finger signature. A job can run over several days: it is *in
progress* until you tick it *finished* — the checkmark beside it, a long press,
or "Work finished" in the editor — and the site's jobs still in progress are
listed at the top of its report. The site's Report button tells the boss what
is done — finished jobs not sent yet, this week or picked dates, and those still
in progress only if you include them, in a section of their own — with the
material used after the work, an optional signature under the lot, and sends a
PDF (or the same report as one tall picture for WhatsApp and other chats, or a
workbook, or a CSV) in the export language; the jobs are marked sent to the boss
once the share goes through. An optional weekly reminder (off by default,
Friday 15:00) says when finished jobs have not been sent yet. It is a progress report, not a bill:
quantities only, never a price, and no lines to fill in.

**Earnings** — set an hourly rate in Settings › Pay and the app leads with what
you earned rather than the hours balance: overtime at the same rate or with a
surcharge after your normal day or your week, Saturday, Sunday and holiday and
night surcharges, and paid days off at the rate. A raise starts from a date, so
the months before it keep the rate they were worked at. The balance is a setting
away, and money never appears on a site, its sheet or anywhere about your crew.

**Field allowance and travel** — off by default. Switched on in Settings ›
Allowance & travel, with your allowance per day and rate per kilometre, a day
gets a field allowance switch (Auslöse, terenski dodatak), kilometres in your
own car and travel time, which counts as work only if you say so. A site can
give the allowance to everyone ticked in, taken off one person from their
row's menu, and has the van's kilometres for the day; your share reaches
your own day without touching what you typed there. The month's summary,
Insights and your timesheet list the days, kilometres and travel, and what
they come to as lines of their own; the site sheet counts allowance days and
kilometres, never money. Amounts and tax-free limits depend on your contract
and your country.

**Welcome and tour** — a fresh install asks a few questions once, each one
skippable: your name for the sheets, your week, paid breaks, where you work,
the language of the reports for your boss (preselected from the country), whether
you lead a crew, and optionally your hourly rate. "Show me around" then walks
through the app in six stops — a dimmed screen with the real control lit up —
and Settings › Show the tour again brings it back. It is never shown to anyone
on its own.

**Settings** — the contracted week (hours per weekday, not one number for all of
them), pay, calculation rules, which fields exist, day types, holidays, calendar
appearance, theme, export options, and backup.

**Public holidays** — never guessed, but one tap away: Settings › Holidays ›
Add public holidays (or the first-run setup, or a one-time card on the
calendar) → country → state or canton where it matters → the list with next
dates → Add. Germany (all 16 states), Austria, Switzerland (12 cantons and the
days all cantons share), Croatia, Slovenia, Italy, France, Spain (national),
Portugal, the Netherlands and Poland, from tables inside the app — nothing is
looked up online. They become ordinary holidays you can edit, switch off or
remove again as a set. On a public holiday, "I worked" opens the day with your
usual times: the holiday stays paid and every hour worked comes on top.

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
- Two hours worked on a public holiday → +2 h (the holiday's 8 h are still
  credited, and the Sunday & holiday surcharge applies to the 2 h)
- Time off in lieu on a Tuesday → nothing worked, 8 h expected → −8 h

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

Earnings are whole cents worked out from whole minutes: each worked minute pays
the rate, plus every surcharge that covers it added together, so an hour of
overtime on a Sunday night pays the rate and the overtime, Sunday and night
percentages. A day is rounded to the cent once, and a month is exactly the sum of
its days. Money is never a floating-point number anywhere in the app.

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
HoursWidget/   the Home Screen and Lock Screen widgets, and the controls
HoursWatch/    the Apple Watch app
HoursWatchWidget/  its watch face complications
HoursWatchShared/  what those two share, and their string catalogue
HoursTests/    unit tests for the engine, holidays, DST and the exports
HoursUITests/  launch and end-to-end tests, and the App Store screenshots
```

`HoursCore` imports nothing but Foundation. No view calculates anything; screens
read values that are already resolved. `Package.swift` builds that same folder
as a Swift package so CI can compile and test it on Linux — where there is no
UIKit, SwiftUI or SwiftData to accidentally import.

## Widgets

Four of them, drawn in the app icon's navy and amber:

- **Today** (small and medium): worked so far against what was expected, in an
  amber ring, with the running clock, its site or job, and when the day is due
  to end — and, with a rate set, what today has earned.
- **This month** (small and medium): what the month has earned, or the balance,
  ahead of or behind plan, and a square for each working day of the month —
  done, short, today, to come.
- **This week** (medium): the week's total against its target, and a bar for
  each day starting on your own first weekday, with the week's earnings or the
  month's balance beneath.
- **Site** (medium): the site you worked on most recently, whether today is
  written yet, who was there on the last day, and two buttons — **Same as
  yesterday** and **Open site**.

Today and This month also work on the Lock Screen, with the clock mark. All
of them follow the tinted and clear Home Screen styles.

While the clock runs, a **Live Activity** shows it on the Lock Screen and in the
Dynamic Island, ticking by itself, with a button that stops it.

A widget runs in its own process and cannot open the app's database, so the app
writes a small JSON snapshot into a shared container and the widget reads that.
It is refreshed whenever anything it shows changes — a day or a site day saved,
the clock started or stopped, the app closed — and every figure in it comes
from the engine the app itself uses, so a widget can never disagree with the
calendar.

**The shared container is an App Group, `group.app.zeitkonto`, and App Groups
need a paid Apple Developer account.** Both targets carry it in their
entitlements (`Hours.entitlements`, `HoursWidget.entitlements`, at the root so
Xcode's synchronised folders do not copy them into the bundle), so the group
has to exist in the developer account before a signed build will go through:

1. developer.apple.com › Certificates, Identifiers & Profiles › Identifiers ›
   **+** › App Groups, identifier `group.app.zeitkonto`.
2. Open the identifiers `app.zeitkonto.hours` and `app.zeitkonto.hours.widget`,
   tick **App Groups**, configure, tick the group, save.

The TestFlight workflow's preflight checks this and says so in plain words if
it is missing, and it makes new signing profiles by itself the first time they
lack the group. A free-account build has to drop the two entitlements files
from the targets' build settings. If the container is ever missing at run time,
the app writes nothing and the widgets say so instead of showing a convincing
screenful of zeroes.

Tapping a widget opens the app. The site widget's buttons are links that open
it at the site (`zeitkonto://site/<id>`, and `…/same-as-last` to fill today from
the last day), because a widget runs in its own process and cannot write the
database; the app does the work, under the same month lock as the button on the
site screen. The Live Activity's stop button is different: it is a
`LiveActivityIntent`, which iOS runs in the app's own process, so it records the
shift exactly as the clock card would. Siri and the Shortcuts app can start and
stop the clock as well. The widgets and the Live Activity are both part of Pro.

**Controls** (iOS 18) put three of these in Control Center, on the Lock Screen
and on the Action Button: **Clock in and out**, a toggle that is on while the
clock runs and records the shift like the Live Activity's button does; **Same
as yesterday**, which opens the site widget's link for the most recent site;
and **Write today**, which opens today's day editor (`zeitkonto://today`). The
same three are App Shortcuts — *Clock in or out*, *Same as yesterday*, *Write
today* — so the Action Button can run one without a control.

## Apple Watch

A small watchOS 11 app: today's hours against what was expected ("6:42 of
8:00"), the month's balance or earnings beneath, as the app's main figure has
it, and one big **Clock in** / **Clock out** button with the site or job and a
live timer while it runs. Complications for the circular, rectangular, inline
and corner slots show today's hours and whether the clock is running.

The watch records nothing itself. The phone sends it the widgets' snapshot over
WatchConnectivity every time it writes one, and the watch asks the phone to
clock in or out; the phone does it with the same clock as everything else.
When the phone is out of reach the tap is queued, shown on the watch at once,
and recorded at the time it was tapped once the two meet again. Nothing goes
through a server: WatchConnectivity is the phone and the watch talking
directly.

The watch app (`app.zeitkonto.hours.watchkitapp`) and its complications
(`…watchkitapp.complications`) carry the same App Group, on the watch, for the
complications to read what the app last heard; tick it on both identifiers as
above. The iPhone app embeds the watch app, so the *Hours* scheme, CI and the
TestFlight workflow build it too; the TestFlight preflight registers the two
identifiers itself, and match makes their profiles. They also build on their
own with the *HoursWatch* scheme.

## iCloud

Off by default, and the app is designed to be complete without it. Turn it on
in Settings › iCloud and your days, holidays, sites, crews, site diaries and
signatures go into **your own** private iCloud database, which only your
devices can read — no account to make, no server of ours, nothing that any
third party sees. Your settings travel with them, through iCloud's key-value
storage, because a second device computing expected hours from a different
contracted week would produce wrong figures rather than merely different ones.

A store's iCloud setting is fixed at the moment it opens, so the switch takes
effect the next time the app is opened, and says so rather than pretending
otherwise. Turning it on mirrors the store already on the phone — the same
file — so months of hours go up with it; a second device's own days merge in.

Two devices can each record the same Tuesday while offline, and CloudKit has no
idea the two rows mean the same day — it merges both in. The last one edited
wins and the other is removed the moment the day is next read, or as soon as
the import lands. Hours are not meaningfully mergeable: a start time from one
device and an end time from another would invent a shift nobody worked. The
same holiday added separately on two devices collapses to one.

**It can never stop the app from opening.** 1.0 in TestFlight crashed at every
launch once sync was on, because that build was not signed for iCloud. Now the
app reads its own code signature before it opens anything, and a build without
the iCloud entitlement keeps sync off and says why in Settings › iCloud; a
launch that dies while connecting is not repeated; and a store that refuses
falls back to the phone's own. See ARCHITECTURE.md, *Persistence*.

**Setting it up needs a paid Apple Developer account**, once, in this order:

1. developer.apple.com › Certificates, Identifiers & Profiles › Identifiers ›
   **+** › **iCloud Containers**: description *Zeitkonto*, identifier
   `iCloud.app.zeitkonto`.
2. Open the identifier `app.zeitkonto.hours`: tick **iCloud** (*Include
   CloudKit support*), **Configure**, tick `iCloud.app.zeitkonto`; tick **Push
   Notifications** (no certificate needed). Save, and confirm the dialog about
   profiles. (The TestFlight preflight switches iCloud and Push on by itself if
   it can; only the container needs the website.)
3. Run *TestFlight* with **CloudKit development** ticked. It makes new signing
   profiles by itself, and stops before building, with these steps, if the
   profile still lacks the container. Install that build, open Settings ›
   iCloud and tap **Initialise the CloudKit schema (Development)** once. (With a
   Mac instead: run the Debug build from Xcode with the launch argument
   `-hours-initialize-cloudkit-schema`.)
4. icloud.developer.apple.com › CloudKit Console › `iCloud.app.zeitkonto` ›
   Schema: the `CD_…` record types are in Development. **Deploy Schema
   Changes…** to Production.
5. Run *TestFlight* again **without** CloudKit development: that is the build
   for testers and App Review. Never submit a CloudKit development build.

Steps 3 and 4 are needed again whenever a release adds columns to the store:
1.2's schema V8 (field allowance, kilometres, travel and the site's arrival
fields) does, so it must be initialised and deployed to Production before 1.2
ships, or a syncing 1.2 device cannot upload what it records.

Until step 4, sync in a TestFlight build opens but uploads nothing, and
Settings › iCloud shows CloudKit's error; repeat steps 3–4 whenever a new
schema version adds or changes stored models. (Schema V6, in 1.1, adds whether an extra-work
job is done — `isDone` and `doneAt` — and V7 why crew members were away on a site day —
`SiteDayEntry.absenceData` — so steps 3–4 are needed again before a 1.1 build syncs them.) A simulator or free-account build
is not signed for iCloud: the row is there, switched off, and says why.

Sync is not a backup. A day you delete is deleted everywhere.

## Zeitkonto Pro

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

The listing, the screenshots and the Pro products are uploaded from this
repository; what is left needs a person in App Store Connect.

**The listing** is `fastlane/metadata/`, in English (U.S.) and German — name,
subtitle, description, keywords, URLs, categories, review notes, and the age
rating in `fastlane/age-rating.json`. `notes/app-store-listing.md` explains it,
and CI fails when a field is over the store's limit.

**Screenshots are made for you.** `ScreenshotTests` drives the app with a
sample month — a site with a crew of five, a month of site days with extra
work on them, a pay rate — and takes eight shots: the calendar with the
month's earnings, a site, the day's extra work, the report to the boss, the
director's sheet, the day editor, Insights and Privacy. The full simulator
job takes them on the largest iPhone the runner has (the 6.9-inch slot), in
English and German, and lays the set out for upload under `app-store/` on the
`screenshots` branch. The Apple Watch shots come from the same job: the watch
app launched on an Apple Watch simulator with sample data, once per line of
`fastlane/watch-screenshots.txt`. The app is iPhone-only, so no iPad set is
needed.

For a design review, run the workflow by hand with **screen_atlas** ticked:
`ScreenAtlasTests` photographs every screen and state, in light, dark, the
largest text size and Croatian, into the `screen-atlas` artifact. Nothing
else runs in that mode.

`fastlane/screenshots.txt` names the version the set is for (`# listing for
version 1.1`), and the *App Store* workflow uploads a set only when that
matches the project's `MARKETING_VERSION`. The 1.1 listing text waits in
`notes/listing-1.1/` while 1.0 is in review; its README says how to switch.

That happens in the full simulator job, which does **not** run on every push:
macOS minutes bill at ten times the Linux rate, so it runs on pull requests and
on demand — Actions › Build and test › Run workflow, on `main` (only a run on
`main` updates the branch).

A push runs the Linux engine job, in about a minute, and — only when it touched
something outside `HoursCore`, `Scripts`, the listing or the prose — a
build-only macOS job that compiles the app and the test bundles without
running them. That second job exists because moving the full one off pushes
left nothing compiling the app target at all.

**Uploading.** Actions › *App Store* › Run workflow, with `what`:

- `listing` — the metadata and the latest screenshots from the branch. Nothing
  is submitted and no build is uploaded.
- `products` — the subscription group (*Hours Pro*, shown as *Zeitkonto Pro*),
  the two subscriptions and the lifetime purchase, with names and descriptions
  in both languages and their prices: €2.99 a month, €19.99 a year, €39.99
  outright, set in Germany and equalized by Apple everywhere else. Whatever
  exists is skipped, so it is safe to run again.
- `both`.

It uses the same `ASC_*` secrets as TestFlight; the key needs the Admin or App
Manager role to create products.

**Still by hand, in order:**

1. **Apple Developer Program** — $99 a year. Nothing here works without it.
2. **Bundle identifiers, App Group and iCloud** — see *Widgets* and *iCloud*
   above; the TestFlight preflight checks them.
3. **Paid Applications agreement** — App Store Connect › Business. Until it is
   signed and the bank and tax details are accepted, purchases fail with no
   useful error.
4. **App Privacy** — "Data Not Collected". True here: no analytics, no
   third-party code, no account, nothing sent to us or anyone else; sync goes to
   the user's own private iCloud, which Apple does not count as collection by
   the developer. The 1.2 arrival reminder uses location on the device only
   and keeps nothing but the site's saved place (`notes/listing-1.2/privacy.md`).
5. **App Review contact** — name, phone and email under App Review
   Information. Deliberately not in this repository.
6. **A review screenshot for each product** — a picture of the paywall, on each
   of the three products' pages.
7. **The build** — run TestFlight with *Unlock Pro for testers* **off**, pick
   that build on the version page, and add the three products to the version
   (the first in-app purchases have to be submitted with an app version).
8. **Apple Watch screenshots** — a build that carries a watch app cannot be
   submitted without at least one, on the version page under Apple Watch.
   CI takes two from 1.1 on (above) and the `listing` upload sends them; the
   1.0 version page needs them by hand.
9. **The owner's name** in `fastlane/metadata/copyright.txt`, and the contact
   email on the privacy and support pages (`notes/app-store-listing.md` says
   where).

`Hours.storekit`'s prices (£1.99, £12.99, £24.99) are only for the simulator;
the real ones are the ones above, and live in App Store Connect.

## Backups

Unless sync is on, nothing is kept anywhere else, so a backup file is the only
copy that survives losing the device — and even with sync on, it is the only
copy a deletion cannot reach. Settings › Backup and data writes plain, readable JSON
containing every day, every holiday and all your settings, and restores it.
