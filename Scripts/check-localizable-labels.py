#!/usr/bin/env python3
"""
Catch strings that look localized and are not.

MetricRow and SettingsRow take `String`, not `LocalizedStringKey`, so a
literal passed to them reaches `Text(_ verbatim:)` and is never looked up.
Most call sites wrap them in String(localized:); twelve did not, and the app
shipped "Expected" and "Fields" in English on a German phone while every row
around them was translated. Nothing failed. It was found by looking at a
screenshot.

A grep is enough to prevent the whole class, and it runs on Linux in a second
rather than needing a simulator.
"""
import pathlib, re, sys

# view name -> the parameter whose value reaches Text() unlocalized
# Every String-typed parameter of these views, not merely the first one.
#
# The earlier version guarded MetricRow(label:) and SettingsRow(title:) alone,
# and the German screenshot showed why that was not enough: the *titles* down
# the Settings screen were all in German and the *values* beside them read
# "Active", "Off", "All days" and "10 columns" in English. Same view, same
# String parameter, same verbatim Text, and a green check.
GUARDED = {
    "MetricRow": ["label", "value"],
    "SettingsRow": ["title", "value"],
    "StatTile": ["label", "caption"],
}

problems = []
for path in sorted(pathlib.Path("Hours").rglob("*.swift")):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        for view, arguments in GUARDED.items():
            for argument in arguments:
                # Both shapes: the literal straight after the label, and the
                # literal on the far side of a ternary — which is how "On" and
                # "Off" reached four rows of Settings untranslated.
                patterns = [
                    rf'{view}\(\s*{argument}:\s*"',
                    rf'{argument}:\s*[^,\n]*\?[^,\n]*"',
                ]
                for pattern in patterns:
                    if not re.search(pattern, line):
                        continue
                    # A ternary between two already-wrapped calls is fine.
                    if "String(localized:" in line and 'localized: "' in line:
                        continue
                    problems.append(
                        f'{path}:{number}: {view}({argument}:) is handed a bare literal.\n'
                        f'    It takes String, so the literal is shown verbatim and never '
                        f'translated.\n    Wrap it: {argument}: String(localized: "…")'
                    )
                    break

if problems:
    print(f"{len(problems)} unlocalized label(s):\n")
    for problem in problems:
        print(f"  - {problem}\n")
    sys.exit(1)
print("no bare literals reaching a verbatim Text()")
