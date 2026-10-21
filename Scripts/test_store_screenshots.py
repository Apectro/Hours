#!/usr/bin/env python3
"""Tests for store-screenshots.py, which lays the CI shots out for deliver.

The failure it guards against is a green upload of the wrong pictures: an
export capture that happens to share a number with a listing shot, or a set
from a phone App Store Connect has no slot for. Both were possible with the
folders as CI writes them, so both are tested here, on Linux, where it costs
nothing.

Run: python3 Scripts/test_store_screenshots.py
"""

import importlib.util
import os
import shutil
import struct
import tempfile
import unittest
import zlib

_spec = importlib.util.spec_from_file_location(
    "store_screenshots",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "store-screenshots.py"),
)
store = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(store)


def png(path, width, height):
    """A real PNG header with the given size; the pixels are never read."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IEND", b""))


LISTING = ["01-calendar", "02-site", "06-pay"]


class LayoutTests(unittest.TestCase):
    def setUp(self):
        self.shots = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.shots, True)

    def folder(self, name, size, names):
        os.makedirs(os.path.join(self.shots, name))
        for item in names:
            png(os.path.join(self.shots, name, item + ".png"), *size)

    def test_only_the_listing_goes_in_and_in_order(self):
        self.folder("iPhone-17-Pro-Max", (1320, 2868), LISTING + ["06-export-pdf-1", "07-export-pdf-summary"])
        self.folder("iPhone-17-Pro-Max-de", (1320, 2868), LISTING)
        problems = store.assemble(self.shots, LISTING, {"iphone": "iPhone-17-Pro-Max"})
        self.assertEqual(problems, [])
        for locale in ("en-US", "de-DE"):
            self.assertEqual(
                sorted(os.listdir(os.path.join(self.shots, "app-store", locale))),
                ["iphone-01-calendar.png", "iphone-02-site.png", "iphone-06-pay.png"],
            )

    def test_a_size_with_no_slot_is_refused(self):
        # An iPhone 17 Pro: 6.3 inches, which is not the 6.9-inch slot.
        self.folder("iPhone-17-Pro", (1206, 2622), LISTING)
        self.folder("iPhone-17-Pro-de", (1206, 2622), LISTING)
        problems = store.assemble(self.shots, LISTING, {"iphone": "iPhone-17-Pro"})
        self.assertTrue(any("1206×2622" in p for p in problems), problems)
        self.assertFalse(os.path.exists(os.path.join(self.shots, "app-store", "en-US", "iphone-01-calendar.png")))

    def test_a_missing_shot_is_reported(self):
        self.folder("iPhone-16-Pro-Max", (1320, 2868), LISTING[:2])
        self.folder("iPhone-16-Pro-Max-de", (1320, 2868), LISTING)
        problems = store.assemble(self.shots, LISTING, {"iphone": "iPhone-16-Pro-Max"})
        self.assertEqual(problems, ["en-US iphone: 06-pay.png is missing"])

    def test_ipad_goes_beside_the_iphone(self):
        self.folder("iPhone-15-Pro-Max", (1290, 2796), LISTING)
        self.folder("iPhone-15-Pro-Max-de", (1290, 2796), LISTING)
        self.folder("iPad-Pro-13-inch-M4", (2064, 2752), LISTING)
        self.folder("iPad-Pro-13-inch-M4-de", (2064, 2752), LISTING)
        problems = store.assemble(
            self.shots, LISTING, {"iphone": "iPhone-15-Pro-Max", "ipad": "iPad-Pro-13-inch-M4"}
        )
        self.assertEqual(problems, [])
        self.assertEqual(len(os.listdir(os.path.join(self.shots, "app-store", "de-DE"))), 6)

    def test_the_listing_file_skips_comments(self):
        path = os.path.join(self.shots, "list.txt")
        with open(path, "w") as handle:
            handle.write("# a comment\n\n01-calendar\n02-site\n")
        self.assertEqual(store.read_listing(path), ["01-calendar", "02-site"])


if __name__ == "__main__":
    unittest.main()
