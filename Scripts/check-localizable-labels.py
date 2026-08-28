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
GUARDED = {"MetricRow": "label", "SettingsRow": "title"}

problems = []
for path in sorted(pathlib.Path("Hours").rglob("*.swift")):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        for view, argument in GUARDED.items():
            for match in re.finditer(rf'{view}\(\s*{argument}:\s*"', line):
                problems.append(
                    f'{path}:{number}: {view}({argument}:) is handed a bare literal.\n'
                    f'    It takes String, so the literal is shown verbatim and never '
                    f'translated.\n    Wrap it: {argument}: String(localized: "…")'
                )

if problems:
    print(f"{len(problems)} unlocalized label(s):\n")
    for problem in problems:
        print(f"  - {problem}\n")
    sys.exit(1)
print("no bare literals reaching a verbatim Text()")
