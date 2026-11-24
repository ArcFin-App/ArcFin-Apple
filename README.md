# Arcfin

<img src="https://git.psmattas.com/ArcFin/ArcFin/media/branch/main/assets/badges/app-store-badge-black.svg" alt="App Store — coming with 0.5.1, not yet available" height="48" style="opacity:0.45">

[<img src="https://git.psmattas.com/ArcFin/ArcFin/media/branch/main/assets/badges/testflight-badge.png" alt="Available on TestFlight" height="48">](https://testflight.apple.com/join/kkC58n2w)

> **Not yet on the App Store.** Arcfin is in beta on [TestFlight](https://testflight.apple.com/join/kkC58n2w). Version 0.5.1, the last beta, goes to Apple for review and becomes the first App Store release. See [Testing Arcfin](docs/TESTING.md#how-releases-work).

[![Build](https://git.psmattas.com/ArcFin/ArcFin/actions/workflows/build.yml/badge.svg?branch=main)](https://git.psmattas.com/ArcFin/ArcFin/actions?workflow=build.yml)
[![Version](https://arcfin.psmattas.com/badges/version.svg)](https://git.psmattas.com/ArcFin/ArcFin/releases)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%20%7C%20macOS%20%7C%20tvOS-lightgrey?logo=apple&logoColor=white)
![Minimum OS](https://img.shields.io/badge/OS-26%2B-black?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-AGPL--3.0-blue)
[![Listed on JellyWatch Hub](https://jellywatch.app/hub/arcfin/badge.svg)](https://jellywatch.app/hub/arcfin)
[![Join our community on Reddit](https://img.shields.io/badge/Join%20our%20community-r%2Farcfin-FF4500?logo=reddit&logoColor=white)](https://www.reddit.com/r/arcfin)

**A native Jellyfin client for iPhone, iPad, Mac and Apple TV.**

Arcfin plays the movies, shows, music and live TV on your own Jellyfin server. It plays almost any file the server has, downloads titles for watching offline, and works with the rest of your Apple devices: AirPlay, Picture in Picture, SharePlay, Siri, widgets, Live Activities, CarPlay, Apple Watch and the Top Shelf.

Each platform gets an interface of its own rather than a stretched phone app: Liquid Glass on iPhone and iPad, a sidebar, menu bar and keyboard shortcuts on the Mac, and a focus-driven layout for the Siri Remote on Apple TV.

> Arcfin is an independent project. It isn't affiliated with or endorsed by the Jellyfin project. See [About the project](docs/ABOUT.md#not-affiliated-with-jellyfin).

---

## Get Arcfin

Tap **Available on TestFlight** at the top to join the public beta, on your iPhone, iPad, Mac or Apple TV. You'll need your own [Jellyfin](https://jellyfin.org) server, or an account on one.

New builds reach a small internal beta first, every night something has changed, and go on to the public beta once those testers approve them. [Testing Arcfin](docs/TESTING.md) covers both betas, how to get an internal seat, how long Apple's review takes, and what happens after the App Store release.

## Features

- **Watching:** three playback engines that between them play almost any file, HDR and Atmos, Skip Intro and Credits, chapters, Up Next, SharePlay and SyncPlay, AirPlay and Chromecast, and a player in its own window on iPad and Mac.
- **Music:** a full music library with lyrics, a visualizer, offline playlists, CarPlay, Apple Watch, widgets, ListenBrainz and Year in Music.
- **Live TV:** channels and the guide, pause and rewind live, and recordings and reminders.
- **Browsing:** a Home you arrange, live updates from your other devices, library filters, title pages with cast, scores and trailers, and search.
- **Downloads:** fast offline playback with your progress synced back, and Smart Downloads that keep your next episodes ready.
- **Profiles and admin:** profile locks, signing in a nearby device from your iPhone, settings that follow you with the Arcfin Sync plugin, and an Admin tab for running the server.
- **Add-ons:** Seerr requests, TMDB scores and where to watch, and ListenBrainz.

The full list, and which platform has what, is in **[Features](docs/FEATURES.md)**.

## Platforms

| Platform | Status |
|---|---|
| iOS 26 and iPadOS 26 | The main platform |
| macOS 26 | Feature parity with iPhone and iPad |
| tvOS 26 | Feature parity apart from downloads |
| watchOS 26 | Music on the watch and a remote, with the iPhone app |
| CarPlay | Music, from the iPhone app |

## Get in touch

| Need | Where |
|---|---|
| Found a bug, or have an idea | [Open an issue](https://git.psmattas.com/ArcFin/ArcFin/issues/new/choose), or use **Settings › About › Report a Problem** in the app |
| Help using Arcfin | [arcfin.psmattas.com/support](https://arcfin.psmattas.com/support), or email **[support.arcfin@psmattas.com](mailto:support.arcfin@psmattas.com)** |
| A security problem | Email **[security@psmattas.com](mailto:security@psmattas.com)**. Please don't open a public issue. See [SECURITY.md](SECURITY.md) |
| Translating Arcfin | Open a **Translation** issue. See [Translating Arcfin](CONTRIBUTING.md#translating-arcfin) |
| A seat in the internal beta | Email **[support.arcfin@psmattas.com](mailto:support.arcfin@psmattas.com)**. See [Internal beta](docs/TESTING.md#internal-beta) |

When you report a problem, **Settings › About › Share Diagnostics** makes a text file of the app's log to attach. It can include your server's address and the titles you played, so look it over before posting it publicly.

## Contributing

Code, translations, bug reports and testing are all welcome.

- **Code:** new here? Pick an issue from [Start here: good first issues](https://git.psmattas.com/ArcFin/ArcFin/issues/255). Then read [CONTRIBUTING.md](CONTRIBUTING.md) for how to build, the project's conventions and the pull request process. [ARCHITECTURE.md](ARCHITECTURE.md) explains how the app fits together.
- **Translations:** Arcfin's first ten translations were machine made and need native speakers to check them. See [Translating Arcfin](CONTRIBUTING.md#translating-arcfin).
- **Testing:** join the [TestFlight beta](https://testflight.apple.com/join/kkC58n2w) and report what you find. See [Testing Arcfin](docs/TESTING.md).

Every commit needs a DCO sign-off (`git commit -s`). Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

Arcfin is written by one developer with help from AI coding tools; every change is reviewed and tested by the maintainer. See [AI-assisted development](docs/ABOUT.md#ai-assisted-development).

## Privacy

Arcfin has no analytics, no tracking and no crash-reporting service, and the developer runs no servers that see your data. The app talks straight from your device to the servers you add (Jellyfin, and Seerr and TMDB if you set them up), plus a few public services for specific features: Wikidata for awards on title pages, and YouTube for trailers when your server has none. Passwords, tokens and keys are kept in the Keychain. See the [privacy policy](https://arcfin.psmattas.com/privacy).

## License

Arcfin's source code is licensed under the **[GNU Affero General Public License v3.0 or later](LICENSE)**, with an additional permission for the App Store and TestFlight. You can use, study, modify and share it; if you share it or run a modified version for others, you must make its source code available too. The Arcfin name, logo and app icon aren't covered by the license; see [TRADEMARK.md](TRADEMARK.md). There's a plain-language summary in [License in short](docs/ABOUT.md#license-in-short).

Arcfin is a player for media you own or have the right to watch. It doesn't provide or link to any content, and piracy isn't welcome anywhere in the project. See the [Disclaimer](docs/ABOUT.md#disclaimer).

## Acknowledgements

Arcfin builds on the work of the [Jellyfin](https://jellyfin.org) project and these open-source projects, among others: [AetherEngine](https://github.com/superuser404notfound/AetherEngine), [SwiftVLC](https://github.com/harflabs/SwiftVLC) and [Nuke](https://github.com/kean/Nuke). The full list, with licenses, is in the app under **Settings › About › Legal & Licenses**, along with the Privacy Policy, Terms of Use and Data Protection notice.

Thank you to the 100 to 150 people testing Arcfin on TestFlight. Arcfin wouldn't be what it is without you.

## More documentation

| Document | What's in it |
|---|---|
| [Testing Arcfin](docs/TESTING.md) | The public and internal betas, how releases work, and reporting a problem |
| [Features](docs/FEATURES.md) | Everything Arcfin does, and which platform has what |
| [About the project](docs/ABOUT.md) | AI-assisted development, Jellyfin, the disclaimer and a license summary |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Building, conventions, translating and pull requests |
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the app and its CI fit together |
| [SECURITY.md](SECURITY.md) | Reporting a vulnerability, and which builds get fixes |
| [TRADEMARK.md](TRADEMARK.md) | Using the Arcfin name and logo |
