#!/usr/bin/env python3
"""Fail when the live SwiftData schema has something CloudKit refuses.

With sync on, the store is mirrored into the user's private CloudKit database,
and CloudKit takes only a model where:

  - every attribute is optional or has a default value,
  - nothing is unique (`@Attribute(.unique)` or `#Unique`),
  - every relationship is optional and has an inverse,
  - no relationship's delete rule is `.deny`.

A model that breaks one of these does not fail to compile. It fails when a
syncing store is opened — on a phone, at launch, for exactly the people who
turned sync on — and the app then falls back to its own copy and says sync
could not start. This finds it on Linux in a second instead.

What is checked is the newest `HoursSchemaV<n>` in HoursSchema.swift: its
`models` list, each class found either nested in that enum (once it has been
frozen) or at the top level of Hours/Data/Models. Older versions are left
alone on purpose: V1 carries `@Attribute(.unique)` and must keep it, since it
describes stores written before sync existed. Every `@Model` class in
Hours/Data/Models must also be in that list, because a model the schema does
not name is a model the store does not have.

A parser of Swift written with regular expressions, so it reads the shapes
this codebase writes: one property per line, attributes on that line or the
lines just above. Proven to fail on each planted violation in
test_check_cloudkit_models.py before being wired into CI.

Run: python3 Scripts/check-cloudkit-models.py [repository root]
"""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

MODELS = Path("Hours/Data/Models")
SCHEMA = Path("Hours/Data/Store/HoursSchema.swift")


@dataclass
class Property:
    name: str
    type: str
    default: bool
    attributes: list[str]
    line: int


@dataclass
class ModelClass:
    name: str
    path: Path
    line: int
    properties: list[Property] = field(default_factory=list)
    unique_macro_line: int | None = None


def strip_comments(source: str) -> str:
    """Comments out, line numbers kept."""
    source = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


def matching_brace(source: str, opening: int) -> int:
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    return len(source)


PROPERTY = re.compile(
    r"^(?P<attrs>(?:@\w+(?:\([^)]*\))?\s+)*)"
    r"(?:(?:private|fileprivate|internal|public)(?:\(set\))?\s+)*"
    r"(?P<kw>var|let)\s+(?P<name>\w+)\s*:\s*(?P<type>[^={]+?)\s*(?P<rest>[={].*)?$"
)
ATTRIBUTE_ONLY = re.compile(r"^(?:@\w+(?:\([^)]*\))?\s*)+$")


def parse_class_body(model: ModelClass, body: str, first_line: int) -> None:
    """Reads the stored properties at the top level of a class body."""
    depth = 0
    pending: list[str] = []
    for offset, raw in enumerate(body.split("\n")):
        line = raw.strip()
        number = first_line + offset
        if depth == 0 and line:
            if line.startswith("#Unique"):
                model.unique_macro_line = number
            elif ATTRIBUTE_ONLY.match(line):
                pending.append(line)
            elif not line.startswith(("static ", "class ", "init", "func ", "deinit", "}")):
                match = PROPERTY.match(line)
                if match:
                    attrs = pending + re.findall(r"@\w+(?:\([^)]*\))?", match.group("attrs") or "")
                    rest = match.group("rest") or ""
                    computed = rest.startswith("{")
                    if not computed:
                        model.properties.append(Property(
                            name=match.group("name"),
                            type=match.group("type").strip(),
                            default=rest.startswith("="),
                            attributes=attrs,
                            line=number,
                        ))
                pending = []
            else:
                pending = []
        depth += raw.count("{") - raw.count("}")


def find_classes(path: Path, source: str, within: tuple[int, int] | None = None) -> list[ModelClass]:
    """Every `@Model ... class Name {` in the source (or in a span of it)."""
    found = []
    pattern = re.compile(r"@Model\s+(?:(?:final|public|internal)\s+)*class\s+(\w+)[^{]*\{")
    start, end = within or (0, len(source))
    for match in pattern.finditer(source, start, end):
        opening = match.end() - 1
        closing = matching_brace(source, opening)
        line = source.count("\n", 0, match.start()) + 1
        model = ModelClass(match.group(1), path, line)
        body_start = opening + 1
        parse_class_body(model, source[body_start:closing], source.count("\n", 0, body_start) + 1)
        found.append(model)
    return found


def newest_schema(source: str) -> tuple[str, list[str], tuple[int, int]] | None:
    versions = []
    for match in re.finditer(r"enum\s+(HoursSchemaV(\d+))\s*:\s*VersionedSchema\s*\{", source):
        opening = match.end() - 1
        versions.append((int(match.group(2)), match.group(1), (opening, matching_brace(source, opening))))
    if not versions:
        return None
    _, name, span = max(versions)
    body = source[span[0]:span[1]]
    listing = re.search(r"static\s+var\s+models[^{]*\{(.*?)\}", body, flags=re.S)
    names = re.findall(r"(\w+)\.self", listing.group(1)) if listing else []
    return name, names, span


def relationship_target(prop: Property, models: dict[str, ModelClass]) -> str | None:
    bare = prop.type.replace("?", "").replace("!", "").strip()
    bare = bare[1:-1].strip() if bare.startswith("[") and bare.endswith("]") else bare
    return bare if bare in models else None


def is_optional(type_name: str) -> bool:
    return type_name.endswith("?") or type_name.endswith("!")


def check(root: Path) -> tuple[list[str], list[str], str]:
    problems: list[str] = []
    schema_path = root / SCHEMA
    schema_source = strip_comments(schema_path.read_text(encoding="utf-8"))
    schema = newest_schema(schema_source)
    if schema is None:
        return [f"{SCHEMA}: no `enum HoursSchemaV<n>: VersionedSchema` found"], [], "?"
    version, listed, span = schema

    top_level: dict[str, ModelClass] = {}
    for path in sorted((root / MODELS).glob("*.swift")):
        source = strip_comments(path.read_text(encoding="utf-8"))
        for model in find_classes(path.relative_to(root), source):
            top_level[model.name] = model
    nested = {m.name: m for m in find_classes(SCHEMA, schema_source, span)}

    live: dict[str, ModelClass] = {}
    for name in listed:
        model = nested.get(name) or top_level.get(name)
        if model is None:
            problems.append(f"{SCHEMA}: {version} lists {name}, but no `@Model class {name}` was found")
        else:
            live[name] = model

    for name, model in top_level.items():
        if name not in listed:
            problems.append(
                f"{model.path}:{model.line}  {name} is a @Model but {version}.models does not list it, "
                "so the store does not have it"
            )

    for model in live.values():
        where = f"{model.path}"
        if model.unique_macro_line is not None:
            problems.append(f"{where}:{model.unique_macro_line}  {model.name}: #Unique — CloudKit refuses unique constraints")
        for prop in model.properties:
            label = f"{model.name}.{prop.name}"
            attributes = " ".join(prop.attributes)
            if "@Transient" in attributes:
                continue
            if re.search(r"\.unique\b", attributes):
                problems.append(f"{where}:{prop.line}  {label}: @Attribute(.unique) — CloudKit refuses unique constraints")
            target = relationship_target(prop, live)
            is_relationship = target is not None or "@Relationship" in attributes
            if is_relationship:
                if not is_optional(prop.type):
                    problems.append(f"{where}:{prop.line}  {label}: a relationship must be optional for CloudKit ({prop.type})")
                if re.search(r"deleteRule:\s*\.deny\b", attributes):
                    problems.append(f"{where}:{prop.line}  {label}: deleteRule .deny — CloudKit cannot honour it")
                if not has_inverse(model, prop, target, live):
                    problems.append(f"{where}:{prop.line}  {label}: a relationship needs an inverse for CloudKit")
            elif not prop.default and not is_optional(prop.type):
                problems.append(
                    f"{where}:{prop.line}  {label}: {prop.type} is neither optional nor given a default "
                    "— CloudKit needs one or the other"
                )
    return problems, sorted(live), version


def has_inverse(model: ModelClass, prop: Property, target: str | None, live: dict[str, ModelClass]) -> bool:
    attributes = " ".join(prop.attributes)
    if re.search(r"inverse:\s*\\\w+\.\w+", attributes):
        return True
    if target is None:
        return False
    # Declared on the other side, pointing back at this property.
    for other in live[target].properties:
        if re.search(rf"inverse:\s*\\{model.name}\.{prop.name}\b", " ".join(other.attributes)):
            return True
    return False


def main(argv: list[str]) -> int:
    root = Path(argv[1]).resolve() if len(argv) > 1 else Path(__file__).resolve().parent.parent
    problems, live, version = check(root)
    if problems:
        print(f"{len(problems)} thing(s) in the live schema ({version}) that CloudKit refuses:\n")
        for problem in problems:
            print(f"  {problem}")
        print(
            "\nA syncing store with any of these will not open on a phone: the app falls back\n"
            "to its own copy and says sync could not start. Give the attribute a default (a\n"
            "lightweight migration for an existing column), make the relationship optional with\n"
            "an inverse, and keep uniqueness in the repositories (see ARCHITECTURE.md,\n"
            "Persistence). If a column's type has to change, that is a new schema version."
        )
        return 1
    print(f"The live schema ({version}) is CloudKit-compatible: {', '.join(live)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
