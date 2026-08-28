# web

The marketing site at <https://apectro.github.io/Hours/>. React 18, TypeScript,
Vite; no UI framework and no analytics, for the same reason the app has none.

```
npm install
npm run dev        # localhost:5173, served at /Hours/
npm run publish    # build, and copy the result into ../docs/
npm run og         # redraw the social card (needs playwright; rarely)
```

`npm run publish` is the whole deployment. Pages serves `main:/docs`, so the
site goes live when the commit lands on `main` — see `docs/README.md` for why
it is arranged that way rather than as an Actions workflow.

## Where the words come from

`src/content.ts` holds everything the page says, so the copy can be read and
corrected without going through JSX. It is drawn from
`docs/app-store-listing.md`, which was written from what the app actually does.
Where the two disagree the listing wins, because that is the one Apple reads.

Two claims on the page are checkable against this repository and have to stay
true: the privacy section pairs each promise with the thing in the code that
makes it (`privacyClaims`), and the six balance cases are the ones the
calculation engine is tested against.

## Screenshots

`shots-src/` comes from the `screenshots` branch, which the test suite writes
on every run, so they cannot drift from what the app really looks like. To
refresh them, copy the current files out of that branch:

```
git show origin/screenshots:iPhone-17-Pro-Max/01-calendar.png > shots-src/01-calendar.png
```

`shots-src/exports/` holds the rendered timesheet the language section shows as
evidence, from the same branch.

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
not otherwise. `npm run og` redraws it from `scripts/og.html`, which is the
site's own hero — the webfonts are fetched and inlined first, so a headless
browser cannot quietly substitute whatever is installed locally.

The URL in the `og:image` tag is absolute, because unfurlers do not resolve
relative ones. It has to change if the site ever moves.

## The base path

Pages serves the site from `/Hours/`, not a domain root, so `vite.config.ts`
sets `base` to match. Set `VITE_BASE=/` when serving it anywhere that has its
own domain.
