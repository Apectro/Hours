# docs

What GitHub Pages serves, which is two things: the marketing site and the
pages the App Store needs.

| | |
|---|---|
| `index.html`, `assets/`, `shots/`, `icon.svg`, `og.png`, `CNAME` | **Built output. Do not edit.** The site is written in `web/` and copied here by `npm run publish`. |
| `privacy/index.html` | The privacy policy, written by hand. Apple requires a reachable URL for one. |
| `app-store-listing.md` | Draft copy for every field App Store Connect asks for. |

## Why the built site lives in a committed folder

Pages serves `main:/docs`, and the privacy policy URL is the one App Store
Connect holds. Moving Pages to an Actions workflow would take that URL down for
as long as it took somebody to notice the source setting had to be flipped by
hand. Copying the build into `docs/` keeps the existing setting, so the privacy
URL cannot break.

`web/scripts/publish.mjs` deletes only the names the build produces before
copying, so a stale asset cannot survive a rebuild and nothing written by hand
can be removed by one.

## The domain

The site is `zeitkonto.app`. `CNAME` in this folder is what tells Pages so, and
it comes from `web/public/CNAME` — it is build output, not a file to edit here,
because a hand-placed CNAME is the kind of thing that gets cleared by a publish
and noticed a week later. `npm run verify` fails if it goes missing or changes.

**DNS.** For the apex, four A records to GitHub's Pages addresses:

```
185.199.108.153
185.199.109.153
185.199.110.153
185.199.111.153
```

and, if you want `www` to work, a CNAME record pointing `www` at
`apectro.github.io`. Then Settings › Pages › Custom domain, enter
`zeitkonto.app`, and tick **Enforce HTTPS** once it becomes available.

**`.app` is on the HSTS preload list**, which means browsers refuse to speak
plain HTTP to it — there is no insecure fallback to land on. So between the DNS
resolving and GitHub finishing the certificate, the site is not slow or ugly,
it is unreachable. That wait is usually minutes and can be an hour. Do not
panic and start changing things during it.

The old `apectro.github.io/Hours/` address keeps working: once a custom domain
is set, Pages redirects it to the new one.

## Turning the privacy policy into a URL

Apple will not accept a submission without a privacy policy URL that resolves.
Pages serves this folder for free:

1. Settings › Pages
2. Source: **Deploy from a branch**
3. Branch: `main`, folder: **`/docs`**
4. Save, and wait a minute

The policy is then at:

```
https://zeitkonto.app/privacy/
```

That is the URL to paste into App Store Connect, and the site itself is at
`https://zeitkonto.app/`.

**Two things to change before you publish it.** The contact address currently
reads `REPLACE-WITH-YOUR-CONTACT-EMAIL`, and the date at the top says
26 August 2026 — set it to the day you actually publish.

**If you make the repository private**, Pages stops serving on a free plan and
the URL dies, which will fail review at the next submission. Owning the domain
does not save you here — it points at Pages. Host the page somewhere else
first, or keep the repository public.

## Is the policy accurate?

It was written from the code rather than from a template, and every claim in it
is checkable:

| Claim | Where it comes from |
|---|---|
| No analytics, no third-party code | `Package.swift` declares no external packages, and the project links no SDKs |
| No account | There is no auth layer anywhere in the app |
| Local storage by default | `HoursModelContainer` opens a local store unless sync is switched on |
| iCloud is the user's own | CloudKit private database and `NSUbiquitousKeyValueStore` |
| Never asks for location | No CoreLocation import; the field is a `TextField` |
| Notifications are local | `UNCalendarNotificationTrigger`, scheduled on the device |
| The app learns only entitlement | `SubscriptionStore` reads `Transaction.currentEntitlements` and nothing else |

If any of that stops being true, the policy has to change with it.
