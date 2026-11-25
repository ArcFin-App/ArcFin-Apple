#!/usr/bin/env python3
"""Makes licenses.json: every component Arcfin ships, with its licence, for Settings ›
Licenses & Third-Party Notices.

The app carries no copy. The nightly runs this for each build and attaches the file to the
build's release; the website's deploy (arcfin-site scripts/legal.py) publishes it at
/legal/v1/licenses/<version>-<build>.json, where the app looks for its own version and build,
and as latest.json. The Privacy Policy, Terms of Use and Data Protection notice come from
the website's /legal/v1/index.json, made from the pages themselves.

    python3 .gitea/scripts/update-licenses.py --out licenses.json                  fetch the pinned sources
    python3 .gitea/scripts/update-licenses.py <SourcePackages> --out licenses.json use a build's SourcePackages

VERSION and BUILD (as the nightly sets them) go in the file's "app"; without them it's
made from the Xcode project. It fails when a pinned package has no licence file, or when the
two Package.resolved files pin a package differently.

Every text is Markdown ("format": "markdown"), so the app draws them all alike. Markdown files
stay as they are. Plain licence files are hard-wrapped: their wrapped lines are joined back
into paragraphs, titles become headings and clause numbers bold, and anything laid out by
hand keeps its line breaks. The words themselves never change.

Components that aren't Swift packages (the libraries inside FFmpegBuild, LibDovi and the
Google Cast SDK, Anime4K's kernels inside AetherEngine, libVLC, and code ported from
Seerr) are added from their own files below. Arcfin's own licence and trademark policy come
first, from this repository. The texts are never translated.
"""

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
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESOLVED = ROOT / "Arcfin.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
PACKAGE_RESOLVED = ROOT / "LocalPackages/Package.resolved"
EXTRA = ROOT / ".gitea/licenses"
PBXPROJ = ROOT / "Arcfin.xcodeproj/project.pbxproj"
SCHEMA = 1

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
            texts.append(licence_text(f.name, read(f)))
    return texts


LIST_ITEM = re.compile(r"^\s*(?:[-*\u2022]|[0-9]{1,2}[.)]|\(?[a-z]\)|\([ivx]{1,4}\)|[a-z]\.)\s")


def unwrap(text):
    """Joins a hard-wrapped plain licence's lines back into paragraphs. A line is joined to
    the next only when it's long enough to have been wrapped, so titles, copyright lists,
    addresses and hand-made layouts keep their breaks, and a list item always starts a line."""
    out = []
    # Blank lines may hold spaces or a form feed (the GNU licences' page breaks).
    for block in re.split(r"\n[ \t\f\v]*\n", text.replace("\r\n", "\n").strip("\n")):
        block = block.strip("\n\f").rstrip()
        if not block.strip():
            continue
        lines = block.split("\n")
        indent = min(len(l) - len(l.lstrip()) for l in lines if l.strip())
        lines = [l[indent:].rstrip() for l in lines]
        if any(re.search(r"\S {3,}\S", l) for l in lines) or (len(lines) > 1 and indent >= 8):
            out.append("\n".join(lines))
            continue
        joined = [lines[0]]
        for line in lines[1:]:
            previous = joined[-1].split("\n")[-1]
            if len(previous) >= 60 and not LIST_ITEM.match(line):
                joined[-1] += " " + line.lstrip()
            else:
                joined.append(line)
        # A paragraph that became one line loses the indent that marked its start.
        out.append(joined[0].lstrip() if len(joined) == 1 else "\n".join(joined))
    return "\n\n".join(out) + "\n"


def escape(text):
    """Plain text that Markdown shows exactly as written."""
    text = re.sub(r"([\\`*_\[\]<>#|~&])", r"\\\1", text)
    text = re.sub(r"(?m)^(\s*)([+\-=])", r"\1\\\2", text)
    return re.sub(r"(?m)^(\s*)(\d+)\.(\s)", r"\1\2\\.\3", text)


MARKER = re.compile(r"^(?P<marker>[-*•]|[0-9]{1,2}[.)]|\(?[a-z]\)|\([ivx]{1,4}\)|[a-z]\.)\s+(?P<rest>.*)$", re.S)
TITLE = re.compile(r"^(preamble|appendix\b.*|how to apply.*|terms and conditions\b.*|"
                   r"end of terms and conditions|no warranty|definitions)$", re.I)
FENCE = "`" * 3


def is_heading(line):
    line = line.strip()
    if not line or len(line) > 72 or line[-1] in ".,;:" or line.startswith(("(", "[")):
        return False
    letters = [c for c in line if c.isalpha()]
    return bool(TITLE.match(line)) or (len(letters) >= 4 and all(c.isupper() for c in letters))


def to_markdown(text):
    """An unwrapped plain licence as Markdown: titles as headings, clause numbers in bold,
    bullets as lists, hand-made tables as code, and every other line break kept. The words
    never change."""
    out = []
    for block in text.strip("\n").split("\n\n"):
        block = block.strip("\n")
        if not block.strip():
            continue
        lines = block.split("\n")
        if len(lines) == 2 and lines[0].strip() and re.fullmatch(r"\s*(=+|-+)\s*", lines[1]):
            out.append("## " + escape(lines[0].strip()))
            continue
        if any(re.search(r"\S {3,}\S", line) for line in lines):
            out.append(f"{FENCE}\n{block.replace(FENCE, '')}\n{FENCE}")
            continue
        if is_heading(lines[0]):
            out.append("## " + escape(lines[0].strip()))
            lines = lines[1:]
            if not lines:
                continue
        first = lines[0].strip()
        match = MARKER.match(first)
        if match and match["marker"] in "-*•":
            body = "- " + escape(match["rest"])
        elif match:
            body = f"**{escape(match['marker'])}** " + escape(match["rest"])
        else:
            body = escape(first)
        # A backslash at the end of a line is a Markdown line break.
        out.append("\\\n".join([body] + [escape(line.strip()) for line in lines[1:]]))
    return "\n\n".join(out) + "\n"


def licence_text(title, text):
    if title.lower().endswith(".md"):
        return {"title": title, "format": "markdown", "text": text}
    return {"title": title, "format": "markdown", "text": to_markdown(unwrap(text))}


def arcfin_entries():
    # No version here: the app shows its own.
    return [
        {"id": "arcfin", "group": "arcfin", "name": "Arcfin", "version": "", "license": "AGPL-3.0-or-later",
         "url": REPO, "texts": [licence_text("LICENSE", read(ROOT / "LICENSE"))]},
        {"id": "arcfin-trademark", "group": "arcfin", "name": "Arcfin Name and Logo", "version": "",
         "license": "Trademark policy", "url": f"{REPO}/src/branch/main/TRADEMARK.md",
         "texts": [licence_text("TRADEMARK.md", read(ROOT / "TRADEMARK.md"))]},
        {"id": "apple-eula", "group": "arcfin", "name": "Apple Standard EULA", "version": "Apple",
         "license": "Licensed Application End User License Agreement",
         "url": "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/",
         "note": "Arcfin's Terms of Use apply alongside Apple's standard licence for apps.", "texts": []},
    ]


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
            texts += [licence_text(f.name, read(f)) for f in sorted(lic.glob("*.txt"))]
        if ident == "google-cast-sdk":
            oss = next(artifacts.rglob("OpenSourceLicenses"))
            index = plistlib.load(open(oss / "oss_licenses_index.plist", "rb"))
            blob = (oss / "oss_licenses.bin").read_bytes()
            for item in sorted(index, key=lambda i: i["name"].lower()):
                body = blob[item["offset"]:item["offset"] + item["size"]].decode("utf-8", "replace").strip()
                texts.append(licence_text(item["name"], body + "\n"))
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
        "platforms": None, "texts": [licence_text("LICENSE", "\n".join(notice).strip() + "\n")],
    }

    # libVLC is a static library inside SwiftVLC, built from VLC with VLC's contrib libraries.
    swiftvlc = entries["swiftvlc"]
    entries["libvlc"] = {
        "id": "libvlc", "name": "libVLC", "version": f"via SwiftVLC {swiftvlc['version']}",
        "license": "LGPL-2.1-or-later", "url": "https://code.videolan.org/videolan/vlc",
        "note": "Arcfin's fallback player. Statically linked; Arcfin's own source is public under the AGPL-3.0, "
                "so it can be rebuilt against a modified libVLC. libVLC includes VLC's contrib libraries, "
                "each under its own licence; see VLC's contrib sources.",
        "platforms": None, "texts": [licence_text("COPYING.LIB", read(EXTRA / "libvlc-COPYING.LIB.txt"))],
    }

    # Request rules ported from Seerr (LocalPackages/Sources/SeerrAPI/SeerrSeasonRequest.swift).
    entries["seerr"] = {
        "id": "seerr", "name": "Seerr", "version": "Request and permission rules", "license": "MIT",
        "url": "https://github.com/seerr-team/seerr",
        "note": "Arcfin's season request and permission rules are ported from Seerr's own code.",
        "platforms": None, "texts": [licence_text("LICENSE", read(EXTRA / "seerr-LICENSE.txt"))],
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


def consistent():
    """Both package lists must agree, or the app and the packages build different versions."""
    app = {p["identity"]: p["state"] for p in pins()}
    wrong = [pin["identity"] for pin in json.load(open(PACKAGE_RESOLVED))["pins"]
             if pin["identity"] in app and app[pin["identity"]] != pin["state"]]
    for ident in wrong:
        print(f"::error::{ident} is pinned differently in LocalPackages/Package.resolved and the Xcode project's Package.resolved")
    if wrong:
        sys.exit(1)


def app_version():
    """The version and build this file is for: the nightly's, or the Xcode project's."""
    if os.environ.get("VERSION") and os.environ.get("BUILD"):
        return os.environ["VERSION"], os.environ["BUILD"]
    project = PBXPROJ.read_text(encoding="utf-8")
    version = re.search(r"MARKETING_VERSION = ([0-9.]+);", project).group(1)
    build = re.search(r"CURRENT_PROJECT_VERSION = ([0-9.]+);", project).group(1)
    return version, build


def main():
    args = sys.argv[1:]
    if "--out" not in args or args.index("--out") == len(args) - 1:
        sys.exit(__doc__)
    i = args.index("--out")
    out = Path(args[i + 1])
    rest = args[:i] + args[i + 2:]
    if len(rest) > 1:
        sys.exit(__doc__)
    consistent()
    with tempfile.TemporaryDirectory() as temp:
        packages = Path(rest[0]) if rest else fetch_sources(Path(temp) / "SourcePackages")
        components = build(packages)
    version, build_number = app_version()
    data = {"schema": SCHEMA, "app": {"version": version, "build": build_number}, "components": components}
    out.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{len(components)} components, {sum(len(e['texts']) for e in components)} texts, "
          f"{out.stat().st_size // 1024} KB for {version} ({build_number}) -> {out}")


if __name__ == "__main__":
    main()
