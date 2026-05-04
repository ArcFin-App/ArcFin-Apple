# Arcfin

A premium native Jellyfin media client for the Apple ecosystem.

---

## What is Arcfin?

Arcfin goes beyond existing Jellyfin clients by natively integrating play stats, content requests, a customisable home screen, and a first-class experience across iPhone, iPad, Apple TV, and Mac — all built on iOS 26.

### Features (planned)

- **Home** — hero banner, customisable shelves, Continue Watching, Recently Added
- **Library** — browse, filter, search with Spotlight integration
- **Player** — chapters, intro skip, audio/subtitle track switching, progress sync
- **Stats** — Streamystats dashboard, play history heatmap, top content, watch time
- **Requests** — Jellyseerr browse, request, and approval status
- **Plugins** — native plugin host with manifest-based third-party plugins
- **Sync** — settings sync via companion Jellyfin server plugin + iCloud CloudKit fallback
- **Admin** — server dashboard and user management

### Platform Targets

| Platform | Status |
|---|---|
| iOS 26 + iPadOS 26 | Primary |
| tvOS 26 | Planned |
| macOS 26 (native SwiftUI) | Planned |

---

## Architecture

Four-layer SPM monorepo under `Packages/` — single `Package.swift`, all targets inside.

```
Packages/
├── Core Services
│   ├── Telemetry        — OSLog wrapper
│   ├── AuthCore         — Keychain, token refresh, multi-server
│   ├── Persistence      — SwiftData models and migrations
│   ├── ImageCache       — Nuke disk + memory cache
│   ├── BackgroundKit    — BGTask scheduling
│   ├── JellyfinAPI      — Jellyfin REST + WebSocket client
│   ├── StreamystatsAPI  — Streamystats REST client
│   └── JellyseerrAPI    — Jellyseerr REST client
└── Feature Packages
    ├── AppState         — TCA store, reducers, actions, effects
    ├── MediaEngine      — MPV (primary) + AVFoundation (fallback) player
    ├── SyncEngine       — Settings sync protocol + conflict resolution
    └── SearchKit        — Server search + Spotlight + local index
```

### Stack

| Concern | Choice |
|---|---|
| Language | Swift 6 |
| UI | SwiftUI + iOS 26 Liquid Glass |
| State | TCA (The Composable Architecture) |
| Storage | SwiftData |
| Images | Nuke |
| Player | MPV wrapper (primary), AVFoundation (fallback) |
| API clients | OpenAPI codegen (swift-openapi-generator) |
| Testing | Swift Testing |
| Sync | Jellyfin companion plugin + CloudKit fallback |

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

Typography uses SF Pro Display for hero titles and SF Pro Text for body and labels. Full iOS 26 Liquid Glass throughout — nav bars, tab bar, player overlay, modal sheets.

---

## External Services

- [Jellyfin](https://jellyfin.org) — media server (REST + WebSocket)
- [Streamystats](https://github.com/fredrikburmester/streamystats) — self-hosted play stats
- [Jellyseerr](https://github.com/Fallenbagel/jellyseerr) — content requests

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

Early development. Scaffold and design system complete. Home screen in progress.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). External contributions are not open at this time.

## Code of Conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Security

See [SECURITY.md](SECURITY.md) for how to report vulnerabilities.

---

## License

Private — not open source.
