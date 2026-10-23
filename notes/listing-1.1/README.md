# The 1.1 listing, staged

1.0 is in App Review, and the *App Store* workflow uploads
`fastlane/metadata/` as it stands. So the 1.1 text waits here until 1.1 is
the version being prepared. English only, like the live listing.

| File | What changes |
|---|---|
| `en-US/release_notes.txt` | "What's New in 1.1" |
| `en-US/description.txt` | Extra work, the site diary and bad weather, crew sign-off, holidays by country, leave, the watch app, Control Center and the Action Button worked into the 1.0 text |
| `en-US/promotional_text.txt` | Leads with extra work |
| `en-US/subtitle.txt` | *Crew timesheets & extra work* (was *Crew timesheets, no account*; "no account" is still the description's second paragraph) |
| `en-US/keywords.txt` | *diary* and *jobsite* in, *payroll* and *builder* out |

The name, the URLs, the categories and the review notes stay as they are.
`Scripts/check-store-metadata.py` measures these files against the store's
limits too, so they fit already.

The screenshots for 1.1 are what CI takes already: `ScreenshotTests` for the
iPhone, as listed in `fastlane/screenshots.txt` (which says `# listing for
version 1.1`), and `fastlane/watch-screenshots.txt` for the Apple Watch. The
App Store workflow uploads a set only when its version matches
the project's, so until the switch below it keeps uploading the 1.0 set
already on the `screenshots` branch, or refuses rather than upload 1.1's.

## Switching to 1.1

1. Copy the files over the live ones:
   `cp notes/listing-1.1/en-US/*.txt fastlane/metadata/en-US/`
2. Set the version to 1.1 in every target: `MARKETING_VERSION = 1.1` in
   `Hours.xcodeproj/project.pbxproj` (Xcode: each target › General ›
   Version). The Fastfile stops if the targets disagree.
3. Delete this folder, so the check stops measuring a copy, and merge.
4. Actions › *Build and test* › Run workflow, on `main`. That takes the
   1.1 iPhone and Apple Watch shots and puts them on the `screenshots`
   branch, marked 1.1.
5. In App Store Connect, add version 1.1 to the app if it is not there yet.
6. Actions › *App Store* › Run workflow, `listing`.

Promotional text can be changed at any time without a review, so it can
go up on its own once 1.0 is out, by editing the live
`promotional_text.txt` and running the `listing` upload — but only while the
project and the screenshots are still both 1.0.
