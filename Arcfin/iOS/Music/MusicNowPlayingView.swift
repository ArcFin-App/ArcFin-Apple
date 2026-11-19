// SPDX-License-Identifier: AGPL-3.0-or-later

import AVKit
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

    /// The artwork across the whole width from the top of the sheet, fading into the
    /// backdrop, like a title's hero. Paused, it dims rather than shrinks: smaller, its edges
    /// would show.
    private func bigArtwork(_ song: MusicSong) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { MusicHeroImage(url: MusicAPI.artworkURL(song, width: 1200)) }
            .overlay { MusicArtworkVisualizer(bars: 32, spacing: 2, cornerRadius: 0).padding(.bottom, 56) }
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .clipped()
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
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.15), in: Circle())
        }
        .accessibilityLabel("More")
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
                MusicVolumeSlider().frame(height: 34)
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
    private var music: MusicPlayback { AppServices.music }

    var body: some View {
        Group {
            if let lyrics, !lyrics.lines.isEmpty {
                let songID = player.current?.id ?? ""
                let current = MusicLyricsSource.shared.lineIndex(lyrics, songID: songID, at: music.position)
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
                                        if let start = line.start { music.seek(to: start + MusicLyricsSource.shared.delay(songID)) }
                                    }
                                    .contextMenu {
                                        if line.start != nil {
                                            Button("Sing This Line Now", systemImage: "music.mic") {
                                                MusicLyricsSource.shared.align(songID, line: line, to: music.position)
                                            }
                                        }
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
                toggle("Autoplay", systemImage: "infinity", isOn: autoplay) { autoplay.toggle() }
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

/// The system volume slider, which also follows the volume buttons. It draws its track at
/// the top of its own frame, so it's made exactly as tall as the slider inside and centred
/// in a holder, which puts the track level with the speaker icons.
private struct MusicVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let holder = UIView()
        let slider = MPVolumeView()
        slider.tintColor = .white
        slider.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(slider)
        let inner = slider.subviews.first { $0 is UISlider }
        let height = inner.map(\.intrinsicContentSize.height).flatMap { $0 > 0 ? $0 : nil } ?? 31
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            slider.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
            slider.heightAnchor.constraint(equalToConstant: height),
        ])
        return holder
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
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
