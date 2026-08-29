#!/usr/bin/env python3
"""Fail on English that reaches a person without passing through a lookup.

The class this catches: a Swift string literal with interpolation in it,
holding real words, that is never handed to a localizing initializer. It is
the shape a translated app quietly keeps producing English in, because every
such literal reads correctly in review — it is correct English — and the only
way to see the bug is to run the app in another language and look.

Two of them were spoken rather than shown. Siri answered "You are 2 hours 45
minutes ahead" on a German phone, and the intent titles either side of it were
translated, which is what made it invisible.

Runs on Linux in seconds, so it runs on every push rather than needing a
simulator — which is what it took to notice the first time.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Where a person reads the result. HoursCore is included: it cannot call
# String(localized:) — it also builds on Linux — but it has its own word table,
# and a literal there is the same defect with a different fix.
SEARCHED = ["Hours", "HoursCore", "HoursWidget", "HoursShared"]

# Anything whose literal is looked up. Matched against the text leading up to
# the literal with newlines removed, because these calls wrap:
#
#     message = String(
#         inflected: "^[\\(n) day](inflect: true) could not be read."
#     )
#
# were the three lines that made an earlier version of this scan report six
# false positives and nearly get the real ones dismissed with them.
LOCALIZING = (
    "String(localized:",
    "String(inflected:",
    "AttributedString(localized:",
    "LocalizedStringResource(",
    "IntentDescription(",
)

# A literal that is not prose. Each of these is a decision, not a shortcut:
#
#   identifiers   what a UI test queries by; changing per language defeats it
#   file paths    a name on disk, not a sentence
#   XML and SUM   the innards of a .xlsx, which has no language
#   diagnostics   preconditions and developer errors nobody ships to a user
NOT_PROSE = [
    re.compile(r"^[a-z][a-z0-9]*(-|\.)"),          # day-, export-, hours.preview.
    re.compile(r"^<"),                             # XML fragments
    re.compile(r"^\s*(SUM|A)\("),                  # spreadsheet formulas
    re.compile(r"^\s+(ht|r)="),                    # XML attribute fragments
    re.compile(r"\.json$|\.csv$|\.xlsx$|\.pdf$"),  # file names
    re.compile(r"^https?://"),
]

# Literals that are prose and are deliberately not looked up. Every entry is a
# claim that a person never reads this, and carries the reason.
ALLOWED = {
    "Unable to create an in-memory model container: \\(error)":
        "a developer crash message; the app is already unusable when it prints",
    "Invalid calendar date key \\(key)":
        "a precondition failure, not a screen",
}

LITERAL = re.compile(r'"((?:[^"\\]|\\.)*\\\((?:[^"\\]|\\.)*)"')


def without_interpolations(literal: str) -> str:
    """The literal with every `\\(...)` removed, at any nesting depth.

    A regex cannot do this: `\\(Int((fraction * 100).rounded()))%` nests three
    deep, and a pattern written for one level left `Int` and `rounded` behind
    and reported a percentage sign as untranslated prose.
    """
    out, i = [], 0
    while i < len(literal):
        if literal.startswith("\\(", i):
            depth, i = 0, i + 1
            while i < len(literal):
                if literal[i] == "(":
                    depth += 1
                elif literal[i] == ")":
                    depth -= 1
                    if depth == 0:
                        i += 1
                        break
                i += 1
        else:
            out.append(literal[i])
            i += 1
    return "".join(out)


def strip_comments(source: str) -> str:
    """Blank out // and /* */ so commented-out code is not scanned."""
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in source.split("\n"))


def squeeze(text: str) -> str:
    """All whitespace removed, so a wrapped call reads as one token."""
    return re.sub(r"\s+", "", text)


def has_words(literal: str) -> bool:
    """Three consecutive letters outside the interpolations.

    Three rather than one: "\\(a)/\\(b)" and "%@ h" are formats, and a rule
    that flags them is a rule people turn off.
    """
    return bool(re.search(r"[A-Za-z]{3,}", without_interpolations(literal)))


def scan(path: Path) -> list[tuple[int, str]]:
    source = strip_comments(path.read_text(encoding="utf-8"))
    lines = source.split("\n")
    found = []
    for i, line in enumerate(lines):
        for match in LITERAL.finditer(line):
            literal = match.group(1)
            if not has_words(literal):
                continue
            if any(p.search(literal) for p in NOT_PROSE):
                continue
            if literal in ALLOWED:
                continue
            # The call that localizes this literal may be several lines above
            # it and broken across them, with the argument label indented onto
            # its own line:
            #
            #     IntentDialog(stringLiteral: String(
            #         localized: "You are \\(duration) ahead."
            #
            # So the lead is joined *and* stripped of whitespace before the
            # tokens are looked for. Joining alone left "String(" and
            # "localized:" separated by sixteen spaces, and every call written
            # that way — which is every long one — was reported as a defect.
            lead = "".join(lines[max(0, i - 4): i]) + line[: match.start()]
            if any(token in squeeze(lead) for token in LOCALIZING):
                continue
            found.append((i + 1, literal))
    return found


def main() -> int:
    problems = []
    for folder in SEARCHED:
        for path in sorted((ROOT / folder).rglob("*.swift")):
            if "Tests" in path.name:
                continue
            for line, literal in scan(path):
                problems.append((path.relative_to(ROOT), line, literal))

    if problems:
        print(f"{len(problems)} interpolated literal(s) never looked up:\n")
        for path, line, literal in problems:
            print(f"  {path}:{line}")
            print(f"      {literal[:100]}")
        print(
            "\nEach of these reads as correct English and is shown to people in "
            "ten languages.\nWrap it in String(localized:) — or, in HoursCore, "
            "add a term to AppVocabulary.swift.\nIf a literal genuinely is not "
            "prose, add it to ALLOWED here with the reason."
        )
        return 1

    print("no interpolated English reaching a screen unlooked-up")
    return 0


if __name__ == "__main__":
    sys.exit(main())
