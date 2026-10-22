#!/usr/bin/env python3
"""Tests for check-cloudkit-models.py.

The check runs against a copy of the real models and schema, so the clean
case is the store as it stands, and each failing case is that same store with
exactly one thing CloudKit refuses planted in it. A check that passed the real
store and also passed every plant would be a check of nothing.

Run: python3 Scripts/test_check_cloudkit_models.py
"""

import os
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

    def list_in_schema(self, *names):
        anchor = "SiteDiaryEntry.self, SiteDiaryPhotoEntry.self, CrewSignatureEntry.self"
        self.replace(SCHEMA, anchor, anchor + "".join(f", {name}.self" for name in names))

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
        self.assertFails("Forgotten", "HoursSchemaV4")

    def test_a_listed_model_that_cannot_be_found_fails(self):
        self.list_in_schema("Ghost")
        self.assertFails("Ghost")

    def test_the_newest_version_is_the_one_checked(self):
        # Freeze V4 the way the Persistence rules ask and add a V5 listing a
        # model with a unique constraint: V5 is now what CloudKit sees.
        self.add_model_file("Planted.swift", """
import SwiftData

@Model
final class Newcomer {
    @Attribute(.unique) var code: String = ""
}
""")
        with open(os.path.join(self.root, SCHEMA), "a", encoding="utf-8") as handle:
            handle.write("""
enum HoursSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            DayEntry.self, HolidayRecord.self, SiteEntry.self, CrewMemberEntry.self, SiteDayEntry.self,
            SiteDiaryEntry.self, SiteDiaryPhotoEntry.self, CrewSignatureEntry.self, Newcomer.self
        ]
    }
}
""")
        self.assertFails("Newcomer.code", "HoursSchemaV5")


if __name__ == "__main__":
    unittest.main()
