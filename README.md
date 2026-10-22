# Arcfin

<img src="assets/badges/app-store-badge-black.svg" alt="App Store — pending review, not yet available" height="48" style="opacity:0.45">

[<img src="assets/badges/testflight-badge.png" alt="Available on TestFlight" height="48">](https://testflight.apple.com/join/kkC58n2w)

> **Not yet on the App Store.** Arcfin is available through [TestFlight](https://testflight.apple.com/join/kkC58n2w). Version 0.1.0 is with Apple for review; 0.1.1 is in testing.

![Version](https://img.shields.io/badge/version-0.1.1-blue)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%20%7C%20macOS%20%7C%20tvOS-lightgrey?logo=apple&logoColor=white)
![Minimum OS](https://img.shields.io/badge/OS-26%2B-black?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-AGPL--3.0-blue)

A native Jellyfin client for iPhone, iPad, Mac and Apple TV.

---

## What is Arcfin?

Arcfin is a SwiftUI client for your own Jellyfin server. It plays almost anything the server has, downloads titles for offline viewing, and works with the rest of the Apple ecosystem: AirPlay, Picture in Picture, SharePlay, Siri, widgets, Live Activities and the Top Shelf. Seerr (requests) and TMDB (scores and where to watch) are optional add-ons.

Each platform gets its own interface rather than a stretched phone app: Liquid Glass on iPhone and iPad, a sidebar, menu bar and keyboard shortcuts on Mac, and a focus-driven layout built for the Siri Remote on Apple TV.

## Features

### Watching
- **Three playback engines:** Aether (FFmpeg demuxing with VideoToolbox decoding, the default), AVFoundation and VLC. Auto picks Aether and falls back to the others if a file won't open.
- **Formats:** direct play or server transcoding, HDR, surround and Atmos audio, text and image subtitles with custom styling.
- **In the player:** skip intro, recap and credits; chapters; scrubbing previews; playback speed; audio and subtitle switching without reloading; Previous and Next; Up Next with a countdown; "Are you still watching?"; X-Ray cast info.
- **Around the player:** AirPlay, Chromecast (iPhone and iPad), Picture in Picture, Now Playing and Control Center.
- **Watching together:** SharePlay over FaceTime, and Jellyfin's SyncPlay.
- **Player in its own window** on iPad and Mac, so you can keep browsing beside it.

### Browsing
- **Home:** Continue Watching, Next Up, Recently Added, recommendations, collections, Seerr and streaming-service shelves. You choose and order the shelves.
- **Library:** filters, sorting, genres, playlists, collections, Surprise Me and Hide Watched.
- **Title pages:** cast, scores, age ratings, where to watch, trailers (local, or YouTube when there's none), More Like This, and the collections and playlists a title is in.
- **Search** across the server, with optional search history.
- **Spoiler Protection** for episode thumbnails and descriptions.

### Stats
An optional tab, off until you turn it on in Settings › Appearance (Navigation on iPhone, iPad and Mac), worked out entirely from your Jellyfin watch history:
- **This week, this month, this year or all time**, each named ("October 2026"): time watched, and how many movies, episodes and shows.
- **Activity** over the period, your busiest day, current and longest streaks, and when you watch: by weekday and time of day.
- **Top shows** with how far through each you are, **top movies**, and what you've watched on repeat.
- **Your taste:** genres, decades, studios and networks, age ratings, and the actors and directors you've seen most.
- **Highlights:** average and highest rating, longest and oldest movie, and how long you've been watching.
- **Your library:** how much of it you've watched, shows finished, titles in progress and favourites.
- **Share:** a story- or post-sized card of your stats, made by Arcfin, ready for social media (iPhone, iPad and Mac).

### Downloads
- **Offline playback** on iPhone, iPad and Mac, with your watch progress synced back when you're online.
- **Fast:** large files download in parallel ranges, several titles at once, and keep going in the background.
- **Live Activity** with progress, time left and a paused or waiting-for-Wi-Fi state.
- **Smart Downloads** keeps the next episodes of your shows downloaded and removes watched ones, within a storage budget. **Keep Downloaded** does the same for one show from its page.
- **Control:** quality, mobile data, Low Power and Low Data Mode pauses, subtitles, and automatic clean-up.

### Profiles and settings
- **Profiles** with a picker, Face ID, Touch ID or PIN lock, and the server's parental controls and access schedule.
- **Settings sync** across devices with the Arcfin Sync server plugin, including settings an admin can lock.
- **Settings** grouped into Playback, Player Features, Downloads, Browsing, Appearance, Notifications, Server and Integrations.

### Across the system
- **Siri and Shortcuts:** play a title, play a random movie, download the next episode of a show, open Discover.
- **Widgets** for Continue Watching and Recently Added, Control Center controls, Spotlight, Handoff and notifications for new episodes, with Quiet Hours.
- **Apple TV:** Top Shelf, and a library screensaver made from your artwork.
- **Mac:** every player control in the menu bar with a keyboard shortcut.

### Add-ons
- **Seerr:** browse, request and keep a watchlist, signed in per profile.
- **TMDB:** an optional key for scores and where-to-watch information.

## Platforms

| Platform | Status |
|---|---|
| iOS 26 and iPadOS 26 | The main platform. 0.1.1 in testing |
| macOS 26 | Feature parity with iPhone and iPad, with a native AppKit video surface, sidebar, menu bar commands and Touch ID |
| tvOS 26 | Feature parity apart from downloads, with remote and focus navigation throughout |

Some features aren't possible on every platform:
- **Chromecast** is iPhone and iPad only, because Google's SDK is.
- **Live Activities and Lock Screen widgets** are iPhone only.
- **Downloads** aren't available on Apple TV, which has no lasting storage.
- **Face ID and Touch ID** aren't available on Apple TV.
- **The screensaver** runs inside Arcfin, because Apple TV doesn't let apps provide a system screensaver.

---

## Architecture

An SPM monorepo under `LocalPackages/`, with every target in one `Package.swift`. The app target (`Arcfin/`) holds the screens, plus the widget (`ArcfinWidgets/`) and Top Shelf (`ArcfinTopShelf/`) extensions.

```
LocalPackages/Sources/
├── Core services
│   ├── Telemetry        — OSLog wrapper (no analytics or crash SDK)
│   ├── AuthCore         — Keychain, multiple servers and profiles
│   ├── Persistence      — SwiftData models
│   ├── ImageCache       — Nuke memory and disk cache
│   ├── BackgroundKit    — background task scheduling
│   ├── LiveActivityKit  — download Live Activity, shared with the widget extension
│   ├── JellyfinAPI      — Jellyfin REST and WebSocket client
│   └── SeerrAPI         — Seerr client
└── Features
    ├── MediaEngine      — Aether, AVFoundation and VLC behind one player protocol
    ├── SyncEngine       — offline progress sync and settings sync
    ├── SearchKit        — server search
    ├── CastKit          — Chromecast sender
    └── AppState         — unused scaffold
```

### Stack

| Concern | Choice |
|---|---|
| Language | Swift 6, strict concurrency |
| UI | SwiftUI, with Liquid Glass on iOS 26 |
| State | Plain `@Observable` classes with `@State` and `@Environment`. TCA is a dependency, used only by the unused `AppState` scaffold |
| Storage | SwiftData |
| Images | Nuke |
| Playback | [AetherEngine](https://github.com/superuser404notfound/AetherEngine), AVFoundation and [SwiftVLC](https://github.com/harflabs/SwiftVLC), behind `MediaPlayerProtocol` |
| API clients | Hand-written for Jellyfin and Seerr |
| Tests | Swift Testing |

## Design system

Tokens live under `DT` in `Arcfin/DesignTokens.swift`. iPhone, iPad and Mac follow the system's light or dark appearance. The players, splash and lock screens, and all of Apple TV, stay dark.

| Token | Dark | Light |
|---|---|---|
| Background primary | `#0A0A0F` | Light equivalent with matching contrast |
| Background secondary | `#12121A` | 〃 |
| Background tertiary | `#1C1C26` | 〃 |
| Accent | `#06B6D4` cyan | `#0E7490` deeper cyan |
| Text primary | `#FFFFFF` | Dark equivalent |
| Text secondary | `#8E8E93` | 〃 |

Labels on accent fills use `DT.Color.onAccent`. Hero titles use SF Pro Display; body text and labels use SF Pro Text.

---

## Building

1. Use Xcode 26 or later.
2. Open `Arcfin.xcodeproj` and pick the **Arcfin** scheme.
3. Choose an iPhone, iPad, Mac or Apple TV destination.
4. Set your own team and bundle identifier to sign.

Swift packages resolve on the first build. To run the package tests:

```sh
cd LocalPackages && swift test
```

## External services

- [Jellyfin](https://jellyfin.org): the media server (REST and WebSocket)
- [Seerr](https://github.com/Fallenbagel/jellyseerr): content requests (formerly Jellyseerr)
- [TMDB](https://www.themoviedb.org): optional metadata

Arcfin runs none of these. The app connects straight from your device to servers you run or have access to. See [arcfin.psmattas.com/privacy](https://arcfin.psmattas.com/privacy).

---

## AI-assisted development

This project uses AI tooling (Claude Code) as a coding assistant. It speeds up implementation; it doesn't replace engineering judgement.

All AI-generated code is:
- written to a spec I defined
- reviewed by me before it lands
- held to the same bar as hand-written code

I'm a software engineer. AI makes some tasks faster, but the architecture, design decisions and code review are mine, and I take responsibility for everything that ships.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the DCO sign-off (`git commit -s`) and coding standards. Please also read the [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

See [SECURITY.md](SECURITY.md) to report a vulnerability privately.

## License

Licensed under the [GNU Affero General Public License v3.0 or later](LICENSE) (AGPL-3.0-or-later).

The "Arcfin" name and logo are **not** covered by this license. See [TRADEMARK.md](TRADEMARK.md).
