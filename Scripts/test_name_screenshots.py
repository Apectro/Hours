#!/usr/bin/env python3
"""Tests for name-screenshots.py, against a manifest Xcode actually wrote.

The fixture beside this file is copied verbatim from a CI run's log, with the
UUIDs of the shots that were not printed filled in. That provenance is the
point: the first two versions of the renamer were written against a manifest
I imagined, and both were wrong in ways a made-up fixture agreed with.

Run: python3 Scripts/test_name_screenshots.py
"""

import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import importlib.util

_spec = importlib.util.spec_from_file_location(
    "name_screenshots",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "name-screenshots.py"),
)
name_screenshots = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(name_screenshots)

FIXTURE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "Fixtures", "manifest-xcode26.json"
)


class RenamingTests(unittest.TestCase):
    def setUp(self):
        self.raw = tempfile.mkdtemp()
        self.out = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.raw, True)
        self.addCleanup(shutil.rmtree, self.out, True)
        shutil.copyfile(FIXTURE, os.path.join(self.raw, "manifest.json"))
        with open(FIXTURE) as handle:
            manifest = json.load(handle)
        for entry in manifest[0]["attachments"]:
            with open(os.path.join(self.raw, entry["exportedFileName"]), "wb") as png:
                png.write(b"not really a png")

    def run_it(self):
        name_screenshots.main(self.raw, self.out)
        return sorted(os.listdir(self.out))

    def test_every_shot_gets_the_name_the_test_gave_it(self):
        self.assertEqual(
            self.run_it(),
            [
                "01-calendar.png",
                "02-day-editor.png",
                "03-insights.png",
                "04-settings.png",
                "05-privacy.png",
            ],
        )

    def test_xctests_own_screenshots_are_left_out(self):
        # kXCTAttachmentLegacyScreenImageData is XCTest photographing whatever
        # was on screen when a step ran. It is not a listing shot.
        self.assertNotIn("kXCTAttachmentLegacyScreenImageData.png", self.run_it())

    def test_the_scheme_name_is_never_mistaken_for_the_shots_name(self):
        # Four keys in a manifest entry end in "Name". Taking whichever came
        # first named all five files "Test Scheme Action" and shipped nothing.
        self.assertNotIn("Test-Scheme-Action.png", self.run_it())
        self.assertIsNone(name_screenshots.label_key_rank("configurationName"))
        self.assertIsNone(name_screenshots.label_key_rank("deviceName"))

    def test_xcodes_decoration_comes_back_off(self):
        self.assertEqual(
            name_screenshots.tidy("01-calendar_0_14ABDA6E-77DC-466B-8D0B-901055A459EA.png"),
            "01-calendar",
        )
        # A name that was never decorated survives unchanged.
        self.assertEqual(name_screenshots.tidy("01-calendar"), "01-calendar")

    def test_a_manifest_that_cannot_be_read_is_a_warning_not_a_crash(self):
        os.remove(os.path.join(self.raw, "manifest.json"))
        self.assertEqual(self.run_it(), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
