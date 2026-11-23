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
    ├── SearchKit        server search
    ├── CastKit          Chromecast sender
    └── AppState         unused scaffold
```

Package tests are in `LocalPackages/Tests/`, one test target per package.

## Stack

| Concern | Choice |
|---|---|
| Language | Swift 6 with strict concurrency |
| UI | SwiftUI, with Liquid Glass on iOS 26 |
| State | Plain `@Observable` classes with `@State` and `@Environment`. TCA is a dependency, but only the unused `AppState` scaffold uses it |
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
- **sign-off:** every commit in a pull request has a `Signed-off-by` line.

Package versions are pinned in the committed `Package.resolved` files, and CI builds only those versions.

`.gitea/workflows/testflight.yml` runs when a release tag such as `iOS-0.2.0-build-2` is pushed. It checks that the tag is signed, on `main` and matches the project's version and build, then archives that platform and uploads it to TestFlight with an App Store Connect API key. The key comes from the `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8_BASE64` secrets, and the team from the `DEVELOPMENT_TEAM` variable.

`.gitea/workflows/nightly.yml` builds `main` for the internal beta every night at midnight Irish time (it's scheduled for 23:00 and 00:00 UTC, and the run that isn't midnight in Dublin stops), and can also be started by hand. It skips a night when `main` hasn't changed since the last nightly, or when the newest commit is a release build. A nightly's build number is the project's build with the Unix time after it, e.g. `2.1764028800`, set only when archiving: TestFlight orders build numbers part by part, so it falls between release builds 2 and 3, nothing is committed, and a second run the same day still gets its own number. `.gitea/scripts/nightly-upload.sh` archives and uploads each platform on its own; `testflight-nightly.py` waits for App Store Connect to process each build, writes What to Test from the commit titles since the last nightly, adds the build to the nightly TestFlight group and submits it for beta review; `nightly-release.py` tags the commit `nightly-<date>-<unix time>` (unsigned, so it never starts `testflight.yml`), publishes a pre-release with the changes, and keeps the last 14 nightlies.
