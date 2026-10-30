#!/usr/bin/env python3
"""Checks that each platform folder builds only for its platform, with no platform checks inside.

usage: check-platform-folders.py [--fix]

Xcode filters platforms per file, not per folder, so every file in Arcfin/iOS, iPadOS, macOS
and tvOS needs its own entry in the project. In Xcode that's the file's Target Membership,
set to the one platform. --fix adds missing entries to the project instead of failing.
"""
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
APP = os.path.join(REPO, "Arcfin")
PROJECT = os.path.join(REPO, "Arcfin.xcodeproj", "project.pbxproj")
FOLDERS = {"iOS": "ios", "iPadOS": "ios", "macOS": "macos", "tvOS": "tvos"}
PLATFORM_CHECK = re.compile(r"^\s*#(if|elseif)\b.*\bos\(")
# The app target's exception set for the Arcfin folder.
BLOCK = re.compile(r'(/\* Exceptions for "Arcfin" folder in "Arcfin" target \*/ = \{.*?'
                   r"platformFiltersByRelativePath = \{\n)(.*?)(\t*\};)", re.S)
ENTRY = re.compile(r'^\s*"?(.+?)"? = \((.*)\);$')


def quoted(path):
    return path if re.fullmatch(r"[A-Za-z0-9_./-]+", path) else f'"{path}"'


fix = "--fix" in sys.argv
project = open(PROJECT).read()
block = BLOCK.search(project)
entries = {}
for line in block.group(2).splitlines():
    match = ENTRY.match(line)
    if match:
        entries[match.group(1)] = match.group(2).replace(" ", "").strip(",").split(",")

problems = []
for folder, platform in FOLDERS.items():
    root = os.path.join(APP, folder)
    for directory, _, files in os.walk(root):
        for name in sorted(files):
            if name.startswith("."):
                continue
            path = os.path.relpath(os.path.join(directory, name), APP)
            if entries.get(path) != [platform]:
                if fix:
                    entries[path] = [platform]
                else:
                    problems.append(f"{path} builds for every platform; set its Target Membership to {folder} only "
                                    f"(or run .gitea/scripts/check-platform-folders.py --fix)")
            if name.endswith(".swift"):
                for number, text in enumerate(open(os.path.join(directory, name)), 1):
                    if PLATFORM_CHECK.match(text):
                        problems.append(f"Arcfin/{path}:{number}: platform check in a platform folder; "
                                        f"code more than one platform needs goes in Arcfin/Shared/")

for path, platforms in list(entries.items()):
    folder = path.split("/")[0]
    if folder in FOLDERS and not os.path.exists(os.path.join(APP, path)):
        if fix:
            del entries[path]
        else:
            problems.append(f"{path} has a platform filter in the project but no longer exists")

if fix:
    lines = "".join(f"\t\t\t\t{quoted(path)} = ({', '.join(platforms)}, );\n" for path, platforms in sorted(entries.items()))
    project = project[:block.start(2)] + lines + project[block.end(2):]
    open(PROJECT, "w").write(project)

for problem in problems:
    print(f"::error::{problem}")
if not problems:
    print("Platform folders build only for their own platform.")
sys.exit(1 if problems else 0)
