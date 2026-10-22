#!/usr/bin/env python3
"""Tests for check-cloudkit-models.py.

The check runs against a copy of the real models and schema, so the clean
case is the store as it stands, and each failing case is that same store with
exactly one thing CloudKit refuses planted in it. A check that passed the real
store and also passed every plant would be a check of nothing.

Run: python3 Scripts/test_check_cloudkit_models.py
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SCRIPT = os.path.join(HERE, "check-cloudkit-models.py")
MODELS = os.path.join("Hours", "Data", "Models")
SCHEMA = os.path.join("Hours", "Data", "Store", "HoursSchema.swift")


class CloudKitModelCheckTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, True)
        shutil.copytree(os.path.join(REPO, MODELS), os.path.join(self.root, MODELS))
        os.makedirs(os.path.dirname(os.path.join(self.root, SCHEMA)))
        shutil.copyfile(os.path.join(REPO, SCHEMA), os.path.join(self.root, SCHEMA))

    def run_check(self):
        result = subprocess.run(
            [sys.executable, SCRIPT, self.root], capture_output=True, text=True
        )
        return result.returncode, result.stdout + result.stderr

    def replace(self, relative, old, new):
        path = os.path.join(self.root, relative)
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        self.assertIn(old, source, f"the plant's anchor is gone from {relative}")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(source.replace(old, new, 1))

    def add_model_file(self, name, source):
        with open(os.path.join(self.root, MODELS, name), "w", encoding="utf-8") as handle:
            handle.write(source)

    def newest_version(self):
        """The highest HoursSchemaV<n> in the copied schema: the live one.

        Read rather than written down, so these tests keep planting into the
        live version when the next one is added.
        """
        with open(os.path.join(self.root, SCHEMA), encoding="utf-8") as handle:
            source = handle.read()
        return max(int(n) for n in re.findall(r"enum\s+HoursSchemaV(\d+)\s*:\s*VersionedSchema", source))

    def list_in_schema(self, *names):
        """Adds models to the live version's list, the last thing in its array."""
        path = os.path.join(self.root, SCHEMA)
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
        start = source.index(f"enum HoursSchemaV{self.newest_version()}")
        close = source.index("\n        ]", source.index("static var models", start))
        extra = "".join(f", {name}.self" for name in names)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(source[:close] + extra + source[close:])

    def assertFails(self, *needles):
        code, output = self.run_check()
        self.assertEqual(code, 1, output)
        for needle in needles:
            self.assertIn(needle, output)

    # The real store

    def test_the_store_as_it_stands_passes(self):
        code, output = self.run_check()
        self.assertEqual(code, 0, output)
        # It must have actually looked: all eight live entities are named.
        for name in [
            "DayEntry", "HolidayRecord", "SiteEntry", "CrewMemberEntry",
            "SiteDayEntry", "SiteDiaryEntry", "SiteDiaryPhotoEntry", "CrewSignatureEntry",
        ]:
            self.assertIn(name, output)

    def test_the_frozen_v1_unique_constraint_is_not_the_live_schema(self):
        # V1 carries @Attribute(.unique) and must keep it: it describes stores
        # written before sync. Only the newest version is what CloudKit sees.
        with open(os.path.join(self.root, SCHEMA), encoding="utf-8") as handle:
            self.assertIn("@Attribute(.unique)", handle.read())
        code, output = self.run_check()
        self.assertEqual(code, 0, output)

    # One plant each

    def test_a_unique_attribute_fails(self):
        self.replace(os.path.join(MODELS, "DayEntry.swift"),
                     "    var dateKey: Int = 0", "    @Attribute(.unique) var dateKey: Int = 0")
        self.assertFails("DayEntry.dateKey", "unique")

    def test_a_unique_attribute_on_the_line_above_fails(self):
        self.replace(os.path.join(MODELS, "SiteEntry.swift"),
                     "    var siteID: String = \"\"", "    @Attribute(.unique)\n    var siteID: String = \"\"")
        self.assertFails("SiteEntry.siteID", "unique")

    def test_a_unique_macro_fails(self):
        self.replace(os.path.join(MODELS, "SiteDayEntry.swift"),
                     "final class SiteDayEntry {",
                     "final class SiteDayEntry {\n    #Unique<SiteDayEntry>([\\.siteID, \\.dateKey])")
        self.assertFails("SiteDayEntry", "#Unique")

    def test_a_required_attribute_without_a_default_fails(self):
        self.replace(os.path.join(MODELS, "HolidayRecord.swift"),
                     "    var name: String = \"\"", "    var name: String")
        self.assertFails("HolidayRecord.name", "default")

    def test_a_computed_property_is_not_an_attribute(self):
        self.replace(os.path.join(MODELS, "HolidayRecord.swift"),
                     "    var createdAt: Date = Date()\n",
                     "    var createdAt: Date = Date()\n    var shout: String { name.uppercased() }\n")
        code, output = self.run_check()
        self.assertEqual(code, 0, output)

    def test_a_transient_property_is_not_an_attribute(self):
        self.replace(os.path.join(MODELS, "HolidayRecord.swift"),
                     "    var createdAt: Date = Date()\n",
                     "    var createdAt: Date = Date()\n    @Transient var scratch: Int\n")
        code, output = self.run_check()
        self.assertEqual(code, 0, output)

    def test_a_relationship_that_is_not_optional_fails(self):
        self.add_model_file("Planted.swift", """
import SwiftData

@Model
final class Parent {
    var name: String = ""
    @Relationship(deleteRule: .cascade, inverse: \\Child.parent) var children: [Child] = []
}

@Model
final class Child {
    var name: String = ""
    var parent: Parent?
}
""")
        self.list_in_schema("Parent", "Child")
        self.assertFails("Parent.children", "optional")

    def test_a_relationship_with_no_inverse_fails(self):
        self.add_model_file("Planted.swift", """
import SwiftData

@Model
final class Parent {
    var name: String = ""
    @Relationship(deleteRule: .cascade) var children: [Child]?
}

@Model
final class Child {
    var name: String = ""
}
""")
        self.list_in_schema("Parent", "Child")
        self.assertFails("Parent.children", "inverse")

    def test_an_inverse_declared_on_the_other_side_is_enough(self):
        self.add_model_file("Planted.swift", """
import SwiftData

@Model
final class Parent {
    var name: String = ""
    @Relationship(deleteRule: .cascade, inverse: \\Child.parent) var children: [Child]?
}

@Model
final class Child {
    var name: String = ""
    var parent: Parent?
}
""")
        self.list_in_schema("Parent", "Child")
        code, output = self.run_check()
        self.assertEqual(code, 0, output)

    def test_a_deny_delete_rule_fails(self):
        self.add_model_file("Planted.swift", """
import SwiftData

@Model
final class Parent {
    var name: String = ""
    @Relationship(deleteRule: .deny, inverse: \\Child.parent) var children: [Child]?
}

@Model
final class Child {
    var name: String = ""
    var parent: Parent?
}
""")
        self.list_in_schema("Parent", "Child")
        self.assertFails("Parent.children", ".deny")

    def test_a_model_missing_from_the_live_schema_fails(self):
        self.add_model_file("Planted.swift", """
import SwiftData

@Model
final class Forgotten {
    var name: String = ""
}
""")
        self.assertFails("Forgotten", f"HoursSchemaV{self.newest_version()}")

    def test_a_listed_model_that_cannot_be_found_fails(self):
        self.list_in_schema("Ghost")
        self.assertFails("Ghost")

    def test_the_newest_version_is_the_one_checked(self):
        # Add a version after the live one listing a model with a unique
        # constraint: that newer version is now what CloudKit sees.
        later = self.newest_version() + 1
        self.add_model_file("Planted.swift", """
import SwiftData

@Model
final class Newcomer {
    @Attribute(.unique) var code: String = ""
}
""")
        with open(os.path.join(self.root, SCHEMA), "a", encoding="utf-8") as handle:
            handle.write(f"""
enum HoursSchemaV{later}: VersionedSchema {{
    static var versionIdentifier: Schema.Version {{ Schema.Version({later}, 0, 0) }}

    static var models: [any PersistentModel.Type] {{
        [
            DayEntry.self, HolidayRecord.self, SiteEntry.self, CrewMemberEntry.self, SiteDayEntry.self,
            SiteDiaryEntry.self, SiteDiaryPhotoEntry.self, CrewSignatureEntry.self, Newcomer.self
        ]
    }}
}}
""")
        self.assertFails("Newcomer.code", f"HoursSchemaV{later}")


if __name__ == "__main__":
    unittest.main()
