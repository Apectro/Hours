#!/usr/bin/env python3
"""Lay the CI screenshots out the way `fastlane deliver` uploads them.

CI writes a folder per device and language — `iPhone-17-Pro-Max`,
`iPhone-17-Pro-Max-de` — and the primary one also holds whatever else the
test run attached: rendered export pages numbered 06 and 07, a CSV, a
workbook. deliver wants `<dir>/<locale>/*.png`, takes every PNG it finds
there, works out the device from the pixel size, and orders by filename.

So this copies exactly the shots named in `fastlane/screenshots.txt`, in that
order, into `app-store/en-US/` and `app-store/de-DE/`, prefixed by device so
the iPhone and iPad sets sort apart. A shot whose size has no slot in App
Store Connect is left out and reported rather than uploaded to fail there.

The Apple Watch set comes from its own folder and its own list
(`fastlane/watch-screenshots.txt`, a name and the watch app's launch
arguments per line) and goes into `app-store/en-US/` only, as
`watch-<name>.png`: the store shows the primary language's watch shots on
every page, and the watch app has no German capture.

Usage: store-screenshots.py <screenshots-dir> <listing-file> <iphone-folder> [<ipad-folder>]
                            [--watch <watch-folder> <watch-listing-file>]
Exits 1 when anything was missing or the wrong size.
"""

import os
import shutil
import struct
import sys

# German shots live beside the English ones, in "<device>-de".
LOCALES = {"en-US": "", "de-DE": "-de"}

# Portrait pixel sizes App Store Connect accepts for the one slot per device
# it still requires: the 6.9-inch iPhone (the 6.7-inch sizes are taken in
# that slot) and the 13-inch iPad.
ACCEPTED = {
    "iphone": {(1320, 2868), (1290, 2796), (1260, 2736)},
    "ipad": {(2064, 2752), (2048, 2732)},
    # Every Apple Watch size fastlane deliver maps to a display type and
    # App Store Connect takes in its one watch slot: Ultra 3 and Ultra 2,
    # Series 10/11 46 mm, Series 7–9 45 mm and Series 4–6 44 mm. The first
    # three need fastlane 2.230 or newer to be recognised.
    "watch": {(422, 514), (410, 502), (416, 496), (396, 484), (368, 448)},
}

# The watch set goes into the primary language only.
WATCH_LOCALE = "en-US"


def read_listing(path):
    """The shot names, in order. A line may carry more after the name — the
    watch list's launch arguments — which is not part of the name."""
    with open(path, encoding="utf-8") as handle:
        return [
            line.split()[0]
            for line in handle
            if line.strip() and not line.lstrip().startswith("#")
        ]


def png_size(path):
    """Width and height from the IHDR chunk, which is always first."""
    with open(path, "rb") as handle:
        head = handle.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", head[16:24])


def copy_checked(path, device, label, target):
    """Copies one shot when it is there and the right size; else a problem."""
    name = os.path.basename(path)
    if not os.path.isfile(path):
        return f"{label} {device}: {name} is missing"
    size = png_size(path)
    if size not in ACCEPTED[device]:
        shown = "×".join(map(str, size)) if size else "not a PNG"
        return f"{label} {device}: {name} is {shown}, which App Store Connect has no slot for"
    shutil.copyfile(path, os.path.join(target, f"{device}-{name}"))
    return None


def assemble_watch(shots, listing, folder):
    """Copies the watch shots into `<shots>/app-store/en-US/`. Returns problems."""
    target = os.path.join(shots, "app-store", WATCH_LOCALE)
    os.makedirs(target, exist_ok=True)
    problems = []
    for name in listing:
        problem = copy_checked(os.path.join(shots, folder, name + ".png"), "watch", WATCH_LOCALE, target)
        if problem:
            problems.append(problem)
    return problems


def assemble(shots, listing, devices):
    """Copies the listing into `<shots>/app-store/<locale>/`. Returns problems."""
    problems = []
    for locale, suffix in LOCALES.items():
        target = os.path.join(shots, "app-store", locale)
        os.makedirs(target, exist_ok=True)
        for device, folder in devices.items():
            source = os.path.join(shots, folder + suffix)
            for name in listing:
                problem = copy_checked(os.path.join(source, name + ".png"), device, locale, target)
                if problem:
                    problems.append(problem)
    return problems


def main(argv):
    argv = list(argv)
    watch = None
    if "--watch" in argv:
        at = argv.index("--watch")
        if len(argv) < at + 3:
            sys.exit(__doc__)
        watch = (argv[at + 1], argv[at + 2])
        del argv[at:at + 3]
    if len(argv) not in (4, 5):
        sys.exit(__doc__)
    shots, listing_file, iphone = argv[1:4]
    devices = {"iphone": iphone}
    if len(argv) == 5 and argv[4]:
        devices["ipad"] = argv[4]
    problems = assemble(shots, read_listing(listing_file), devices)
    if watch:
        problems += assemble_watch(shots, read_listing(watch[1]), watch[0])
    for locale in LOCALES:
        folder = os.path.join(shots, "app-store", locale)
        print(f"{locale}: {len(os.listdir(folder))} screenshots")
    for problem in problems:
        print(f"::warning::{problem}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
