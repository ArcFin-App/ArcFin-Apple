#!/usr/bin/env python3
"""Rebuild Arcfin/Shared/Settings/ThirdPartyLicenses.json, the licences the app shows in
Settings › Licenses & Third-Party Notices.

Every package comes from the resolved pins, with its licence files copied verbatim from
its checkout and a link to the exact version built against. Run it after any dependency
bump:

    python3 .gitea/scripts/update-licenses.py                 fetch the pinned sources and rewrite the file
    python3 .gitea/scripts/update-licenses.py <SourcePackages> use a build's SourcePackages folder instead
    python3 .gitea/scripts/update-licenses.py --check         fail if the file is missing a component,
                                                              lists one Arcfin no longer ships, or is out of date

ARCFIN_LEGAL_SITE=http://localhost:8000 reads the legal pages from there instead of the live
site, so a site branch that isn't deployed yet can be copied into the app in the same release.
The stored links still point at the live site.

--check is what CI runs. It needs only git, Python and the network, so it runs on Linux. A
change on the website's legal pages is reported as a warning, since the website, not the app,
holds their binding text.

Components that aren't Swift packages (the libraries inside FFmpegBuild, LibDovi and the
Google Cast SDK, Anime4K's kernels inside AetherEngine, libVLC, and code ported from
Seerr) are added from their own files below. Arcfin's own licence, trademark policy and
legal pages come first: the licence and policy from this repository, the Privacy Policy,
Terms of Use and Data Protection notice from the live website (the binding English text).
The texts are never translated.
"""

import html
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOLVED = ROOT / "Arcfin.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
PACKAGE_RESOLVED = ROOT / "LocalPackages/Package.resolved"
EXTRA = ROOT / ".gitea/licenses"
OUT = ROOT / "Arcfin/Shared/Settings/ThirdPartyLicenses.json"

SITE = "https://arcfin.psmattas.com"
REPO = "https://git.psmattas.com/ArcFin/ArcFin"

# Build tools that never reach the app.
NOT_SHIPPED = {"swift-syntax"}
# Packages linked only on some platforms (LocalPackages/Package.swift conditions).
PLATFORMS = {"google-cast-sdk": ["iOS"], "youtubeplayerkit": ["iOS", "macOS"]}
# Shown first, in this order; the rest follow alphabetically.
FIRST = ["aetherengine", "ffmpegbuild", "libdovi", "anime4k", "swiftvlc", "libvlc", "google-cast-sdk",
         "youtubeplayerkit", "youtube", "nuke", "seerr"]
NAMES = {"aetherengine": "AetherEngine", "ffmpegbuild": "FFmpeg (FFmpegBuild)", "libdovi": "libdovi (LibDovi)",
         "swiftvlc": "SwiftVLC", "google-cast-sdk": "Google Cast SDK", "youtubeplayerkit": "YouTubePlayerKit",
         "nuke": "Nuke", "smbclient": "SMBClient", "xctest-dynamic-overlay": "xctest-dynamic-overlay (IssueReporting)"}
LICENSES = {"aetherengine": "LGPL-3.0 with App Store exception", "ffmpegbuild": "LGPL-2.1-or-later and others",
            "libdovi": "MIT", "swiftvlc": "MIT", "google-cast-sdk": "Google APIs Terms of Service and others"}
NOTES = {
    "ffmpegbuild": "FFmpeg (libavcodec, libavformat, libavutil, libswresample, libswscale, libavfilter) under "
                   "LGPL-2.1-or-later, dav1d under BSD-2-Clause, zimg under WTFPL, libzvbi under LGPL-2.1 "
                   "(its ure.c under MIT). Dynamically linked; built without GPL components.",
    "aetherengine": "Statically linked. Arcfin's source, including how it uses AetherEngine, is public under the AGPL-3.0.",
    "smbclient": "A dependency of AetherEngine; Arcfin doesn't link its SMB part.",
    "google-cast-sdk": "Google's SDK for Chromecast, used under Google's terms, and the open-source components it includes.",
}


def git_tag(url, version):
    """The exact tag for a pinned version, which some repositories prefix with v."""
    try:
        out = subprocess.run(["git", "ls-remote", "--tags", url], capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return version
    tags = {line.rsplit("refs/tags/", 1)[-1].removesuffix("^{}") for line in out.splitlines()}
    for tag in (version, f"v{version}"):
        if tag in tags:
            return tag
    return version


def source_url(location, ref):
    base = location.removesuffix(".git")
    return f"{base}/tree/{ref}"


def license_name(text):
    head = text[:4000]
    for pattern, name in [
        (r"Apache License\s*\n?\s*Version 2\.0", "Apache-2.0"),
        (r"GNU LESSER GENERAL PUBLIC LICENSE\s*\n?\s*Version 3", "LGPL-3.0"),
        (r"GNU LESSER GENERAL PUBLIC LICENSE\s*\n?\s*Version 2\.1", "LGPL-2.1"),
        (r"MIT License|Permission is hereby granted, free of charge", "MIT"),
        (r"Redistribution and use in source and binary forms", "BSD"),
    ]:
        if re.search(pattern, head):
            return name
    return "See licence"


def read(path):
    return Path(path).read_text(encoding="utf-8", errors="replace").strip() + "\n"


def package_texts(checkout):
    texts = []
    for f in sorted(checkout.iterdir()):
        if re.match(r"(?i)^(licen[cs]e|copying|notice)(\.(txt|md))?$", f.name) and f.is_file():
            texts.append({"title": f.name, "text": read(f)})
    return texts


class ProseText(HTMLParser):
    """Plain text of a legal page's <article class="prose">: headings, paragraphs, list
    items and table rows, each on its own, with links kept as their text."""

    BLOCKS = {"h2", "h3", "p", "li", "tr"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth = 0
        self.blocks, self.current, self.cells = [], None, None

    def handle_starttag(self, tag, attrs):
        if tag == "article" and ("class", "prose") in attrs:
            self.depth = 1
        elif self.depth:
            if tag == "article":
                self.depth += 1
            if tag in self.BLOCKS and self.current is None:
                self.current, self.kind = [], tag
            if tag in ("td", "th") and self.current is not None:
                self.current.append("\u0000")
            if tag == "br" and self.current is not None:
                self.current.append("\n")

    def handle_endtag(self, tag):
        if not self.depth:
            return
        if tag == "article":
            self.depth -= 1
        if tag == getattr(self, "kind", None) and self.current is not None:
            text = re.sub(r"[ \t\r\n]+", " ", "".join(self.current)).strip()
            if self.kind == "tr":
                text = " | ".join(c.strip() for c in text.split("\u0000") if c.strip())
            if text:
                prefix = {"li": "• ", "h2": "", "h3": ""}.get(self.kind, "")
                self.blocks.append((self.kind, prefix + text.replace("\u0000", " ")))
            self.current = None

    def handle_data(self, data):
        if self.depth and self.current is not None:
            self.current.append(data)

    def text(self):
        out = []
        for kind, block in self.blocks:
            if kind in ("h2", "h3"):
                out.append(("\n" if out else "") + block.upper() if kind == "h2" else block)
            else:
                out.append(block)
        return "\n\n".join(out).strip() + "\n"


def legal_page(path):
    """The page's text and its effective date, from the live site."""
    base = os.environ.get("ARCFIN_LEGAL_SITE", SITE).rstrip("/")
    req = urllib.request.Request(f"{base}/{path}/", headers={"User-Agent": "arcfin-licenses-script"})
    page = urllib.request.urlopen(req, timeout=30).read().decode("utf-8")
    parser = ProseText()
    parser.feed(page)
    effective = re.search(r"Effective ([0-9]{1,2} [A-Z][a-z]+ [0-9]{4})", page)
    return parser.text(), effective.group(1) if effective else "Current"


def arcfin_entries():
    # No version here: the app shows its own, so a version bump doesn't make this file stale.
    entries = [
        {"id": "arcfin", "group": "arcfin", "name": "Arcfin", "version": "", "license": "AGPL-3.0-or-later",
         "url": REPO, "texts": [{"title": "LICENSE", "text": read(ROOT / "LICENSE")}]},
        {"id": "arcfin-trademark", "group": "arcfin", "name": "Arcfin Name and Logo", "version": "",
         "license": "Trademark policy", "url": f"{REPO}/src/branch/main/TRADEMARK.md",
         "texts": [{"title": "TRADEMARK.md", "text": read(ROOT / "TRADEMARK.md")}]},
    ]
    for ident, name, path in [("arcfin-privacy", "Privacy Policy", "privacy"),
                              ("arcfin-terms", "Terms of Use", "terms"),
                              ("arcfin-data-protection", "Data Protection", "data-protection")]:
        text, effective = legal_page(path)
        entries.append({"id": ident, "group": "arcfin", "name": name, "version": effective, "license": "Arcfin",
                        "url": f"{SITE}/{path}/", "texts": [{"title": name, "text": text}]})
    entries.append({"id": "apple-eula", "group": "arcfin", "name": "Apple Standard EULA", "version": "Apple",
                    "license": "Licensed Application End User License Agreement",
                    "url": "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/",
                    "note": "Arcfin's Terms of Use apply alongside Apple's standard licence for apps.", "texts": []})
    return entries


def pins():
    return json.load(open(RESOLVED))["pins"]


def retrying(step, attempts=4):
    """GitHub drops the odd fetch on CI; a few tries a few seconds apart get past it."""
    for attempt in range(1, attempts + 1):
        try:
            return step()
        except (subprocess.CalledProcessError, OSError) as error:
            if attempt == attempts:
                raise
            print(f"Retrying after: {error}", file=sys.stderr)
            time.sleep(5 * attempt)


def fetch_sources(root):
    """Each pinned package at its exact revision, plus the Google Cast SDK's binary (its
    bundled open-source licences are inside), laid out like Xcode's SourcePackages."""
    checkouts, artifacts = root / "checkouts", root / "artifacts"
    checkouts.mkdir(parents=True)
    artifacts.mkdir()
    for pin in pins():
        if pin["identity"] in NOT_SHIPPED:
            continue
        name = pin["location"].rstrip("/").removesuffix(".git").rsplit("/", 1)[-1]
        dest = checkouts / name
        git = ["git", "-C", str(dest), "-c", "advice.detachedHead=false"]
        subprocess.run(["git", "init", "-q", str(dest)], check=True)
        retrying(lambda: subprocess.run(git + ["fetch", "-q", "--depth", "1", pin["location"], pin["state"]["revision"]],
                                        check=True))
        subprocess.run(git + ["checkout", "-q", "FETCH_HEAD"], check=True)
        if pin["identity"] == "google-cast-sdk":
            version = pin["state"]["version"]
            url = f"https://github.com/SRGSSR/google-cast-sdk/releases/download/{version}/GoogleCast.xcframework.zip"
            zipped = artifacts / "GoogleCast.zip"
            retrying(lambda: urllib.request.urlretrieve(url, zipped))
            with zipfile.ZipFile(zipped) as archive:
                for member in archive.namelist():
                    if "/OpenSourceLicenses/" in member and not member.endswith("/"):
                        archive.extract(member, artifacts / "google-cast-sdk")
    return root


def build(packages):
    checkouts, artifacts = packages / "checkouts", packages / "artifacts"
    entries = {}

    for pin in pins():
        ident, location, state = pin["identity"], pin["location"], pin["state"]
        if ident in NOT_SHIPPED:
            continue
        version = state.get("version")
        ref = git_tag(location, version) if version else state["revision"]
        checkout = next((c for c in checkouts.iterdir() if c.name.lower() == ident), None)
        if checkout is None:
            sys.exit(f"No checkout for {ident} in {checkouts}")
        texts = package_texts(checkout)
        if ident == "ffmpegbuild":
            lic = checkout / "LICENSES"
            texts += [{"title": f.name, "text": read(f)} for f in sorted(lic.glob("*.txt"))]
        if ident == "google-cast-sdk":
            oss = next(artifacts.rglob("OpenSourceLicenses"))
            index = plistlib.load(open(oss / "oss_licenses_index.plist", "rb"))
            blob = (oss / "oss_licenses.bin").read_bytes()
            for item in sorted(index, key=lambda i: i["name"].lower()):
                body = blob[item["offset"]:item["offset"] + item["size"]].decode("utf-8", "replace").strip()
                texts.append({"title": item["name"], "text": body + "\n"})
        if not texts:
            sys.exit(f"No licence file in {checkout}")
        entries[ident] = {
            "id": ident,
            "name": NAMES.get(ident, checkout.name),
            "version": version or state["revision"][:12],
            "license": LICENSES.get(ident) or license_name(texts[0]["text"]),
            "url": source_url(location, ref),
            "note": NOTES.get(ident),
            "platforms": PLATFORMS.get(ident),
            "texts": texts,
        }

    # Anime4K's kernels are compiled into AetherEngine; its notice is in the source file.
    shader = next(checkouts.rglob("LineArtShaderSource.swift"))
    lines = shader.read_text(encoding="utf-8").splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip() == "/// MIT License")
    notice = []
    for line in lines[start:]:
        if not line.startswith("///"):
            break
        notice.append(line[3:].removeprefix(" "))
    entries["anime4k"] = {
        "id": "anime4k", "name": "Anime4K", "version": "Upscale CNN x2 (S)", "license": "MIT",
        "url": "https://github.com/bloc97/Anime4K",
        "note": "Its line-art upscaling kernels are compiled into AetherEngine.",
        "platforms": None, "texts": [{"title": "LICENSE", "text": "\n".join(notice).strip() + "\n"}],
    }

    # libVLC is a static library inside SwiftVLC, built from VLC with VLC's contrib libraries.
    swiftvlc = entries["swiftvlc"]
    entries["libvlc"] = {
        "id": "libvlc", "name": "libVLC", "version": f"via SwiftVLC {swiftvlc['version']}",
        "license": "LGPL-2.1-or-later", "url": "https://code.videolan.org/videolan/vlc",
        "note": "Arcfin's fallback player. Statically linked; Arcfin's own source is public under the AGPL-3.0, "
                "so it can be rebuilt against a modified libVLC. libVLC includes VLC's contrib libraries, "
                "each under its own licence; see VLC's contrib sources.",
        "platforms": None, "texts": [{"title": "COPYING.LIB", "text": read(EXTRA / "libvlc-COPYING.LIB.txt")}],
    }

    # Request rules ported from Seerr (LocalPackages/Sources/SeerrAPI/SeerrSeasonRequest.swift).
    entries["seerr"] = {
        "id": "seerr", "name": "Seerr", "version": "Request and permission rules", "license": "MIT",
        "url": "https://github.com/seerr-team/seerr",
        "note": "Arcfin's season request and permission rules are ported from Seerr's own code.",
        "platforms": None, "texts": [{"title": "LICENSE", "text": read(EXTRA / "seerr-LICENSE.txt")}],
    }

    # Terms for the embedded YouTube player (trailers), not an open-source licence.
    entries["youtube"] = {
        "id": "youtube", "name": "YouTube API Services", "version": "Terms of Service",
        "license": "Terms of Service", "url": "https://developers.google.com/youtube/terms/api-services-terms-of-service",
        "note": "Govern the embedded trailer player. Not an open-source licence.",
        "platforms": ["iOS", "macOS"], "texts": [],
    }

    order = [i for i in FIRST if i in entries] + sorted((i for i in entries if i not in FIRST), key=lambda i: entries[i]["name"].lower())
    return arcfin_entries() + [{k: v for k, v in entries[i].items() if v is not None} for i in order]


LEGAL_PAGES = {"arcfin-privacy", "arcfin-terms", "arcfin-data-protection"}


def check(expected):
    """Compares the committed file with what the pins and sources say it should hold."""
    errors, warnings = [], []
    # Both package lists must agree, or the app and the packages build different versions.
    app = {p["identity"]: p["state"] for p in pins()}
    for pin in json.load(open(PACKAGE_RESOLVED))["pins"]:
        if pin["identity"] in app and app[pin["identity"]] != pin["state"]:
            errors.append(f"{pin['identity']} is pinned differently in LocalPackages/Package.resolved and the Xcode project's Package.resolved")
    try:
        committed = {e["id"]: e for e in json.loads(OUT.read_text(encoding="utf-8"))}
    except (OSError, ValueError) as error:
        return [f"{OUT.relative_to(ROOT)} can't be read: {error}"], []
    wanted = {e["id"]: e for e in expected}
    for ident, entry in wanted.items():
        have = committed.get(ident)
        if have is None:
            errors.append(f"{entry['name']} ships in Arcfin but isn't on the Legal & Licenses screen")
            continue
        changed = [k for k in ("name", "version", "license", "url", "platforms", "group", "note") if have.get(k) != entry.get(k)]
        if have.get("texts") != entry.get("texts"):
            changed.append("licence text")
        if not changed:
            continue
        message = f"{entry['name']}: {', '.join(changed)} out of date"
        if ident in LEGAL_PAGES:
            warnings.append(message + " (the website's page changed since the app's copy was made)")
        else:
            errors.append(message)
    for ident, entry in committed.items():
        if ident not in wanted:
            errors.append(f"{entry['name']} is on the Legal & Licenses screen but Arcfin no longer ships it")
    return errors, warnings


def main():
    args = [a for a in sys.argv[1:] if a != "--check"]
    checking = "--check" in sys.argv[1:]
    if len(args) > 1:
        sys.exit(__doc__)
    with tempfile.TemporaryDirectory() as temp:
        packages = Path(args[0]) if args else fetch_sources(Path(temp) / "SourcePackages")
        expected = build(packages)
    if checking:
        errors, warnings = check(expected)
        for w in warnings:
            print(f"::warning file={OUT.relative_to(ROOT)}::{w}")
        for e in errors:
            print(f"::error file={OUT.relative_to(ROOT)}::{e}")
        if errors:
            print(f"{len(errors)} licence problem(s). Run python3 .gitea/scripts/update-licenses.py and commit the result.")
            sys.exit(1)
        print(f"All {len(expected)} components and their licences are on the Legal & Licenses screen and up to date.")
        return
    OUT.write_text(json.dumps(expected, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    size = OUT.stat().st_size
    print(f"{len(expected)} components, {sum(len(e['texts']) for e in expected)} texts, {size // 1024} KB -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
