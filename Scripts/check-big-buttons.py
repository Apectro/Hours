#!/usr/bin/env python3
"""Fail when a big button is given a size of its own.

Two big buttons share a row by each taking half (`BigActionButtonStyle` gives
every one `maxWidth: .infinity`). A `.layoutPriority(` on one of them makes
it take what it wants first and squeezes its neighbour: Missing › Send the
list shipped with "Send as message" at full width and the PDF button crushed
to a sliver beside it, and nothing failed. A `.fixedSize()` (horizontally)
or a fixed `.frame(width:` on one does the same.

So: none of those within a few lines after `.buttonStyle(.bigAction(` in
`Hours/**/*.swift`. `.fixedSize(horizontal: false, vertical: true)` only
lets text grow down, and is allowed.

A grep, so it runs on Linux in seconds on every push.

Usage: python3 Scripts/check-big-buttons.py [root]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SEARCHED = "Hours"
# How many lines after the style are the same button's modifiers.
WINDOW = 3

BIG = re.compile(r"\.buttonStyle\(\s*\.bigAction\(")
SIZING = [
    (re.compile(r"\.layoutPriority\("), ".layoutPriority"),
    # `.fixedSize()` or `.fixedSize(horizontal: true …`; vertical-only is fine.
    (re.compile(r"\.fixedSize\(\s*(?:\)|horizontal:\s*true)"), ".fixedSize"),
    (re.compile(r"\.frame\(\s*width:"), ".frame(width:"),
]


def scan(source: str) -> list[tuple[int, str]]:
    """The (line, modifier) pairs that size a big button on its own."""
    lines = [re.sub(r"//.*$", "", line) for line in source.splitlines()]
    found: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        if not BIG.search(line):
            continue
        for offset in range(1, WINDOW + 1):
            if index + offset >= len(lines):
                break
            following = lines[index + offset]
            # The next button's own style starts a new button.
            if BIG.search(following):
                break
            for pattern, name in SIZING:
                if pattern.search(following):
                    found.append((index + offset + 1, name))
    return found


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    problems = []
    for path in sorted((root / SEARCHED).rglob("*.swift")):
        for line, name in scan(path.read_text(encoding="utf-8")):
            problems.append((str(path.relative_to(root)), line, name))

    if problems:
        print(f"{len(problems)} big button(s) sized on their own:\n")
        for rel, line, name in problems:
            print(f"  {rel}:{line}  {name}")
        print(
            "\nTwo big buttons in a row each take half. This modifier makes one take\n"
            "more and squeezes the other. Remove it; if a label is too long, shorten\n"
            "the label or put the buttons one under the other."
        )
        return 1

    print("no big button is sized on its own")
    return 0


if __name__ == "__main__":
    sys.exit(main())
