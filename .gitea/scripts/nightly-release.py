# SPDX-License-Identifier: AGPL-3.0-or-later
"""Tags tonight's nightly, publishes its pre-release, and removes nightlies past the last KEEP.

The tag isn't signed: CI has no signing key. Release uploads only follow signed
<Platform>-<version>-build-<N> tags, so a nightly tag can never start one.
"""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API = os.environ["API"]
LABELS = {"iOS": "iOS & iPadOS", "macOS": "macOS", "tvOS": "tvOS"}


def call(method: str, path: str, body: dict | None = None):
    request = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                     headers={"Authorization": f"token {os.environ['TOKEN']}",
                                              "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        text = response.read()
        return json.loads(text) if text else None


def notes() -> str:
    tag, previous = os.environ["NIGHTLY_TAG"], os.environ.get("PREVIOUS_TAG", "")
    repo = f"{os.environ['SERVER_URL']}/{os.environ['REPOSITORY']}"
    platforms = " · ".join(LABELS[p] for p in os.environ["UPLOADED"].split())
    changes = []
    with open(os.environ["CHANGES"], encoding="utf-8") as lines:
        for line in lines:
            subject, _, sha = line.rstrip("\n").partition("\t")
            if subject:
                changes.append(f"- {subject} ({sha})")
    body = [
        f"> **Nightly build.** Built from `main` at {os.environ['SHA'][:8]} for the Arcfin Nightly Builds "
        "TestFlight group. It hasn't been tested like a release. It reaches the group once Apple's beta "
        "review approves it, usually within a few hours.",
        "",
        f"**Version:** {os.environ['VERSION']} ({os.environ['BUILD']}) · **Uploaded:** {platforms}",
        "",
        "## Changes",
        *(changes or ["- Small fixes and changes under the hood."]),
        "",
        f"**Full changes:** [{previous}...{tag}]({repo}/compare/{previous}...{tag})" if previous
        else f"**Commit:** [{os.environ['SHA'][:8]}]({repo}/commit/{os.environ['SHA']})",
    ]
    return "\n".join(body)


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
    tag = os.environ["NIGHTLY_TAG"]
    day = tag.removeprefix("nightly-")
    call("POST", "/tags", {"tag_name": tag, "target": os.environ["SHA"],
                           "message": f"Nightly {os.environ['VERSION']} build {os.environ['BUILD']}"})
    call("POST", "/releases", {
        "tag_name": tag,
        "name": f"Arcfin Nightly {day[:4]}-{day[4:6]}-{day[6:8]} · {os.environ['VERSION']} ({os.environ['BUILD']})",
        "body": notes(), "draft": False, "prerelease": True,
    })
    print(f"Published {tag}")
    try:
        prune(int(os.environ.get("KEEP", "14")))
    except urllib.error.HTTPError as error:
        print(f"::warning::Couldn't remove old nightlies: HTTP {error.code}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
