# SPDX-License-Identifier: AGPL-3.0-or-later
"""Publishes the Gitea pre-release for tonight's tag, then removes nightlies past the last KEEP.

One release covers every platform that uploaded. A build that goes to the App Store is made a
full release by hand, which keeps it: only pre-releases of this scheme's tags (and the older
nightly-<date> ones) are removed. A release that's already there is left as it is, so a run
can be repeated.
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

API = os.environ["API"]
REPO = f"{os.environ['SERVER_URL']}/{os.environ['REPOSITORY']}"
VERSION, BUILD, SHA, TAG = os.environ["VERSION"], os.environ["BUILD"], os.environ["SHA"], os.environ["TAG"]
PREVIOUS = os.environ.get("PREVIOUS", "")
UPLOADED = os.environ["UPLOADED"].split()
TITLES = {"iOS": "iOS & iPadOS", "macOS": "macOS", "tvOS": "tvOS"}
BADGES = {"iOS": "iOS%20%7C%20iPadOS", "macOS": "macOS", "tvOS": "tvOS"}
PRUNED = ("v", "nightly-")


def call(method: str, path: str, body: dict | None = None):
    request = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                     headers={"Authorization": f"token {os.environ['TOKEN']}",
                                              "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            text = response.read()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")[:300]
        sys.exit(f"::error::{method} {path}: {error.code} {detail}")


def exists(path: str) -> bool:
    request = urllib.request.Request(API + path, headers={"Authorization": f"token {os.environ['TOKEN']}"})
    try:
        urllib.request.urlopen(request, timeout=60).close()
        return True
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return False
        raise


def changes() -> list[str]:
    lines = []
    with open(os.environ["CHANGES"], encoding="utf-8") as log:
        for line in log:
            subject, _, sha = line.rstrip("\n").partition("\t")
            if subject:
                lines.append(f"- {subject} ({sha})")
    return lines or ["- Small fixes and changes under the hood."]


def first_of_version() -> bool:
    """Build 1 of this version, with no earlier build of it tagged (in this scheme or the older
    per-platform tags)."""
    if BUILD.split(".")[0] != "1":
        return False
    tags = subprocess.run(["git", "tag", "-l", f"v{VERSION}-build-*", f"*-{VERSION}-build-*"],
                          capture_output=True, text=True).stdout.split()
    return not [t for t in tags if t != TAG]


def body() -> str:
    wait = ("This is the first build of a new version, so Apple's TestFlight review usually takes "
            "**1 to 3 days** before it reaches testers." if first_of_version() else
            "This is a new build of an existing version, so Apple's TestFlight review is usually done "
            "**within 24 hours**, though it can take as long as a new version (up to 3 days).")
    platforms = "%20%7C%20".join(BADGES[p] for p in UPLOADED)
    return "\n".join([
        '[<img src="https://git.psmattas.com/ArcFin/ArcFin/media/branch/main/assets/badges/testflight-badge.png" '
        'alt="Available on TestFlight" height="48">](https://testflight.apple.com/join/kkC58n2w)',
        "",
        f"![Version](https://img.shields.io/badge/version-{VERSION}%20(build%20{BUILD})-blue) "
        f"![Platform](https://img.shields.io/badge/platform-{platforms}-lightgrey?logo=apple&logoColor=white)",
        "",
        f"Built from `main` at {SHA[:8]} for the internal beta. A build the internal testers approve goes on "
        "to the public beta, and then the App Store.",
        "",
        "> **When will I get this build?**",
        ">",
        f"> {wait}",
        ">",
        "> - **Already testing Arcfin?** TestFlight updates you automatically once Apple approves it.",
        "> - **Joining TestFlight now?** You'll get the previous build first, and this one arrives once Apple "
        "approves and releases it.",
        ">",
        "> Thanks for your patience.",
        "",
        "## Changes",
        *changes(),
        "",
        f"**Full changes:** [{PREVIOUS}...{TAG}]({REPO}/compare/{PREVIOUS}...{TAG})" if PREVIOUS
        else f"**Commit:** [{SHA[:8]}]({REPO}/commit/{SHA})",
    ])


def prune(keep: int) -> None:
    releases, page = [], 1
    while True:
        batch = call("GET", f"/releases?limit=50&page={page}") or []
        releases += batch
        if len(batch) < 50:
            break
        page += 1
    nightlies = [r for r in releases if r["prerelease"] and not r["draft"] and r["tag_name"].startswith(PRUNED)]
    nightlies.sort(key=lambda r: r["created_at"], reverse=True)
    for old in nightlies[keep:]:
        call("DELETE", f"/releases/{old['id']}")
        call("DELETE", f"/tags/{urllib.parse.quote(old['tag_name'], safe='')}")
        print(f"Removed {old['tag_name']}")


def main() -> int:
    if exists(f"/releases/tags/{urllib.parse.quote(TAG, safe='')}"):
        print(f"{TAG} already has a release")
    else:
        # The title's "Arcfin <version> (Build <n>) ·" start is what the README's version badge reads.
        call("POST", "/releases", {
            "tag_name": TAG, "name": f"Arcfin {VERSION} (Build {BUILD}) · {' · '.join(TITLES[p] for p in UPLOADED)}",
            "body": body(), "draft": False, "prerelease": True,
        })
        print(f"Published {TAG}")
    prune(int(os.environ.get("KEEP", "14")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
