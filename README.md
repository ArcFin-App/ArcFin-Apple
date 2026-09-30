# Arcfin

<img src="assets/badges/app-store-badge-black.svg" alt="App Store — pending review, not yet available" height="48" style="opacity:0.45">

[<img src="assets/badges/testflight-badge.png" alt="Available on TestFlight" height="48">](https://testflight.apple.com/join/kkC58n2w)

> **Not yet on the App Store.** Arcfin is currently available via [TestFlight](https://testflight.apple.com/join/kkC58n2w) only — v0.1.0 is uploaded to App Store Connect and pending Apple's review.

![Version](https://img.shields.io/badge/version-0.1.0-blue)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%20%7C%20macOS%20%7C%20tvOS-lightgrey?logo=apple&logoColor=white)
![Minimum OS](https://img.shields.io/badge/OS-26%2B-black?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-AGPL--3.0-blue)

A premium native Jellyfin media client for the Apple ecosystem.

---

## What is Arcfin?

A ground-up SwiftUI client for Jellyfin — direct play and transcoded streaming (AVFoundation, with a VLC fallback for containers AVFoundation can't open), downloads for offline playback, AirPlay/Chromecast/Picture in Picture, a Netflix-style profile picker with per-profile Face ID/PIN lock, and optional Seerr (content requests) and Streamystats (watch stats) integrations. Built around iOS 26/iPadOS 26's Liquid Glass design on iPhone/iPad, a native AppKit sidebar UI with full feature parity on Mac, and a native focus/remote-driven UI with full feature parity on Apple TV.

### Features

- **Home** — Continue Watching, Next Up, Recently Added, and recommended shelves
- **Library** — browse, filter, search, sort (including by genre)
- **Player** — direct play/transcode with automatic quality stepping, AirPlay, Chromecast, Picture in Picture, Now Playing/Control Center integration, chapters, skip intro/credits/recap, custom subtitle styling, playback speed, Up Next with an "are you still watching" check, SyncPlay
- **Downloads** — offline playback with Wi-Fi-only/quality controls and a Live Activity for progress
- **Trailers** — local trailers, with an in-app YouTube fallback when a title has none
- **Requests** — Seerr browse/request, right alongside the library
- **Stats** — Streamystats dashboard
- **Profiles** — Netflix-style picker, per-profile Face ID/PIN app lock
- **Settings** — grouped hub (Playback, Downloads, Appearance, Notifications, Server, Integrations), Privacy Policy/Terms/Data Protection links

### Platform Targets

| Platform | Status |
|---|---|
| iOS 26 + iPadOS 26 | Primary — v0.1.0 uploaded to App Store Connect, processing |
| macOS | Full feature parity with iOS — native AppKit video surface, sidebar navigation, mouse/keyboard controls, Touch ID, AirPlay/PiP. A few gaps documented inline: judder-free frame matching (no public API on macOS), AirPlay from the offline/VLC-engine player (needs a real AVPlayer to route, which VLC playback doesn't have) |
| tvOS 26 | Full feature parity — playback, focus/remote navigation, library filters, Settings, Seerr, casting links all wired up. Newest of the four platforms |

---

## Architecture

SPM monorepo under `LocalPackages/` — single `Package.swift`, all targets inside.

```
LocalPackages/Sources/
├── Core Services
│   ├── Telemetry        — OSLog wrapper (no analytics/crash SDK)
│   ├── AuthCore         — Keychain, multi-server/multi-profile auth
│   ├── Persistence      — SwiftData models
│   ├── ImageCache       — Nuke disk + memory cache
│   ├── BackgroundKit    — BGTask scheduling (smart downloads)
│   ├── LiveActivityKit  — Download progress Live Activity (shared with the widget extension)
│   ├── JellyfinAPI      — Jellyfin REST + WebSocket client
│   ├── StreamystatsAPI  — Streamystats REST client
│   └── SeerrAPI         — Seerr REST client
└── Feature Packages
    ├── AppState         — thin scaffold; not currently used by any shipping feature
    ├── MediaEngine       — AVFoundation (default) + VLC (SwiftVLC) player engines behind one protocol
    ├── SyncEngine        — offline progress sync
    ├── SearchKit         — server search
    └── CastKit           — Chromecast (Google Cast SDK) sender wrapper
```

### Stack

| Concern | Choice |
|---|---|
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI + iOS 26 Liquid Glass |
| State | Plain `@Observable` classes + `@State`/`@Environment` — **not** TCA. TCA is a dependency and exists in one unused `AppState` scaffold file, but no shipping feature uses it; every real feature (auth, media, downloads, casting, sync play, etc.) is a plain `@Observable` class. Docs previously claimed TCA as the locked choice — this reflects what's actually shipping instead. |
| Storage | SwiftData (models in `Persistence`) |
| Images | Nuke |
| Player | AVFoundation (default) / VLC via SwiftVLC (selectable in Settings; downloads always use VLC) — both behind `MediaPlayerProtocol` |
| API clients | Manual clients (JellyfinAPI, StreamystatsAPI, SeerrAPI) — not OpenAPI-generated despite the dependency being present |
| Testing | Swift Testing (not XCTest) |
| Sync | Offline playback-progress sync (`SyncEngine`); no CloudKit sync shipped yet |

---

## Design System

Token namespace: `DT` (`Arcfin/DesignTokens.swift`)

| Token | Value |
|---|---|
| Background primary | `#0A0A0F` — deep cinematic black |
| Background secondary | `#12121A` — midnight navy |
| Background tertiary | `#1C1C26` |
| Accent | `#06B6D4` — cyan / ice |
| Text primary | `#FFFFFF` |
| Text secondary | `#8E8E93` |

Typography uses SF Pro Display for hero titles and SF Pro Text for body and labels. Liquid Glass throughout — nav bars, tab bar, player overlay, modal sheets.

---

## External Services

- [Jellyfin](https://jellyfin.org) — media server (REST + WebSocket)
- [Streamystats](https://github.com/fredrikburmester/streamystats) — self-hosted play stats
- [Seerr](https://github.com/Fallenbagel/jellyseerr) — content requests (formerly Jellyseerr)

None of these are servers Arcfin operates — the app connects directly from the device to a server you already run or have access to. See [arcfin.psmattas.com/privacy](https://arcfin.psmattas.com/privacy).

---

## AI-Assisted Development

This project uses AI tooling (Claude Code) as a coding assistant. AI assistance speeds up implementation — it does not replace engineering judgement.

All AI-generated code is:
- Written to a spec I defined
- Reviewed by me before it lands
- Held to the same quality bar as hand-written code

I am a software engineer. AI makes certain tasks faster and easier, but the architecture, design decisions, and code review are mine. I take responsibility for everything that ships.

---

## Project Status

Feature-complete for an initial release — playback, library, downloads, casting, profiles, and Settings are all built. v0.1.0 is on [TestFlight](https://testflight.apple.com/join/kkC58n2w) now; the same build is uploaded to App Store Connect and pending Apple's review (see `fastlane/metadata/`).

---

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for the DCO
sign-off process and coding standards.

## Code of Conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Security

See [SECURITY.md](SECURITY.md) for how to report vulnerabilities.

---

## License

Licensed under the [GNU Affero General Public License v3.0 or later](LICENSE)
(AGPL-3.0-or-later).

The "Arcfin" name and logo are **not** covered by this license — see
[TRADEMARK.md](TRADEMARK.md).
