#!/usr/bin/env python3
"""Give the exported test attachments the names the test gave them.

`xcresulttool export attachments` names every file after its UUID, which is
useless for an App Store listing where the order is half the argument. The
manifest it writes alongside them carries the name each attachment was given
in the test, so this puts the two back together.

Usage: name-screenshots.py <exported-dir> <output-dir>
"""

import json
import os
import re
import shutil
import sys


def pairs(node):
    """Every (file on disk, name a human chose) pair anywhere in the manifest.

    Written loosely on purpose: the manifest's key names are Xcode's, not
    ours, and they have changed between versions. Matching on the shape of
    the data rather than on exact keys means a rename upstream costs a
    warning here instead of a silent directory of UUIDs.
    """
    if isinstance(node, dict):
        filename = next(
            (v for k, v in node.items()
             if re.search(r"file_?ame|file ?name", k, re.I) and isinstance(v, str)),
            None,
        )
        label = next(
            (v for k, v in node.items()
             if re.search(r"name", k, re.I) and isinstance(v, str) and v != filename),
            None,
        )
        if filename:
            yield filename, label
        for value in node.values():
            yield from pairs(value)
    elif isinstance(node, list):
        for value in node:
            yield from pairs(value)


# The names ScreenshotTests gives its captures: "01-calendar" and its four
# siblings. XCTest attaches automatic screenshots of its own under names like
# "kXCTAttachmentLegacyScreenImageData", and those are a picture of whatever
# the simulator was showing when a step ran — not something to put on a store
# listing. Requiring the numbered form is what separates the two.
OURS = re.compile(r"^\d{2}-[a-z0-9-]+$", re.I)


def main(raw, out):
    named = {}
    manifest = os.path.join(raw, "manifest.json")
    try:
        with open(manifest) as handle:
            named = {f: n for f, n in pairs(json.load(handle)) if n}
    except Exception as error:  # noqa: BLE001 - a warning is the useful outcome
        print(f"::warning::could not read {manifest}: {error}")

    os.makedirs(out, exist_ok=True)
    kept = 0
    for entry in sorted(os.listdir(raw)):
        if not entry.lower().endswith(".png"):
            continue
        label = (named.get(entry) or "").removesuffix(".png")
        if not OURS.match(label):
            print(f"skipping {entry} ({label or 'unnamed'})")
            continue
        shutil.copyfile(os.path.join(raw, entry), os.path.join(out, f"{label}.png"))
        print(f"{entry} -> {label}.png")
        kept += 1

    print(f"named screenshots: {kept}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
