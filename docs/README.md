# docs

Things the App Store needs that are writing rather than code.

| | |
|---|---|
| `privacy/index.html` | The privacy policy. Apple requires a reachable URL for one. |
| `app-store-listing.md` | Draft copy for every field App Store Connect asks for. |

## Turning the privacy policy into a URL

Apple will not accept a submission without a privacy policy URL that resolves.
GitHub Pages serves this folder for free:

1. Settings › Pages
2. Source: **Deploy from a branch**
3. Branch: `main`, folder: **`/docs`**
4. Save, and wait a minute

The policy is then at:

```
https://apectro.github.io/Hours/privacy/
```

That is the URL to paste into App Store Connect.

**Two things to change before you publish it.** The contact address currently
reads `REPLACE-WITH-YOUR-CONTACT-EMAIL`, and the date at the top says
26 August 2026 — set it to the day you actually publish.

**If you make the repository private**, Pages stops serving on a free plan and
the URL dies, which will fail review at the next submission. Host the page
somewhere else first, or keep the repository public.

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
