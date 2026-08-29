#!/usr/bin/env python3
"""Fail when a field in the App Store listing is longer than the store allows.

`docs/app-store-listing.md` is drafted so the whole of step 22 is paste-and-go,
and it states each field's limit right above the field — 30 characters for the
name, 170 for the promotional text, 4,000 for the description. Those notes were
being written and then not enforced, so the description reached 5,025
characters: a quarter over, and the kind of thing you find out about with the
form already open and App Store Connect refusing to save.

The limits are read out of the file rather than hard-coded here, so the
document stays the single statement of what the store wants. A field whose
note says "30 characters" and whose block is 34 fails; a field with no stated
limit is skipped and reported, so a new one cannot arrive unmeasured.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

LISTING = Path(__file__).resolve().parent.parent / "docs/app-store-listing.md"

# "*30 characters. Shown under the icon…*" and "*4,000 characters. …*"
LIMIT = re.compile(r"^\*(\d[\d,]*)\s+characters", re.M)
FENCE = re.compile(r"```\n(.*?)\n```", re.S)

# Fields the store does not cap, or that hold something other than prose.
UNCAPPED = {
    "App Review notes",
    "Version release notes",
    "What still needs a decision",
    "Age rating",
    "Category",
    "Support URL",
    "Marketing URL",
    "Privacy Policy URL",
}


def sections(text: str) -> list[tuple[str, str]]:
    """Each `## Heading` with the text under it, up to the next heading."""
    marks = [(m.group(1), m.end()) for m in re.finditer(r"^## (.+)$", text, re.M)]
    out = []
    for index, (name, start) in enumerate(marks):
        end = marks[index + 1][1] - len(marks[index + 1][0]) - 4 if index + 1 < len(marks) else len(text)
        out.append((name, text[start:end]))
    return out


def main() -> int:
    text = LISTING.read_text(encoding="utf-8")
    problems, unmeasured, report = [], [], []

    for name, body in sections(text):
        if name in UNCAPPED:
            continue
        limit_match = LIMIT.search(body)
        blocks = FENCE.findall(body)
        if not blocks:
            continue
        if not limit_match:
            unmeasured.append(name)
            continue

        limit = int(limit_match.group(1).replace(",", ""))

        # The first block is the field. Any block after it is the alternatives
        # list — one candidate per line, each annotated with the count somebody
        # worked out by hand:
        #
        #     Private work-hours calendar     (29)
        #
        # Measuring that block whole makes a 25-character subtitle look like a
        # 110-character one, which is how this check first reported the
        # Subtitle as eighty over when every option in it fits.
        for index, block in enumerate(blocks):
            if index == 0:
                candidates = [(name, block)]
            else:
                candidates = [
                    (f"{name} (alternative)", re.sub(r"\s*\(\d+\)\s*$", "", line))
                    for line in block.split("\n")
                    if line.strip()
                ]
            for label, value in candidates:
                length = len(value)
                report.append((label, length, limit))
                if length > limit:
                    problems.append(
                        f"{label}: {length} characters against a limit of {limit} "
                        f"— over by {length - limit}"
                    )

    width = max((len(n) for n, _, _ in report), default=0)
    for name, length, limit in report:
        room = limit - length
        flag = "  OVER" if room < 0 else ""
        print(f"  {name:<{width}}  {length:>5} / {limit:<5}{flag}")

    if unmeasured:
        print(f"\nfields with a block and no stated limit: {', '.join(unmeasured)}")
        print("Add the store's limit above them, or list them in UNCAPPED here.")
        return 1

    if problems:
        print("\n" + "\n".join(f"  {p}" for p in problems))
        print(
            "\nApp Store Connect refuses these outright, with the form already open.\n"
            "Trim the field, or correct the limit above it if the store changed it."
        )
        return 1

    print(f"\nevery listing field fits ({len(report)} measured)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
