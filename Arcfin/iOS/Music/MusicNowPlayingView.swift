// SPDX-License-Identifier: AGPL-3.0-or-later

import AVKit
import ImageIO
import CastKit
import GoogleCast
import MediaPlayer
import SwiftUI
import JellyfinAPI
import MediaEngine

/// The bar above the tabs while music plays: the cover, the song, play or pause and next.
/// Tapping it opens Now Playing.
struct MusicMiniPlayer: View {
    @Binding var isExpanded: Bool
    private var player: MusicQueuePlayer { AppServices.music.player }
    private var music: MusicPlayback { AppServices.music }

    var body: some View {
        if let song = player.current {
            HStack(spacing: DT.Spacing.sm) {
                Button { isExpanded = true } label: {
                    HStack(spacing: DT.Spacing.sm) {
                        MusicArtwork(url: MusicAPI.artworkURL(song, width: 120), cornerRadius: DT.Radius.xs)
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: song.name)
                                .font(.system(.footnote, weight: .semibold))
                            if let artist = song.artistLine {
                                Text(verbatim: artist)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1)
                        Spacer(minLength: DT.Spacing.xs)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityHint("Opens Now Playing")
                MusicMiniFavoriteButton(song: song)
                Button { music.togglePlayPause() } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(music.isPlaying ? "Pause" : "Play")
                Button { music.next() } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Next")
            }
            .buttonStyle(.plain)
            .padding(.leading, DT.Spacing.sm)
            .padding(.trailing, DT.Spacing.xs)
            .contentShape(Rectangle())
            // Up opens Now Playing; left skips ahead and right goes back.
            .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { drag in
                let (x, y) = (drag.translation.width, drag.translation.height)
                if abs(x) > abs(y), abs(x) > 50 {
                    x < 0 ? music.next() : music.previous()
                } else if y < -20 {
                    isExpanded = true
                }
            })
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: "Previous") { music.previous() }
        }
    }
}

/// The pill's star, sized like its other buttons.
private struct MusicMiniFavoriteButton: View {
    let song: MusicSong
    private var isFavorite: Bool { MusicFavorites.shared.isFavorite(song.id, server: song.isFavorite) }
    private var likes: Bool? { MusicRatings.shared.likes(song.id, server: song.likes) }

    var body: some View {
        Button { MusicFavorites.shared.toggle(song.id, server: song.isFavorite) } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.body)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .contextMenu {
            Button("Like", systemImage: likes == true ? "hand.thumbsup.fill" : "hand.thumbsup") {
                MusicRatings.shared.set(song.id, likes: true, server: song.likes)
            }
            Button("Dislike", systemImage: likes == false ? "hand.thumbsdown.fill" : "hand.thumbsdown") {
                MusicRatings.shared.set(song.id, likes: false, server: song.likes)
            }
        }
    }
}

/// The full player: the cover over its own colours, the song, a scrubber, the transport and
/// volume, then lyrics, AirPlay and the queue along the bottom.
struct MusicNowPlayingView: View {
    enum Panel { case artwork, lyrics, queue }

    @Environment(\.dismiss) private var dismiss
    @State private var panel = Panel.artwork
    @State private var scrubbing: Double?
    /// A held drag seeks when it's let go. A flick doesn't always say it's finished, so a
    /// value that stops changing seeks too: at once off a drag, after a pause in one.
    @State private var isDragging = false
    @State private var scrubSettle: Task<Void, Never>?
    @State private var lyrics: Lyrics?
    private var player: MusicQueuePlayer { AppServices.music.player }
    private var music: MusicPlayback { AppServices.music }

    var body: some View {
        Group {
            if let song = player.current {
                VStack(spacing: DT.Spacing.lg) {
                    // Over the artwork, which runs up to the top; above the other panels.
                    if panel != .artwork { grabber }
                    switch panel {
                    case .artwork: bigArtwork(song)
                    case .lyrics: MusicLyricsPanel(lyrics: lyrics)
                    case .queue: MusicQueuePanel()
                    }
                    if panel == .artwork {
                        titleRow(song)
                    } else {
                        compactTitleRow(song)
                    }
                    scrubber
                    transport
                    volume
                    bottomBar(song)
                }
                .padding(.horizontal, DT.Spacing.lg)
                .padding(.bottom, DT.Spacing.sm)
                .background { MusicArtworkBackdrop(url: MusicAPI.artworkURL(song, width: 600)) }
                .task(id: song.id) { await loadLyrics(song) }
            } else {
                Color.black.onAppear { dismiss() }
            }
        }
        .foregroundStyle(.white)
        .alwaysDarkPlayer()
        .animation(DT.Animation.standard, value: panel)
    }

    private var grabber: some View {
        Button { dismiss() } label: {
            Capsule()
                .fill(.white.opacity(0.4))
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    /// The whole square cover across the width from the top of the sheet, carrying on below
    /// as a blurred continuation of itself that fades into the backdrop, so nothing ends in a
    /// line. The visualizer stands just below the cover's edge and melts into that blur.
    /// Paused, it dims rather than shrinks: smaller, its edges would show. It's always the
    /// screen's full width; on a short screen the soft part below is what gives way to the
    /// controls.
    private func bigArtwork(_ song: MusicSong) -> some View {
        let url = MusicAPI.artworkURL(song, width: 1200)
        return Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                GeometryReader { proxy in
                    let side = proxy.size.width
                    ZStack(alignment: .top) {
                        // The cover again, blurred, filling the extra space below.
                        // Larger than the space, so the blur's soft edges fall outside it.
                        MusicHeroImage(url: url)
                            .frame(width: side, height: proxy.size.height)
                            .scaleEffect(1.3)
                            .blur(radius: 40)
                            .frame(width: side, height: proxy.size.height)
                            .clipped()
                        MusicHeroImage(url: url)
                            .frame(width: side, height: side)
                            .clipped()
                            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.82),
                                                         .init(color: .clear, location: 1)],
                                                 startPoint: .top, endPoint: .bottom))
                        // Standing a little below the cover's edge, their feet softening away.
                        ZStack {
                            MusicArtworkVisualizer(bars: 32, spacing: 2, cornerRadius: 0)
                                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.82),
                                                             .init(color: .clear, location: 1)],
                                                     startPoint: .top, endPoint: .bottom))
                            MusicArtworkVisualizer(bars: 32, spacing: 2, cornerRadius: 0)
                                .blur(radius: 6)
                                .mask(LinearGradient(stops: [.init(color: .clear, location: 0.78), .init(color: .black, location: 0.9),
                                                             .init(color: .clear, location: 1)],
                                                     startPoint: .top, endPoint: .bottom))
                        }
                        .frame(width: side, height: side * 1.1)
                    }
                    .frame(width: side, height: proxy.size.height, alignment: .top)
                    .clipped()
                }
            }
            // The whole of it fades into the backdrop; nothing is cut off at the foot.
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .opacity(music.isPlaying ? 1 : 0.7)
            .animation(.easeInOut(duration: 0.35), value: music.isPlaying)
            .accessibilityHidden(true)
            .overlay(alignment: .top) { grabber }
            .padding(.horizontal, -DT.Spacing.lg)
            .ignoresSafeArea(edges: .top)
    }

    private func titleRow(_ song: MusicSong) -> some View {
        HStack(alignment: .center, spacing: DT.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: song.name)
                    .font(.title3.weight(.semibold))
                Text(verbatim: song.artistLine ?? "")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .lineLimit(1)
            Spacer()
            MusicRatingButtons(song: song, spacing: DT.Spacing.md)
                .font(.title3)
                .buttonStyle(.plain)
            songMenu(song)
        }
    }

    private func compactTitleRow(_ song: MusicSong) -> some View {
        HStack(spacing: DT.Spacing.sm) {
            MusicArtwork(url: MusicAPI.artworkURL(song, width: 160), cornerRadius: DT.Radius.xs)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: song.name).font(.headline)
                Text(verbatim: song.artistLine ?? "").font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }
            .lineLimit(1)
            Spacer()
            MusicRatingButtons(song: song, spacing: DT.Spacing.md)
                .font(.title3)
                .buttonStyle(.plain)
            songMenu(song)
        }
    }

    private func songMenu(_ song: MusicSong) -> some View {
        Menu {
            Button("Create Station", systemImage: "dot.radiowaves.left.and.right") {
                Task { await MusicActions.instantMix(from: song.id) }
            }
            MusicAddToPlaylistButton { [song] }
            MusicDownloadButton(songs: { [song] }, known: [song])
            Section {
                if let albumID = song.albumId {
                    Button("Go to Album", systemImage: "square.stack") {
                        go(to: .album(MusicAlbum(id: albumID, name: song.albumName ?? "", albumArtist: song.albumArtist)))
                    }
                }
                if let artist = song.artists.first {
                    Button("Go to Artist", systemImage: "music.microphone") {
                        go(to: .artist(MusicArtist(id: artist.id, name: artist.name), libraryID: nil))
                    }
                }
                ShareLink(item: [song.name, song.artistLine, song.albumName].compactMap { $0 }.joined(separator: " – ")) {
                    Label("Share Song", systemImage: "square.and.arrow.up")
                }
            }
            Section { MusicSharePlayButton() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.15), in: Circle())
        }
        .accessibilityLabel("More")
    }

    /// Closes Now Playing and opens the page in Browse.
    private func go(to route: MusicRoute) {
        music.isNowPlayingOpen = false
        dismiss()
        MusicNavigator.shared.open(route)
    }

    private func finishScrub() {
        scrubSettle?.cancel()
        scrubSettle = nil
        guard let scrubbing else { return }
        music.seek(to: scrubbing)
        self.scrubbing = nil
    }

    private var scrubber: some View {
        let duration = max(player.duration, 1)
        let position = scrubbing ?? music.position
        return VStack(spacing: DT.Spacing.xxs) {
            Slider(value: Binding(get: { position }, set: { value in
                scrubbing = value
                scrubSettle?.cancel()
                scrubSettle = Task {
                    try? await Task.sleep(for: .milliseconds(isDragging ? 700 : 150))
                    guard !Task.isCancelled else { return }
                    finishScrub()
                }
            }), in: 0...duration) { editing in
                isDragging = editing
                if !editing { finishScrub() }
            }
            .tint(.white)
            .accessibilityLabel("Position")
            .accessibilityValue(Text(verbatim: position.musicTime))
            ZStack {
                HStack {
                    Text(verbatim: position.musicTime)
                    Spacer()
                    Text(verbatim: "-" + max(duration - position, 0).musicTime)
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.6))
                .accessibilityHidden(true)
                if let song = player.current { MusicQualityBadge(song: song) }
            }
        }
    }

    private var transport: some View {
        HStack {
            Spacer()
            Button { music.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 30))
            }
            .accessibilityLabel("Previous")
            Spacer()
            Button { music.togglePlayPause() } label: {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 64, height: 64)
            }
            .accessibilityLabel(music.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { music.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 30))
            }
            .accessibilityLabel("Next")
            Spacer()
        }
        .buttonStyle(.plain)
    }

    /// The system volume, or the receiver's while casting: the system slider can't reach a
    /// Chromecast and hides itself then.
    private var volume: some View {
        HStack(spacing: DT.Spacing.sm) {
            Image(systemName: "speaker.fill").accessibilityHidden(true)
            if music.isCasting {
                Slider(value: Binding(get: { Double(CastManager.shared.volume) },
                                      set: { CastManager.shared.setVolume(Float($0)) }), in: 0...1)
                    .tint(.white)
                    .accessibilityLabel("Volume")
            } else {
                MusicVolumeSlider()
            }
            Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.6))
    }

    private func bottomBar(_ song: MusicSong) -> some View {
        HStack {
            Spacer()
            panelButton(.lyrics, systemImage: "quote.bubble", label: "Lyrics")
                .disabled(!MusicLyricsSource.shared.isAvailable(song))
            Spacer()
            MusicRoutePicker()
                .frame(width: 44, height: 44)
                .accessibilityLabel("AirPlay")
            Spacer()
            // The Cast button hides itself with no Cast device around (on mobile data, say),
            // so its place goes too rather than leaving a gap.
            if CastManager.shared.hasDevices || music.isCasting {
                MusicCastButton()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Cast")
                Spacer()
            }
            sleepTimerMenu
            Spacer()
            panelButton(.queue, systemImage: "list.bullet", label: "Playing Next")
            Spacer()
        }
        .font(.title3)
    }

    private var sleepTimerMenu: some View {
        Menu {
            Section { MusicSleepTimerOptions() } header: { MusicSleepTimerStatus() }
        } label: {
            Image(systemName: music.sleepTimer == nil ? "moon.zzz" : "moon.zzz.fill")
                .frame(width: 44, height: 44)
                .background(music.sleepTimer == nil ? .clear : .white.opacity(0.2), in: Circle())
        }
        .accessibilityLabel("Sleep Timer")
        .accessibilityValue(music.sleepTimer == nil ? Text("Off") : MusicSleepTimerStatus.text)
    }

    private func panelButton(_ target: Panel, systemImage: String, label: LocalizedStringKey) -> some View {
        Button { panel = panel == target ? .artwork : target } label: {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
                .background(panel == target ? .white.opacity(0.2) : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(panel == target ? .isSelected : [])
    }

    private func loadLyrics(_ song: MusicSong) async {
        lyrics = nil
        lyrics = await MusicLyricsSource.shared.lyrics(for: song)
        if lyrics == nil, panel == .lyrics { panel = .artwork }
    }
}

/// The cover blown up and blurred behind everything, darkened so white text reads on it.
private struct MusicArtworkBackdrop: View {
    let url: URL?
    @State private var palette: [Color] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if palette.count == 9 {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                    MeshGradient(width: 3, height: 3, points: Self.points(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate),
                                 colors: palette, smoothsColors: true)
                }
            } else {
                Color.black
            }
        }
        .overlay(.black.opacity(0.35))
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .animation(.easeInOut(duration: 0.8), value: palette)
        .task(id: url) {
            guard let url else { return }
            let data = url.isFileURL ? try? Data(contentsOf: url) : await URLSession.arcfin.imageData(from: url)
            guard let data else { return }
            let found = await Task.detached(priority: .utility) { Self.palette(from: data) }.value
            if !found.isEmpty { palette = found }
        }
    }

    /// The middle points drift slowly on their own circles; the corners and edges stay put.
    private static func points(at time: Double) -> [SIMD2<Float>] {
        let t = Float(time)
        func drift(_ x: Float, _ y: Float, _ speed: Float, _ phase: Float) -> SIMD2<Float> {
            SIMD2(x + 0.12 * sin(t * speed + phase), y + 0.12 * cos(t * speed * 0.8 + phase))
        }
        return [
            [0, 0], [0.5 + 0.1 * sin(t * 0.21), 0], [1, 0],
            [0, 0.5 + 0.1 * cos(t * 0.17)], drift(0.5, 0.5, 0.23, 0), [1, 0.5 + 0.1 * sin(t * 0.19 + 1)],
            [0, 1], [0.5 + 0.1 * cos(t * 0.15 + 2), 1], [1, 1],
        ]
    }

    /// Nine colours from the cover, one for each point of the mesh: the cover shrunk to 3 by 3,
    /// a little richer.
    nonisolated private static func palette(from data: Data) -> [Color] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 48,
              ] as CFDictionary)
        else { return [] }
        var pixels = [UInt8](repeating: 0, count: 3 * 3 * 4)
        guard let context = CGContext(data: &pixels, width: 3, height: 3, bitsPerComponent: 8, bytesPerRow: 12,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 3, height: 3))
        return (0..<9).map { index in
            let i = index * 4
            return Color(red: Double(pixels[i]) / 255, green: Double(pixels[i + 1]) / 255, blue: Double(pixels[i + 2]) / 255)
                .mix(with: .black, by: 0.15)
        }
    }
}

/// The words, following the song when the server has times for them; tap a line to go there.
private struct MusicLyricsPanel: View {
    let lyrics: Lyrics?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var player: MusicQueuePlayer { AppServices.music.player }
    private var music: MusicPlayback { AppServices.music }

    /// As Apple Music has them: the line being sung bright and full size, the rest dimmer,
    /// a touch smaller and softer the further they are from it.
    private func distance(_ index: Int, from current: Int?) -> Int {
        guard let current else { return 0 }
        return abs(index - current)
    }

    /// A long gap with nothing to sing: dots where the next line will be.
    private func isInGap(after index: Int, in lyrics: Lyrics, songID: String) -> Bool {
        guard index + 1 < lyrics.lines.count, let start = lyrics.lines[index].start,
              let next = lyrics.lines[index + 1].start, next - start > 10 else { return false }
        let position = music.position - MusicLyricsSource.shared.delay(songID)
        return position > start + 5 && position < next
    }

    var body: some View {
        Group {
            if let lyrics, !lyrics.lines.isEmpty {
                let songID = player.current?.id ?? ""
                let current = MusicLyricsSource.shared.lineIndex(lyrics, songID: songID, at: music.position)
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: DT.Spacing.md) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                                let away = lyrics.isSynced ? distance(index, from: current) : 0
                                Text(verbatim: line.text)
                                    .font(.title.weight(.bold))
                                    .foregroundStyle(.white.opacity(away == 0 ? 1 : 0.4))
                                    .scaleEffect(away == 0 ? 1 : 0.96, anchor: .leading)
                                    .blur(radius: reduceMotion ? 0 : min(Double(away) * 0.7, 2.5))
                                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: current)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                                    .onTapGesture {
                                        if let start = line.start { music.seek(to: start + MusicLyricsSource.shared.delay(songID)) }
                                    }
                                    .contextMenu {
                                        if line.start != nil {
                                            Button("Sing This Line Now", systemImage: "music.mic") {
                                                MusicLyricsSource.shared.align(songID, line: line, to: music.position)
                                            }
                                        }
                                    }
                                if lyrics.isSynced, index == current, isInGap(after: index, in: lyrics, songID: songID) {
                                    Image(systemName: "ellipsis")
                                        .font(.title.weight(.bold))
                                        .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                                        .foregroundStyle(.white.opacity(0.8))
                                        .transition(.opacity)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                        .padding(.vertical, DT.Spacing.xxl)
                    }
                    // The lines fade in and out at the edges rather than being cut off.
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                                 .init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .onChange(of: current) { _, line in
                        guard let line else { return }
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { proxy.scrollTo(line, anchor: UnitPoint(x: 0.5, y: 0.35)) }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if lyrics.isSynced {
                        MusicLyricsTimingMenu(songID: songID)
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, DT.Spacing.sm)
                            .padding(.vertical, DT.Spacing.xs)
                            .background(.white.opacity(0.15), in: Capsule())
                            .tint(.white)
                    }
                }
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Shuffle and repeat, then what plays next, to drag into order or swipe away.
private struct MusicQueuePanel: View {
    @AppStorage(MusicSettings.autoplayKey) private var autoplay = true
    private var player: MusicQueuePlayer { AppServices.music.player }
    private var music: MusicPlayback { AppServices.music }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            HStack(spacing: DT.Spacing.sm) {
                toggle("Shuffle", systemImage: "shuffle", isOn: player.queue.isShuffled) {
                    AppServices.music.setShuffled(!player.queue.isShuffled)
                }
                toggle("Repeat", systemImage: player.repeatMode == .one ? "repeat.1" : "repeat",
                       isOn: player.repeatMode != .off) {
                    AppServices.music.cycleRepeatMode()
                }
                toggle("Autoplay", systemImage: "infinity", isOn: autoplay) { autoplay.toggle() }
            }
            HStack {
                Text("Playing Next").font(.headline)
                Spacer()
                if !player.queue.upNext.isEmpty {
                    Button("Clear") { music.clearUpNext() }
                        .font(.subheadline.weight(.semibold))
                }
            }
            List {
                // Earlier in this queue: tap one to go back to it.
                if !player.queue.history.isEmpty {
                    Section {
                        ForEach(Array(player.queue.history.suffix(20))) { entry in
                            HStack(spacing: DT.Spacing.sm) {
                                MusicArtwork(url: MusicAPI.artworkURL(entry.track, width: 120), cornerRadius: DT.Radius.xs)
                                    .frame(width: 44, height: 44)
                                    .opacity(0.6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: entry.track.name).foregroundStyle(.white.opacity(0.7))
                                    Text(verbatim: entry.track.artistLine ?? "")
                                        .font(.footnote)
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                                .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { music.jump(to: entry.id) }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.white.opacity(0.15))
                            .moveDisabled(true)
                            .deleteDisabled(true)
                        }
                    } header: {
                        Text("Played").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                ForEach(Array(player.queue.upNext)) { entry in
                    HStack(spacing: DT.Spacing.sm) {
                        MusicArtwork(url: MusicAPI.artworkURL(entry.track, width: 120), cornerRadius: DT.Radius.xs)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: entry.track.name)
                            Text(verbatim: entry.track.artistLine ?? "")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { music.jump(to: entry.id) }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.white.opacity(0.15))
                }
                .onMove { from, to in
                    guard let source = from.first else { return }
                    music.moveUpNext(from: source, to: to > source ? to - 1 : to)
                }
                .onDelete { offsets in
                    let entries = Array(player.queue.upNext)
                    offsets.map { entries[$0].id }.forEach(music.remove)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .frame(maxHeight: .infinity)
    }

    private func toggle(_ title: LocalizedStringKey, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(isOn ? .black : .white)
                .background(isOn ? .white : .white.opacity(0.15), in: RoundedRectangle(cornerRadius: DT.Radius.sm))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The system volume as an ordinary slider, so it lines up with the speaker icons like any
/// other control. It follows the volume buttons, and sets the volume through the system
/// volume view's own slider, mounted out of sight (there's no other way to set it).
private struct MusicVolumeSlider: View {
    @State private var volume = Double(AVAudioSession.sharedInstance().outputVolume)
    @State private var controller: SystemVolumeController?
    @State private var observation: NSKeyValueObservation?

    var body: some View {
        Slider(value: Binding(get: { volume }, set: { value in
            volume = value
            controller?.setVolume(Float(value))
        }), in: 0...1)
        .tint(.white)
        .accessibilityLabel("Volume")
        .onAppear {
            controller = SystemVolumeController()
            observation = AVAudioSession.sharedInstance().observe(\.outputVolume) { session, _ in
                let level = Double(session.outputVolume)
                Task { @MainActor in volume = level }
            }
        }
        .onDisappear {
            observation = nil
            controller?.teardown()
            controller = nil
        }
    }
}

/// AirPlay, offering speakers first.
private struct MusicRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(DT.Color.accent)
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// Chromecast; picking one moves the music to it.
private struct MusicCastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let view = GCKUICastButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        view.tintColor = .white
        return view
    }
    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}
