// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

/// Now Playing on Apple TV: the cover over its own colours, the song, where it is and the
/// controls, with Playing Next or the lyrics in a column on the right when one is turned on,
/// and the song across the whole screen when neither is. Play/Pause on the remote works
/// anywhere on the screen; Back leaves the music playing.
struct TVMusicNowPlaying: View {
    enum Panel: String { case upNext, lyrics }

    @Environment(\.dismiss) private var dismiss
    /// The right-hand column, kept between songs and visits; empty for none.
    @AppStorage("tvMusicNowPlayingPanel") private var panelName = ""
    @State private var lyrics: Lyrics?
    @State private var showsSleepTimer = false
    private var player: MusicQueuePlayer { AppServices.music.player }

    private var panel: Panel? { Panel(rawValue: panelName) }

    private func toggle(_ panel: Panel) {
        withAnimation(DT.Animation.standard) { panelName = self.panel == panel ? "" : panel.rawValue }
    }

    var body: some View {
        Group {
            if let song = player.current {
                HStack(alignment: panel == nil ? .center : .top, spacing: 80) {
                    songColumn(song)
                        .frame(width: panel == nil ? nil : 720, alignment: .leading)
                        // Back from the column on the right always finds the controls.
                        .focusSection()
                    if let panel {
                        Group {
                            switch panel {
                            case .upNext: upNext
                            case .lyrics: lyricsView
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 100)
                .padding(.vertical, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panel == nil ? .center : .topLeading)
                .background { backdrop(MusicAPI.artworkURL(song, width: 600)) }
                .task(id: song.id) {
                    lyrics = nil
                    lyrics = await MusicLyricsSource.shared.lyrics(for: song)
                    if lyrics == nil, panel == .lyrics, !MusicLyricsSource.shared.isAvailable(song) { panelName = "" }
                }
            } else {
                Color.black.onAppear { dismiss() }
            }
        }
        .foregroundStyle(.white)
        .onPlayPauseCommand { player.togglePlayPause() }
    }

    /// The cover beside the song across the screen, or above it in the left column.
    private func songColumn(_ song: MusicSong) -> some View {
        let wide = panel == nil
        let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 80))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: 36))
        return layout {
            TVMusicArtwork(url: MusicAPI.artworkURL(song, width: 1000))
                .overlay { MusicArtworkVisualizer(bars: 36, spacing: 3, cornerRadius: DT.Radius.card) }
                .frame(width: wide ? 640 : 380, height: wide ? 640 : 380)
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
            .frame(maxWidth: wide ? 860 : nil, alignment: .leading)
        }
    }

    private func controls(_ song: MusicSong) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 28) {
                circle("backward.fill", label: "Previous") { player.previous() }
                circle(player.isPlaying ? "pause.fill" : "play.fill", label: player.isPlaying ? "Pause" : "Play", large: true) {
                    player.togglePlayPause()
                }
                circle("forward.fill", label: "Next") { player.next() }
            }
            TVWrapLayout(spacing: 20) {
                circle("shuffle", label: "Shuffle", isOn: player.queue.isShuffled, small: true) {
                    player.setShuffled(!player.queue.isShuffled)
                }
                circle(player.repeatMode == .one ? "repeat.1" : "repeat", label: "Repeat", isOn: player.repeatMode != .off,
                       small: true) {
                    player.repeatMode = switch player.repeatMode {
                    case .off: .all
                    case .all: .one
                    case .one: .off
                    }
                }
                ratingCircles(song)
                circle("list.bullet", label: "Playing Next", isOn: panel == .upNext, small: true) { toggle(.upNext) }
                if MusicLyricsSource.shared.isAvailable(song) {
                    circle("quote.bubble", label: "Lyrics", isOn: panel == .lyrics, small: true) { toggle(.lyrics) }
                }
                circle("moon.zzz", label: "Sleep Timer", isOn: AppServices.music.sleepTimer != nil, small: true) {
                    showsSleepTimer = true
                }
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
        circle(isFavorite ? "star.fill" : "star", label: isFavorite ? "Remove from Favorites" : "Add to Favorites", isOn: isFavorite,
               small: true) {
            MusicFavorites.shared.toggle(song.id, server: song.isFavorite)
        }
        circle("hand.thumbsup", label: "Like", isOn: likes == true, small: true) {
            MusicRatings.shared.set(song.id, likes: true, server: song.likes)
        }
        circle("hand.thumbsdown", label: "Dislike", isOn: likes == false, small: true) {
            MusicRatings.shared.set(song.id, likes: false, server: song.likes)
        }
    }

    private func circle(_ systemImage: String, label: LocalizedStringKey, isOn: Bool = false, large: Bool = false,
                        small: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CircleControl(systemImage: systemImage, isOn: isOn, size: large ? 104 : small ? 64 : 80)
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// What plays next, as a grid filling the column: as many across as fit at about 220 pt.
    private var upNext: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Playing Next").font(.headline).foregroundStyle(.white.opacity(0.7))
            if player.queue.upNext.isEmpty {
                Text("Nothing Up Next").font(.callout).foregroundStyle(.white.opacity(0.5))
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 36, alignment: .top)], spacing: 36) {
                        ForEach(Array(player.queue.upNext.prefix(60))) { entry in
                            Button { player.jump(to: entry.id) } label: {
                                TVMusicTile(url: MusicAPI.artworkURL(entry.track, width: 480), title: entry.track.name,
                                            subtitle: entry.track.artistLine)
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                            .contextMenu {
                                Button("Remove", systemImage: "minus.circle", role: .destructive) { player.remove(entry.id) }
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollClipDisabled()
                .focusSection()
            }
        }
    }

    /// The words down the column, the line being sung bright and kept in the middle.
    @ViewBuilder
    private var lyricsView: some View {
        if let lyrics, !lyrics.lines.isEmpty {
            let songID = player.current?.id ?? ""
            let current = MusicLyricsSource.shared.lineIndex(lyrics, songID: songID, at: player.position)
            VStack(alignment: .leading, spacing: 16) {
                if lyrics.isSynced {
                    MusicLyricsTimingMenu(songID: songID).font(.callout)
                }
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                                Text(verbatim: line.text)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white.opacity(lyrics.isSynced && index != current ? 0.35 : 1))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(.vertical, 200)
                    }
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.15),
                                                 .init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .onChange(of: current, initial: true) { _, line in
                        guard let line else { return }
                        withAnimation(DT.Animation.standard) { proxy.scrollTo(line, anchor: .center) }
                    }
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
