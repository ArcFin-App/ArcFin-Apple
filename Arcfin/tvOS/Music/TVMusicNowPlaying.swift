// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

/// Now Playing on Apple TV: the cover over its own colours, the song, where it is, the
/// transport, and below either what plays next or the lyrics. Play/Pause on the remote works
/// anywhere on the screen; Back leaves the music playing.
struct TVMusicNowPlaying: View {
    enum Panel { case upNext, lyrics }

    @Environment(\.dismiss) private var dismiss
    @State private var panel = Panel.upNext
    @State private var lyrics: Lyrics?
    @State private var showsSleepTimer = false
    private var player: MusicQueuePlayer { AppServices.music.player }

    var body: some View {
        Group {
            if let song = player.current {
                VStack(alignment: .leading, spacing: 36) {
                    HStack(alignment: .center, spacing: 80) {
                        TVMusicArtwork(url: MusicAPI.artworkURL(song, width: 1000))
                            .overlay { MusicArtworkVisualizer(bars: 36, spacing: 3, cornerRadius: DT.Radius.card) }
                            // Leaves the room below for Playing Next's larger tiles.
                            .frame(width: 440, height: 440)
                            .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
                            .focusable(false)
                        VStack(alignment: .leading, spacing: 32) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(verbatim: song.name).font(.title.weight(.bold)).lineLimit(2)
                                if let artist = song.artistLine {
                                    Text(verbatim: artist).font(.title3).foregroundStyle(.white.opacity(0.7))
                                }
                                if let album = song.albumName {
                                    Text(verbatim: album).font(.callout).foregroundStyle(.white.opacity(0.5))
                                }
                                MusicQualityBadge(song: song)
                            }
                            TVMusicScrubber(player: player)
                            controls(song)
                        }
                    }
                    // Up from anywhere in the queue, even its first song under the cover, lands
                    // on the controls.
                    .focusSection()
                    switch panel {
                    case .upNext: upNext
                    case .lyrics: lyricsView
                    }
                }
                .padding(.horizontal, 100)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background { backdrop(MusicAPI.artworkURL(song, width: 600)) }
                .task(id: song.id) {
                    lyrics = nil
                    lyrics = await MusicLyricsSource.shared.lyrics(for: song)
                    if lyrics == nil, panel == .lyrics { panel = .upNext }
                }
            } else {
                Color.black.onAppear { dismiss() }
            }
        }
        .foregroundStyle(.white)
        .onPlayPauseCommand { player.togglePlayPause() }
    }

    private func controls(_ song: MusicSong) -> some View {
        HStack(spacing: 28) {
            circle("backward.fill", label: "Previous") { player.previous() }
            circle(player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Play", large: true) {
                player.togglePlayPause()
            }
            circle("forward.fill", label: "Next") { player.next() }
            circle("shuffle", label: "Shuffle", isOn: player.queue.isShuffled) { player.setShuffled(!player.queue.isShuffled) }
            circle(player.repeatMode == .one ? "repeat.1" : "repeat", label: "Repeat", isOn: player.repeatMode != .off) {
                player.repeatMode = switch player.repeatMode {
                case .off: .all
                case .all: .one
                case .one: .off
                }
            }
            ratingCircles(song)
            if MusicLyricsSource.shared.isAvailable(song) {
                circle("quote.bubble", label: "Lyrics", isOn: panel == .lyrics) {
                    panel = panel == .lyrics ? .upNext : .lyrics
                }
            }
            circle("moon.zzz", label: "Sleep Timer", isOn: AppServices.music.sleepTimer != nil) {
                showsSleepTimer = true
            }
        }
        .focusSection()
        .confirmationDialog(Text("Sleep Timer"), isPresented: $showsSleepTimer) {
            MusicSleepTimerOptions()
        } message: {
            MusicSleepTimerStatus()
        }
    }

    @ViewBuilder
    private func ratingCircles(_ song: MusicSong) -> some View {
        let isFavorite = MusicFavorites.shared.isFavorite(song.id, server: song.isFavorite)
        let likes = MusicRatings.shared.likes(song.id, server: song.likes)
        circle(isFavorite ? "star.fill" : "star", label: isFavorite ? "Remove from Favorites" : "Add to Favorites", isOn: isFavorite) {
            MusicFavorites.shared.toggle(song.id, server: song.isFavorite)
        }
        circle("hand.thumbsup", label: "Like", isOn: likes == true) {
            MusicRatings.shared.set(song.id, likes: true, server: song.likes)
        }
        circle("hand.thumbsdown", label: "Dislike", isOn: likes == false) {
            MusicRatings.shared.set(song.id, likes: false, server: song.likes)
        }
    }

    private func circle(_ systemImage: String, label: LocalizedStringKey, isOn: Bool = false, large: Bool = false,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CircleControl(systemImage: systemImage, isOn: isOn, size: large ? 104 : 80)
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Playing Next").font(.headline).foregroundStyle(.white.opacity(0.7))
            if player.queue.upNext.isEmpty {
                Text("Nothing Up Next").font(.callout).foregroundStyle(.white.opacity(0.5))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 36) {
                        ForEach(Array(player.queue.upNext.prefix(30))) { entry in
                            Button { player.jump(to: entry.id) } label: {
                                TVMusicTile(url: MusicAPI.artworkURL(entry.track, width: 480), title: entry.track.name,
                                            subtitle: entry.track.artistLine)
                            }
                            // As many as fit across at about 240 pt, sized to fill the row
                            // exactly: more on a large screen, fewer on a small one.
                            .containerRelativeFrame(.horizontal) { width, _ in
                                let count = max(3, ((width + 36) / (240 + 36)).rounded(.down))
                                return (width - 36 * (count - 1)) / count
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                            .contextMenu {
                                Button("Remove", systemImage: "minus.circle", role: .destructive) { player.remove(entry.id) }
                            }
                        }
                    }
                    .padding(.vertical, 20)
                }
                .focusSection()
            }
        }
    }

    @ViewBuilder
    private var lyricsView: some View {
        if let lyrics, !lyrics.lines.isEmpty {
            let songID = player.current?.id ?? ""
            let current = MusicLyricsSource.shared.lineIndex(lyrics, songID: songID, at: player.position)
            let lines = Array(lyrics.lines.enumerated())
            let shown = current.map { index in lines.filter { $0.offset >= index - 1 && $0.offset <= index + 2 } }
                ?? Array(lines.prefix(4))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(shown, id: \.offset) { index, line in
                    Text(verbatim: line.text)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white.opacity(lyrics.isSynced && index != current ? 0.35 : 1))
                        .lineLimit(1)
                }
                if lyrics.isSynced {
                    MusicLyricsTimingMenu(songID: songID)
                        .font(.callout)
                }
            }
            .animation(DT.Animation.standard, value: current)
        } else {
            ProgressView().tint(.white)
        }
    }

    private func backdrop(_ url: URL?) -> some View {
        Color.black
            .overlay {
                CachedAsyncImage(url: url) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                }
                .blur(radius: 80)
                .scaleEffect(1.3)
            }
            .overlay(.black.opacity(0.5))
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// Where the song is. Focus it and press left or right to go back or ahead 10 seconds; held
/// presses keep going. It thickens and brightens while focused.
private struct TVMusicScrubber: View {
    let player: MusicQueuePlayer
    @FocusState private var isFocused: Bool
    /// Where presses have moved to, shown until the player catches up.
    @State private var target: Double?
    @State private var settle: Task<Void, Never>?

    var body: some View {
        let duration = max(player.duration, 1)
        let position = min(target ?? player.position, duration)
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25))
                    Capsule().fill(.white)
                        .frame(width: proxy.size.width * position / duration)
                }
            }
            .frame(height: isFocused ? 14 : 6)
            HStack {
                Text(verbatim: position.musicTime)
                Spacer()
                Text(verbatim: "-" + max(duration - position, 0).musicTime)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(isFocused ? 1 : 0.6))
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .focusable()
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.02 : 1)
        .animation(DT.Animation.fast, value: isFocused)
        .onMoveCommand { direction in
            switch direction {
            case .left: step(-10, duration: duration)
            case .right: step(10, duration: duration)
            default: break
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position")
        .accessibilityValue(Text(verbatim: position.musicTime))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(10, duration: duration)
            case .decrement: step(-10, duration: duration)
            @unknown default: break
            }
        }
    }

    /// Presses add up and seek once they stop, so five quick presses jump 50 seconds.
    private func step(_ seconds: Double, duration: Double) {
        target = min(max((target ?? player.position) + seconds, 0), duration)
        settle?.cancel()
        settle = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let target else { return }
            player.seek(to: target)
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self.target = nil
        }
    }
}

private struct CircleControl: View {
    let systemImage: String
    let isOn: Bool
    let size: CGFloat
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.36, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .foregroundStyle(isFocused ? .black : .white)
            .background(isFocused ? .white : (isOn ? .white.opacity(0.35) : .white.opacity(0.15)), in: Circle())
            .scaleEffect(isFocused ? 1.1 : 1)
            .animation(DT.Animation.fast, value: isFocused)
    }
}
