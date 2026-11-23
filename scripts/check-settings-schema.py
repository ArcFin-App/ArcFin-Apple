#!/usr/bin/env python3
"""Checks that every setting the app stores is in settings-schema.json or on the exclusion list below.

usage: check-settings-schema.py [--plugin <path to the Arcfin-Sync checkout>]

Scans the app's Swift sources for @AppStorage("key") / @AppStorage(Type.constant) and
UserDefaults reads and writes with forKey: "key" or forKey: Type.constant. Each key found
has to be in LocalPackages/Sources/SyncEngine/Resources/settings-schema.json (scope synced or
device) or in EXCLUDED, with the reason it isn't a setting the plugin should know about.
An @AppStorage whose key can't be worked out fails too, so a new setting can't slip past.
Keys built at run time ("prefix.\\(id)") aren't checked.

A new or changed setting goes in SettingsSyncRegistry (synced) or the schema's device scope,
with its title and options, and the same schema file goes to the Arcfin-Sync plugin
(Schema/settings-schema.json) in the same change. --plugin checks that copy is identical.
"""
import json
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCHEMA = os.path.join(REPO, "LocalPackages", "Sources", "SyncEngine", "Resources", "settings-schema.json")
SOURCES = ["Arcfin", "LocalPackages/Sources", "ArcfinWidgets", "ArcfinTopShelf", "ArcfinWatch Watch App"]

# Stored by the app but deliberately not in the schema: secrets, state and history, and what
# would break another device. Every setting a screen lets someone choose is in the schema.
EXCLUDED = {
    # Secrets and sign-in state
    "arcfin.deviceId": "this device's Jellyfin device id",
    "arcfin.cachedDeviceName": "the device name read from the system",
    "arcfin.activeProfileID": "which profile is signed in",
    "arcfin.keychainAfterFirstUnlock": "Keychain migration flag",
    "arcfin.seerrAccountOwner": "which profile the Seerr sign-in belongs to",
    # State and history, not choices
    "homeShelfKnown": "the shelves there were at the last save, to spot new ones (bookkeeping)",
    "lastPlaybackRate": "the speed last used, not a choice (Remember Playback Speed reads it)",
    "arcfin.showTrackMemory": "the tracks last picked in each show (history)",
    "recentSearches": "private search history",
    "carplay.recentSearches": "private search history",
    "bottomNavProfile": "which profile the tab layout in place belongs to (bookkeeping)",
    "tvMusicNowPlayingPanel": "which panel is open (state)",
    # What this device is doing right now
    "offlineModeEnabled": "what this device is doing right now; on another device it would cut it off from the server",
    "AppleLanguages": "owned by the system (Settings › Arcfin › Language) and read only at launch",
    # Onboarding and prompts
    "arcfin.introduction.onboardingSeen": "onboarding",
    "arcfin.introduction.whatsNewSeen": "onboarding",
    "arcfin.adminTabOffered": "prompt shown once",
    "arcfin.whoIsWatchingOffered": "prompt shown once",
    # Sync's own bookkeeping
    "arcfin.settingsSync.lastSynced": "sync state",
    "arcfin.settingsSync.lastProfile": "sync state",
    "arcfin.settingsSync.handledRemote": "sync state",
    "arcfin.profileSettings.owner": "sync state",
    "arcfin.offlineProgressOfDeletedDownloads": "progress waiting to sync",
    # Queues, caches and hand-offs between parts of the app
    "arcfin.autoplayStreak": "state",
    "arcfin.downloadQueue": "state",
    "arcfin.pendingDownloads": "state",
    "pendingWatchedDeleteIDs": "state",
    "smartDownloadsItemIds": "state",
    "smartDownloadsMovieIds": "state",
    "music.autoRecent": "state",
    "music.seenNewAlbums": "state",
    "musicLyricsDelays": "per-song state",
    "arcfin.notify.announcedWatchlistIDs": "state",
    "arcfin.notify.lastActivityID": "state",
    "arcfin.notify.lastOpenCheck": "state",
    "arcfin.notify.seerrRequestStatus": "state",
    "arcfin.notify.sentRequestNotices": "state",
    "arcfin.pendingControlLink": "hand-off",
    "arcfin.pendingDiscover": "hand-off",
    "arcfin.pendingDownloadID": "hand-off",
    "arcfin.pendingFindFocus": "hand-off",
    "arcfin.pendingOpenFile": "hand-off",
    "arcfin.pendingPlayID": "hand-off",
    "arcfin.pendingResume": "hand-off",
    "arcfin.pendingSearch": "hand-off",
    "arcfin.pendingSeerrTitle": "hand-off",
    "arcfin.pendingShowDownloads": "hand-off",
    "arcfin.pendingWatchID": "hand-off",
    "arcfin.pendingWatchStart": "hand-off",
    "arcfin.seerrCertifications": "cache",
    "arcfin.seerrSpotlight": "cache",
    "arcfin.trustedClock.monotonic": "cache",
    "arcfin.trustedClock.serverDate": "cache",
    "topShelf.continueWatching": "Top Shelf cache",
    "topShelf.liveChannels": "Top Shelf cache",
    "topShelf.nextUp": "Top Shelf cache",
    "topShelf.recentlyAdded": "Top Shelf cache",
}

TYPE = re.compile(r"^(\s*)(?:(?:@\w+(?:\([^)]*\))?|public|private|fileprivate|internal|final|nonisolated)\s+)*"
                  r"(?:enum|struct|class|extension|actor)\s+(\w+)")
CONST = re.compile(r'\blet\s+(\w+)(?:\s*:\s*String)?\s*=\s*"([^"\\]+)"')
APPSTORAGE_LITERAL = re.compile(r'@AppStorage\(\s*"([^"\\]+)"')
APPSTORAGE_NAME = re.compile(r"@AppStorage\(\s*([A-Za-z_][\w.]*)")
FORKEY_LITERAL = re.compile(r'forKey:\s*"([^"\\]+)"')
FORKEY_NAME = re.compile(r"forKey:\s*([A-Z][\w]*\.[a-z]\w*)\s*[,)]")


def swift_files():
    for folder in SOURCES:
        for directory, _, names in os.walk(os.path.join(REPO, folder)):
            if "/.build" in directory:
                continue
            for name in names:
                if name.endswith(".swift"):
                    yield os.path.join(directory, name)


def main():
    files = list(swift_files())
    by_type, by_file = {}, {}
    for path in files:
        stack = []
        for line in open(path, errors="ignore"):
            closing = re.match(r"^(\s*)\}\s*$", line)
            if closing:
                while stack and stack[-1][0] >= len(closing.group(1)):
                    stack.pop()
            match = TYPE.match(line)
            if match:
                indent = len(match.group(1))
                while stack and stack[-1][0] >= indent:
                    stack.pop()
                stack.append((indent, match.group(2)))
            for name, value in CONST.findall(line):
                if stack:
                    by_type.setdefault(f"{stack[-1][1]}.{name}", set()).add(value)
                by_file.setdefault((path, name), set()).add(value)

    def resolve(token, path):
        if token.startswith("Self."):
            return by_file.get((path, token[5:]))
        if "." in token:
            return by_type.get(token)
        return by_file.get((path, token))

    found, problems = {}, []
    for path in files:
        rel = os.path.relpath(path, REPO)
        source = open(path, errors="ignore").read()
        for key in APPSTORAGE_LITERAL.findall(source) + FORKEY_LITERAL.findall(source):
            found.setdefault(key, rel)
        for token in APPSTORAGE_NAME.findall(source):
            values = resolve(token, path)
            if not values:
                problems.append(f"{rel}: can't tell which key @AppStorage({token}) stores; "
                                "give it a string constant this script can read")
            for value in values or ():
                found.setdefault(value, rel)
        for token in FORKEY_NAME.findall(source):
            for value in resolve(token, path) or ():
                found.setdefault(value, rel)

    schema = json.load(open(SCHEMA))
    keys = {setting["key"] for setting in schema["settings"]}
    for key in sorted(found):
        if key not in keys and key not in EXCLUDED:
            problems.append(f"{found[key]}: setting {key!r} is in neither settings-schema.json nor this script's "
                            "EXCLUDED list. Add it to SettingsSyncRegistry (synced) or the schema's device scope, "
                            "or exclude it here with the reason")
    for key in sorted(keys & EXCLUDED.keys()):
        problems.append(f"{key!r} is in the schema and on the exclusion list")
    group_ids = {group["id"] for group in schema["groups"]}
    for setting in schema["settings"]:
        if not setting.get("title"):
            problems.append(f"{setting['key']!r} has no title")
        if setting["group"] not in group_ids:
            problems.append(f"{setting['key']!r} is in unknown group {setting['group']!r}")
        if setting["scope"] not in ("synced", "device"):
            problems.append(f"{setting['key']!r} has scope {setting['scope']!r}")

    if "--plugin" in sys.argv:
        plugin = sys.argv[sys.argv.index("--plugin") + 1]
        copy = os.path.join(plugin, "Schema", "settings-schema.json")
        if not os.path.exists(copy):
            problems.append(f"{copy} is missing")
        elif open(copy, "rb").read() != open(SCHEMA, "rb").read():
            problems.append(f"{copy} differs from the app's settings-schema.json; copy it over")

    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print(f"settings-schema.json covers all {len(found)} stored keys "
          f"({len(keys)} in the schema, {len(found) - len(keys & found.keys())} excluded or not settings)")


main()
