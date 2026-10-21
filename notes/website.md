# docs

What Cloudflare Pages serves at `https://zeitkonto.app/`: the marketing site
and the pages the App Store needs.

| | |
|---|---|
| `index.html`, `de/`, `assets/`, `shots/`, `icon.svg`, `og*.png`, `404.html`, `_headers`, `_redirects` | **Built output. Do not edit.** The site is written in `web/` and copied here by `npm run publish`. |
| `privacy/index.html`, `privacy/de/index.html` | The privacy policy, written by hand. App Store Connect holds `/privacy/`. |
| `support/index.html`, `support/de/index.html` | The support page, written by hand. App Store Connect holds `/support/`. |
| `app-store-listing.md`, `README.md`, `superpowers/` | Working notes. Not pages: `_redirects` sends them to the home page. |

## Why the built site lives in a committed folder

Cloudflare Pages deploys this folder exactly as it stands on `main`, with no
build step of its own. So what is live is what is committed, CI checks on every
push that it is what `web/` builds (`npm run verify`), and a broken build tool
on Cloudflare's side cannot take the privacy policy down.

`web/scripts/publish.mjs` keeps a short list of the hand-written names and
clears everything else before copying, so a stale asset cannot survive a
rebuild and nothing written by hand can be removed by one.

`_headers` sets the same Content-Security-Policy and security headers the
`Caddyfile` does, and caches the hashed files under `assets/` for a year.
`404.html` is there so an unknown path is a 404: without one, Cloudflare Pages
treats a site as a single-page app and answers every typo with the home page.

## Setting it up

**1. Put the domain on Cloudflare.** dash.cloudflare.com › **Add a domain** ›
`zeitkonto.app` › Free plan. Cloudflare imports the existing records and
names two nameservers; at the registrar, replace the domain's nameservers with
those two (the registration stays where it is). Wait for the email saying the
domain is active.

**As it is actually set up:** the project was created as a Cloudflare
**Worker** named `hours` (Workers & Pages › Workers), connected to this repo,
not as a Pages project. That works the same, as long as `wrangler.jsonc` at the
repository root stays: it names the Worker and points its static assets at
`docs/`, which both the production deploy and the pull-request preview uploads
read; pull requests run `wrangler preview`, which also needs its `"previews": {}` block. Without them the previews fail ("Workers Builds: hours" red on a PR).

**2. Create the Pages project.** dash.cloudflare.com › **Workers & Pages** ›
**Create** › **Pages** › **Connect to Git** › authorise GitHub for this
repository only › pick it, then:

- Production branch: `main`
- Framework preset: None
- Build command: *(empty)*
- Build output directory: `docs`

Save and Deploy. Open the `…pages.dev` address and check `/`, `/de/`,
`/privacy/` and `/support/` before going further. Every push to `main`
redeploys; pushes to other branches get preview addresses.

**3. Attach the domain.** The project › **Custom domains** › **Set up a custom
domain** › `zeitkonto.app` (and `www.zeitkonto.app` if wanted). With the
domain on Cloudflare, the record and the certificate are added for you.

**`.app` is on the HSTS preload list**, so browsers refuse plain HTTP to it.
Between the domain resolving and the certificate being issued the site is not
slow, it is unreachable. That is usually minutes. Wait rather than change
things.

Then `python3 Scripts/check-site-routes.py https://zeitkonto.app` checks the
pages, images and redirects.

**The repository can be private.** Nothing public links to it, and Cloudflare
deploys from a private repository the same as from a public one.

The `Caddyfile`, `Dockerfile` and `railway.json` at the root are the earlier
self-hosted setup. CI still boots that Caddyfile against this folder as a
second check that the routes answer, but it is not what serves the site.

## Before it goes live

The privacy and support pages each name the contact address
(marijomiksa@pm.me) once — four places in all, two per language. Change it in
each if it ever changes, and keep the date at the top of the policy current.

## Is the policy accurate?

It was written from the code rather than from a template, and every claim in it
is checkable:

| Claim | Where it comes from |
|---|---|
| No analytics, no third-party code | `Package.swift` declares no external packages, and the project links no SDKs |
| No account | There is no auth layer anywhere in the app |
| Stored on the device | `HoursModelContainer` opens a local store; this build cannot sync (`SyncPreference.isAvailable` is false without `ICLOUD_SYNC`) |
| Crew names are typed, not read from Contacts | No Contacts import; a crew member is a `TextField` |
| Pay stays off site sheets | Site exports are built without earnings; earnings appear on a personal timesheet only with `ExportPreferences.includeEarnings` |
| Widgets read a local snapshot | `WidgetSnapshotWriter` writes JSON into the `group.app.zeitkonto` App Group container |
| Never asks for location | No CoreLocation import; the field is a `TextField` |
| Notifications are local | `UNCalendarNotificationTrigger`, scheduled on the device |
| The app learns only entitlement | `SubscriptionStore` reads `Transaction.currentEntitlements` and nothing else |

If any of that stops being true, the policy has to change with it.
