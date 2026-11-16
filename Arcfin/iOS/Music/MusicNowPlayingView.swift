// SPDX-License-Identifier: AGPL-3.0-or-later

import AVKit
import MediaPlayer
import SwiftUI
import JellyfinAPI
import MediaEngine

/// The bar above the tabs while music plays: the cover, the song, play or pause and next.
/// Tapping it opens Now Playing.
struct MusicMiniPlayer: View {
    @Binding var isExpanded: Bool
    private var player: MusicQueuePlayer { AppServices.music.player }

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
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.next() } label: {
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
            .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { drag in
                if drag.translation.height < -20 { isExpanded = true }
            })
            .accessibilityElement(children: .contain)
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
    @State private var lyrics: Lyrics?
    private var player: MusicQueuePlayer { AppServices.music.player }

    var body: some View {
        Group {
            if let song = player.current {
                VStack(spacing: DT.Spacing.lg) {
                    grabber
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

    private func bigArtwork(_ song: MusicSong) -> some View {
        MusicArtwork(url: MusicAPI.artworkURL(song, width: 1000), cornerRadius: DT.Radius.md)
            .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
            .scaleEffect(player.isPlaying ? 1 : 0.82)
            .animation(.spring(response: 0.45, dampingFraction: 0.7), value: player.isPlaying)
            .frame(maxHeight: .infinity)
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
            songMenu(song)
        }
    }

    private func songMenu(_ song: MusicSong) -> some View {
        Menu {
            Button("Create Station", systemImage: "dot.radiowaves.left.and.right") {
                Task { await MusicActions.instantMix(from: song.id) }
            }
            MusicFavoriteButton(id: song.id, server: song.isFavorite)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.15), in: Circle())
        }
        .accessibilityLabel("More")
    }

    private var scrubber: some View {
        let duration = max(player.duration, 1)
        let position = scrubbing ?? player.position
        return VStack(spacing: DT.Spacing.xxs) {
            Slider(value: Binding(get: { position }, set: { scrubbing = $0 }), in: 0...duration) { editing in
                if !editing, let scrubbing {
                    player.seek(to: scrubbing)
                    self.scrubbing = nil
                }
            }
            .tint(.white)
            .accessibilityLabel("Position")
            .accessibilityValue(Text(verbatim: position.musicTime))
            HStack {
                Text(verbatim: position.musicTime)
                Spacer()
                Text(verbatim: "-" + max(duration - position, 0).musicTime)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
            .accessibilityHidden(true)
        }
    }

    private var transport: some View {
        HStack {
            Spacer()
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 30))
            }
            .accessibilityLabel("Previous")
            Spacer()
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 44))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 64, height: 64)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 30))
            }
            .accessibilityLabel("Next")
            Spacer()
        }
        .buttonStyle(.plain)
    }

    private var volume: some View {
        HStack(spacing: DT.Spacing.sm) {
            Image(systemName: "speaker.fill").accessibilityHidden(true)
            MusicVolumeSlider().frame(height: 34)
            Image(systemName: "speaker.wave.3.fill").accessibilityHidden(true)
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.6))
    }

    private func bottomBar(_ song: MusicSong) -> some View {
        HStack {
            Spacer()
            panelButton(.lyrics, systemImage: "quote.bubble", label: "Lyrics")
                .disabled(!song.hasLyrics)
            Spacer()
            MusicRoutePicker()
                .frame(width: 44, height: 44)
                .accessibilityLabel("AirPlay")
            Spacer()
            panelButton(.queue, systemImage: "list.bullet", label: "Playing Next")
            Spacer()
        }
        .font(.title3)
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
        guard song.hasLyrics else {
            if panel == .lyrics { panel = .artwork }
            return
        }
        lyrics = try? await MusicAPI.call { try await $0.getLyrics(credential: $1, authHeader: $2, trackId: song.id) } ?? nil
    }
}

/// The cover blown up and blurred behind everything, darkened so white text reads on it.
private struct MusicArtworkBackdrop: View {
    let url: URL?

    var body: some View {
        Color.black
            .overlay {
                CachedAsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    }
                }
                .blur(radius: 60)
                .scaleEffect(1.4)
            }
            .overlay(.black.opacity(0.45))
            .clipped()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The words, following the song when the server has times for them; tap a line to go there.
private struct MusicLyricsPanel: View {
    let lyrics: Lyrics?
    private var player: MusicQueuePlayer { AppServices.music.player }

    var body: some View {
        Group {
            if let lyrics, !lyrics.lines.isEmpty {
                let current = lyrics.isSynced ? lyrics.lineIndex(at: player.position) : nil
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: DT.Spacing.md) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                                Text(verbatim: line.text)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.white.opacity(lyrics.isSynced && index != current ? 0.35 : 1))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                                    .onTapGesture {
                                        if let start = line.start { player.seek(to: start) }
                                    }
                            }
                        }
                        .padding(.vertical, DT.Spacing.xl)
                    }
                    .onChange(of: current) { _, line in
                        guard let line else { return }
                        withAnimation(DT.Animation.standard) { proxy.scrollTo(line, anchor: .center) }
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
    private var player: MusicQueuePlayer { AppServices.music.player }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            HStack(spacing: DT.Spacing.sm) {
                toggle("Shuffle", systemImage: "shuffle", isOn: player.queue.isShuffled) {
                    player.setShuffled(!player.queue.isShuffled)
                }
                toggle("Repeat", systemImage: player.repeatMode == .one ? "repeat.1" : "repeat",
                       isOn: player.repeatMode != .off) {
                    player.repeatMode = switch player.repeatMode {
                    case .off: .all
                    case .all: .one
                    case .one: .off
                    }
                }
            }
            HStack {
                Text("Playing Next").font(.headline)
                Spacer()
                if !player.queue.upNext.isEmpty {
                    Button("Clear") { player.clearUpNext() }
                        .font(.subheadline.weight(.semibold))
                }
            }
            List {
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
                    .onTapGesture { player.jump(to: entry.id) }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.white.opacity(0.15))
                }
                .onMove { from, to in
                    guard let source = from.first else { return }
                    player.moveUpNext(from: source, to: to > source ? to - 1 : to)
                }
                .onDelete { offsets in
                    let entries = Array(player.queue.upNext)
                    offsets.map { entries[$0].id }.forEach(player.remove)
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

/// The system volume slider, which also follows the volume buttons.
private struct MusicVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.tintColor = .white
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
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
