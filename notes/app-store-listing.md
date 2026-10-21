> **The first release is free, with everything unlocked and nothing sold**
> (`HoursCore/Settings/FreeLaunch.swift`, `paymentsEnabled = false`). Don't run
> the `products` lane, don't attach in-app purchases to the version, and no
> Paid Apps agreement is needed yet. To start selling: sign the agreement, run
> the App Store workflow with `products`, flip the constant, restore the Pro
> section of the description, the website's pricing and the support/privacy
> wording, and ship a build — deciding first what early free users keep.

# App Store listing

The listing itself is **`fastlane/metadata/`**: every field App Store Connect
asks for, in English (U.S.) and German, as the files `fastlane deliver`
uploads. This page is the reasoning behind them and the parts no file can
hold. Edit the copy there, not here — the *App Store* workflow uploads those
files as they stand, and `Scripts/check-store-metadata.py` fails CI when a
field is over the store's limit.

| Field | File (per language) | Limit |
|---|---|---|
| Name | `name.txt` | 30 characters |
| Subtitle | `subtitle.txt` | 30 characters |
| Promotional text | `promotional_text.txt` | 170 characters, changeable without review |
| Description | `description.txt` | 4,000 characters |
| Keywords | `keywords.txt` | 100 bytes, commas, no spaces |
| What's new | `release_notes.txt` | 4,000 characters |
| Support URL | `support_url.txt` | `https://zeitkonto.app/support/` (`/support/de/`) |
| Marketing URL | `marketing_url.txt` | `https://zeitkonto.app/` (`/de/`) |
| Privacy policy | `privacy_url.txt` | `https://zeitkonto.app/privacy/` (`/privacy/de/`) |

Once for the app: `copyright.txt`, `primary_category.txt` (Productivity),
`secondary_category.txt` (Business), `review_information/notes.txt`, and the
age rating in `fastlane/age-rating.json` (4+, every question "none").

## Who it is written for

The person who runs a site — a foreman, a Polier, a supervisor with a crew of
four or five — and has to hand the director a sheet at the end of the month.
That is what the app does better than any general hours tracker: one entry for
the whole crew, "Same as last day", the site's month, and the monthly sheet,
with a reminder on the 1st. The listing leads with it, then earnings (the
reason to open the app on a day nothing went wrong), then the calendar and the
balance for everyone else. The privacy story stays in the second paragraph:
no account, no server, nothing leaves the phone unless exported.

**Earnings are private.** The copy says so in both languages, because a
supervisor showing the crew's sheet must be able to trust that their own rate
is not on it.

**iCloud sync is not mentioned.** The current build does not offer it
(`SyncPreference.isAvailable` is false without `ICLOUD_SYNC`), and a listing
that sells a feature the reviewer cannot find is a rejection.

## The German copy

Informal *du*, like the app's newer screens, and the app's own words: Baustelle,
Mannschaft, Bauleitung, Monatsliste, Verdienst, Zuschläge, Saldo, Soll,
Auswertung, „Wie am letzten Tag“. Careful, not reviewed — worth a native read
before it does any real selling.

## The name

`Zeitkonto` is the standard German term for a working-time account, so in
the DACH market it is a word people already have. The listing adds what it is
for after a colon — *Site Hours*, *Baustellen-Stunden* — because the name
field is the strongest search signal and the brand alone says nothing to
someone searching for timesheets. App Store names are unique across the store:
reserve it before anything else.

## Keywords

Not repeated from the name (Apple indexes the name anyway; the check refuses
a repeat). German keywords are counted in bytes, so an umlaut costs two.

## Screenshots

Taken by `ScreenshotTests` with the sample month (`SampleData.seed`): a site
with a crew of five, a month of site days, a pay rate with surcharges. Seven
shots, in this order — the calendar with the month's earnings, the site's
month and day card, the director's sheet, the day editor, Insights with
earnings, Pay, and Privacy. CI takes them on the largest iPhone (6.9-inch
slot), in English and German, and lays them out for upload on the
`screenshots` branch under `app-store/`.

The app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), the owner's choice, so
App Store Connect asks for no iPad screenshots. Turning iPad back on means
taking a 13-inch iPad set too.

## App Review notes

`fastlane/metadata/review_information/notes.txt`: the app works unpaid, where
the paywall is (Settings › Unlock Zeitkonto Pro, and from every Pro feature),
the three sandbox products, no account, no network except the App Store, no
location permission, and that the TestFlight tester unlock is compiled out of
the review build. Submit a build made with the TestFlight workflow's *Unlock
Pro for testers* switch **off**.

The review contact (name, phone, email) is entered in App Store Connect by
hand and is deliberately not in this repository.

## Pro products

Created by `fastlane ios products` (the *App Store* workflow, `what: products`):

| Product | Type | Price (base: Germany) |
|---|---|---|
| `app.zeitkonto.pro.monthly` | auto-renewable, 1 month | €2.99 |
| `app.zeitkonto.pro.yearly` | auto-renewable, 1 year | €19.99 |
| `app.zeitkonto.pro.lifetime` | non-consumable | €39.99 |

The two subscriptions share one group, referenced as *Hours Pro* (the name in
`Hours.storekit`). Apple gives the group a numeric id of its own; the lane
prints it.

## App Privacy

App Store Connect › App Privacy: **Data Not Collected**. True here: no
analytics, no third-party code, no account, and nothing sent anywhere. Crew
names, sites and pay stay on the device; the widgets read a snapshot in the
app's own App Group container on the same device.

## Contact

The privacy policy and the support page give a contact address. It is
marijomiksa@pm.me, written once per page; to change it, edit
`docs/privacy/index.html`, `docs/privacy/de/index.html`,
`docs/support/index.html` and `docs/support/de/index.html` (and the same in
`web/src/` if the site is rebuilt).

## Hosting

The site, the privacy policy and the support page are served by Cloudflare
Pages from this repository's `docs/` folder — see `notes/website.md`. Nothing
public links to the repository, so it can be private.

## What still needs a decision

- **The owner's name** for the copyright line (`fastlane/metadata/copyright.txt`).
- **The contact email** (above).
- **Territories.** Worldwide is the default and usually right.
