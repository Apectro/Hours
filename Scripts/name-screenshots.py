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
OURS = re.compile(r"^\d{2}-[a-z0-9-]+(\.[a-z0-9]+)?$", re.I)

# Screenshots, plus the files the export tests produce. Anything else an
# attachment might be is not something to publish.
KEPT_TYPES = {".png", ".csv", ".xlsx", ".pdf", ".txt"}


def tidy(label):
    """The name the test asked for, with Xcode's decoration taken back off.

    The decoration sits before the extension — "01-calendar_0_<UUID>.png" —
    so the extension has to come off first or the anchored pattern never
    matches. Getting that wrong silently drops every non-PNG attachment,
    which is the same shape of failure as the original UUID bug.
    """
    label = label or ""
    stem, suffix = os.path.splitext(label)
    if suffix.lower() not in KEPT_TYPES:
        stem, suffix = label, ""
    stem = DECORATION.sub("", stem)
    # A name the test already spelled with an extension keeps its own.
    if os.path.splitext(stem)[1].lower() in KEPT_TYPES:
        return stem
    return stem + suffix


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
        if entry == "manifest.json":
            continue
        suffix = os.path.splitext(entry)[1].lower()
        if suffix not in KEPT_TYPES:
            continue
        label = tidy(named.get(entry))
        if not OURS.match(label):
            print(f"skipping {entry} ({label or 'unnamed'})")
            continue
        # The exported CSV and workbook carry their own extension in the name
        # the test gave them; a screenshot does not.
        name = label if os.path.splitext(label)[1] else label + suffix
        shutil.copyfile(os.path.join(raw, entry), os.path.join(out, name))
        print(f"{entry} -> {name}")
        kept += 1

    print(f"named screenshots: {kept}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
