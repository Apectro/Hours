#!/usr/bin/env python3
"""Splits the UI test classes into parts that take about as long as each other.

    python3 Scripts/ui-test-shards.py <part> <parts>

prints the xcodebuild arguments that run part <part> (0-based) of <parts>:
`-only-testing:HoursUITests/<Class>` for each class in it. Every class in
HoursUITests is in exactly one part, so a class added later is never left out;
one that is not in Scripts/ui-test-timings.json counts as 60 seconds.

Left out of every part: the screen atlas and the walkthrough, which ordinary
runs skip, and the store screenshots, which the main job runs itself.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
EXCLUDED = {"ScreenAtlasTests", "WalkthroughTests", "ScreenshotTests"}
DEFAULT_SECONDS = 60
CLASS = re.compile(r"^\s*(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase\b", re.M)


def test_classes():
    names = set()
    for path in sorted((ROOT / "HoursUITests").glob("*.swift")):
        names.update(CLASS.findall(path.read_text(encoding="utf-8")))
    return sorted(names - EXCLUDED)


def parts(count):
    timings = json.loads((ROOT / "Scripts" / "ui-test-timings.json").read_text(encoding="utf-8"))
    weight = lambda name: timings.get(name, DEFAULT_SECONDS)
    buckets = [[0, []] for _ in range(count)]
    # Longest first into the lightest part: close enough to even for a
    # couple of dozen classes, and the same input always gives the same split.
    for name in sorted(test_classes(), key=lambda n: (-weight(n), n)):
        lightest = min(buckets, key=lambda b: b[0])
        lightest[0] += weight(name)
        lightest[1].append(name)
    return buckets


def main(argv):
    if len(argv) != 3:
        sys.exit(__doc__)
    part, count = int(argv[1]), int(argv[2])
    if not 0 <= part < count:
        sys.exit(f"part must be between 0 and {count - 1}")
    seconds, names = parts(count)[part]
    print(f"part {part + 1} of {count}: about {seconds // 60} min, {len(names)} classes", file=sys.stderr)
    print(" ".join(f"-only-testing:HoursUITests/{name}" for name in names))


if __name__ == "__main__":
    main(sys.argv)
