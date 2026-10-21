# web

The marketing site at <https://zeitkonto.app/>, in English and German. React 18, TypeScript,
Vite; no UI framework and no analytics, for the same reason the app has none.

The page is laid out as a ledger, because that is what a timesheet is: a label
column, an entry column, and rules between. One device — see `.row` in
`styles.css` — does the work that an uppercase eyebrow over every section and
three grids of rounded cards were doing before. If you add a section, add rows
to it rather than a new kind of box.

`docs/privacy/index.html` is hand-written and carries its own copy of the
palette so it keeps resolving even if this app is rebuilt or replaced. If the
tokens here move, move those with them.

```
npm install
npm run dev        # localhost:5173
npm run publish    # build, and copy the result into ../docs/
npm run verify     # fail if ../docs/ is not what this builds
npm run og         # redraw the social card (rarely)
```

CI runs `verify` on every push. Committing build output buys a privacy-policy
URL that cannot break, and costs one failure mode: editing `src/` without
running `publish` leaves the live site quietly serving the previous build. That
job is the price of the trade.

`npm run publish` is the whole deployment. Cloudflare Pages serves `docs/` as it
stands on `main`, with no build step of its own, so the site goes live when the
commit lands — see `notes/website.md` for the setup.

## Two languages

English at `/`, German at `/de/`. The site is built twice — `npm run build`
runs vite once per language — rather than switched in the browser, so each page
carries the right `lang` attribute, the right title and description for search
and link previews, and no flash of the wrong language while the bundle loads.
Each language is a real URL that can be shared, which a runtime toggle is not.

German takes `base: "/de/"` so its own JS and CSS resolve, but images are
referenced absolutely and its `publicDir` is off: the screenshots say the same
thing in both languages and 145KB is not worth duplicating to prove it.

`src/copy/en.ts` is the source of the shape. `de.ts` is typed as `Copy`, so a
section added to one and forgotten in the other is a compile error rather than
a paragraph that quietly comes out in English. `vite.config.ts` rewrites the
head per language and emits the `hreflang` pair.

The German copy is careful, not reviewed. Worth a native pass before it does
any real selling.

## Where the words come from

`src/copy/` holds everything each page says, so the copy can be read and
corrected without going through JSX. It is drawn from
the store listing in `fastlane/metadata/`, which was written from what the app actually does.
Where the two disagree the listing wins, because that is the one Apple reads.

Two claims on the page are tied to this repository and have to stay true: the
privacy section pairs each promise with what keeps it (`privacy.claims` in the
copy, matching the table in `notes/website.md`), and the six balance cases are
the ones the calculation engine is tested against.

## Screenshots

`shots-src/` comes from the `screenshots` branch, which the test suite writes
on every run, so they cannot drift from what the app really looks like. To
refresh them, copy the current files out of that branch:

```
git show origin/screenshots:iPhone-17-Pro-Max/01-calendar.png > shots-src/01-calendar.png
```

`shots-src/exports/` holds the four rendered timesheets the language section
shows as evidence, from the same branch. Those four are the ones the capture
suite renders; the other six languages are covered by tests, which is why the
caption on the page says so rather than implying the set is complete. Adding a
fifth means adding it to the capture suite first, then to `timesheetProof` in
`content.ts` — the crop and the widths are handled by `scripts/images.mjs`.

**`public/shots/` is output, and is not in git.** The captures are 1320px wide
and the page renders them at 318px and 225px, so publishing them as they come
sent four to six times the pixels any screen asks for — 1.77MB of a 1.9MB page.
`scripts/images.mjs` resizes each one to 480px and 960px of WebP with a 640px
PNG behind it, and runs before both `dev` and `build` so the two always see the
same files. A phone now fetches 378KB for the whole page.

If you add a screenshot, put it in `shots-src/` and refer to it by base name in
`content.ts`; the `<Shot>` component builds the `srcset` from there.

## The social card

`public/og.png` is what an unfurler shows when the link is pasted anywhere, and
it is committed rather than built, because it changes when the wording does and
not otherwise. `npm run og` redraws it.

It is composed with sharp, which is already a dependency, rather than by
screenshotting a headless browser — so the script runs from a clean
`npm install` instead of needing a browser nobody declared. The webfonts are
downloaded into `.fontcache/` and handed to fontconfig, because the card's
whole job is to look like the site and a renderer quietly falling back to
whatever is installed is exactly the drift it exists to avoid. That is checked
rather than hoped for: the script draws a string in the wanted face and again
in a family that cannot exist, and fails if the two come out identical.

The URL in the `og:image` tag is absolute, because unfurlers do not resolve
relative ones. It has to change if the site ever moves.

## The domain

The site is `zeitkonto.app`, so `base` is the root and asset paths are rooted.
The domain is attached in the Cloudflare dashboard, not by a file.

`public/` also holds the three files Cloudflare Pages reads from the root of
what it serves: `_headers` (the security headers and long caching for
`assets/`), `_redirects` (the working notes in `docs/` are not pages) and
`404.html` (without it every unknown path would get the home page and a 200).
They are ordinary build output, so a publish cannot lose them, and
`npm run verify` fails if the copies in `docs/` differ.

The footer links the privacy policy and the support page, both hand-written in
`docs/`. Nothing on the site links to the repository: the app is not open
source.

`og:url` and `og:image` in `index.html` are absolute, because unfurlers do not
resolve relative ones. They name the domain and have to move with it.

`notes/website.md` has the Cloudflare setup.
