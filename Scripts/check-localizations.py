# -*- coding: utf-8 -*-
"""
Check the catalogue before trusting it.

The failure that matters is a placeholder that does not survive translation:
a %@ dropped or a %lld added changes what the format call is handed, and the
app either shows the wrong value or crashes. Everything else here is hygiene.
"""
import json, pathlib, re, sys

LANGS = ["de","hr","sl","it","fr","es","pt","nl","pl"]
SPEC = re.compile(r"%(?:\d+\$)?[@dlfsu]+|%#@\w+@")

def specs(text):
    # %#@name@ is a substitution reference; the name is what matters, not order.
    return sorted(re.findall(r"%#@(\w+)@", text)) , sorted(m for m in re.findall(r"%(?:\d+\$)?(?:lld|ld|d|@|f|lf)", text))

# Translations that are legitimately identical to the English. Each one is a
# decision, not an oversight, so it is written down rather than tolerated.
SAME_ON_PURPOSE = {
    ("Byte-order mark", "nl"),  # Dutch technical writing leaves this in English.
}

problems = []
data = json.loads(pathlib.Path("Hours/Resources/Localizable.xcstrings").read_text())

for key, entry in data["strings"].items():
    locs = entry.get("localizations", {})
    source = locs.get("en", {}).get("stringUnit", {}).get("value") or key
    want_subs, want_specs = specs(source)

    missing = [l for l in LANGS if l not in locs]
    if missing:
        problems.append(f"{key[:48]!r}: missing {','.join(missing)}")

    for lang in LANGS:
        unit = locs.get(lang, {}).get("stringUnit", {})
        value = unit.get("value")
        if value is None:
            continue
        if not value.strip():
            problems.append(f"{key[:48]!r} [{lang}]: empty")
        got_subs, got_specs = specs(value)
        if got_subs != want_subs:
            problems.append(f"{key[:48]!r} [{lang}]: substitutions {got_subs} vs {want_subs}")
        if got_specs != want_specs:
            problems.append(f"{key[:48]!r} [{lang}]: specifiers {got_specs} vs {want_specs}")
        # A translation identical to the source is usually an untranslated line.
        if (value == source and (key, lang) not in SAME_ON_PURPOSE
                and not re.fullmatch(r"[%#@\w\s]+", source) and len(source) > 3):
            problems.append(f"{key[:48]!r} [{lang}]: identical to English")

print(f"{len(data['strings'])} keys checked across {len(LANGS)} languages")
if problems:
    print(f"\n{len(problems)} problems:")
    for p in problems[:40]:
        print("  -", p)
    sys.exit(1)
print("placeholders survive every translation; nothing empty; nothing missing")
