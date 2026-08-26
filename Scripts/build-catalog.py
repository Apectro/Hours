#!/usr/bin/env python3
"""Generate the String Catalog entries for the app's inflected strings.

Every string using `^[n noun](inflect: true)` needs an entry, because
automatic grammar agreement is resolved during the bundle lookup and a key
that is not in the catalog comes back with its markup intact. Committed
empty, the catalog compiled to nothing at all: no en.lproj, no strings
table, and "^[16 day](inflect: true) worked" on the calendar.

The keys are not guesses. A diagnostic in InflectionTests asked the bundle
for "^[%lld day](inflect: true) worked" directly and the miss was reported
against that exact spelling, which is how the `%lld` form is known to be
what Foundation looks up.

Written as a generator rather than by hand because the substitution form is
repetitive and easy to get subtly wrong in ways that fail silently — the
failure mode this whole exercise is about.

Run: python3 Scripts/build-catalog.py
"""

import json
import os

APP = "Hours/Resources/Localizable.xcstrings"
WIDGET = "HoursWidget/Localizable.xcstrings"


def plural(name, arg_num, one, other):
    """One `%#@name@` substitution, singular and plural."""
    return name, {
        "argNum": arg_num,
        "formatSpecifier": "lld",
        "variations": {
            "plural": {
                "one": {"stringUnit": {"state": "translated", "value": one}},
                "other": {"stringUnit": {"state": "translated", "value": other}},
            }
        },
    }


def entry(value, *substitutions):
    """A catalog entry whose value refers to its substitutions by name.

    `extractionState: manual` matters: these keys reach the bundle through
    String(inflected:), which Xcode's extractor does not recognise, and
    without it a build that prunes unextracted keys would quietly empty the
    catalog again.
    """
    return {
        "extractionState": "manual",
        "localizations": {
            "en": {
                "stringUnit": {"state": "translated", "value": value},
                "substitutions": dict(substitutions),
            }
        },
    }


DAYS = lambda n=1: plural("days", n, "%lld day", "%lld days")
HOLIDAYS = lambda n: plural("holidays", n, "%lld holiday", "%lld holidays")
HOURS = lambda n=1: plural("hours", n, "%lld hour", "%lld hours")
MINUTES = lambda n=1: plural("minutes", n, "%lld minute", "%lld minutes")

APP_STRINGS = {
    "^[%lld day](inflect: true)": entry("%#@days@", DAYS()),
    "^[%lld day](inflect: true) worked": entry("%#@days@ worked", DAYS()),
    "Clear ^[%lld day](inflect: true)": entry("Clear %#@days@", DAYS()),
    "Clear ^[%lld day](inflect: true)?": entry("Clear %#@days@?", DAYS()),
    "Apply to ^[%lld day](inflect: true)": entry("Apply to %#@days@", DAYS()),
    "Replace what is on ^[%lld day](inflect: true)?": entry(
        "Replace what is on %#@days@?", DAYS()
    ),
    "Backup ready: ^[%lld day](inflect: true).": entry("Backup ready: %#@days@.", DAYS()),
    # The schedule summary puts a preformatted duration first, so the count
    # is the second argument and has to say so.
    "%@ over ^[%lld day](inflect: true)": entry("%@ over %#@days@", DAYS(2)),
    "^[%lld hour](inflect: true)": entry("%#@hours@", HOURS()),
    "^[%lld minute](inflect: true)": entry("%#@minutes@", MINUTES()),
    "^[%lld hour](inflect: true) ^[%lld minute](inflect: true)": entry(
        "%#@hours@ %#@minutes@", HOURS(1), MINUTES(2)
    ),
    "Restored ^[%lld day](inflect: true) and ^[%lld holiday](inflect: true).": entry(
        "Restored %#@days@ and %#@holidays@.", DAYS(1), HOLIDAYS(2)
    ),
    # %@ is the damage warning, which is empty when the file is undamaged.
    "The backup holds ^[%lld day](inflect: true) and ^[%lld holiday](inflect: true).%@ "
    "Everything currently stored will be removed.": entry(
        "The backup holds %#@days@ and %#@holidays@.%@ Everything currently stored will be removed.",
        DAYS(1),
        HOLIDAYS(2),
    ),
    # Reporting days a backup held but could not be read.
    "^[%lld day](inflect: true) in the file is damaged and will not be restored.": entry(
        "%#@days@ in the file is damaged and will not be restored.", DAYS()
    ),
    "^[%lld day](inflect: true) with no readable date": entry(
        "%#@days@ with no readable date", DAYS()
    ),
    "^[%lld day](inflect: true) could not be read and was not restored: %@.": entry(
        "%#@days@ could not be read and was not restored: %@.", DAYS()
    ),
    "Nothing was restored: all ^[%lld day](inflect: true) in that file are damaged. "
    "Your existing hours have not been touched.": entry(
        "Nothing was restored: all %#@days@ in that file are damaged. "
        "Your existing hours have not been touched.",
        DAYS(),
    ),
    # Warning before deleting a day type that recorded days still point at.
    "^[%lld day](inflect: true) still use “%@”. Those days will show as Unknown "
    "and stop counting towards your balance. The hours recorded on them are kept.": entry(
        "%#@days@ still use “%@”. Those days will show as Unknown and stop counting "
        "towards your balance. The hours recorded on them are kept.",
        DAYS(),
    ),
}

WIDGET_STRINGS = {
    "^[%lld day](inflect: true) missing": entry("%#@days@ missing", DAYS()),
}


def write(path, strings):
    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    with open(path, "w") as handle:
        json.dump(catalog, handle, indent=2, ensure_ascii=False, sort_keys=True)
        handle.write("\n")
    print(f"{path}: {len(strings)} entries")


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    write(os.path.join(root, APP), APP_STRINGS)
    write(os.path.join(root, WIDGET), WIDGET_STRINGS)
