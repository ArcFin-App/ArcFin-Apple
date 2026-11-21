// SPDX-License-Identifier: AGPL-3.0-or-later

import AVKit
import SwiftUI
import JellyfinAPI
import MediaEngine

/// Music's bar along the bottom of the window: the song, the transport, where it is, shuffle
/// and repeat, volume, AirPlay, and buttons for lyrics and the queue.
struct MusicPlayerBar: View {
    @State private var nowPlaying: MusicMacNowPlaying.Panel?
    private var player: MusicQueuePlayer { AppServices.music.player }

    var body: some View {
        if let song = player.current {
            HStack(spacing: DT.Spacing.lg) {
                songInfo(song)
                    .frame(width: 260, alignment: .leading)
                // Everything between the song and the controls, so the times and the format
                // badge have room beside the bar.
                VStack(spacing: DT.Spacing.xxs) {
                    transport
                    MusicBarScrubber()
                }
                .frame(maxWidth: .infinity)
                trailingControls(song)
                    .fixedSize()
            }
            .padding(.horizontal, DT.Spacing.md)
            .padding(.vertical, DT.Spacing.xs)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .sheet(item: $nowPlaying) { panel in
                MusicMacNowPlaying(panel: panel)
            }
        }
    }

    private func songInfo(_ song: MusicSong) -> some View {
        Button { nowPlaying = .queue } label: {
            HStack(spacing: DT.Spacing.sm) {
                MusicArtwork(url: MusicAPI.artworkURL(song, width: 120), cornerRadius: DT.Radius.xs)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: song.name)
                        .font(.callout.weight(.semibold))
                    if let artist = song.artistLine {
                        Text(verbatim: artist)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show Now Playing")
    }

    private var transport: some View {
        HStack(spacing: DT.Spacing.lg) {
            toggle(systemImage: "shuffle", isOn: player.queue.isShuffled, label: "Shuffle") {
                AppServices.music.setShuffled(!player.queue.isShuffled)
            }
            Button { AppServices.music.previous() } label: { Image(systemName: "backward.fill") }
                .accessibilityLabel("Previous")
            Button { AppServices.music.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Button { AppServices.music.next() } label: { Image(systemName: "forward.fill") }
                .accessibilityLabel("Next")
            toggle(systemImage: player.repeatMode == .one ? "repeat.1" : "repeat", isOn: player.repeatMode != .off,
                   label: "Repeat") {
                AppServices.music.cycleRepeatMode()
            }
        }
        .buttonStyle(.plain)
        .font(.body)
    }

    private func trailingControls(_ song: MusicSong) -> some View {
        HStack(spacing: DT.Spacing.sm) {
            MusicRatingButtons(song: song)
            MusicSharePlayButton(iconOnly: true)
            Button { nowPlaying = .lyrics } label: { Image(systemName: "quote.bubble") }
                .disabled(!MusicLyricsSource.shared.isAvailable(song))
                .accessibilityLabel("Lyrics")
                .help("Lyrics")
            Button { nowPlaying = .queue } label: { Image(systemName: "list.bullet") }
                .accessibilityLabel("Playing Next")
                .help("Playing Next")
            Menu {
                Section { MusicSleepTimerOptions() } header: { MusicSleepTimerStatus() }
            } label: {
                Image(systemName: AppServices.music.sleepTimer == nil ? "moon.zzz" : "moon.zzz.fill")
                    .foregroundStyle(AppServices.music.sleepTimer == nil ? Color.primary : DT.Color.accent)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sleep Timer")
            .accessibilityLabel("Sleep Timer")
            MusicMacRoutePicker()
                .frame(width: 22, height: 22)
                .accessibilityLabel("AirPlay")
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(value: Binding(get: { Double(player.volume) }, set: { player.volume = Float($0) }), in: 0...1)
                .controlSize(.mini)
                .frame(width: 90)
                .accessibilityLabel("Volume")
        }
        .buttonStyle(.plain)
    }

    private func toggle(systemImage: String, isOn: Bool, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(isOn ? DT.Color.accent : .secondary)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Where the song is, with the times and its format beside it. Its own view, so the position
/// ticking twice a second redraws only this, not the whole bar.
private struct MusicBarScrubber: View {
    @State private var scrubbing: Double?
    /// A held drag seeks when it's let go. A flick doesn't always say it's finished, so a
    /// value that stops changing seeks too: at once off a drag, after a pause in one.
    @State private var isDragging = false
    @State private var scrubSettle: Task<Void, Never>?
    private var player: MusicQueuePlayer { AppServices.music.player }

    private func finishScrub() {
        scrubSettle?.cancel()
        scrubSettle = nil
        guard let scrubbing else { return }
        AppServices.music.seek(to: scrubbing)
        self.scrubbing = nil
    }

    var body: some View {
        let duration = max(player.duration, 1)
        let position = scrubbing ?? player.position
        HStack(spacing: DT.Spacing.xs) {
            Text(verbatim: position.musicTime)
                .fixedSize()
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
            .controlSize(.mini)
            .tint(DT.Color.accent)
            .accessibilityLabel("Position")
            Text(verbatim: "-" + max(duration - position, 0).musicTime)
                .fixedSize()
            if let song = player.current { MusicQualityBadge(song: song, tint: .primary).fixedSize() }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

/// The song large, and beside it Playing Next or the lyrics.
struct MusicMacNowPlaying: View {
    enum Panel: String, Identifiable {
        case queue, lyrics
        var id: String { rawValue }
    }

    @State var panel: Panel
    @State private var lyrics: Lyrics?
    /// The lyrics request has come back, with or without them.
    @State private var lyricsLoaded = false
    @State private var lyricsAttempt = 0
    @Environment(\.dismiss) private var dismiss
    private var player: MusicQueuePlayer { AppServices.music.player }

    var body: some View {
        Group {
            if let song = player.current {
                HStack(alignment: .top, spacing: DT.Spacing.xl) {
                    VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                        MusicArtwork(url: MusicAPI.artworkURL(song, width: 800), cornerRadius: DT.Radius.md)
                            .overlay { MusicArtworkVisualizer(bars: 28, spacing: 2, cornerRadius: DT.Radius.md) }
                            .frame(width: 300, height: 300)
                            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                        Text(verbatim: song.name)
                            .font(.title2.weight(.bold))
                        if let artist = song.artistLine {
                            Text(verbatim: artist).font(.title3).foregroundStyle(.secondary)
                        }
                        if let album = song.albumName {
                            Text(verbatim: album).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 300)
                    VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                        Picker("Show", selection: $panel) {
                            Text("Playing Next").tag(Panel.queue)
                            Text("Lyrics").tag(Panel.lyrics)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        switch panel {
                        case .queue: queue
                        case .lyrics: MusicMacLyrics(song: song, lyrics: lyrics, isLoaded: lyricsLoaded) { lyricsAttempt += 1 }
                        }
                    }
                }
                .padding(DT.Spacing.xl)
                .task(id: "\(song.id) \(lyricsAttempt)") {
                    lyrics = nil
                    lyricsLoaded = false
                    lyrics = await MusicLyricsSource.shared.lyrics(for: song)
                    lyricsLoaded = true
                }
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "music.note")
            }
        }
        .frame(width: 820, height: 520)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private var queue: some View {
        List {
            // Earlier in this queue: double-click one to go back to it.
            if !player.queue.history.isEmpty {
                Section("Played") {
                    ForEach(Array(player.queue.history.suffix(20))) { entry in
                        HStack(spacing: DT.Spacing.sm) {
                            MusicArtwork(url: MusicAPI.artworkURL(entry.track, width: 100), cornerRadius: DT.Radius.xs)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: entry.track.name)
                                Text(verbatim: entry.track.artistLine ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { AppServices.music.jump(to: entry.id) }
                        .contextMenu { Button("Play", systemImage: "play") { AppServices.music.jump(to: entry.id) } }
                    }
                }
            }
            ForEach(Array(player.queue.upNext)) { entry in
                HStack(spacing: DT.Spacing.sm) {
                    MusicArtwork(url: MusicAPI.artworkURL(entry.track, width: 100), cornerRadius: DT.Radius.xs)
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: entry.track.name)
                        Text(verbatim: entry.track.artistLine ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer()
                    if let duration = entry.track.duration {
                        Text(verbatim: duration.musicTime).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { AppServices.music.jump(to: entry.id) }
                .contextMenu {
                    Button("Play", systemImage: "play") { AppServices.music.jump(to: entry.id) }
                    Button("Remove", systemImage: "minus.circle", role: .destructive) { AppServices.music.remove(entry.id) }
                }
            }
            .onMove { from, to in
                guard let source = from.first else { return }
                AppServices.music.moveUpNext(from: source, to: to > source ? to - 1 : to)
            }
        }
        .overlay {
            if player.queue.upNext.isEmpty {
                ContentUnavailableView("Nothing Up Next", systemImage: "list.bullet")
            }
        }
    }
}

/// The words, the line being sung picked out. Its own view, so following the song redraws only
/// this, not the whole sheet.
private struct MusicMacLyrics: View {
    let song: MusicSong
    let lyrics: Lyrics?
    let isLoaded: Bool
    let retry: () -> Void
    private var player: MusicQueuePlayer { AppServices.music.player }

    var body: some View {
        if let lyrics, !lyrics.lines.isEmpty {
            let current = MusicLyricsSource.shared.lineIndex(lyrics, songID: song.id, at: player.position)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                            Text(verbatim: line.text)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(lyrics.isSynced && index != current ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                                .onTapGesture { if let start = line.start { AppServices.music.seek(to: start + MusicLyricsSource.shared.delay(song.id)) } }
                                .contextMenu {
                                    if line.start != nil {
                                        Button("Sing This Line Now", systemImage: "music.mic") {
                                            MusicLyricsSource.shared.align(song.id, line: line, to: player.position)
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.vertical, DT.Spacing.md)
                }
                .onChange(of: current) { _, line in
                    guard let line else { return }
                    withAnimation(DT.Animation.standard) { proxy.scrollTo(line, anchor: .center) }
                }
                .overlay(alignment: .topTrailing) {
                    if lyrics.isSynced {
                        MusicLyricsTimingMenu(songID: song.id).fixedSize()
                    }
                }
            }
        } else if MusicLyricsSource.shared.isAvailable(song), !isLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if MusicLyricsSource.shared.isAvailable(song) {
            // The song has lyrics, but they didn't come.
            ContentUnavailableView {
                Label("Lyrics Unavailable", systemImage: "quote.bubble")
            } actions: {
                Button("Try Again", action: retry)
            }
        } else {
            ContentUnavailableView("No Lyrics", systemImage: "quote.bubble")
        }
    }
}

/// AirPlay, offering speakers first.
private struct MusicMacRoutePicker: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.isRoutePickerButtonBordered = false
        return view
    }
    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
