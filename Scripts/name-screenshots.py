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


# A manifest entry, as Xcode 26 writes it:
#
#     {
#       "configurationName": "Test Scheme Action",
#       "deviceName": "iPhone 17 Pro",
#       "exportedFileName": "4C5D85BB-....png",
#       "isAssociatedWithFailure": false,
#       "suggestedHumanReadableName": "01-calendar_0_14ABDA6E-....png",
#       "timestamp": 1787725824.161
#     }
#
# Four keys there end in "Name" and only one of them is the attachment's. The
# first version of this script took whichever came first and named every file
# "Test Scheme Action", so the ranking below is the whole point: keys are
# scored, best wins, and a key naming a device or a scheme is never eligible.
FILE_KEY = re.compile(r"file_?name", re.I)
NEVER = re.compile(r"device|configuration|scheme|class|target|test|module", re.I)


def label_key_rank(key):
    """How likely a key is to hold the name the test gave its attachment."""
    if NEVER.search(key):
        return None
    if re.search(r"human", key, re.I):
        return 0
    if re.search(r"suggested", key, re.I):
        return 1
    if key.lower() in ("name", "attachmentname"):
        return 2
    return None


def pairs(node):
    """Every (file on disk, name the test chose) pair anywhere in the manifest.

    Still walks the whole tree rather than assuming the layout above: the
    manifest is Xcode's, not ours, and it has changed between versions. What
    is no longer loose is which key wins.
    """
    if isinstance(node, dict):
        filename = next(
            (v for k, v in node.items() if FILE_KEY.search(k) and isinstance(v, str)),
            None,
        )
        candidates = sorted(
            (rank, v)
            for k, v in node.items()
            if isinstance(v, str) and v != filename and (rank := label_key_rank(k)) is not None
        )
        if filename:
            yield filename, candidates[0][1] if candidates else None
        for value in node.values():
            yield from pairs(value)
    elif isinstance(node, list):
        for value in node:
            yield from pairs(value)


# Xcode appends "_<n>_<UUID>" to the name the test gave: "01-calendar" comes
# back as "01-calendar_0_14ABDA6E-77DC-466B-8D0B-901055A459EA.png".
DECORATION = re.compile(r"_\d+_[0-9A-F-]{36}$", re.I)

# The names ScreenshotTests gives its captures: "01-calendar" and its four
# siblings. XCTest attaches automatic screenshots of its own under names like
# "kXCTAttachmentLegacyScreenImageData", and those are a picture of whatever
# the simulator was showing when a step ran — not something to put on a store
# listing. Requiring the numbered form is what separates the two.
OURS = re.compile(r"^\d{2}-[a-z0-9-]+$", re.I)


def tidy(label):
    """The name the test asked for, with Xcode's decoration taken back off."""
    return DECORATION.sub("", (label or "").removesuffix(".png"))


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
        label = tidy(named.get(entry))
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
