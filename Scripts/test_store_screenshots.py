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


WATCH_LISTING = ["01-running", "02-day"]


class WatchTests(unittest.TestCase):
    """The Apple Watch set: English only, from its own folder and list."""

    def setUp(self):
        self.shots = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.shots, True)

    def folder(self, name, size, names):
        os.makedirs(os.path.join(self.shots, name))
        for item in names:
            png(os.path.join(self.shots, name, item + ".png"), *size)

    def test_watch_shots_go_beside_the_iphone_in_english(self):
        self.folder("Apple-Watch-Ultra-3-49mm", (422, 514), WATCH_LISTING)
        problems = store.assemble_watch(self.shots, WATCH_LISTING, "Apple-Watch-Ultra-3-49mm")
        self.assertEqual(problems, [])
        self.assertEqual(
            sorted(os.listdir(os.path.join(self.shots, "app-store", "en-US"))),
            ["watch-01-running.png", "watch-02-day.png"],
        )
        self.assertFalse(os.path.exists(os.path.join(self.shots, "app-store", "de-DE", "watch-01-running.png")))

    def test_every_size_deliver_maps_to_a_watch_is_taken(self):
        for size in [(410, 502), (422, 514), (416, 496), (396, 484), (368, 448)]:
            with self.subTest(size=size):
                folder = f"watch-{size[0]}"
                self.folder(folder, size, WATCH_LISTING[:1])
                self.assertEqual(store.assemble_watch(self.shots, WATCH_LISTING[:1], folder), [])

    def test_a_watch_size_with_no_slot_is_refused(self):
        # A 41 mm Series 7: smaller than any slot App Store Connect has.
        self.folder("Apple-Watch-Series-7-41mm", (352, 430), WATCH_LISTING)
        problems = store.assemble_watch(self.shots, WATCH_LISTING, "Apple-Watch-Series-7-41mm")
        self.assertTrue(any("352×430" in p for p in problems), problems)

    def test_a_missing_watch_shot_is_reported(self):
        self.folder("Apple-Watch-Ultra-2-49mm", (410, 502), WATCH_LISTING[:1])
        problems = store.assemble_watch(self.shots, WATCH_LISTING, "Apple-Watch-Ultra-2-49mm")
        self.assertEqual(problems, ["en-US watch: 02-day.png is missing"])

    def test_the_watch_list_carries_launch_arguments(self):
        path = os.path.join(self.shots, "watch.txt")
        with open(path, "w") as handle:
            handle.write("# a comment\n\n01-running -hours-sample-data\n02-day -hours-sample-data -hours-sample-clock-stopped\n")
        self.assertEqual(store.read_listing(path), WATCH_LISTING)

    def test_the_command_line_takes_a_watch_folder(self):
        self.folder("iPhone-17-Pro-Max", (1320, 2868), LISTING)
        self.folder("iPhone-17-Pro-Max-de", (1320, 2868), LISTING)
        self.folder("Apple-Watch-Ultra-3-49mm", (422, 514), WATCH_LISTING)
        listing = os.path.join(self.shots, "listing.txt")
        with open(listing, "w") as handle:
            handle.write("\n".join(LISTING) + "\n")
        watch = os.path.join(self.shots, "watch.txt")
        with open(watch, "w") as handle:
            handle.write("01-running -hours-sample-data\n02-day -hours-sample-data\n")
        status = store.main([
            "store-screenshots.py", self.shots, listing, "iPhone-17-Pro-Max",
            "--watch", "Apple-Watch-Ultra-3-49mm", watch,
        ])
        self.assertEqual(status, 0)
        self.assertEqual(len(os.listdir(os.path.join(self.shots, "app-store", "en-US"))), 5)


if __name__ == "__main__":
    unittest.main()
