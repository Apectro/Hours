# App Store listing

Draft copy for App Store Connect. Every field Apple asks for, with the length
limit it enforces, so nothing has to be rewritten at the paste stage.

Nothing here is binding — it is a first draft written from what the app
actually does, which is the part that takes the longest. Edit freely.

---

## Name

*30 characters. Shown under the icon, and truncated hard.*

```
Zeitkonto
```

Named after the thing it keeps. *Zeitkonto* is the standard German term for a
working-time account, so in the DACH market it is the word people already have
in their heads rather than a brand they have to learn — and it matches the
domain. It is opaque to a French or Polish user, which is the price of the
choice: the app ships in ten languages, the name is in one.

**Check it is free before anything else.** App Store names are unique across
the store, so reserve it in App Store Connect, and check the DACH trademark
registers while you are at it.

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
Zeitkonto is a work-hours calendar that keeps your hours on your phone.

No account. No sign-up. No server. Nothing about you is collected, and
nothing leaves the device unless you export it or switch on iCloud sync,
which puts your data in your own iCloud and nowhere else.

A CALENDAR FIRST

The main screen is a month, colour-washed by day type, totals underneath.
Tap a day to see it, tap again to edit it. A past working day with nothing
on it gets a quiet dashed outline, so you spot the gap while scanning rather
than on the last day of the month.

HOURS THE WAY YOURS ACTUALLY WORK

• Start and end times, or a figure you type
• An end before the start is an overnight shift, and is measured as one
• Breaks as a length or as clock times, several a day if you need them
• Split shifts, where the gap between two blocks is neither worked nor break
• A contracted week per weekday: 6/6/6/6/8 and four-day weeks are ordinary
• A weekly target overriding the days, for a contract stating 37½ hours
• More than one job, each with its own contracted week
• Vacation, sick leave, public holidays, days off — and your own day types
• Overtime paid out, recorded as a payout rather than a mystery correction
• Every field behind a switch — what you switch off disappears rather than
  sitting greyed out

THE YEAR, AND THE ACCOUNT IT KEEPS

A Zeitkonto has a year boundary. Close a year and the figure it carried is
fixed, so a correction two years later cannot move what was already agreed.
Cap the carry-over if your contract does — paid out or forfeited above it. A
shortfall always carries in full; forgiving one would invent hours nobody
worked.

A month already handed to payroll can be closed to editing, refusing changes
from the day editor, a bulk edit, the clock and Siri alike. Reopening it is
one swipe.

THE BALANCE IS ONE LINE

worked + credited − expected + adjustment

Every day type carries a policy saying how it counts, so the line is right
in every case. Vacation on a Tuesday is zero, credited against what the day
expected; on a Saturday it is zero too, because nothing was expected.

Worked time and paid absence are reported separately, so a month reads
"worked 152 h, paid absence 16 h, expected 168 h, balance 0" rather than
quietly inflating hours nobody worked.

INSIGHTS

Today, this week, this month, this year: worked, expected, balance,
averages, day counts, and a running balance recomputed from your days rather
than stored — so correcting a day from three years ago corrects everything
after it. A period still in progress stops at today, so days yet to come do
not read as a growing deficit.

TIMESHEETS

Export a day, a week, a month, a year or any range, as CSV, Excel or PDF.
Columns are yours to pick and reorder, and the preview is the file. The
sheet's language is its own setting, because whoever reads a timesheet is
often not whoever filled it in.

BUILT NOT TO LOSE YOUR DATA

Days are stored as dates, never timestamps, so crossing a time zone or a
clock change cannot reshape what you recorded. The one question a
clock-change day raises — eight hours or nine — is a setting.

Backup and restore writes plain, readable JSON holding every day you entered:
a file you keep, not a service you trust.

WIDGETS AND SHORTCUTS

Today's hours and this month's balance on the Home Screen and Lock Screen.
Siri and Shortcuts can start and stop the clock.

ZEITKONTO PRO

Recording your hours is free and stays free: the calendar, the day editor,
breaks, overtime, the balance, reminders, and the backup holding everything
you entered. Nothing recorded is held behind a payment — if a subscription
lapses, every figure is still there and the backup still writes.

What is paid for is producing: timesheets as CSV, Excel or PDF; widgets; a
second job; editing a range in one pass; iCloud sync. Monthly, yearly, or
bought outright once — an app with no server behind it should not only be
rentable. No account, no login; a purchase belongs to your Apple Account.
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
https://zeitkonto.app/
```

Written in `web/`, published into `docs/` by `npm run publish`, served by the
same Pages setting as the privacy policy. The domain is attached by
`docs/CNAME`; see `docs/README.md` for the DNS records it needs.

## Privacy Policy URL

*Required.*

```
https://zeitkonto.app/privacy/
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
Zeitkonto is fully functional without paying. Recording hours, the calendar, the
day editor, breaks, overtime, the balance and the JSON backup are all free
and unlimited, and no recorded data is ever withheld behind a purchase.

Zeitkonto Pro unlocks producing timesheets (CSV / Excel / PDF), the widgets, a
second job, bulk range editing and iCloud sync. The paywall is reachable
from Settings > Zeitkonto Pro, and from any of those features.

The purchases can be exercised with a sandbox account. The three products
are:
  app.zeitkonto.pro.monthly   (auto-renewable, group "zeitkonto.pro")
  app.zeitkonto.pro.yearly    (auto-renewable, same group)
  app.zeitkonto.pro.lifetime  (non-consumable)

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

- **Prices.** The numbers in `HoursTests/Hours.storekit` — £1.99 monthly,
  £12.99 yearly, £24.99 outright — were chosen to make the paywall render in
  the simulator, not as a recommendation.
- **A contact email** for the privacy policy, which currently says
  `REPLACE-WITH-YOUR-CONTACT-EMAIL`.
- **Territories.** Worldwide is the default and is usually right.
