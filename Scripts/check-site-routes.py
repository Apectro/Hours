#!/usr/bin/env python3
"""Fail when the served site does not answer on the paths that matter.

The privacy policy URL is in App Store Connect. `web/scripts/publish.mjs`
already throws if docs/privacy/index.html stops existing, but existing in the
tree and being reachable over HTTP are different claims, and moving the site
behind a server of our own is what put a gap between them: a matcher in the
Caddyfile that 404s more than it meant to would break that URL with every file
still in place and every existing check still green.

So this asks the running server. Point it at a base URL — the local Caddy in
CI, or the Railway deployment once it is up:

    python3 Scripts/check-site-routes.py http://127.0.0.1:8891

It checks the status, and for pages a phrase that has to be in the body, so a
server that answers 200 with the wrong file still fails.
"""
from __future__ import annotations

import sys
import urllib.error
import urllib.request

# path, expected status, a phrase the body must contain (None to skip)
ROUTES = [
    ("/", 200, "never leave your phone"),
    ("/de/", 200, "Deine Stunden"),
    # The two that are in App Store Connect and in the German page's footer.
    ("/privacy/", 200, "collects nothing"),
    ("/privacy/de/", 200, "erhebt nichts"),
    ("/icon.svg", 200, None),
    ("/og.png", 200, None),
    ("/og-de.png", 200, None),
    ("/shots/01-calendar.480.webp", 200, None),
    # Working drafts that sit in docs/ and are not pages. Pages served them;
    # this server does not, and that is deliberate rather than accidental.
    ("/app-store-listing.md", 404, None),
    ("/README.md", 404, None),
    ("/CNAME", 404, None),
    # A path that has never existed must not resolve to the homepage. The site
    # is four static pages, not an app with a client-side router, and serving
    # index.html for everything would tell a crawler every typo is a page.
    ("/no-such-page", 404, None),
]

# Directory paths redirect to their trailing-slash form. Losing this turns
# every link written without the slash into a 404.
REDIRECTS = [("/privacy", "/privacy/"), ("/de", "/de/"), ("/privacy/de", "/privacy/de/")]


def fetch(url: str) -> tuple[int, bytes, str]:
    request = urllib.request.Request(url, headers={"User-Agent": "check-site-routes"})
    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(request, timeout=15) as response:
            return response.status, response.read(), response.headers.get("Location", "")
    except urllib.error.HTTPError as error:
        return error.code, error.read(), error.headers.get("Location", "")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Redirects are the assertion here, so they must not be followed."""

    def redirect_request(self, *_args):
        return None


def main(base: str) -> int:
    base = base.rstrip("/")
    problems = []

    for path, expected, phrase in ROUTES:
        status, body, _ = fetch(base + path)
        note = ""
        if status != expected:
            problems.append(f"{path}: {status}, expected {expected}")
            note = "  WRONG STATUS"
        elif phrase and phrase.encode() not in body:
            problems.append(f"{path}: 200 but the body does not contain {phrase!r}")
            note = "  WRONG BODY"
        print(f"  {path:<32} {status}  {len(body):>7} bytes{note}")

    for path, target in REDIRECTS:
        status, _, location = fetch(base + path)
        ok = status in (301, 307, 308) and location.endswith(target)
        if not ok:
            problems.append(f"{path}: {status} -> {location or 'nowhere'}, expected a redirect to {target}")
        print(f"  {path:<32} {status}  -> {location or '-'}{'' if ok else '  WRONG'}")

    if problems:
        print("\n" + "\n".join(f"  {p}" for p in problems))
        print("\nThe privacy policy URL is the one App Store Connect holds.")
        return 1

    print(f"\nall {len(ROUTES) + len(REDIRECTS)} routes answer as expected")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
