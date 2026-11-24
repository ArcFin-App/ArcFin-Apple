# Architecture

How Arcfin is put together: the project layout, the stack, the design system and the services it talks to. For building and contributing, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Project layout

```
Arcfin.xcodeproj
Arcfin/                 the app target, shared by iOS, iPadOS, macOS and tvOS
├── Shared/             code that builds the same on every platform, with no #if
│   ├── App/            the app, its root state and deep links
│   ├── Components/     views used across screens: shelf row, sheets, PIN pad
│   ├── <Screen>/       each screen's state, and the views it shows on every platform
│   └── DesignTokens.swift  the DT design system
├── iOS/                iPhone and iPad (built for iOS only)
│   ├── App/            the root view and the app's scenes
│   ├── Components/     this platform's version of a shared component
│   ├── Platform/       hooks each platform defines under the same name
│   └── <Screen>/       the platform's screens
├── iPadOS/             iPad screens that differ from iPhone (built for iOS only)
├── macOS/              the Mac, laid out like iOS/ (built for macOS only)
├── tvOS/               Apple TV, laid out like iOS/ (built for tvOS only)
├── Intents/            App Intents, Siri phrases and Spotlight
├── TopShelf/           data shared with the Top Shelf extension
├── *Repository.swift   data for the screens (Jellyfin, Seerr)
├── *Manager.swift      auth, downloads, notifications, SharePlay, SyncPlay
└── *.xcstrings         String Catalogs
ArcfinWidgets/          widgets, Control Center controls and Live Activities
ArcfinTopShelf/         the Apple TV Top Shelf extension
LocalPackages/          Swift packages, one Package.swift
.gitea/                 CI workflow, scripts, issue and PR templates
assets/                 badges and App Store artwork (not under the code license)
fastlane/metadata/      App Store Connect metadata (not under the code license)
```

Each file in a platform folder compiles only for that platform through its Target Membership in the project, so the files in it have no `#if os(...)`, and editing one platform's screen can't change another's. Loading, filtering and playback decisions live once in `Shared/`, and each platform's view lays them out. iPad uses the iOS build: an iOS screen shows its `iPadOS/` view when the window is wide. Small differences inside a shared view go through hooks in each platform's `Platform/` folder. Every screen was split this way for 0.4.0 ([#198](https://git.psmattas.com/ArcFin/ArcFin/issues/198)); a few logic files at the top of `Arcfin/` and in `Intents/` still have `#if`. [CONTRIBUTING.md](CONTRIBUTING.md#where-platform-code-goes) has the rules.

## Packages

Everything that isn't a screen lives in `LocalPackages/`, a single Swift package with these targets:

```
LocalPackages/Sources/
├── Core services
│   ├── Telemetry        OSLog wrapper and on-device diagnostics (no analytics or crash SDK)
│   ├── AuthCore         Keychain, multiple servers and profiles, custom headers, TMDB key
│   ├── Persistence      SwiftData models
│   ├── ImageCache       Nuke memory and disk cache, with an original-size fallback
│   ├── BackgroundKit    background task scheduling
│   ├── LiveActivityKit  the download Live Activity, shared with the widget extension
│   ├── JellyfinAPI      Jellyfin REST and WebSocket client
│   └── SeerrAPI         Seerr client
└── Features
    ├── MediaEngine      Aether, AVFoundation and VLC behind one player protocol
    ├── SyncEngine       offline progress sync and Arcfin Sync settings sync
    └── CastKit          Chromecast sender
```

Package tests are in `LocalPackages/Tests/`, one test target per package.

## Stack

| Concern | Choice |
|---|---|
| Language | Swift 6 with strict concurrency |
| UI | SwiftUI, with Liquid Glass on iOS 26 |
| State | Plain `@Observable` classes with `@State` and `@Environment` |
| Storage | SwiftData for app data, the Keychain for secrets |
| Images | Nuke |
| Playback | [AetherEngine](https://github.com/superuser404notfound/AetherEngine) (the default), AVFoundation and [SwiftVLC](https://github.com/harflabs/SwiftVLC), behind `MediaPlayerProtocol`. Downloads play through Aether or VLC |
| API clients | Hand-written for Jellyfin and Seerr |
| Localization | String Catalogs, English as the source language |
| Tests | Swift Testing |
| CI | Gitea Actions on a macOS runner |

### Networking

Every HTTP client uses a session with `waitsForConnectivity` turned on, plus a wait for the network path, so requests made at launch don't fail before the network is up. New clients need both. Custom request headers (for servers behind an access gateway) are added to every request to the Jellyfin server.

## Design system

Tokens live under `DT` in `Arcfin/Shared/DesignTokens.swift`; the sizes that differ per platform (page margin, card sizes, font scale) come from each platform's `Platform/PlatformMetrics.swift`. iPhone, iPad and Mac follow the system's light or dark appearance. The players, splash and lock screens, and all of Apple TV, stay dark.

| Token | Dark | Light |
|---|---|---|
| Background primary | `#0B0B0C` | `#F4F4F5` |
| Background secondary | `#141416` | `#FFFFFF` |
| Background tertiary | `#1E1E21` | `#E4E4E7` |
| Accent | `#FF6A4D` coral | `#B83A25` deeper coral |
| Text primary | `#FFFFFF` | Dark equivalent |
| Text secondary | `#8E8E93` | 〃 |

- Labels on accent fills use `DT.Color.onAccent`: dark on the bright coral, white on the deeper one.
- Status colours go through `DT.Color.palette(_:)`.
- Text over artwork stays white.
- Hero titles use SF Pro Display; body text and labels use SF Pro Text.

## Services

| Service | Used for | When |
|---|---|---|
| [Jellyfin](https://jellyfin.org) | Your library, playback, progress and live updates (REST and WebSocket) | Always |
| [Seerr](https://github.com/seerr-team/seerr) | Requests, Discover and the watchlist | If you connect it |
| [TMDB](https://www.themoviedb.org) | Review scores, where to watch, what's popular | If you add a key, or through Seerr |
| [Wikidata](https://www.wikidata.org) | Awards on title pages | Title pages |
| YouTube | Trailers | When your server has no trailer |
| Google Cast | Casting | When you cast |

The developer runs none of these. Arcfin connects straight from the device to each one.

## Localization

All user-facing text goes through String Catalogs (`LocalizedStringKey` or `String(localized:)`). CI fails a pull request when a build contains text that isn't in a catalog. How to translate is in [CONTRIBUTING.md](CONTRIBUTING.md#translating-arcfin).

## CI

`.gitea/workflows/build.yml` runs on pull requests into `main` and on pushes to it:

- **package tests:** `swift test` for `LocalPackages/`;
- **build:** iOS, macOS and tvOS, with the String Catalog check and a warnings report;
- **release build:** an iOS Release build;
- **sign-off:** every commit in a pull request has a `Signed-off-by` line;
- **commit format:** every commit subject in a pull request is `<type>(scope): message` (Conventional Commits), checked by `.gitea/scripts/check-commits.py`, which `scripts/git-hooks/commit-msg` also runs locally. Merge commits and `Revert "…"` commits are skipped.

Package versions are pinned in the committed `Package.resolved` files, and CI builds only those versions.

`.gitea/workflows/nightly.yml` is how every build reaches TestFlight. It runs every night at midnight Irish time (it's scheduled for 23:00 and 00:00 UTC, and the run that isn't midnight in Dublin stops), and can be started by hand for a build that can't wait. It skips the night when `main` hasn't changed since the last build's tag. Its jobs:

- **plan** reads the version and build from the project and works out the build number: the project's build with the Unix time after it, e.g. `2.1764028800`, set only when archiving. TestFlight orders build numbers part by part, so the builds of 2 fall between 1 and 3 in the order they were made, nothing is committed, and a second run the same day still gets a number Apple hasn't seen. On a night with nothing new it instead submits for beta review any build Apple refused because another build of the same version was in review then.
- **upload**, once per platform and side by side: `.gitea/scripts/nightly-upload.sh` archives and uploads with an App Store Connect API key (the `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8_BASE64` secrets, and the team from the `DEVELOPMENT_TEAM` variable), then `testflight-nightly.py` waits for App Store Connect to process the build, writes What to Test from the commit titles since the last build, adds it to the nightly TestFlight group and submits it for beta review. One platform failing doesn't stop the others.
- **release**, once the platforms are done: it asks App Store Connect which of them made it, then `nightly-tag.sh` tags the commit `v<version>-build-<build number>` (e.g. `v0.5.0-build-2.1764028800`), one tag for all of them, and `nightly-release.py` publishes it as a pre-release with the changes and removes nightly pre-releases past the last 14. Tags are protected, so only `arcfin-bot` makes them: it pushes with the `RELEASE_TOKEN` secret and signs with its CI key from the `ARCFIN_BOT_GPG_KEY` secret, in a keyring of its own, and the step checks the signature is the bot's before pushing.

A build goes on to the public beta and the App Store from App Store Connect; nothing is uploaded again. Its release is then edited from a pre-release to a full release, which keeps it past the pruning and starts `.gitea/workflows/screenshots.yml`: the platforms side by side run `ScreenshotTests` (`.gitea/scripts/release-screenshots.sh`) and attach `screenshots-<platform>.zip` to the release, which the website shows. It can also be run by hand for any release tag. The Mac's run needs an unlocked, logged-in session, so it only happens when the `MAC_SCREENSHOTS` repository variable is `true`.

Releases up to 0.4.0 have one tag per platform, `<Platform>-X.Y.Z-build-N`, signed by the maintainer.
