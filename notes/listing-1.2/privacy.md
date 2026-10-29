# App Privacy and review notes for 1.2

1.2 is the first version that can use the phone's location: the opt-in
arrival reminder on a site. Until 1.2 every privacy text said "no location
access"; from 1.2 the promise is:

> Location only if you turn on an arrival reminder for a site, and it never
> leaves your phone.

## App Privacy answer: still "Data Not Collected"

Nothing changes in App Store Connect › App Privacy. Apple counts data as
*collected* when it is transmitted off the device in a way the developer or a
third party can access. The arrival reminder does not do that:

- **Used on the device only.** The location is read once, when the user
  taps "Use my current location" in a site's settings, to save where the
  site is. After that, iOS itself watches the area around each such site
  (region monitoring) and wakes the app when its edge is crossed; the app
  never receives a stream of positions and keeps no history of where the
  phone has been.
- **Never stored beyond the site's saved coordinates.** The site's latitude,
  longitude, radius and the reminder switch are the only location data, kept
  with the site in the app's own store. "Clear location" removes them.
- **Never sent.** No server, no analytics, nothing to us. The saved place
  travels only where the site already did: in a backup file the user exports
  through the share sheet, and in the user's own private iCloud if they
  turned sync on — the same as every other part of their data, which Apple
  does not count as collection by the developer.

The small map in the site's settings is MapKit's `Map`, which loads Apple's
map tiles for that area, as every map does. The app makes no network call of
its own for it.

**A site's address.** A site can carry an address for its sheets, typed by the
user. For a site with a saved place, "Fill in from the saved place" asks Apple
Maps (`CLGeocoder`, a system service) for the address at those coordinates —
only when tapped, only that one place, and the answer is put in the field for
the user to keep or change. That is the device asking Apple for an address on
the user's request, like the map tiles; nothing reaches us or a third party,
and nothing is looked up otherwise. It does not change the answer below.

So the answer for **Location → Precise Location** and **Coarse Location** is
"not collected", and the overall label stays **Data Not Collected**.

## Permissions the app now asks for

| Key | When it is asked | Why |
|---|---|---|
| `NSLocationWhenInUseUsageDescription` | Turning on a site's arrival reminder, after an explanation in the app | One fix, saved as the site's place |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Straight after, the upgrade to Always | Region monitoring, so arriving is noticed while the app is closed |
| Notifications | As before, plus when the arrival reminder is turned on | The "Arrived at … — start the clock?" question |

No `location` background mode: region monitoring does not need it.

## Review notes for 1.2

When 1.2 is the version being prepared, the PERMISSIONS paragraph of
`fastlane/metadata/review_information/notes.txt` changes from "the app never
asks for location permission and links no location framework" to:

> PERMISSIONS
> Notifications, only when the user turns a reminder on. Location, only when
> the user turns on the arrival reminder in a site's settings (Sites > a site >
> ... > Edit site > Remind me when I arrive): the app explains why first, saves
> the site's place from one location fix, then asks for "Always" so iOS region
> monitoring can notice arriving at and leaving the site while the app is
> closed. The location never leaves the phone; the app keeps only the site's
> saved coordinates. The optional "location" field on a day is still text the
> user types.

## Where the promise is written

- The app's Privacy screen (Settings › Privacy, `AboutScreen`).
- `docs/privacy/index.html`, the privacy policy, under *Location*.
- The website's privacy claims (`web/src/copy/en.ts`, `de.ts`), built into
  `docs/` by `npm run publish`.
- `README.md` and `ARCHITECTURE.md`, *Privacy*.

Each also says, since the site's address, that "Fill in from the saved place"
asks Apple Maps for that one place's address, only when tapped.
