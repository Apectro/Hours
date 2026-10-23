#!/usr/bin/env python3
"""Fail when the App Store listing would not save in App Store Connect.

`fastlane/metadata/` is the listing — `fastlane ios listing` uploads it as it
stands — so a field over its limit is found here, on a push, rather than by
deliver halfway through an upload with half the languages already written.
The listing once reached 5,025 characters against a 4,000 cap while its own
notes said 4,000; nothing was enforcing them.

Checks, per language:
  - every field deliver uploads is there and not empty;
  - each is within the store's limit (characters; keywords in bytes, which
    is how App Store Connect counts them, so an umlaut costs two);
  - keywords are comma-separated with no spaces around the commas and no
    word twice, and none repeats a word of the name, which Apple indexes
    anyway;
  - the URLs are https.
And once:
  - the review notes fit, the categories are ones App Store Connect knows;
  - `fastlane/screenshots.txt` names the same shots, in the same order, as
    ScreenshotTests takes — the upload copies by that list — and says which
    version the set is for (`# listing for version 1.1`), which the App
    Store workflow holds the set to;
  - `fastlane/watch-screenshots.txt` gives each Apple Watch shot a name,
    in filename order, launched with the sample data.
And for the next version's listing, staged in `notes/listing-<version>/`
until the owner switches to it: whatever fields it holds fit the same
limits and keyword rules.

A placeholder still waiting for the owner (REPLACE-WITH-…) is reported but
does not fail: the copy is final, the owner's details are not ours to invent.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
METADATA = ROOT / "fastlane/metadata"
# Whichever languages the listing has: a folder per locale is what deliver
# uploads. German is parked in notes/listing-de until it has a free name.
LOCALES = sorted(
    d.name for d in METADATA.iterdir() if d.is_dir() and d.name != "review_information"
)

# What App Store Connect allows, per field.
LIMITS = {
    "name": 30,
    "subtitle": 30,
    "promotional_text": 170,
    "description": 4000,
    "keywords": 100,
    "release_notes": 4000,
}
URLS = ["support_url", "marketing_url", "privacy_url"]
CATEGORIES = {
    "BOOKS", "BUSINESS", "DEVELOPER_TOOLS", "EDUCATION", "ENTERTAINMENT", "FINANCE",
    "FOOD_AND_DRINK", "GAMES", "GRAPHICS_AND_DESIGN", "HEALTH_AND_FITNESS", "LIFESTYLE",
    "MAGAZINES_AND_NEWSPAPERS", "MEDICAL", "MUSIC", "NAVIGATION", "NEWS", "PHOTO_AND_VIDEO",
    "PRODUCTIVITY", "REFERENCE", "SHOPPING", "SOCIAL_NETWORKING", "SPORTS", "STICKERS",
    "TRAVEL", "UTILITIES", "WEATHER",
}
PLACEHOLDER = re.compile(r"REPLACE-WITH-[A-Z-]+")
# The next version's text, waiting in notes/ so the live listing stays the
# one in review (notes/listing-1.1/README.md).
STAGED = sorted(p for p in (ROOT / "notes").glob("listing-[0-9]*") if p.is_dir())
VERSION_LINE = re.compile(r"^#\s*listing for version (\d+(?:\.\d+)+)\s*$", re.M)


def read(path: Path) -> str | None:
    if not path.is_file():
        return None
    # deliver strips the trailing newline an editor leaves, and so does this.
    return path.read_text(encoding="utf-8").strip()


def measure(folder: Path, label_prefix: str, name: str, staged: bool,
            problems: list[str], report: list[tuple[str, int, int]]) -> None:
    """Checks one language's fields against the limits. A staged listing
    holds only what changes, so a field it lacks is not missing."""
    values = {}
    for field, limit in LIMITS.items():
        value = read(folder / f"{field}.txt")
        label = f"{label_prefix}/{field}"
        if not value:
            if not staged or (folder / f"{field}.txt").exists():
                problems.append(f"{label}: missing or empty")
            continue
        values[field] = value
        size = len(value.encode("utf-8")) if field == "keywords" else len(value)
        report.append((label, size, limit))
        if size > limit:
            unit = "bytes" if field == "keywords" else "characters"
            problems.append(f"{label}: {size} {unit} against {limit} — over by {size - limit}")

    keywords = values.get("keywords", "")
    if keywords:
        words = keywords.split(",")
        if any(w != w.strip() or not w for w in words):
            problems.append(f"{label_prefix}/keywords: a space beside a comma, or an empty keyword")
        lowered = [w.strip().lower() for w in words]
        twice = sorted({w for w in lowered if lowered.count(w) > 1})
        if twice:
            problems.append(f"{label_prefix}/keywords: listed twice: {', '.join(twice)}")
        named = set(re.findall(r"\w+", values.get("name", name).lower()))
        repeated = sorted(named & set(lowered))
        if repeated:
            problems.append(f"{label_prefix}/keywords: already in the name: {', '.join(repeated)}")


def main() -> int:
    problems: list[str] = []
    placeholders: list[str] = []
    report: list[tuple[str, int, int]] = []

    for locale in LOCALES:
        folder = METADATA / locale
        measure(folder, locale, "", False, problems, report)

        for field in URLS:
            value = read(folder / f"{field}.txt")
            if not value or not value.startswith("https://") or " " in value:
                problems.append(f"{locale}/{field}: not an https URL ({value!r})")

    # The next version's text: the fields it changes, measured as the live
    # ones are, with the live name for the keyword rule when it keeps it.
    for staged in STAGED:
        for folder in sorted(d for d in staged.iterdir() if d.is_dir()):
            live_name = read(METADATA / folder.name / "name.txt") or ""
            measure(folder, f"{staged.name}/{folder.name}", live_name, True, problems, report)

    notes = read(METADATA / "review_information/notes.txt")
    if not notes:
        problems.append("review_information/notes.txt: missing or empty")
    else:
        report.append(("review notes", len(notes), 4000))
        if len(notes) > 4000:
            problems.append(f"review notes: {len(notes)} characters against 4000")

    for field in ["primary_category", "secondary_category"]:
        value = read(METADATA / f"{field}.txt")
        if value not in CATEGORIES:
            problems.append(f"{field}: {value!r} is not an App Store Connect category")

    for path in sorted(METADATA.rglob("*.txt")):
        for match in PLACEHOLDER.findall(path.read_text(encoding="utf-8")):
            placeholders.append(f"{path.relative_to(ROOT)}: {match}")

    # The upload copies by fastlane/screenshots.txt, the test takes by its own
    # list; a shot renamed in one and not the other is silently not uploaded.
    listing_text = (ROOT / "fastlane/screenshots.txt").read_text(encoding="utf-8")
    listed = [
        line.strip()
        for line in listing_text.splitlines()
        if line.strip() and not line.startswith("#")
    ]
    if len(VERSION_LINE.findall(listing_text)) != 1:
        problems.append(
            "fastlane/screenshots.txt: needs exactly one '# listing for version X.Y' line — "
            "the App Store workflow uploads a set only for the version it names"
        )
    test = (ROOT / "HoursUITests/ScreenshotTests.swift").read_text(encoding="utf-8")
    block = re.search(r"static let listing = \[(.*?)\]", test, re.S)
    taken = re.findall(r'"([^"]+)"', block.group(1)) if block else []
    if listed != taken:
        problems.append(
            "fastlane/screenshots.txt and ScreenshotTests.listing differ:\n"
            f"      file: {listed}\n      test: {taken}"
        )

    # The watch shots: CI launches the watch app once per line, so a line is
    # a name and its launch arguments. Without the sample data the watch,
    # which has no phone in the simulator, shows only "open the iPhone app".
    watch_lines = [
        line.split()
        for line in (ROOT / "fastlane/watch-screenshots.txt").read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    watch_names = [words[0] for words in watch_lines]
    if not watch_lines:
        problems.append("fastlane/watch-screenshots.txt: no Apple Watch shots listed")
    for words in watch_lines:
        if "-hours-sample-data" not in words[1:]:
            problems.append(f"fastlane/watch-screenshots.txt: {words[0]} is not launched with -hours-sample-data")
        if not re.fullmatch(r"\d\d-[a-z0-9-]+", words[0]):
            problems.append(f"fastlane/watch-screenshots.txt: {words[0]!r} is not a name like 01-running")
    if watch_names != sorted(set(watch_names)):
        problems.append("fastlane/watch-screenshots.txt: names repeat or are out of order (deliver sorts by filename)")

    width = max((len(n) for n, _, _ in report), default=0)
    for name, size, limit in report:
        flag = "  OVER" if size > limit else ""
        print(f"  {name:<{width}}  {size:>5} / {limit:<5}{flag}")

    if placeholders:
        print("\nstill to be filled in by the owner:")
        for line in placeholders:
            print(f"  {line}")

    if problems:
        print("\n" + "\n".join(f"  {p}" for p in problems))
        print("\nApp Store Connect would refuse these. Fix the files named above.")
        return 1

    print(f"\nthe listing fits ({len(report)} fields measured, {len(LOCALES)} languages)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
