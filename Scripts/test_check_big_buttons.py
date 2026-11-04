#!/usr/bin/env python3
"""Tests for check-big-buttons.py: the app as it stands passes, and the
squeezed button it was written for (and its cousins) fails.

Run: python3 Scripts/test_check_big_buttons.py
"""

import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "check-big-buttons.py")

spec = importlib.util.spec_from_file_location("check_big_buttons", SCRIPT)
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

SQUEEZED = """
HStack {
    Button("Send as message") { send() }
        .buttonStyle(.bigAction(.primary))
        .layoutPriority(1)
        .accessibilityIdentifier("missing-send-message")
    Button("PDF") { pdf() }
        .buttonStyle(.bigAction(.secondary))
}
"""


class BigButtonCheckTests(unittest.TestCase):
    def test_the_squeezed_button_fails(self):
        self.assertEqual(check.scan(SQUEEZED), [(5, ".layoutPriority")])

    def test_a_fixed_width_or_size_fails(self):
        for modifier, name in [
            (".fixedSize()", ".fixedSize"),
            (".fixedSize(horizontal: true, vertical: false)", ".fixedSize"),
            (".frame(width: 120)", ".frame(width:"),
        ]:
            source = SQUEEZED.replace(".layoutPriority(1)", modifier)
            self.assertEqual(check.scan(source), [(5, name)], modifier)

    def test_growing_down_and_plain_buttons_pass(self):
        self.assertEqual(check.scan(SQUEEZED.replace(".layoutPriority(1)", ".fixedSize(horizontal: false, vertical: true)")), [])
        self.assertEqual(check.scan(SQUEEZED.replace(".layoutPriority(1)", "")), [])
        self.assertEqual(check.scan('Text("x")\n    .layoutPriority(1)\n'), [])

    def test_only_the_lines_right_after_count(self):
        far = SQUEEZED.replace(".layoutPriority(1)\n", "\n\n\n.layoutPriority(1)\n")
        self.assertEqual(check.scan(far), [])

    def test_the_app_passes_and_a_planted_one_fails(self):
        result = subprocess.run([sys.executable, SCRIPT], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

        root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, root, True)
        os.makedirs(os.path.join(root, "Hours", "Features"))
        with open(os.path.join(root, "Hours", "Features", "Sheet.swift"), "w") as f:
            f.write(SQUEEZED)
        result = subprocess.run([sys.executable, SCRIPT, root], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("Hours/Features/Sheet.swift:5", result.stdout)


if __name__ == "__main__":
    unittest.main()
