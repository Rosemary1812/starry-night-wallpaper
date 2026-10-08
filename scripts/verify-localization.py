#!/usr/bin/env python3
"""Check the twelve-painting translation tables without loading artwork assets."""

import json
from pathlib import Path
import re
import subprocess

root = Path(__file__).resolve().parent.parent
slugs = [
    "starrynight", "water-lilies", "wheat-stacks", "rhone", "cypresses",
    "impression-sunrise", "waterloo-bridge", "nocturne-bognor", "approach-venice",
    "cliff-walk", "bridge-villeneuve", "parliament-sunset",
]
tables = {}
for language in ["en", "zh-Hans", "zh-Hant"]:
    path = root / f"{language}.lproj/Localizable.strings"
    keys = re.findall(r'^\s*"([^"]+)"\s*=', path.read_text(), re.MULTILINE)
    assert len(keys) == len(set(keys)), f"Duplicate localization key in {language}"
    table = json.loads(subprocess.check_output([
        "plutil", "-convert", "json", "-o", "-", str(path),
    ], text=True))
    assert all(value.strip() for value in table.values()), f"Empty value in {language}"
    assert table["app.name"] == "StarryNight", f"Brand changed in {language}"
    for slug in slugs:
        for field in ["name", "artist", "description"]:
            key = f"artwork.{slug}.{field}"
            assert key in table, f"Missing {key} in {language}"
    tables[language] = table

for language, table in tables.items():
    assert table.keys() == tables["en"].keys(), f"Resource keys differ in {language}"
    for key, value in table.items():
        placeholders = re.findall(r"%(?:\d+\$)?[d@]", value)
        expected = re.findall(r"%(?:\d+\$)?[d@]", tables["en"][key])
        assert placeholders == expected, f"Format placeholders differ: {language} {key}"

print(f"PASS: {len(tables['en'])} matching keys; all {len(slugs)} paintings have three-language names, artists, and descriptions")
