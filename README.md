# Arcfin

<img src="https://git.psmattas.com/ArcFin/ArcFin/media/branch/main/assets/badges/app-store-badge-black.svg" alt="App Store — coming with 0.5.1, not yet available" height="48" style="opacity:0.45">

[<img src="https://git.psmattas.com/ArcFin/ArcFin/media/branch/main/assets/badges/testflight-badge.png" alt="Available on TestFlight" height="48">](https://testflight.apple.com/join/kkC58n2w)

> **Not yet on the App Store.** Arcfin is in beta on [TestFlight](https://testflight.apple.com/join/kkC58n2w). Version 0.5.1, the last beta, goes to Apple for review and becomes the first App Store release. See [How releases work](#how-releases-work).

[![Build](https://git.psmattas.com/ArcFin/ArcFin/actions/workflows/build.yml/badge.svg?branch=main)](https://git.psmattas.com/ArcFin/ArcFin/actions?workflow=build.yml)
[![Version](https://img.shields.io/badge/dynamic/xml?url=https%3A%2F%2Fgit.psmattas.com%2FArcFin%2FArcFin%2Freleases.rss&query=substring-before%28substring-after%28%2F%2Fitem%5B1%5D%2Ftitle%2C%27Arcfin%20%27%29%2C%27%20%C2%B7%27%29&label=version&color=blue&cacheSeconds=3600)](https://git.psmattas.com/ArcFin/ArcFin/releases)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%20%7C%20macOS%20%7C%20tvOS-lightgrey?logo=apple&logoColor=white)
![Minimum OS](https://img.shields.io/badge/OS-26%2B-black?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-AGPL--3.0-blue)
[![Listed on JellyWatch Hub](https://jellywatch.app/hub/arcfin/badge.svg)](https://jellywatch.app/hub/arcfin)
[![Join our community on Reddit](https://img.shields.io/badge/Join%20our%20community-r%2Farcfin-FF4500?logo=reddit&logoColor=white)](https://www.reddit.com/r/arcfin)

**A native Jellyfin client for iPhone, iPad, Mac and Apple TV.**

Arcfin plays the movies and shows on your own Jellyfin server. It plays almost any file the server has, downloads titles for watching offline, and works with the rest of your Apple devices: AirPlay, Picture in Picture, SharePlay, Siri, widgets, Live Activities and the Top Shelf.

Each platform gets an interface of its own rather than a stretched phone app: Liquid Glass on iPhone and iPad, a sidebar, menu bar and keyboard shortcuts on the Mac, and a focus-driven layout for the Siri Remote on Apple TV.

> Arcfin is an independent project. It isn't affiliated with or endorsed by the Jellyfin project. See [Not affiliated with Jellyfin](#not-affiliated-with-jellyfin).

---

## Get Arcfin

You need your own [Jellyfin](https://jellyfin.org) server, or an account on one. Every build first goes to a small internal beta as a nightly, and only a nightly the internal testers approve goes on to the public beta that anyone can join.

### Public beta

Anyone can join on **[TestFlight](https://testflight.apple.com/join/kkC58n2w)**. Install TestFlight from the App Store, open the invite on your iPhone, iPad, Mac or Apple TV, and you'll get each new build automatically.

Public builds go through Apple's TestFlight review first. A new version usually takes 1 to 3 days; a new build of an existing version is usually through within a day, but can take as long. The [release notes](https://git.psmattas.com/ArcFin/ArcFin/releases) list what's in each build.

### Internal beta

Internal testers get a **nightly build**. Every night at midnight Irish time, if anything has changed since the last one, Arcfin builds the newest code and sends it to them on iPhone, iPad, Mac and Apple TV. They test it first: once a nightly has held up and they've approved it, that build goes on to the public beta.

- **Apple checks every nightly first.** Most get through within a few hours, depending on how quickly Apple's reviewers get to them, so a nightly often arrives in the morning rather than at midnight.
- **A new version takes longer.** The first build of each new version gets Apple's full review, which usually takes 1 to 3 days. After a version change, nightlies can wait in line until Apple approves it.
- **Sometimes there's more than one a day,** when an urgent fix can't wait until midnight.
- **Seats are limited.** To ask for one, email **[support.arcfin@psmattas.com](mailto:support.arcfin@psmattas.com)** with the Apple Account email to invite and the devices you'd test on.
- **Expect rough edges.** Internal builds are the newest and least tested, so please report problems with **Settings › About › Report a Problem**.

### How releases work

**Until the App Store release**

- **0.5.0** brings the last big batch of features.
- **0.5.1** is the last beta. It adds no new features: it's for stability fixes, and tests covering everything Arcfin does.
- Once testers are happy with 0.5.1, it goes to Apple for review. When Apple approves it, that build is Arcfin's first App Store release.

**After the App Store release**

Arcfin moves to a rolling cycle. New features and improvements go through three stages:

1. **Nightly builds** go to the [internal beta](#internal-beta) every night something has changed. Anyone can ask for a seat.
2. **Approved nightlies** go to the [public beta](#public-beta) on TestFlight, once the internal testers have used a nightly and approved it. It's the same invite link, so nothing changes if you've already joined.
3. **App Store updates** reach everyone once both beta groups have used a build without problems.

Every build has a pre-release on the [Releases](https://git.psmattas.com/ArcFin/ArcFin/releases) page with what changed, and a build that reached the App Store is a full release there.

**Security fixes** skip the wait. They go out as fast as the targets in [SECURITY.md](SECURITY.md#what-happens-next), on TestFlight and on the App Store.

### Thank you, testers

Between 100 and 150 people have been testing Arcfin on TestFlight, reporting bugs and suggesting ideas. Arcfin wouldn't be what it is without you. Thank you.

## Features

### Watching
- **Three playback engines:** Aether (FFmpeg demuxing with VideoToolbox decoding, the default), AVFoundation and VLC. Auto picks Aether and falls back to the others if a file won't open.
- **Formats:** direct play or server transcoding, HEVC and HDR, surround and Atmos audio, and text and image subtitles with your own styling.
- **In the player:** Skip Intro, Recap, Credits and Preview, right in the controls while they're showing; chapters; scrubbing previews; playback speed; audio and subtitle switching without reloading; Previous and Next; Up Next with a countdown; "Are you still watching?"; Cast & Characters; and a sleep timer.
- **Around the player:** AirPlay, Chromecast (iPhone and iPad), Picture in Picture, Now Playing and Control Center.
- **Watching together:** SharePlay over FaceTime, and Jellyfin's SyncPlay.
- **Player in its own window** on iPad and Mac, so you can keep browsing beside it.
- **Downloads and your own files** play in the same player as streaming, with chapters, scrubbing previews and Up Next. Open a video file from the device with **Browse Files**.
- **Play On and remote control:** send what you're watching to another device signed in to the server, or control one from here, from the Jellyfin web app or from your Apple Watch.

### Music
- **A full music library:** artists with an A–Z bar, albums, songs, genres with covers, playlists and favourites, each with its own search, and Made for You playlists. Artist pages show the artist's logo and backdrop when the server has them.
- **Now Playing** with the cover as the hero, synced and plain lyrics, a visualizer, a quality badge, the queue and what played earlier, Repeat, Shuffle and a sleep timer.
- **Offline and in the background:** download songs, albums, playlists or everything by an artist, with smart downloads, a storage limit and a Live Activity.
- **Together and everywhere:** SharePlay, CarPlay with voice search, Siri ("Play … in Arcfin"), interactive widgets in every size, and AirPlay and casting.
- **Your listening:** likes and dislikes, ListenBrainz scrobbling and loves, importing your listening history from other music services, What's Playing? to recognise a song and find it, and Year in Music.

### Live TV
- **Channels and the guide,** narrowed to movies, series, news, kids or sports, with radio stations and search across channels and programmes.
- **Watch live:** pause and rewind a channel, and switch from a channel list over the picture.
- **Recordings:** record a programme or a whole series, programme reminders, and finished recordings to watch.
- **On Home:** favourite, on-now and recent channels. Live TV follows the server's permissions.

### Browsing
- **Home:** Continue Watching, Next Up, Recently Added, recommendations, collections, and Seerr and streaming-service shelves. You choose and order the shelves.
- **Live updates:** what you watch on other devices, and new titles on the server, show up on Home while the app is open.
- **Library:** filters, sorting, genres, playlists, collections, Surprise Me and Hide Watched, with search inside Movies, Shows, Collections and Playlists.
- **Title pages:** cast, review scores, age ratings, where to watch, trailers (the server's, or YouTube when it has none), More Like This, and the collections and playlists a title is in.
- **Search** across the server and Discover, with optional search history.
- **Spoiler Protection** for episode thumbnails and descriptions.

### Downloads
- **Offline playback** on iPhone, iPad and Mac, with your progress synced back when you're online.
- **Fast:** large files download in parallel ranges, several titles at once, and keep going in the background.
- **Live Activity** with progress, time left, and a paused or waiting-for-Wi-Fi state.
- **Smart Downloads** keep the next episodes of your shows downloaded and remove watched ones, within a storage budget. **Keep Downloaded** does the same for one show from its page.
- **Control:** quality, mobile data, pausing in Low Power and Low Data Mode, subtitles, and automatic clean-up.

### Stats
An optional tab with **All**, **Movies & Shows** and **Music**, by week, month, year or all time:
- **Watching,** worked out from your Jellyfin watch history: time watched, streaks and when you watch, top shows and movies, and the genres, decades, studios and people you watch most.
- **Listening:** plays, minutes listened, your top songs, artists, albums and genres, from ListenBrainz when it's linked (it counts every listen) or from your Jellyfin server.
- **A card to share** for both, in Story or Post size.

### Profiles, settings and help
- **Profiles** with a picker, Face ID, Touch ID or PIN lock, and the server's parental controls and access schedule.
- **Set Up Nearby Device:** sign in an Apple TV, iPad or Mac from your iPhone or iPad, with every profile you pick and their Seerr and ListenBrainz, over your own network. Both screens show a code to compare, nothing is sent until you allow it on the new device, and passwords are never sent.
- **Devices & Sync** with the Arcfin Sync server plugin: your settings follow you to your other devices, automatically, after asking first, or not at all, and you can send one device's settings to all the others.
- **Admin tab** for server admins:
  - the server dashboard, Active Sessions (see who's watching and why a stream transcodes, then pause, stop or message them), scheduled tasks and activity;
  - libraries, users, devices, plugins, API keys, logs and backups;
  - server settings, and a title's metadata editor;
  - **Arcfin for Everyone**: defaults and locks for every Arcfin app on the server, or for one person.
- **Languages:** English, German, French, Spanish, Simplified Chinese, Brazilian Portuguese, Japanese, Italian, Korean, Dutch and Russian, with a language picker in Settings.
- **Accessibility:** VoiceOver labels throughout, Dynamic Type, Increase Contrast and Reduce Motion.
- **Help:** Report a Problem and Share Diagnostics in Settings › About. Diagnostics stay on your device until you choose to send them.

### Across the system
- **Siri and Shortcuts:** play a title, play a random movie, download the next episode of a show, open Discover.
- **Widgets** for Continue Watching and Recently Added, Control Center controls, Spotlight, Handoff, and notifications for new episodes with Quiet Hours.
- **Apple TV:** Top Shelf with trailers from the server, Spotlight Home with the title you're on full screen and its trailer, Always Ask Who's Watching, and a library screensaver made from your artwork.
- **CarPlay:** your music in the car, laid out like the system's music app, with Home, New, Radio and Library, rows of covers, A–Z artists and album pages. Search has its own tab, with voice search and quick buttons, and Now Playing shows whether Shuffle and Repeat are on. It starts signed in from the car, keeps your profile's PIN, and has a widget on the CarPlay dashboard.
- **Apple Watch:** your music on the watch, with playlists kept on it to play without the phone, and a remote for Arcfin playing on another device, with the Digital Crown for volume.
- **Mac:** every player control in the menu bar, with a keyboard shortcut.

### Add-ons
- **[Seerr](https://github.com/seerr-team/seerr):** browse, request and keep a watchlist, signed in per profile.
- **[TMDB](https://www.themoviedb.org):** an optional key for review scores, where to watch and what's popular.
- **[ListenBrainz](https://listenbrainz.org):** an optional token per profile. Arcfin sends your listens and loves to it, and Stats and Year in Music can count from it. On a Jellyfin 12.4 server, Jellyfin's own ListenBrainz similarity provider also feeds Similar Artists.

## Platforms

| Platform | Status |
|---|---|
| iOS 26 and iPadOS 26 | The main platform |
| macOS 26 | Feature parity with iPhone and iPad, with a native video surface, sidebar, menu bar commands and Touch ID |
| tvOS 26 | Feature parity apart from downloads, with remote and focus navigation throughout |
| watchOS 26 | Music on the watch and a remote, with the iPhone app |
| CarPlay | Music, from the iPhone app |

Some features can't work on every platform:
- **Chromecast** is iPhone and iPad only, because Google's SDK is.
- **Live Activities and Lock Screen widgets** are iPhone only.
- **Downloads** aren't available on Apple TV, which has no lasting storage.
- **Face ID and Touch ID** aren't available on Apple TV.
- **The screensaver** runs inside Arcfin, because Apple TV doesn't let apps provide a system screensaver.

---

## Get in touch

| Need | Where |
|---|---|
| Found a bug, or have an idea | [Open an issue](https://git.psmattas.com/ArcFin/ArcFin/issues/new/choose), or use **Settings › About › Report a Problem** in the app |
| Help using Arcfin | [arcfin.psmattas.com/support](https://arcfin.psmattas.com/support), or email **[support.arcfin@psmattas.com](mailto:support.arcfin@psmattas.com)** |
| A security problem | Email **[security@psmattas.com](mailto:security@psmattas.com)**. Please don't open a public issue. See [SECURITY.md](SECURITY.md) |
| Translating Arcfin | Open a **Translation** issue. See [Translating Arcfin](CONTRIBUTING.md#translating-arcfin) |
| A seat in the internal beta | Email **[support.arcfin@psmattas.com](mailto:support.arcfin@psmattas.com)**. See [Internal beta](#internal-beta) |

When you report a problem, **Settings › About › Share Diagnostics** makes a text file of the app's log to attach. It can include your server's address and the titles you played, so look it over before posting it publicly.

## Contributing

Code, translations, bug reports and testing are all welcome.

- **Code:** new here? Pick an issue from [Start here: good first issues](https://git.psmattas.com/ArcFin/ArcFin/issues/255). Then read [CONTRIBUTING.md](CONTRIBUTING.md) for how to build, the project's conventions and the pull request process. [ARCHITECTURE.md](ARCHITECTURE.md) explains how the app fits together.
- **Translations:** Arcfin's first ten translations were machine made and need native speakers to check them. See [Translating Arcfin](CONTRIBUTING.md#translating-arcfin).
- **Testing:** join the [TestFlight beta](https://testflight.apple.com/join/kkC58n2w) and report what you find. See [How releases work](#how-releases-work) for what each beta gets.

Every commit needs a DCO sign-off (`git commit -s`). Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## AI-assisted development

Arcfin is written by one developer with help from AI coding tools (Claude Code).

- **What the AI does:** writes code to specifications the maintainer defines, runs builds and tests, and drafts documentation and pull requests.
- **What it doesn't do:** decide the architecture, the design or what gets built. Those decisions are the maintainer's.
- **Review:** every change is read and tested by the maintainer before it merges, and held to the same standard as hand-written code.
- **Responsibility:** the maintainer is responsible for everything that ships, however it was written.

Contributors can use AI tools too. The rules are in [CONTRIBUTING.md](CONTRIBUTING.md#ai-assisted-contributions).

## Privacy

Arcfin has no analytics, no tracking and no crash-reporting service, and the developer runs no servers that see your data. The app talks straight from your device to the servers you add (Jellyfin, and Seerr and TMDB if you set them up), plus a few public services for specific features: Wikidata for awards on title pages, and YouTube for trailers when your server has none. Passwords, tokens and keys are kept in the Keychain. See the [privacy policy](https://arcfin.psmattas.com/privacy).

## Not affiliated with Jellyfin

Arcfin is an independent, third-party client. It is **not** an official Jellyfin app, and it isn't affiliated with, endorsed by or supported by the [Jellyfin project](https://jellyfin.org).

"Jellyfin" and the Jellyfin logo belong to the Jellyfin project. Arcfin uses the name only to say which server it works with, as Jellyfin's [branding guidelines](https://jellyfin.org/docs/general/contributing/branding/) allow, and doesn't use the Jellyfin logo. Please don't ask the Jellyfin team for help with Arcfin; [get in touch](#get-in-touch) here instead.

Seerr and TMDB are likewise independent of Arcfin. This product uses the TMDB API but is not endorsed or certified by TMDB.

## Disclaimer

Arcfin is a player for media you own or have the right to watch. It doesn't provide, host or link to any content; everything it plays comes from a server you or someone you trust runs.

Arcfin does not promote, support or condone piracy. Discussion of piracy, requests for help with pirated content, and links to piracy tools or sites aren't allowed anywhere in the project, including issues, pull requests and support email, and will be closed or removed.

## License

Arcfin's source code is licensed under the **[GNU Affero General Public License v3.0 or later](LICENSE)** (AGPL-3.0-or-later), with an additional permission that allows it to be distributed through the App Store and TestFlight, as long as the complete source code stays freely available.

In short:
- **You can** use, study, modify and share Arcfin, including commercially.
- **If you share it,** modified or not, you must make the complete source code available under the same license, and keep the copyright and license notices.
- **If you run a modified version** that people use over a network, you must offer them its source code as well.
- **There's no warranty.** Arcfin is provided as is.

This summary isn't legal advice. The [LICENSE](LICENSE) file is the full, binding text.

The **Arcfin name, logo and app icon aren't covered by the license**. Forks are welcome but need a name and icon of their own. See [TRADEMARK.md](TRADEMARK.md).

## Acknowledgements

Arcfin builds on the work of the [Jellyfin](https://jellyfin.org) project and these open-source projects, among others: [AetherEngine](https://github.com/superuser404notfound/AetherEngine), [SwiftVLC](https://github.com/harflabs/SwiftVLC) and [Nuke](https://github.com/kean/Nuke). The full list, with licenses, is in the app under **Settings › About › Legal & Licenses**, along with the Privacy Policy, Terms of Use and Data Protection notice.
