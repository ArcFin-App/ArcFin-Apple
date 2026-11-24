# SPDX-License-Identifier: AGPL-3.0-or-later
"""Tags tonight's upload and makes its Gitea release.

- Nightly: an unsigned nightly-<date>-<unix time> tag and a published pre-release; nightlies
  past the last KEEP are removed.
- Release: an unsigned <Platform>-<version>-build-<N> tag and a published pre-release for each
  platform that uploaded, in the release notes' usual layout, its changes under one heading.
  A tag or release that's already there is left as it is, so a run can be repeated.

CI has no signing key, so the tags aren't signed. testflight.yml skips tags CI made, so a tag
from here never starts a second upload.
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
VERSION, BUILD, SHA = os.environ["VERSION"], os.environ["BUILD"], os.environ["SHA"]
LABELS = {"iOS": "iOS/iPadOS", "macOS": "macOS", "tvOS": "tvOS"}
TITLES = {"iOS": "iOS & iPadOS", "macOS": "macOS", "tvOS": "tvOS"}
BADGES = {"iOS": "iOS%20%7C%20iPadOS", "macOS": "macOS", "tvOS": "tvOS"}


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


def nightly() -> None:
    tag, previous = os.environ["NIGHTLY_TAG"], os.environ.get("PREVIOUS_TAG", "")
    day = tag.split("-")[1]
    platforms = " · ".join(TITLES[p] for p in os.environ["UPLOADED"].split())
    body = "\n".join([
        f"> **Nightly build.** Built from `main` at {SHA[:8]} for the internal beta. It hasn't been tested "
        "like a release. It reaches testers once Apple's beta review approves it, usually within a few hours.",
        "",
        f"**Version:** {VERSION} ({BUILD}) · **Uploaded:** {platforms}",
        "",
        "## Changes",
        *changes(),
        "",
        f"**Full changes:** [{previous}...{tag}]({REPO}/compare/{previous}...{tag})" if previous
        else f"**Commit:** [{SHA[:8]}]({REPO}/commit/{SHA})",
    ])
    call("POST", "/tags", {"tag_name": tag, "target": SHA, "message": f"Nightly {VERSION} build {BUILD}"})
    call("POST", "/releases", {
        "tag_name": tag, "name": f"Arcfin Nightly {day[:4]}-{day[4:6]}-{day[6:8]} · {VERSION} ({BUILD})",
        "body": body, "draft": False, "prerelease": True,
    })
    print(f"Published {tag}")
    try:
        prune(int(os.environ.get("KEEP", "14")))
    except urllib.error.HTTPError as error:
        print(f"::warning::Couldn't remove old nightlies: HTTP {error.code}")


def previous_tag(platform: str) -> str:
    """The platform's last release tag before this one, for the compare link."""
    found = subprocess.run(["git", "describe", "--tags", "--abbrev=0", "--match", f"{platform}-*-build-*", SHA],
                           capture_output=True, text=True)
    return found.stdout.strip() if found.returncode == 0 else ""


def release(platform: str) -> None:
    tag = f"{platform}-{VERSION}-build-{BUILD}"
    previous = previous_tag(platform)
    wait = ("This is a new version, so Apple's TestFlight review usually takes **1 to 3 days** before it "
            "reaches testers." if BUILD == "1" else
            "This is a new build of an existing version, so Apple's TestFlight review is usually done "
            "**within 24 hours**, though it can take as long as a new version (up to 3 days).")
    body = "\n".join([
        '[<img src="https://git.psmattas.com/ArcFin/ArcFin/media/branch/main/assets/badges/testflight-badge.png" '
        'alt="Available on TestFlight" height="48">](https://testflight.apple.com/join/kkC58n2w)',
        "",
        f"![Version](https://img.shields.io/badge/version-{VERSION}%20(build%20{BUILD})-blue) "
        f"![Platform](https://img.shields.io/badge/platform-{BADGES[platform]}-lightgrey?logo=apple&logoColor=white)",
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
        f"**Full changes:** [{previous}...{tag}]({REPO}/compare/{previous}...{tag})" if previous
        else f"**Commit:** [{SHA[:8]}]({REPO}/commit/{SHA})",
    ])
    quoted = urllib.parse.quote(tag, safe="")
    if not exists(f"/tags/{quoted}"):
        call("POST", "/tags", {"tag_name": tag, "target": SHA, "message": f"{LABELS[platform]} {VERSION} build {BUILD}"})
    if exists(f"/releases/tags/{quoted}"):
        print(f"{tag} already has a release")
        return
    call("POST", "/releases", {
        "tag_name": tag, "name": f"Arcfin {VERSION} (Build {BUILD}) · {TITLES[platform]}",
        "body": body, "draft": False, "prerelease": True,
    })
    print(f"Tagged {tag} and published its release")


def prune(keep: int) -> None:
    nightlies, page = [], 1
    while True:
        releases = call("GET", f"/releases?limit=50&page={page}") or []
        nightlies += [r for r in releases if r["tag_name"].startswith("nightly-")]
        if len(releases) < 50:
            break
        page += 1
    nightlies.sort(key=lambda r: r["created_at"], reverse=True)
    for old in nightlies[keep:]:
        call("DELETE", f"/releases/{old['id']}")
        call("DELETE", f"/tags/{urllib.parse.quote(old['tag_name'], safe='')}")
        print(f"Removed {old['tag_name']}")


def main() -> int:
    if os.environ.get("MODE") == "release":
        for platform in os.environ["UPLOADED"].split():
            release(platform)
    else:
        nightly()
    return 0


if __name__ == "__main__":
    sys.exit(main())
