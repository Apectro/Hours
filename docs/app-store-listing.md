# App Store listing

Draft copy for App Store Connect. Every field Apple asks for, with the length
limit it enforces, so nothing has to be rewritten at the paste stage.

Nothing here is binding — it is a first draft written from what the app
actually does, which is the part that takes the longest. Edit freely.

---

## Name

*30 characters. Shown under the icon, and truncated hard.*

```
Hours
```

`Hours` alone is almost certainly taken. If it is, keep the first word short
and specific rather than descriptive — `Hours Timesheet` reads as a category,
`Hours Worked` reads as a feature. Candidates that stay short:

```
Hours — Work Log
Hours Timesheet
```

## Subtitle

*30 characters. Sits under the name in search results and does most of the work.*

```
Your hours, on your phone
```

Alternatives, depending on what you want to lead with:

```
Private work-hours calendar     (29)
Track hours. No account.        (24)
A calendar for your hours       (25)
```

## Promotional text

*170 characters. Can be changed without submitting an update — useful for
saying what is new without waiting for review.*

```
No account, no server, no analytics. Your hours stay on your phone. A calendar first: see the month, tap a day, done. Free to record; pay only to export.
```

## Description

*4,000 characters. The first three lines are all most people read before
tapping "more".*

```
Hours is a work-hours calendar that keeps your hours on your phone.

No account. No sign-up. No server. Nothing about you is collected, and
nothing leaves the device unless you export it or switch on iCloud sync —
which puts your data in your own iCloud and nowhere else.

A CALENDAR FIRST

The main screen is a month, colour-washed by day type, with your totals for
the period underneath. Tap a day to see it, tap again to edit it. A working
day in the past with nothing recorded gets a quiet dashed outline, so gaps
are obvious when you scan a month rather than something you find out about
at the end of it.

HOURS THE WAY YOURS ACTUALLY WORK

• Start and end times, or a figure you type — whichever suits you
• An end time before the start is an overnight shift, and is measured as one
• Breaks as a length or as clock times, several a day if you need them
• Split shifts: a morning and an evening are two blocks, and the gap between
  them is neither worked nor a break
• A contracted week set per weekday, not one number for all of them — a
  6/6/6/6/8 week and a four-day week are ordinary, not special cases
• A weekly target that overrides the days, for a contract stating 37½ hours
• More than one job, each with its own contracted week
• Vacation, sick leave, public holidays, days off — and your own day types
• A manual adjustment that moves your balance without inventing hours
• Overtime paid out, recorded as a payout rather than a mystery correction

THE BALANCE IS ONE LINE

worked + credited − expected + adjustment

Every day type carries a policy saying how it counts, so the same line is
right in every case. Eight hours on an eight-hour day is zero. Vacation on a
Tuesday is zero — the day is credited against what it expected. Vacation on
a Saturday is zero, because nothing was expected. Two hours on a public
holiday is plus two.

Worked time and paid absence are always reported separately, so a month
reads "worked 152 h, paid absence 16 h, expected 168 h, balance 0" rather
than quietly inflating hours nobody worked.

INSIGHTS

Today, this week, this month, this year: worked, expected, balance,
averages, day counts, and a running balance that is recomputed from your
days every time rather than stored — so correcting a day from three years
ago corrects everything after it.

Totals for a period still in progress stop at today, so the days still to
come this month do not read as a growing deficit.

TIMESHEETS

Export a day, a week, a month, a year or any range you choose, as CSV, Excel
or PDF. Columns are yours to pick and reorder, and you see the exact table
before you share it.

EVERYTHING IS A SETTING

Breaks, notes, locations, tags, overtime, holidays, the clock, the weekend —
every field is behind a switch, and anything you switch off disappears
rather than sitting greyed out. An app for recording eight hours a day
should not make you scroll past nine fields you never use.

BUILT NOT TO LOSE YOUR DATA

Days are stored as dates and times, never as timestamps, so crossing a time
zone or a daylight-saving change cannot move or reshape what you recorded.
The one thing that genuinely needs an answer on a clock-change day — how
long the shift lasted — is a setting: wall clock, or actual elapsed time.

Backup and restore writes plain, readable JSON containing every day you have
ever entered. It is a file you keep, not a service you trust.

WIDGETS AND SHORTCUTS

Today's hours and this month's balance on the Home Screen and the Lock
Screen. Siri and the Shortcuts app can start and stop the clock.

HOURS PRO

Recording your hours is free and stays free: the calendar, the day editor,
breaks, overtime, the balance, reminders, and the backup file that holds
everything you ever entered. Nothing you have recorded is ever held behind a
payment — if a subscription lapses, every figure is still there and the
backup still writes.

What is paid for is producing and creating: timesheets as CSV, Excel or PDF;
the widgets; a second job; editing a range in one pass; and iCloud sync.
Monthly, yearly, or bought outright once — an app with no server behind it
should not only be rentable.

There is no account and no login. A purchase belongs to your Apple Account,
so it is already on your other devices.
```

## Keywords

*100 characters total, comma-separated, no spaces after commas. Do not repeat
words already in the name or subtitle — Apple indexes those anyway.*

```
timesheet,overtime,shift,work,tracker,clock,payroll,flexitime,rota,attendance,freelance,invoice
```

That is 94 characters. Swap in whatever matches your market — `flexitime` and
`rota` are British; `PTO` and `punch clock` are American.

## Support URL

*Required. A page that exists is enough; it does not have to be elaborate.*

```
https://github.com/Apectro/Hours
```

If the repository goes private this has to become something else, and Pages
would stop serving on a free plan at the same moment, so the privacy policy
would need rehoming too. Plan for both together or keep the repository public.

## Marketing URL

*Optional, and worth filling in now that there is a page behind it.*

```
https://apectro.github.io/Hours/
```

Written in `web/`, published into `docs/` by `npm run publish`, served by the
same Pages setting as the privacy policy.

## Privacy Policy URL

*Required.*

```
https://apectro.github.io/Hours/privacy/
```

`docs/privacy/index.html` in this repository is the page. See
`docs/README.md` for turning Pages on.

## Age rating

`4+`. Nothing in the app triggers a higher rating: no user-generated content
that is shared, no web view, no links out except the App Store, no gambling,
no contests.

## Category

Primary: **Productivity** — already set in the project as
`public.app-category.productivity`.

Secondary: **Business**.

## App Review notes

*Not shown to users. Reviewers reject paywalls they cannot get behind, so say
plainly that they do not need to.*

```
Hours is fully functional without paying. Recording hours, the calendar, the
day editor, breaks, overtime, the balance and the JSON backup are all free
and unlimited, and no recorded data is ever withheld behind a purchase.

Hours Pro unlocks producing timesheets (CSV / Excel / PDF), the widgets, a
second job, bulk range editing and iCloud sync. The paywall is reachable
from Settings > Hours Pro, and from any of those features.

The purchases can be exercised with a sandbox account. The three products
are:
  com.hours.app.pro.monthly   (auto-renewable, group "hours.pro")
  com.hours.app.pro.yearly    (auto-renewable, same group)
  com.hours.app.pro.lifetime  (non-consumable)

The app has no account and no login. It makes no network requests other than
to the App Store, and to the user's own iCloud if they switch sync on. There
is no analytics, no tracking and no third-party code.

The optional "location" field on a day is a text note the user types. The app
never requests location permission and links no location framework.

No demo account is needed, as there is nothing to sign in to.
```

## Version release notes

*For 1.0.*

```
The first version.
```

---

## What still needs a decision

- **The name**, if `Hours` is taken.
- **Prices.** The numbers in `HoursTests/Hours.storekit` — £1.99 monthly,
  £12.99 yearly, £24.99 outright — were chosen to make the paywall render in
  the simulator, not as a recommendation.
- **A contact email** for the privacy policy, which currently says
  `REPLACE-WITH-YOUR-CONTACT-EMAIL`.
- **Territories.** Worldwide is the default and is usually right.
