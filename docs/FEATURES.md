# Arcfin's features

Everything Arcfin does, by area. For which platform has what, see [Platform differences](#platform-differences) at the end.

- [Watching](#watching)
- [Music](#music)
- [Live TV](#live-tv)
- [Browsing](#browsing)
- [Downloads](#downloads)
- [Stats](#stats)
- [Profiles, settings and help](#profiles-settings-and-help)
- [Across the system](#across-the-system)
- [Add-ons](#add-ons)
- [With the Arcfin Sync plugin](#with-the-arcfin-sync-plugin)
- [Platform differences](#platform-differences)

## Watching
- **Three playback engines:** Aether (FFmpeg demuxing with VideoToolbox decoding, the default), AVFoundation and VLC. Auto picks Aether and falls back to the others if a file won't open.
- **Formats:** direct play or server transcoding, HEVC and HDR, surround and Atmos audio, and text and image subtitles with your own styling.
- **In the player:** Skip Intro, Recap, Credits and Preview, right in the controls while they're showing; chapters; scrubbing previews; playback speed; audio and subtitle switching without reloading; Previous and Next; Up Next with a countdown; "Are you still watching?"; Cast & Characters; and a sleep timer.
- **Around the player:** AirPlay, Chromecast (iPhone and iPad), Picture in Picture, Now Playing and Control Center.
- **Watching together:** SharePlay over FaceTime, and Jellyfin's SyncPlay.
- **Player in its own window** on iPad and Mac, so you can keep browsing beside it.
- **Downloads and your own files** play in the same player as streaming, with chapters, scrubbing previews and Up Next. Open a video file from the device with **Browse Files**.
- **Play On and remote control:** send what you're watching to another device signed in to the server, or control one from here, from the Jellyfin web app or from your Apple Watch.

## Music
- **A full music library:** artists with an A–Z bar, albums, songs, genres with covers, playlists and favourites, each with its own search, and Made for You playlists. Artist pages show the artist's logo and backdrop when the server has them.
- **Now Playing** with the cover as the hero, synced and plain lyrics, a visualizer, a quality badge, the queue and what played earlier, Repeat, Shuffle and a sleep timer.
- **Offline and in the background:** download songs, albums, playlists or everything by an artist, with smart downloads, a storage limit and a Live Activity.
- **Together and everywhere:** SharePlay, CarPlay with voice search, Siri ("Play … in Arcfin"), interactive widgets in every size, and AirPlay and casting.
- **Your listening:** likes and dislikes, ListenBrainz scrobbling and loves, importing your listening history from other music services, What's Playing? to recognise a song and find it, and Year in Music.

## Live TV
- **Channels and the guide,** narrowed to movies, series, news, kids or sports, with radio stations and search across channels and programmes.
- **Watch live:** pause and rewind a channel, and switch from a channel list over the picture.
- **Recordings:** record a programme or a whole series, programme reminders, and finished recordings to watch.
- **On Home:** favourite, on-now and recent channels. Live TV follows the server's permissions.

## Browsing
- **Home:** Continue Watching, Next Up, Recently Added, recommendations, collections, and Seerr and streaming-service shelves. You choose and order the shelves.
- **Live updates:** what you watch on other devices, and new titles on the server, show up on Home while the app is open.
- **Library:** filters, sorting, genres, playlists, collections, Surprise Me and Hide Watched, with search inside Movies, Shows, Collections and Playlists.
- **Title pages:** cast, review scores, age ratings, where to watch, trailers (the server's, or YouTube when it has none), More Like This, and the collections and playlists a title is in.
- **Search** across the server and Discover, with optional search history.
- **Spoiler Protection** for episode thumbnails and descriptions.

## Downloads
- **Offline playback** on iPhone, iPad and Mac, with your progress synced back when you're online.
- **Fast:** large files download in parallel ranges, several titles at once, and keep going in the background.
- **Live Activity** with progress, time left, and a paused or waiting-for-Wi-Fi state.
- **Smart Downloads** keep the next episodes of your shows downloaded and remove watched ones, within a storage budget. **Keep Downloaded** does the same for one show from its page.
- **Control:** quality, mobile data, pausing in Low Power and Low Data Mode, subtitles, and automatic clean-up.

## Stats
An optional tab with **All**, **Movies & Shows** and **Music**, by week, month, year or all time:
- **Watching,** worked out from your Jellyfin watch history: time watched, streaks and when you watch, top shows and movies, and the genres, decades, studios and people you watch most.
- **Listening:** plays, minutes listened, your top songs, artists, albums and genres, from ListenBrainz when it's linked (it counts every listen) or from your Jellyfin server.
- **A card to share** for both, in Story or Post size.

## Profiles, settings and help
- **Profiles** with a picker, Face ID, Touch ID or PIN lock, and the server's parental controls and access schedule.
- **Set Up Nearby Device:** sign in an Apple TV, iPad or Mac from your iPhone or iPad, with every profile you pick and their Seerr and ListenBrainz, over your own network. Both screens show a code to compare, nothing is sent until you allow it on the new device, and passwords are never sent.
- **Pick Together** (iPhone and iPad) with the Arcfin Sync server plugin: swipe through titles with the people you're with until you all like the same one, then watch it here, on another device or together over SyncPlay.
- **Devices & Sync** with the Arcfin Sync server plugin: your settings follow you to your other devices, automatically, after asking first, or not at all, and you can send one device's settings to all the others.
- **Admin tab** for server admins:
  - the server dashboard, Active Sessions (see who's watching and why a stream transcodes, then pause, stop or message them), scheduled tasks and activity;
  - libraries, users, devices, plugins, API keys, logs and backups;
  - server settings, and a title's metadata editor;
  - **Arcfin for Everyone**: defaults and locks for every Arcfin app on the server, or for one person.
- **Languages:** English, German, French, Spanish, Simplified Chinese, Brazilian Portuguese, Japanese, Italian, Korean, Dutch and Russian, with a language picker in Settings.
- **Accessibility:** VoiceOver labels throughout, Dynamic Type, Increase Contrast and Reduce Motion.
- **Help:** Report a Problem and Share Diagnostics in Settings › About. Diagnostics stay on your device until you choose to send them.

## Across the system
- **Siri and Shortcuts:** play a title, play a random movie, download the next episode of a show, open Discover.
- **Widgets** for Continue Watching and Recently Added, Control Center controls, Spotlight, Handoff, and notifications for new episodes with Quiet Hours.
- **Apple TV:** Top Shelf with trailers from the server, Spotlight Home with the title you're on full screen and its trailer, Always Ask Who's Watching, and a library screensaver made from your artwork.
- **CarPlay:** your music in the car, laid out like the system's music app, with Home, New, Radio and Library, rows of covers, A–Z artists and album pages. Search has its own tab, with voice search and quick buttons, and Now Playing shows whether Shuffle and Repeat are on. It starts signed in from the car, keeps your profile's PIN, and has a widget on the CarPlay dashboard.
- **Apple Watch:** your music on the watch, with playlists kept on it to play without the phone, and a remote for Arcfin playing on another device, with the Digital Crown for volume.
- **Mac:** every player control in the menu bar, with a keyboard shortcut.

## Add-ons
- **[Seerr](https://github.com/seerr-team/seerr):** browse, request and keep a watchlist, signed in per profile.
- **[TMDB](https://www.themoviedb.org):** an optional key for review scores, where to watch and what's popular.
- **[ListenBrainz](https://listenbrainz.org):** an optional token per profile. Arcfin sends your listens and loves to it, and Stats and Year in Music can count from it. On a Jellyfin 12.4 server, Jellyfin's own ListenBrainz similarity provider also feeds Similar Artists.

## With the Arcfin Sync plugin

[Arcfin Sync](https://arcfin.psmattas.com/plugin/) is a free plugin for your Jellyfin server. Everything above works without it; these need it, from the version shown. Every 0.6 feature is off until the server's admin turns it on, in the plugin's dashboard page or Admin › Arcfin for Everyone:

| Feature | What it does | Needs |
|---|---|---|
| **Watch parties** | Watch together in sync over SyncPlay, hosting or joining on iPhone, iPad, Mac or Apple TV. Invite people with a code, which guests type in or, on iPhone and iPad, scan as a QR code; plan a party up to 30 days ahead and see what time it'll be for each guest. Start one from Home or a title's page. People in other SyncPlay apps can join; the host needs Arcfin. | 0.6 or later |
| **Seerr and TMDB through the server** | The admin keeps the Seerr and TMDB keys on the server, encrypted, and they never reach a device. Requests are made as you, with your own Seerr limits, and one made while Seerr is down is sent once it's back. | 0.6 or later |
| **Signed commands** | Your admin can clear a forgotten PIN, lock or unlock a profile and wipe a lost device. Commands are signed with the server's key, so nothing else can send them. Also PIN rules, approving new devices from a trusted iPhone or iPad, HTTPS away from home, and signing out devices that fall behind. | 0.6 or later |
| **Watch time and bedtime** | Daily limits and a bedtime per person, counted across every app, with warnings 10 and 5 minutes before. | 0.6 or later |
| **Download limits** | Caps on titles and space for movies and shows, and albums, songs and space for music, counted once across all your devices. | 0.6 or later |
| **Who's Watching?** | On a shared account, like the living-room TV, pick who's watching and each person's progress follows along. | 0.6 or later |
| **Announcements and maintenance** | Messages from the admin and planned maintenance at the top of Home. | 0.6 or later |
| **Hide from Continue Watching** | Hidden titles are the same on all your devices, and come back once you play them again. | 0.6 or later |
| **Recommendations** | Top Picks, Because You Watched and Popular on This Server rows on Home. | 0.6 or later |
| **Pick Together** (iPhone and iPad) | Everyone swipes through titles on their own device until you all like the same one, then watches it here, on another device or together over SyncPlay. Join with a code or a QR code; the device that starts it can lock the session and remove people. | 0.5 or later |
| **Devices & Sync** | Your settings follow you to your other devices: automatically, after asking first, or not at all. Send one device's settings to all the others. | 0.4 or later |
| **Arcfin for Everyone** | Server admins give any setting a default or lock it, for everyone or for one person, and choose who can use Pick Together. | 0.4 or later |
| **Every audio track in a converted download** | A smaller download keeps each audio language you pick. | 0.3.1 or later |
| **AV1 downloads** | Lower-quality downloads use AV1, about half the size of H.264, when the server's hardware can really encode it. | 0.3 or later |

## Platform differences

| Platform | Status |
|---|---|
| iOS 26 and iPadOS 26 | The main platform |
| macOS 26 | Feature parity with iPhone and iPad, with a native video surface, sidebar, menu bar commands and Touch ID |
| tvOS 26 | Feature parity apart from downloads, with remote and focus navigation throughout |
| watchOS 26 | Music on the watch and a remote, with the iPhone app |
| CarPlay | Music, from the iPhone app |

Some features can't work on every platform:
- **Chromecast** is iPhone and iPad only, because Google's SDK is.
- **Pick Together**, and scanning a watch party's QR code, are iPhone and iPad only. Mac and Apple TV join a watch party with its code.
- **Live Activities and Lock Screen widgets** are iPhone only.
- **Downloads** aren't available on Apple TV, which has no lasting storage.
- **Face ID and Touch ID** aren't available on Apple TV.
- **The screensaver** runs inside Arcfin, because Apple TV doesn't let apps provide a system screensaver.
