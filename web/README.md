# web

The marketing site at <https://apectro.github.io/Hours/>. React 18, TypeScript,
Vite; no UI framework and no analytics, for the same reason the app has none.

```
npm install
npm run dev        # localhost:5173, served at /Hours/
npm run publish    # build, and copy the result into ../docs/
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

`public/shots/` comes from the `screenshots` branch, which the test suite
writes on every run, so they cannot drift from what the app really looks like.
To refresh them, copy the current files out of that branch:

```
git show origin/screenshots:iPhone-17-Pro-Max/01-calendar.png > public/shots/01-calendar.png
```

## The base path

Pages serves the site from `/Hours/`, not a domain root, so `vite.config.ts`
sets `base` to match. Set `VITE_BASE=/` when serving it anywhere that has its
own domain.
