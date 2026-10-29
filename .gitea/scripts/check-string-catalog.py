#!/usr/bin/env python3
"""Fails when a build extracted text that isn't in its String Catalog.

usage: check-string-catalog.py <derived data path> <repo path>

Command-line builds don't update catalogs (only the Xcode app does), so this compares the
strings the compiler extracted with what the catalogs hold.
"""
import glob
import json
import os
import sys

derived_data, repo = sys.argv[1], os.path.abspath(sys.argv[2])
targets = {"Arcfin": "Arcfin.build", "ArcfinWidgets": "ArcfinWidgetsExtension.build"}
missing = 0

for folder, target in targets.items():
    with open(os.path.join(repo, folder, "Localizable.xcstrings")) as catalog:
        known = set(json.load(catalog)["strings"])
    found = {}
    pattern = f"{derived_data}/Build/Intermediates.noindex/Arcfin.build/*/{target}/Objects-normal/*/*.stringsdata"
    for path in glob.glob(pattern):
        with open(path) as extracted:
            data = json.load(extracted)
        source = data.get("source", "")
        if not source.startswith(os.path.join(repo, folder) + os.sep):
            continue
        for entry in data["tables"].get("Localizable", []):
            found.setdefault(entry["key"], source)
    for key in sorted(set(found) - known):
        missing += 1
        print(f"::error file={os.path.relpath(found[key], repo)}::{key!r} isn't in {folder}/Localizable.xcstrings")

if missing:
    print(f"{missing} string(s) missing. Build in the Xcode app once to add them to the catalog, then commit it.")
else:
    print("Every extracted string is in its catalog.")
sys.exit(1 if missing else 0)
