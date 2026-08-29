#!/usr/bin/env python3
"""Fail when a writing path builds a repository without the month lock.

`WorkdayRepository(context:)` defaults its lock to `.unlocked`, because most
of the twenty-odd construction sites only read. That default is convenient and
it is also exactly the shape of a bug that cannot be seen: a screen that writes
days, built without the lock, silently keeps accepting edits to a closed month
and looks completely correct.

So: any file that calls `save(` or `delete(on:` on a repository must pass a
lock where it builds one. Reading paths are left alone, and the two writing
paths that are unlocked on purpose say so here rather than in a comment nobody
greps for.

A grep, so it runs on Linux in seconds on every push.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEARCHED = ["Hours"]

CONSTRUCTS = re.compile(r"WorkdayRepository\(")
WITH_LOCK = re.compile(r"WorkdayRepository\([^)]*lock:")
WRITES = re.compile(r"(?:^|[^\w.])(?:try |try\? )?\w*[Rr]epository\.(?:save|delete)\(")

# Writing paths that are deliberately unlocked, each with the reason.
EXEMPT = {
    "Hours/Data/Store/SampleData.swift":
        "seeds a fresh store for screenshots and the simulator; nothing is closed yet",
    "Hours/Features/Shared/PreviewSupport.swift":
        "builds an in-memory store for Xcode previews",
    "Hours/Features/Settings/DataSettingsScreen.swift":
        "a restore is the file becoming the database, not an edit to a closed month",
}


def main() -> int:
    problems = []
    for folder in SEARCHED:
        for path in sorted((ROOT / folder).rglob("*.swift")):
            source = path.read_text(encoding="utf-8")
            source = re.sub(r"//.*$", "", source, flags=re.M)
            rel = str(path.relative_to(ROOT))

            if not WRITES.search(source):
                continue
            if not CONSTRUCTS.search(source):
                continue  # writes through a repository somebody else built
            if rel in EXEMPT:
                continue
            if WITH_LOCK.search(source):
                continue
            line = source[: CONSTRUCTS.search(source).start()].count("\n") + 1
            problems.append((rel, line))

    if problems:
        print(f"{len(problems)} writing path(s) building an unlocked repository:\n")
        for rel, line in problems:
            print(f"  {rel}:{line}")
        print(
            "\nThis file writes days and builds its own repository without a lock, so\n"
            "edits to a closed month go through and nothing says otherwise.\n"
            "Pass `lock: settingsStore.settings.monthLock` — or, if being unlocked is\n"
            "the point, add the file to EXEMPT here with the reason."
        )
        return 1

    stale = [name for name in EXEMPT if not (ROOT / name).exists()]
    if stale:
        print(f"EXEMPT names files that no longer exist: {stale}")
        return 1

    print(f"every writing path passes a lock ({len(EXEMPT)} exempt, with reasons)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
