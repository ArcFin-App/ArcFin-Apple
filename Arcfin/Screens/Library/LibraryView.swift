// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AVKit
import JellyfinAPI
import SeerrAPI
import AuthCore
import MediaEngine
import Persistence
import SwiftVLC
import Telemetry
import os

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Library screen

struct LibraryView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var showDocPicker = false
    @State private var pickedURL: URL?
    @State private var navigateToLocalPlayer = false
    @State private var navigateToDownloadsDeepLink = false
    @State private var searchQuery = ""
    @State private var openedLibrary: JellyfinLibrary?
#if os(macOS)
    @FocusState private var isSearchFocused: Bool

    /// Find… (⌘F) can come before Browse has ever been open, so it's left as a flag.
    private func focusSearchIfPending() {
        guard UserDefaults.standard.bool(forKey: "arcfin.pendingFindFocus") else { return }
        UserDefaults.standard.removeObject(forKey: "arcfin.pendingFindFocus")
        isSearchFocused = true
    }
#endif

    private var gridColumns: [GridItem] {
#if os(macOS)
        // Fixed 2-up stretches library cards absurdly wide on a resizable Mac window —
        // adaptive reflows into more columns as it grows instead.
        [GridItem(.adaptive(minimum: 220), spacing: 12)]
#else
        if isWide {
            return [GridItem(.adaptive(minimum: 240), spacing: 12)]
        }
        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
#endif
    }
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isWide: Bool { horizontalSizeClass == .regular }
#else
    private let isWide = false
#endif

    var body: some View {
        NavigationStack {
            Group {
                if searchQuery.isEmpty {
                    browseContent
                } else {
                    SearchView(query: $searchQuery)
                }
            }
            .screenBackground()
            .navigationTitle("Browse")
            .searchable(text: $searchQuery, prompt: "Movies, shows, people…")
#if os(macOS)
            .searchFocused($isSearchFocused)
#endif
#if !os(macOS) && !os(tvOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
#endif
            .navigationDestination(for: JellyfinLibrary.self) { library in
                LibraryDetailView(library: library)
            }
            // On the Mac a tile's NavigationLink(value:) can't find the destination above.
            .navigationDestination(item: $openedLibrary) { library in
                LibraryDetailView(library: library)
            }
            .navigationDestination(for: LibraryNavTarget.self) { target in
                switch target {
                case .media(let item):   MediaDetailView(item: item)
                case .collection(let item):
                    CollectionDetailView(collection: item)
                case .playlist(let item):
                    LibraryDetailView(playlistItem: item)
                }
            }
            .navigationDestination(for: MediaItem.self) { item in
                MediaDetailView(item: item)
            }
#if canImport(UIKit) && !os(tvOS)
            .sheet(isPresented: $showDocPicker) {
                DocumentPickerView { url in
                    pickedURL = url
                    navigateToLocalPlayer = true
                }
            }
#elseif os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .arcfinOpenFile)) { _ in
                showDocPicker = true
                // After the tab bar's own handler, which buffers it for an unmounted Browse.
                Task { UserDefaults.standard.removeObject(forKey: "arcfin.pendingOpenFile") }
            }
            // File › Open Video File… while Browse wasn't on screen yet.
            .onAppear {
                if UserDefaults.standard.bool(forKey: "arcfin.pendingOpenFile") {
                    UserDefaults.standard.removeObject(forKey: "arcfin.pendingOpenFile")
                    showDocPicker = true
                }
            }
            .fileImporter(isPresented: $showDocPicker, allowedContentTypes: UTType.playableVideo) { result in
                guard case .success(let url) = result else { return }
                pickedURL = url
                navigateToLocalPlayer = true
            }
#endif
            .navigationDestination(isPresented: $navigateToLocalPlayer) {
                if let url = pickedURL {
#if !os(macOS)
                    LocalPlayerView(url: url)
                        .toolbar(.hidden, for: .tabBar)
#else
                    LocalPlayerView(url: url)
#endif
                }
            }
            #if !os(tvOS)
            .navigationDestination(isPresented: $navigateToDownloadsDeepLink) {
                DownloadsView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .arcfinSearch)) { note in
                if let term = note.userInfo?["term"] as? String { searchQuery = term }
                #if os(macOS)
                focusSearchIfPending()
                #endif
            }
            .onAppear {
                #if os(macOS)
                focusSearchIfPending()
                #endif
                if let term = UserDefaults.standard.string(forKey: "arcfin.pendingSearch") {
                    UserDefaults.standard.removeObject(forKey: "arcfin.pendingSearch")
                    searchQuery = term
                }
                if UserDefaults.standard.bool(forKey: "arcfin.pendingShowDownloads") {
                    UserDefaults.standard.removeObject(forKey: "arcfin.pendingShowDownloads")
                    navigateToDownloadsDeepLink = true
                }
            }
            // arcfin://downloads — the download Live Activity or the Downloads control.
            .onReceive(NotificationCenter.default.publisher(for: .arcfinShowDownloads)) { _ in
                UserDefaults.standard.removeObject(forKey: "arcfin.pendingShowDownloads")
                searchQuery = ""
                navigateToDownloadsDeepLink = true
            }
            #endif
        }
    }

    private var browseContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                // ── Your Libraries ──────────────────────────────────────
                if !supportedLibraries.isEmpty {
                    librariesSection
                }

                // ── Your Requests ───────────────────────────────────────
                if seerrRepo.isConfigured {
                    requestsSection
                }

                // ── Downloads ───────────────────────────────────────────
                #if !os(tvOS)
                jellyfinDownloadsSection
                #endif

                // ── On This Device ──────────────────────────────────────
                onDeviceSection
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Libraries section

    /// Live TV and Music aren't playable yet (no live-TV tuner support, no music player
    /// UI) — hide them from the library list rather than showing a section that just
    /// leads to a dead end.
    private var supportedLibraries: [JellyfinLibrary] {
        let hidden = LibraryVisibility.hiddenIDs
        let libraries = mediaRepo.libraries.filter { $0.collectionType != .livetv && $0.collectionType != .music && !hidden.contains($0.id) }
        #if os(tvOS)
        return libraries
        #else
        // The server only lists a Playlists library once a playlist exists; the tile is
        // always there so the first one can be made from it.
        guard !libraries.isEmpty, !libraries.contains(where: { $0.collectionType == .playlists }) else { return libraries }
        return libraries + [JellyfinLibrary(id: LibraryDetailModel.allPlaylistsID, name: "Playlists", collectionType: .playlists)]
        #endif
    }

    private var librariesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Your Libraries")
#if os(tvOS)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Spacing.shelfGap) {
                    ForEach(supportedLibraries) { library in
                        NavigationLink(value: library) {
                            TVLibraryCard(library: library)
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .focusSection()
            }
            .shelfScrollButtons()
            .padding(.horizontal, -DT.Spacing.pagePad)
#else
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(supportedLibraries) { library in
                    libraryLink(library) {
                        LibraryCard(library: library, imageURL: mediaRepo.libraryBackdropURL(for: library))
                    }
                    .buttonStyle(.plain)
                }
            }
#endif
        }
    }

    @ViewBuilder
    private func libraryLink<Label: View>(_ library: JellyfinLibrary, @ViewBuilder label: () -> Label) -> some View {
        #if os(macOS)
        Button { openedLibrary = library } label: { label() }
        #else
        // A library opened from a binding sits above the path, so titles pushed onto the
        // path from inside it would land underneath.
        NavigationLink(value: library) { label() }
        #endif
    }

    // MARK: - Your Requests section

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Your Requests")
            NavigationLink {
                SeerrRequestsListView(filter: nil, title: "Requests")
            } label: {
                RequestsCard()
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 220)
        }
    }

    // MARK: - Jellyfin downloads section

    #if !os(tvOS)
    @ViewBuilder
    private var jellyfinDownloadsSection: some View {
        NavigationLink {
            DownloadsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(.title3))
                    .foregroundStyle(DT.Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloads")
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("Movies and episodes saved for offline playback")
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.footnote))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.card)
                    .fill(DT.Color.backgroundSecondary)
                    .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - On this device section

    private var onDeviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("On This Device")

            Button {
                showDocPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(.title3))
                        .foregroundStyle(DT.Color.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Browse Files")
                            .font(.system(.subheadline, design: .default, weight: .semibold))
                            .foregroundStyle(DT.Color.textPrimary)
                        Text("Pick a video file from Files app")
                            .font(.system(.caption))
                            .foregroundStyle(DT.Color.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .fill(DT.Color.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: DT.Radius.card)
                                .stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DT.Font.cardTitle)
            .foregroundStyle(DT.Color.textPrimary)
            .tracking(-0.2)
            .accessibilityAddTraits(.isHeader)
    }

}

// MARK: - tvOS landscape library card

#if os(tvOS)
private struct TVLibraryCard: View {
    let library: JellyfinLibrary
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .fill(LinearGradient(
                    colors: [
                        Color(hex: library.collectionType.accentHex).opacity(0.3),
                        DT.Color.backgroundSecondary,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: 3)
                )

            HStack(spacing: 20) {
                Image(systemName: library.collectionType.systemIcon)
                    .scaledFont(size: 40, weight: .light)
                    .foregroundStyle(Color(hex: library.collectionType.accentHex))

                Text(library.name)
                    .scaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(isFocused ? DT.Color.accent : DT.Color.textPrimary)
                    .lineLimit(2)
                    .animation(DT.Animation.fast, value: isFocused)
            }
            .padding(24)
        }
        .frame(width: DT.Size.posterCard.width, height: DT.Size.posterCard.height)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .shadow(color: isFocused ? DT.Color.accent.opacity(0.4) : .clear, radius: 10)
        .animation(DT.Animation.motion(.spring(response: 0.2, dampingFraction: 0.75)), value: isFocused)
        .contentShape(Rectangle())
    }
}
#endif

// MARK: - Local player

/// Plays any file the user picks via Files (the "On This Device" section) — always VLC,
/// same reasoning as OfflinePlayerView: an arbitrary local file can be any container/codec,
/// and VLC opens it natively without AVFoundation's mkv/HEVC-tag limitations. Simpler than
/// OfflinePlayerView by design: no Jellyfin metadata exists for a raw picked file, so no
/// trickplay/skip-intro/resume-position — just playback, subtitle tracks VLC finds in the
/// file itself, and the same fill-screen/rotate/PiP affordances the other players have.
struct LocalPlayerView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var player = VLCEnginePlayer()
    @State private var isControlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isScrubbing = false
    @State private var scrubTicks: Double = 0
    @State private var showTrackMenu = false
    #if canImport(UIKit) && !os(tvOS)
    @State private var vlcPipController: SwiftVLC.PiPController?
    #endif
    #if !os(tvOS)
    @State private var isFillScreen = false
    #endif

    var body: some View {
        bodyContent.alwaysDarkPlayer()
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if canImport(UIKit) && !os(tvOS)
            GeometryReader { proxy in
                // See PlayerView/OfflinePlayerView's own comment on why hit-testing is
                // disabled here — PiPVideoView's native drawable is itself interactive and
                // would otherwise swallow the tap before the toggleControls gesture sees it.
                ZStack {
                    PiPVideoView(player.vlcPlayer, controller: $vlcPipController,
                                 startsAutomaticallyFromInline: UserDefaults.standard.bool(forKey: "autoPictureInPicture"),
                                 managesAudioSession: false)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }
            }
            .ignoresSafeArea()
            #elseif os(macOS)
            // No PiPVideoView on macOS (it's built on UIKit) — SwiftVLC's plain VideoView
            // is the cross-platform drawable surface and is all a windowed Mac player needs.
            SwiftVLC.VideoView(player.vlcPlayer)
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }
            #endif

            if player.status == .idle || player.status == .loading || player.isBuffering {
                ProgressView().tint(.white).scaleEffect(1.4)
            }

            if isControlsVisible {
                controlsOverlay.transition(.opacity)
            }
        }
        #if canImport(UIKit) && !os(tvOS)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        #endif
        .keepsScreenAwake(status: player.status)
        .task {
            _ = url.startAccessingSecurityScopedResource()
            try? await player.load(url: url, startPositionTicks: 0)
            await player.play()
        }
        .onDisappear {
            Task { await player.stop() }
            url.stopAccessingSecurityScopedResource()
            #if canImport(UIKit) && !os(tvOS)
            resetPlayerOrientation()
            #endif
        }
        .onChange(of: player.status) { _, status in
            if status == .playing { scheduleAutoHide() }
            if status == .ended { closeRotatedPlayer { dismiss() } }
        }
        #if !os(tvOS)
        .onChange(of: isFillScreen) { _, newValue in
            player.vlcPlayer.aspectRatio = newValue ? .fill : .default
        }
        #endif
        .sheet(isPresented: $showTrackMenu) {
            trackSheet
        }
#if !os(macOS) && !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
#endif
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            bottomBar
        }
        .background(
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.7),
                    .init(color: .black.opacity(0.65), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button { closeRotatedPlayer { dismiss() } } label: {
                Image(systemName: "chevron.down")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            #if canImport(UIKit) && !os(tvOS)
            AirPlayButton().frame(width: 44, height: 44)
            if vlcPipController != nil {
                Button { vlcPipController?.toggle() } label: {
                    Image(systemName: "pip.enter")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Picture in Picture")
            }
            Button { togglePlayerOrientation() } label: {
                Image(systemName: "rotate.right")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Rotate")
            #endif
            #if !os(tvOS)
            Button { isFillScreen.toggle() } label: {
                Image(systemName: isFillScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(isFillScreen ? DT.Color.accent : .white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isFillScreen ? "Fit to screen" : "Fill screen")
            #endif
            if !player.availableSubtitleTracks.isEmpty {
                Button { showTrackMenu = true } label: {
                    Image(systemName: "captions.bubble")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Subtitles and audio")
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            scrubber
            HStack {
                Text(timeLabel(ticks: isScrubbing ? Int64(scrubTicks) : player.positionTicks))
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                HStack(spacing: 28) {
                    Button { seek(by: -10) } label: {
                        Image(systemName: "gobackward.10").font(.system(.title3)).foregroundStyle(.white)
                    }
                    .accessibilityLabel("Skip back 10 seconds")
                    Button { togglePlayPause() } label: {
                        Image(systemName: player.status == .playing ? "pause.fill" : "play.fill")
                            .font(.system(.largeTitle))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(player.status == .playing ? "Pause" : "Play")
                    Button { seek(by: 10) } label: {
                        Image(systemName: "goforward.10").font(.system(.title3)).foregroundStyle(.white)
                    }
                    .accessibilityLabel("Skip forward 10 seconds")
                }
                Spacer()
                Text(remainingLabel)
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, 24)
    }

    private var scrubber: some View {
        GeometryReader { proxy in
            let duration = max(player.durationTicks, 1)
            let fraction = Double(isScrubbing ? Int64(scrubTicks) : player.positionTicks) / Double(duration)
            let thumbX = proxy.size.width * min(max(fraction, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                Capsule().fill(DT.Color.accent).frame(width: thumbX, height: 4)
                Circle().fill(.white)
                    .frame(width: isScrubbing ? 16 : 10, height: isScrubbing ? 16 : 10)
                    .offset(x: thumbX - (isScrubbing ? 8 : 5))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            #if !os(tvOS)
            // A plain DragGesture works with a mouse drag on macOS same as a touch drag
            // on iOS — no UIKit dependency, so this isn't restricted to canImport(UIKit).
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        hideControlsTask?.cancel()
                        let fraction = min(max(value.location.x / proxy.size.width, 0), 1)
                        scrubTicks = Double(player.durationTicks) * fraction
                    }
                    .onEnded { _ in
                        Task {
                            await player.seek(to: Int64(scrubTicks))
                            isScrubbing = false
                            scheduleAutoHide()
                        }
                    }
            )
            #endif
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(timeLabel(ticks: isScrubbing ? Int64(scrubTicks) : player.positionTicks)) of \(timeLabel(ticks: player.durationTicks))")
        .accessibilityAdjustableAction { direction in
            seek(by: direction == .increment ? 10 : -10)
        }
    }

    private var trackSheet: some View {
        NavigationStack {
            List {
                Button {
                    Task { await player.setSubtitleTrack(index: nil) }
                    showTrackMenu = false
                } label: {
                    HStack {
                        Text("Off")
                        Spacer()
                        if player.selectedSubtitleTrackIndex == nil { Image(systemName: "checkmark") }
                    }
                }
                ForEach(player.availableSubtitleTracks) { track in
                    Button {
                        Task { await player.setSubtitleTrack(index: track.id) }
                        showTrackMenu = false
                    } label: {
                        HStack {
                            Text(track.displayName)
                            Spacer()
                            if player.selectedSubtitleTrackIndex == track.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            .navigationTitle("Subtitles")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium])
    }

    private func togglePlayPause() {
        Task { if player.status == .playing { await player.pause() } else { await player.play() } }
        toggleControlsVisibilityOnAction()
    }

    private func seek(by seconds: Int) {
        let newTicks = max(0, player.positionTicks + Int64(seconds) * 10_000_000)
        Task { await player.seek(to: min(newTicks, player.durationTicks)) }
        toggleControlsVisibilityOnAction()
    }

    private func toggleControls() {
        withAnimation(DT.Animation.fast) { isControlsVisible.toggle() }
        if isControlsVisible { scheduleAutoHide() }
    }

    private func toggleControlsVisibilityOnAction() {
        if !isControlsVisible { withAnimation(DT.Animation.fast) { isControlsVisible = true } }
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, player.status == .playing else { return }
            withAnimation(DT.Animation.fast) { isControlsVisible = false }
        }
    }

    private var remainingLabel: String {
        let remaining = max(player.durationTicks - player.positionTicks, 0)
        return "-" + timeLabel(ticks: remaining)
    }

    private func timeLabel(ticks: Int64) -> String {
        let totalSeconds = Int(Double(ticks) / 10_000_000)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Document picker (UIKit bridge)

#if canImport(UIKit) && !os(tvOS)
// Not private — reused by ContentView's offline-mode flow for the same "On This Device"
// file picker outside of Browse.
struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // VLC opens containers AVFoundation never could — broadened past the old
        // AVFoundation-only list (.movie/.video/.mpeg4Movie/.quickTimeMovie) to include mkv.
        let types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .avi, .matroska]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // Access is started/stopped as a matched pair inside LocalPlayerView itself
            // (task/onDisappear), not here — starting it in both places would leave one
            // extra unmatched start once LocalPlayerView's single stop call runs.
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

import UniformTypeIdentifiers

private extension UTType {
    static let avi = UTType(filenameExtension: "avi") ?? .movie
    static let matroska = UTType(filenameExtension: "mkv") ?? .movie
}
#endif

#if os(macOS)
import UniformTypeIdentifiers

extension UTType {
    /// What the Mac's file picker offers for local playback: VLC opens containers AVFoundation can't, mkv and avi among them.
    static let playableVideo: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        + ["avi", "mkv"].compactMap { UTType(filenameExtension: $0) }
}
#endif
