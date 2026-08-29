#!/usr/bin/env python3
"""Fail when the code looks up a key the catalogue does not hold.

A missing key is not an error at runtime. `String(localized:)` returns the key
itself, which is the English text, so the app carries on looking perfectly
correct in English and silently monolingual everywhere else. Four keys were
already in that state before anyone went looking — "%lld scheduled", "%lld
off", the two percentage lines on the insights screen — all written correctly,
all wrapped correctly, none of them in the catalogue.

That could not happen with Xcode's own extraction, which writes the catalogue
from the code. This project generates it from `Scripts/translations.json`
instead, because the translations are maintained there rather than in Xcode,
and the price of that choice is exactly this failure mode. This is the check
that pays it.

Placeholder types are not asserted. Deciding whether `\\(x)` is `%@` or `%lld`
means knowing Swift types, which needs a compiler; instead a key matches if
*any* assignment of `%@`/`%lld` to its slots is present. That still catches
the whole "no such key" class, which is the one that has actually bitten.
"""
from __future__ import annotations

import itertools
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEARCHED = ["Hours", "HoursWidget", "HoursShared"]

# Both localizing initializers, across line breaks: these calls wrap.
CALL = re.compile(r'(?:localized|inflected):\s*"((?:[^"\\]|\\.)*)"', re.S)


def strip_comments(source: str) -> str:
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in source.split("\n"))


def key_shapes(literal: str) -> list[str]:
    """Every catalogue key this literal could be looking up.

    An inflected count — `^[\\(n) day](inflect: true)` — is always `%lld`;
    the placeholder sits inside markup that only takes a number. Everything
    else could be either, so both are offered.
    """
    pieces: list[str] = []
    fixed: list[str | None] = []
    i = 0
    while i < len(literal):
        if literal.startswith("\\(", i):
            depth, j = 0, i + 1
            while j < len(literal):
                if literal[j] == "(":
                    depth += 1
                elif literal[j] == ")":
                    depth -= 1
                    if depth == 0:
                        j += 1
                        break
                j += 1
            pieces.append("\x00")
            fixed.append("%lld" if "".join(pieces).endswith("^[\x00") else None)
            i = j
        else:
            pieces.append(literal[i])
            i += 1

    template = "".join(pieces)
    slots = [f for f in fixed]
    options = [[f] if f else ["%@", "%lld"] for f in slots]
    shapes = []
    for combination in itertools.product(*options) if options else [()]:
        out, it = [], iter(combination)
        for char in template:
            out.append(next(it) if char == "\x00" else char)
        shapes.append("".join(out))
    return shapes or [literal]


def main() -> int:
    catalogue = json.loads((ROOT / "Hours/Resources/Localizable.xcstrings").read_text("utf-8"))
    widget = json.loads((ROOT / "HoursWidget/Localizable.xcstrings").read_text("utf-8"))
    known = set(catalogue["strings"]) | set(widget["strings"])

    missing = []
    for folder in SEARCHED:
        for path in sorted((ROOT / folder).rglob("*.swift")):
            if "Tests" in path.name:
                continue
            source = strip_comments(path.read_text(encoding="utf-8"))
            for match in CALL.finditer(source):
                literal = match.group(1)
                shapes = key_shapes(literal)
                if any(shape in known for shape in shapes):
                    continue
                line = source[: match.start()].count("\n") + 1
                missing.append((path.relative_to(ROOT), line, shapes[0]))

    if missing:
        print(f"{len(missing)} lookup(s) with no key in the catalogue:\n")
        for path, line, key in missing:
            print(f"  {path}:{line}")
            print(f"      {key[:100]}")
        print(
            "\nEach of these returns its own key at runtime, which is the English "
            "text — so\nthe app reads correctly in English and stays English in the "
            "other nine languages.\nAdd the key to Scripts/translations.json and run "
            "Scripts/build-catalog.py."
        )
        return 1

    print(f"every lookup has a key ({len(known)} in the catalogues)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
