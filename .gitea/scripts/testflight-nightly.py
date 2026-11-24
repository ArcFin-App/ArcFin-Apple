# SPDX-License-Identifier: AGPL-3.0-or-later
"""Sends tonight's uploaded builds to the nightly TestFlight group.

For each platform in UPLOADED: waits for App Store Connect to finish processing the build, sets
its What to Test, adds it to GROUP and submits it for beta review, which external groups need.

The App Store Connect token is signed with the openssl command line, so this needs nothing
beyond the standard library.
"""

import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
PLATFORMS = {"iOS": "IOS", "macOS": "MAC_OS", "tvOS": "TV_OS"}
SUBMITTED_STATES = {"WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW", "BETA_APPROVED", "IN_BETA_TESTING"}
# Commits testers can't see: CI, docs, the project file, strings, tests and build numbers.
UNDER_THE_HOOD = re.compile(r"^(CI|Docs?|Project|Strings?|String Catalogs?|Translations?|Tests?|README|ARCHITECTURE|Build \d+|Release|Merge)\b", re.I)
FOOTER = """Found a problem? Open an issue: https://git.psmattas.com/ArcFin/ArcFin/issues
Please include your device and OS version, your Jellyfin server version (Settings › Server), and what you did right before it happened. Screen recordings help a lot for anything visual.

Help and FAQ: https://arcfin.psmattas.com/support
Source code, changes and what's being worked on: https://git.psmattas.com/ArcFin/ArcFin"""


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """An ECDSA signature from openssl (DER) as the 64 bytes a JWT wants."""
    def read_int(at: int) -> tuple[int, int]:
        assert der[at] == 0x02
        length = der[at + 1]
        value = int.from_bytes(der[at + 2:at + 2 + length], "big")
        return value, at + 2 + length
    assert der[0] == 0x30
    at = 3 if der[1] & 0x80 else 2
    r, at = read_int(at)
    s, _ = read_int(at)
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


def token() -> str:
    now = int(time.time())
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    signing = f"{b64(json.dumps(header).encode())}.{b64(json.dumps(payload).encode())}"
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"]],
                         input=signing.encode(), capture_output=True, check=True).stdout
    return f"{signing}.{b64(der_to_raw(der))}"


def call(method: str, path: str, body: dict | None = None, query: dict | None = None) -> tuple[int, dict]:
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    request = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None,
                                     headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            text = response.read()
            return response.status, json.loads(text) if text else {}
    except urllib.error.HTTPError as error:
        text = error.read()
        return error.code, json.loads(text) if text else {}


def first_error(reply: dict) -> str:
    errors = reply.get("errors") or [{}]
    return errors[0].get("detail") or errors[0].get("title") or "unknown error"


def what_to_test() -> str:
    lines = []
    with open(os.environ["CHANGES"], encoding="utf-8") as changes:
        for line in changes:
            subject = line.rstrip("\n").split("\t")[0].strip()
            if subject and not UNDER_THE_HOOD.match(subject):
                lines.append(f"• {subject}.")
    if os.environ.get("MODE") == "release":
        intro = (f"Arcfin {os.environ['VERSION']} ({os.environ['BUILD']}). This build goes on to the public beta "
                 "once it has held up here, so please give it a good try.\n\nChanged since the last release:\n\n")
    else:
        intro = (f"Nightly build {os.environ['VERSION']} ({os.environ['BUILD']}). Nightlies are built from "
                 "everything finished so far and haven't been tested like a release, so expect the odd rough edge.\n\n"
                 "Changed since the last nightly:\n\n")
    if not lines:
        lines = ["• Small fixes and changes under the hood."]
    # TestFlight's limit is 4000 characters.
    budget = 4000 - len(intro) - len(FOOTER) - 40
    shown = []
    for line in lines:
        if sum(len(s) + 1 for s in shown) + len(line) + 1 > budget:
            shown.append(f"• …and {len(lines) - len(shown)} more.")
            break
        shown.append(line)
    return intro + "\n".join(shown) + "\n\n" + FOOTER


def find_build(app_id: str, platform: str, quiet: bool = False) -> dict | None:
    """Waits up to 90 minutes for the upload to show up and finish processing. Quiet: looks
    once, for a build of this number in any state, and says nothing."""
    deadline = time.time() + 90 * 60
    while time.time() < deadline:
        status, reply = call("GET", "/builds", query={
            "filter[app]": app_id,
            "filter[version]": os.environ["BUILD"],
            "filter[preReleaseVersion.version]": os.environ["VERSION"],
            "filter[preReleaseVersion.platform]": PLATFORMS[platform],
            "limit": "1",
        })
        builds = reply.get("data") or []
        if quiet:
            return builds[0] if status == 200 and builds else None
        if status == 200 and builds:
            state = builds[0]["attributes"].get("processingState")
            if state == "VALID":
                return builds[0]
            if state in ("FAILED", "INVALID"):
                print(f"::error::{platform}: App Store Connect says the build is {state}")
                return None
        time.sleep(60)
    print(f"::error::{platform}: the build didn't finish processing within 90 minutes")
    return None


def set_what_to_test(build_id: str, locale: str, platform: str, notes: str) -> bool:
    """TestFlight's What to Test, which the API calls whatsNew."""
    _, reply = call("GET", f"/builds/{build_id}/betaBuildLocalizations")
    localizations = reply.get("data") or []
    for localization in localizations:
        status, reply = call("PATCH", f"/betaBuildLocalizations/{localization['id']}", {"data": {
            "type": "betaBuildLocalizations", "id": localization["id"], "attributes": {"whatsNew": notes}}})
        if status >= 300:
            print(f"::error::{platform}: couldn't set What to Test: {first_error(reply)}")
            return False
    if not localizations:
        status, reply = call("POST", "/betaBuildLocalizations", {"data": {
            "type": "betaBuildLocalizations", "attributes": {"locale": locale, "whatsNew": notes},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
        if status >= 300:
            print(f"::error::{platform}: couldn't set What to Test: {first_error(reply)}")
            return False
    return True


def distribute(app_id: str, locale: str, group_id: str, platform: str, notes: str) -> bool:
    build = find_build(app_id, platform)
    if not build:
        return False
    build_id = build["id"]

    if not set_what_to_test(build_id, locale, platform, notes):
        return False

    status, reply = call("POST", f"/betaGroups/{group_id}/relationships/builds",
                         {"data": [{"type": "builds", "id": build_id}]})
    # 409: already in the group, from a run that stopped after this.
    if status >= 300 and status != 409:
        print(f"::error::{platform}: couldn't add the build to the group: {first_error(reply)}")
        return False

    label = f"{platform} {os.environ['VERSION']} ({os.environ['BUILD']})"
    return submit_for_review(build_id, label) is not False


def review_state(build_id: str) -> str | None:
    _, reply = call("GET", f"/builds/{build_id}/buildBetaDetail")
    return ((reply.get("data") or {}).get("attributes") or {}).get("externalBuildState")


def submit_for_review(build_id: str, label: str) -> bool | None:
    """Submits a build for beta review. True once Apple has it (or it needs none), None when
    Apple won't take it yet, which is usually another build of the version still in review: it
    stays in the group, ready, for the sweep on a later night. False on any other failure."""
    status, reply = call("POST", "/betaAppReviewSubmissions", {"data": {
        "type": "betaAppReviewSubmissions",
        "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
    # A refusal's code doesn't say whether it was already submitted or can't be yet; its state does.
    state = review_state(build_id)
    if state in SUBMITTED_STATES:
        print(f"{label} is in {os.environ['GROUP']}, {state.replace('_', ' ').lower()}")
        return True
    if state == "READY_FOR_BETA_SUBMISSION":
        print(f"::warning::{label} is in {os.environ['GROUP']}, but Apple won't take it for review yet "
              f"({first_error(reply) if status >= 300 else 'no reason given'}). A later night submits it.")
        return None
    print(f"::error::{label}: couldn't submit for beta review ({state}): {first_error(reply)}")
    return False


def sweep(app_id: str, group_id: str) -> None:
    """Each platform's newest build that's in the group but was never submitted, because
    another was in review then, goes for review now."""
    for platform, code in PLATFORMS.items():
        _, reply = call("GET", "/builds", query={
            "filter[app]": app_id, "filter[preReleaseVersion.platform]": code,
            "sort": "-uploadedDate", "limit": "1", "include": "buildBetaDetail,betaGroups,preReleaseVersion"})
        builds = reply.get("data") or []
        if not builds:
            continue
        build = builds[0]
        included = {(i["type"], i["id"]): i for i in reply.get("included") or []}
        detail_ref = (build["relationships"].get("buildBetaDetail") or {}).get("data") or {}
        state = ((included.get(("buildBetaDetails", detail_ref.get("id"))) or {}).get("attributes") or {}).get("externalBuildState")
        groups = {g["id"] for g in (build["relationships"].get("betaGroups") or {}).get("data") or []}
        if state != "READY_FOR_BETA_SUBMISSION" or group_id not in groups:
            continue
        version_ref = (build["relationships"].get("preReleaseVersion") or {}).get("data") or {}
        version = ((included.get(("preReleaseVersions", version_ref.get("id"))) or {}).get("attributes") or {}).get("version", "?")
        submit_for_review(build["id"], f"{platform} {version} ({build['attributes']['version']})")


def main() -> int:
    status, reply = call("GET", "/apps", query={"filter[bundleId]": os.environ["BUNDLE_ID"], "limit": "1"})
    apps = reply.get("data") or []
    if status != 200 or not apps:
        print(f"::error::No app for {os.environ['BUNDLE_ID']}: {first_error(reply)}")
        return 1
    app_id = apps[0]["id"]
    locale = apps[0]["attributes"].get("primaryLocale") or "en-US"
    if os.environ.get("EXISTS_FOR"):
        return 0 if find_build(app_id, os.environ["EXISTS_FOR"], quiet=True) else 1

    _, reply = call("GET", f"/apps/{app_id}/betaGroups", query={"limit": "200"})
    group = next((g for g in reply.get("data") or [] if g["attributes"]["name"] == os.environ["GROUP"]), None)
    if not group:
        print(f"::error::No TestFlight group called {os.environ['GROUP']}")
        return 1

    if os.environ.get("SWEEP_ONLY") == "1":
        sweep(app_id, group["id"])
        return 0
    notes = what_to_test()
    results = [distribute(app_id, locale, group["id"], platform, notes) for platform in os.environ["UPLOADED"].split()]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
