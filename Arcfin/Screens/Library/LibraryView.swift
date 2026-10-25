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
        return libraries + [JellyfinLibrary(id: LibraryDetailView.allPlaylistsID, name: "Playlists", collectionType: .playlists)]
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
                    NavigationLink(value: library) {
                        LibraryCard(library: library, imageURL: mediaRepo.libraryBackdropURL(for: library))
                    }
                    .buttonStyle(.plain)
                }
            }
#endif
        }
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

// MARK: - Library card

private struct LibraryCard: View {
    let library: JellyfinLibrary
    let imageURL: URL?

    @State private var hovered = false

    var body: some View {
        ZStack {
            background

            Rectangle()
                .fill(.black.opacity(0.35))

            VStack(spacing: 10) {
                Image(systemName: library.collectionType.systemIcon)
                    .font(.system(.title, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6)

                Text(library.name)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 6)
            }
            .padding(16)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(hovered ? DT.Color.accent.opacity(0.5) : Color(hex: library.collectionType.accentHex).opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .scaleEffect(hovered ? 1.02 : 1)
        .animation(DT.Animation.fast, value: hovered)
        #if !os(tvOS)
        .onHover { hovered = $0 }
        #endif
    }

    @ViewBuilder
    private var background: some View {
        if let imageURL {
            CachedAsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill().blur(radius: 3)
                default: gradientFallback
                }
            }
            .clipped()
        } else {
            gradientFallback
        }
    }

    private var gradientFallback: some View {
        LinearGradient(
            colors: [
                Color(hex: library.collectionType.accentHex).opacity(0.25),
                DT.Color.backgroundSecondary,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Same tile treatment as LibraryCard (icon + centered label, gradient background, height
/// 110) so "Your Requests" reads as one more tile alongside the library ones, not a
/// differently-styled row.
private struct RequestsCard: View {
    @State private var hovered = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DT.Color.accent.opacity(0.25), DT.Color.backgroundSecondary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            VStack(spacing: 10) {
                Image(systemName: "text.badge.checkmark")
                    .font(.system(.title, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6)

                Text("Requests")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.6), radius: 6)
            }
            .padding(16)
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(hovered ? DT.Color.accent.opacity(0.5) : DT.Color.accent.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .scaleEffect(hovered ? 1.02 : 1)
        .animation(DT.Animation.fast, value: hovered)
        #if !os(tvOS)
        .onHover { hovered = $0 }
        #endif
    }
}

// MARK: - Library grid item card

private struct LibraryItemCard: View {
    let imageURL: URL?
    let title: String
    let year: String?

    @State private var hovered = false

    var body: some View {
        // The card's shape comes from the grid, not the image: a square cover (a playlist's)
        // filled to the image's own size made the card wider than its column.
        Color.clear
            .aspectRatio(2/3, contentMode: .fit)
            .overlay {
                if let imageURL {
                    CachedAsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color(DT.Color.backgroundSecondary)
                        }
                    }
                } else {
                    DT.Color.backgroundSecondary
                }
            }
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let year {
                            Text(year)
                                .font(.system(.caption2))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(2)
                        }
                    }
                    .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(hovered ? DT.Color.accent.opacity(0.4) : DT.Color.textPrimary.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(hovered ? 1.03 : 1)
        .shadow(color: hovered ? DT.Color.accent.opacity(0.2) : .clear, radius: hovered ? 12 : 0)
        .animation(DT.Animation.fast, value: hovered)
        #if !os(tvOS)
        .onHover { hovered = $0 }
        #endif
        // Without this, a NavigationLink wrapping this ZStack has no explicit click
        // target, which AppKit's hit-testing is stricter about than UIKit's.
        .contentShape(Rectangle())
    }
}

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

// MARK: - Library detail

enum LibraryNavTarget: Hashable {
    case playlist(MediaItem)     // a playlist in the Playlists library — opens its titles
    case media(MediaItem)
    case collection(MediaItem)   // BoxSet item — routed to collection detail
}

enum LibraryWatchedFilter: String, CaseIterable, Identifiable {
    case all = "All", unwatched = "Unwatched", watched = "Watched"
    var id: String { rawValue }
}

/// Filters beyond genre/year/watched/favorites: content rating and a minimum community
/// score, kept as one value so it travels through the filter sheet as a single binding.
struct LibraryExtraFilters: Equatable {
    var officialRatings: Set<String> = []
    var minRating: Double?
    /// Jellyfin's `Genres` filter is "any of"; this narrows to titles carrying every selected genre.
    var matchAllGenres = false
    var tags: Set<String> = []
    var quality: LibraryQualityFilter = .any
    var hasSubtitles = false

    var isActive: Bool {
        !officialRatings.isEmpty || minRating != nil || !tags.isEmpty || quality != .any || hasSubtitles
    }

    private static let maturityOrder = [
        "G", "TV-Y", "TV-G", "TV-Y7", "PG", "TV-PG", "PG-13", "TV-14", "R", "TV-MA", "NC-17",
    ]

    /// Least to most mature; ratings outside the known scale sort last by name.
    static func ordered(_ ratings: [String]) -> [String] {
        ratings.sorted { lhs, rhs in
            let l = maturityOrder.firstIndex(of: lhs) ?? .max
            let r = maturityOrder.firstIndex(of: rhs) ?? .max
            return l == r ? lhs < rhs : l < r
        }
    }

    /// Slider position for a selection: `ordered.count` means no limit.
    static func ratingStep(_ selected: Set<String>, in ordered: [String]) -> Int {
        ordered.lastIndex { selected.contains($0) } ?? ordered.count
    }

    static func ratings(upToStep step: Int, in ordered: [String]) -> Set<String> {
        step >= ordered.count ? [] : Set(ordered.prefix(step + 1))
    }
}

enum LibraryQualityFilter: String, CaseIterable, Identifiable {
    case any = "Any", hd = "HD", uhd = "4K"
    var id: String { rawValue }
}

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case nameAsc = "Name (A–Z)"
    case nameDesc = "Name (Z–A)"
    case dateAddedDesc = "Recently Added"
    case releaseDateDesc = "Release Date (Newest)"
    case releaseDateAsc = "Release Date (Oldest)"
    case ratingDesc = "Rating (Highest)"
    case genreAsc = "Genre"
    /// The order the playlist was put together in; only offered for playlists.
    case playlistOrder = "Playlist Order"

    var id: String { rawValue }

    static let standard = allCases.filter { $0 != .playlistOrder }

    var sortBy: String {
        switch self {
        case .nameAsc, .nameDesc: return "SortName"
        case .dateAddedDesc: return "DateCreated"
        case .releaseDateDesc, .releaseDateAsc: return "PremiereDate"
        case .ratingDesc: return "CommunityRating"
        case .genreAsc: return "Genres"
        case .playlistOrder: return "SortName"
        }
    }

    var sortOrder: String {
        switch self {
        case .nameAsc, .releaseDateAsc: return "Ascending"
        case .nameDesc, .dateAddedDesc, .releaseDateDesc, .ratingDesc: return "Descending"
        case .genreAsc, .playlistOrder: return "Ascending"
        }
    }
}

enum LibraryGridDensity: String, CaseIterable, Identifiable {
    case compact, normal, comfortable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return "Compact"
        case .normal: return "Normal"
        case .comfortable: return "Comfortable"
        }
    }

    var systemIcon: String {
        switch self {
        case .compact: return "square.grid.4x3.fill"
        case .normal: return "square.grid.3x2.fill"
        case .comfortable: return "square.grid.2x2.fill"
        }
    }

    var columnCount: Int {
        switch self {
        case .compact: return 5
        case .normal: return 3
        case .comfortable: return 2
        }
    }

    /// Minimum poster width for the adaptive grid (macOS and iPad) — a fixed column
    /// count doesn't reflow as the window resizes or leaves iPad's much larger screen
    /// with absurdly wide cards, so density instead sets how small a card can get
    /// before another column joins.
    var adaptiveMinimumWidth: CGFloat {
        switch self {
        case .compact: return 110
        case .normal: return 140
        case .comfortable: return 180
        }
    }
}

struct LibraryDetailView: View {
    let library: JellyfinLibrary
    /// Set when this shows a playlist: the same grid, filters and sort as any library, plus
    /// playlist order, playing through it, and adding and removing titles.
    var playlist: MediaPlaylist? = nil
    /// Opens the title picker straight away, for a playlist that was just created.
    var startsAddingTitles = false

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(PlaybackPresenter.self) private var playbackPresenter
    @Environment(\.dismiss) private var dismiss

    // Playlist
    @State private var playlistName: String?
    /// Playlist entry ids by item id, which removing a row needs.
    @State private var entryIds: [String: String] = [:]
    @State private var playlistPlayback: MediaDetailView.PlaybackRequest?
    @State private var showAddTitles = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var confirmDeletePlaylist = false
    @State private var playlistError: String?
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var createdPlaylist: MediaPlaylist?
    @State private var playlistTint: Color?

    init(library: JellyfinLibrary, playlist: MediaPlaylist? = nil, startsAddingTitles: Bool = false) {
        self.library = library
        self.playlist = playlist
        self.startsAddingTitles = startsAddingTitles
        // Settings › Appearance › Hide Watched in Libraries; a playlist always shows everything.
        let hidesWatched = UserDefaults.standard.bool(forKey: "libraryHideWatched") && library.collectionType != .playlists
        _watchedFilter = State(initialValue: hidesWatched ? .unwatched : .all)
    }

    /// A playlist picked from the Playlists library.
    init(playlistItem item: MediaItem, startsAddingTitles: Bool = false) {
        self.init(
            library: JellyfinLibrary(id: item.id, name: item.name, collectionType: .playlists),
            playlist: MediaPlaylist(id: item.id, name: item.name, itemCount: 0, primaryImageTag: item.primaryImageTag),
            startsAddingTitles: startsAddingTitles)
    }

    /// The Playlists tile Browse shows before the server has a Playlists library of its own.
    static let allPlaylistsID = "arcfin.playlists"

    /// The Playlists library itself (its titles are playlists), as opposed to one playlist.
    private var isPlaylistsLibrary: Bool { library.collectionType == .playlists && playlist == nil }
    private var parentId: String { library.id == Self.allPlaylistsID ? "" : library.id }

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var totalItems = 0
    /// Where the next server page starts. Equals `items.count` unless genres are matched
    /// with "all", where the client drops titles from each server page.
    @State private var serverOffset = 0
    @State private var hasLoaded = false
    @State private var scrolledItemID: MediaItem.ID? = nil
    private let pageSize = 100
    /// Every filter/sort change spawns its own uncancelled fetchFirstPage() Task (see the
    /// onChange handlers below) — nothing stopped an older, still-in-flight request from
    /// overwriting a newer one's results once it finally responded. Clicking through several
    /// filters quickly (easy with a mouse, less so with touch) could land a stale response
    /// for an earlier, narrower selection last, silently blanking out the correct one.
    @State private var fetchGeneration = 0

    // Filters
    @State private var availableGenres: [String] = []
    @State private var availableYears: [Int] = []
    @State private var availableRatings: [String] = []
    @State private var availableTags: [String] = []
    @State private var extraFilters = LibraryExtraFilters()
    @State private var selectedGenres: Set<String> = []
    @State private var selectedYears: Set<Int> = []
    @State private var watchedFilter: LibraryWatchedFilter = .all
    @State private var favoritesOnly = false
    @State private var sortOption: LibrarySortOption = .nameAsc
    @State private var randomPick: MediaItem?
    @State private var trailerLaunchItem: MediaItem?
    @State private var quickPlayRequest: PlaybackRequest?
    @State private var isPickingRandom = false
    /// Set while load() restores the saved sort, so the resulting onChange doesn't fire a
    /// second fetch on top of the initial one.
    @State private var restoringSort = false

    private var sortDefaultsKey: String { "librarySort.\(library.id)" }

    private var filtersActive: Bool {
        !selectedGenres.isEmpty || !selectedYears.isEmpty || watchedFilter != .all || favoritesOnly
            || extraFilters.isActive
    }

    private var matchesAllGenres: Bool { extraFilters.matchAllGenres && selectedGenres.count > 1 }
    private var hasMore: Bool { serverOffset < totalItems }
    private var isCollections: Bool { library.collectionType == .boxsets }

    // Maps the library type to the items it should show.
    // .unknown = BoxSet contents (Movie+Series from within a collection).
    private var includeTypes: String? {
        switch library.collectionType {
        case .movies:  return "Movie"
        case .tvshows: return "Series"
        case .boxsets: return "BoxSet"
        case .music:   return "MusicAlbum"
        case .unknown: return "Movie,Series"   // inside a BoxSet
        case .playlists: return playlist == nil ? "Playlist" : nil
        default:       return nil
        }
    }

    private let client = JellyfinMediaClient()
#if os(tvOS)
    private let columns = [GridItem(.adaptive(minimum: 200), spacing: DT.Spacing.shelfGap)]
#elseif os(macOS)
    @AppStorage("libraryGridDensity") private var gridDensity = LibraryGridDensity.normal
    private var columns: [GridItem] {
        // A fixed column count leaves a resizable Mac window either cramped or with
        // cards stretched absurdly wide — adaptive reflows as the window resizes,
        // with density still controlling how small a card can get first.
        [GridItem(.adaptive(minimum: gridDensity.adaptiveMinimumWidth), spacing: 12)]
    }
#else
    @AppStorage("libraryGridDensity") private var gridDensity = LibraryGridDensity.normal
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var columns: [GridItem] {
        // A wide window stretched a fixed 3-flexible-column grid into oversized posters —
        // the same adaptive, density-driven sizing as macOS keeps cards a sane size there.
        // By width, not device: an iPad in Split View or Slide Over is compact too.
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: gridDensity.adaptiveMinimumWidth), spacing: 12)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: gridDensity.columnCount)
    }
#endif

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .screenBackground()
            } else if items.isEmpty, playlist != nil, !filtersActive {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "Empty Playlist", systemImage: "list.and.film",
                        description: Text("Add movies, shows and episodes, or long-press any title and choose Add to Playlist."))
                    Button { showAddTitles = true } label: {
                        Label("Add Titles", systemImage: "plus").font(.headline)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DT.Color.accent)
                    .foregroundStyle(DT.Color.onAccent)
                    Spacer()
                }
                .screenBackground()
            } else if items.isEmpty, isPlaylistsLibrary, !filtersActive {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "No Playlists", systemImage: "list.and.film",
                        description: Text("Make a playlist, then add movies, shows and episodes to it."))
                    Button { showNewPlaylist = true } label: {
                        Label("New Playlist", systemImage: "plus").font(.headline)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DT.Color.accent)
                    .foregroundStyle(DT.Color.onAccent)
                    Spacer()
                }
                .screenBackground()
            } else if items.isEmpty {
                ContentUnavailableView(library.name,
                                      systemImage: library.collectionType.systemIcon,
                                      description: Text("Nothing found in this library."))
                .screenBackground()
            } else {
                ScrollView(showsIndicators: false) {
                    if playlist != nil { playlistHeader }
                    #if os(tvOS)
                    tvActionRow
                    #endif
                    LazyVGrid(columns: columns, spacing: DT.Spacing.shelfGap) {
                        ForEach(gridEntries) { entry in
                            Group {
                                if entry.items.count > 1 {
                                    showGroupCell(entry.items)
                                } else {
                                    itemCell(entry.items[0])
                                }
                            }
                            .onAppear {
                                if let last = entry.items.last, shouldLoadMore(after: last) {
                                    Task { await loadMore() }
                                }
                            }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding(DT.Spacing.pagePad)
#if os(tvOS)
                    .focusSection()
                    .scrollClipDisabled()
#endif
                }
                .scrollPosition(id: $scrolledItemID)
                .modifier(PlaylistPageStyle(isPlaylist: playlist != nil, tint: playlistTint))
            }
        }
#if os(macOS)
        .navigationTitle(playlistName ?? library.name)
#elseif os(tvOS)
        .navigationTitle("")
#else
        // Large + pinned-on-scroll, matching Browse (the parent screen) — this used to fake
        // its own title with a plain Text inside the ScrollView content instead, which just
        // scrolled away with nothing left pinned once you scrolled past it.
        // A playlist has its own title in the hero.
        .navigationTitle(playlist != nil ? "" : (playlistName ?? library.name))
        .navigationBarTitleDisplayMode(playlist != nil ? .inline : .large)
        .toolbarBackground(playlist != nil ? .hidden : .automatic, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
#endif
#if !os(tvOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await pickRandom() } } label: {
                    Image(systemName: "dice")
                }
                .disabled(isPickingRandom)
                .accessibilityLabel("Surprise me")
                .accessibilityHint(isCollections
                    ? "Opens a random collection"
                    : "Opens a random title from this library using the current filters")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showFilterSheet = true } label: {
                    Image(systemName: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Grid Density", selection: $gridDensity) {
                        ForEach(LibraryGridDensity.allCases) { density in
                            Label(density.label, systemImage: density.systemIcon).tag(density)
                        }
                    }
                } label: {
                    Image(systemName: gridDensity.systemIcon)
                }
                .accessibilityLabel("Grid density")
            }
            if isPlaylistsLibrary {
                ToolbarItem(placement: .primaryAction) {
                    Button { showNewPlaylist = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New Playlist")
                }
            }
            if playlist != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showAddTitles = true } label: { Label("Add Titles", systemImage: "plus") }
                        Button { renameText = playlistName ?? library.name; showRename = true } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) { confirmDeletePlaylist = true } label: {
                            Label("Delete Playlist", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Playlist options")
                }
            }
        }
#endif
#if !os(macOS)
        .sheet(isPresented: $showFilterSheet) {
            LibraryFilterSheet(
                availableGenres: availableGenres, availableYears: availableYears, availableRatings: availableRatings, availableTags: availableTags,
                selectedGenres: $selectedGenres, selectedYears: $selectedYears,
                watchedFilter: $watchedFilter, favoritesOnly: $favoritesOnly, sortOption: $sortOption,
                extraFilters: $extraFilters, sortOptions: sortOptions
            )
            #if os(iOS)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            #endif
        }
#else
        // .sheet doesn't reliably render its content on macOS here (same class of issue as
        // PlayerView's track/chapter menus) — rendered as a plain in-place overlay instead.
        .overlay {
            if showFilterSheet {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { showFilterSheet = false }
                        .accessibilityHidden(true)
                    VStack(spacing: 0) {
                        HStack {
                            Text("Filter & Sort").font(.system(.subheadline, design: .default, weight: .semibold))
                            Spacer()
                            Button("Done") { showFilterSheet = false }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        Divider()
                        LibraryFilterList(
                            availableGenres: availableGenres, availableYears: availableYears, availableRatings: availableRatings, availableTags: availableTags,
                            selectedGenres: $selectedGenres, selectedYears: $selectedYears,
                            watchedFilter: $watchedFilter, favoritesOnly: $favoritesOnly, sortOption: $sortOption,
                            extraFilters: $extraFilters, sortOptions: sortOptions
                        )
                    }
                    .frame(width: 380, height: 480)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(DT.Color.textPrimary.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 30)
                }
                .transition(.opacity)
            }
        }
        .animation(DT.Animation.motion(.easeInOut(duration: 0.15)), value: showFilterSheet)
#endif
        .onChange(of: selectedGenres) { _, _ in Task { await reload() } }
        .onChange(of: selectedYears) { _, _ in Task { await reload() } }
        .onChange(of: extraFilters) { _, _ in Task { await reload() } }
        .onChange(of: watchedFilter) { _, _ in Task { await reload() } }
        .onChange(of: favoritesOnly) { _, _ in Task { await reload() } }
        #if !os(tvOS)
        .quickPlayback($quickPlayRequest, trailer: $trailerLaunchItem)
        #endif
        #if !os(macOS)
        .fullScreenCover(item: $playlistPlayback, onDismiss: {
            PlayQueue.clear()
            Task { await reload() }
        }) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                PlayerView.keepOrientationOnNextDisappear = true
                playlistPlayback = MediaDetailView.PlaybackRequest(item: next, startTicks: 0)
            }
            .id(request.item.id)
        }
        #endif
        .navigationDestination(item: $randomPick) { pick in
            if pick.type == .boxSet {
                #if os(tvOS)
                TVCollectionDetailView(item: pick)
                #else
                CollectionDetailView(collection: pick)
                #endif
            } else if pick.type == .playlist {
                LibraryDetailView(playlistItem: pick)
            } else {
                #if os(tvOS)
                TVMediaDetailView(item: pick)
                #else
                MediaDetailView(item: pick)
                #endif
            }
        }
        .onChange(of: sortOption) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: sortDefaultsKey)
            if restoringSort { restoringSort = false; return }
            Task { await reload() }
        }
        .modifier(PlaylistModifiers(
            isPlaylist: playlist != nil || isPlaylistsLibrary,
            playback: $playlistPlayback,
            showAddTitles: $showAddTitles,
            showRename: $showRename,
            renameText: $renameText,
            confirmDelete: $confirmDeletePlaylist,
            error: $playlistError,
            playlistId: playlist?.id ?? "",
            playlistName: playlistName ?? library.name,
            existingIds: Set(items.map(\.id)),
            onRename: renamePlaylist,
            onDelete: deletePlaylist,
            onChanged: { Task { await reload() } }
        ))
        #if os(macOS)
        .onChange(of: playlistPlayback) { _, request in
            guard let request else { return }
            playbackPresenter.present(request.item, startTicks: request.startTicks)
            playlistPlayback = nil
        }
        .onChange(of: playbackPresenter.request == nil) { _, closed in
            if closed, playlist != nil { PlayQueue.clear(); Task { await reload() } }
        }
        #endif
        .alert("New Playlist", isPresented: $showNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
            Button("Create") { createPlaylist() }
        }
        .navigationDestination(item: $createdPlaylist) { created in
            LibraryDetailView(
                library: JellyfinLibrary(id: created.id, name: created.name, collectionType: .playlists),
                playlist: created, startsAddingTitles: true)
        }
        .task { await load() }
        .task { await loadFilterOptions() }
        .task(id: playlistHeroURL) {
            guard playlist != nil, let url = playlistHeroURL else { return }
            playlistTint = await AverageColor.load(from: url)
        }
    }

    /// Creates it empty, then opens it straight into picking titles.
    private func createPlaylist() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        newPlaylistName = ""
        guard !name.isEmpty, let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        Task {
            do {
                let id = try await client.createPlaylist(credential: cred, authHeader: header, name: name, itemIds: [])
                ContainingSets.shared.invalidate()
                await PlaylistStore.shared.load(credential: cred, authHeader: header)
                await reload()
                createdPlaylist = MediaPlaylist(id: id, name: name, itemCount: 0)
            } catch {
                playlistError = error.localizedDescription
            }
        }
    }

    private var sortOptions: [LibrarySortOption] {
        playlist != nil ? LibrarySortOption.allCases : LibrarySortOption.standard
    }

    /// A playlist's titles open a Play / Show Details choice instead of their page.
    @ViewBuilder
    private func gridLink<Content: View>(for item: MediaItem, @ViewBuilder label: () -> Content) -> some View {
        if playlist != nil {
            // A menu opens the same way from every card; a confirmation dialog switched
            // between a popover and a full sheet depending on the room around the card.
            Menu { playlistActions(item) } label: { label() }
                .menuStyle(.button)
                .menuIndicator(.hidden)
        } else {
            NavigationLink(value: navTarget(for: item)) { label() }
        }
    }

    private func itemCell(_ item: MediaItem) -> some View {
        gridLink(for: item) {
#if os(tvOS)
            PosterCard(
                title: cardTitle(item),
                subtitle: cardSubtitle(item),
                imageURL: cardPosterURL(item),
                width: 200,
                height: 356
            )
#else
            libraryItemCard(item)
#endif
        }
#if os(tvOS)
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
#else
        .buttonStyle(PressableButtonStyle())
#endif
        .contextMenu(menuItems: { libraryMenu(item) }, preview: { libraryItemPreview(item) })
    }

    /// One grid cell: a title, or in a playlist a run of episodes from one show.
    private struct GridEntry: Identifiable {
        let items: [MediaItem]
        var id: String { items[0].id }
    }

    /// A playlist holds a show as all of its episodes. In playlist order, three or more in a
    /// row from one show become a single card, so a whole series doesn't fill the page;
    /// one or two stay as they are, since those were most likely added one by one.
    private var gridEntries: [GridEntry] {
        guard playlist != nil, sortOption == .playlistOrder else { return items.map { GridEntry(items: [$0]) } }
        var entries: [GridEntry] = []
        var run: [MediaItem] = []
        func flush() {
            if run.count >= 3 {
                entries.append(GridEntry(items: run))
            } else {
                entries += run.map { GridEntry(items: [$0]) }
            }
            run = []
        }
        for item in items {
            if item.type == .episode, let seriesId = item.seriesId, run.first?.seriesId == seriesId {
                run.append(item)
            } else {
                flush()
                if item.type == .episode, item.seriesId != nil {
                    run = [item]
                } else {
                    entries.append(GridEntry(items: [item]))
                }
            }
        }
        flush()
        return entries
    }

    private func showGroupCell(_ episodes: [MediaItem]) -> some View {
        let first = episodes[0]
        let seasons = Set(episodes.compactMap(\.parentIndexNumber)).sorted()
        let seasonText = seasons.count > 1 ? "S\(seasons[0])–S\(seasons[seasons.count - 1])"
            : seasons.first.map { "Season \($0)" }
        let subtitle = (["\(episodes.count) episodes"] + [seasonText].compactMap { $0 }).joined(separator: " · ")
        return Menu {
            showGroupActions(episodes)
        } label: {
#if os(tvOS)
            PosterCard(title: first.seriesName ?? first.name, subtitle: subtitle,
                       imageURL: cardPosterURL(first), width: 200, height: 356)
#else
            LibraryItemCard(imageURL: cardPosterURL(first), title: first.seriesName ?? first.name, year: subtitle)
#endif
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
#if os(tvOS)
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
#else
        .buttonStyle(PressableButtonStyle())
#endif
        .contextMenu {
            Button(role: .destructive) { removeFromPlaylist(episodes) } label: {
                Label("Remove \(episodes.count) Episodes from Playlist", systemImage: "minus.circle")
            }
        }
    }

    @ViewBuilder
    private func showGroupActions(_ episodes: [MediaItem]) -> some View {
        let next = episodes.first { $0.userData?.played != true } ?? episodes[0]
        let resume = next.userData?.played == true ? 0 : (next.userData?.playbackPositionTicks ?? 0)
        let code = [next.parentIndexNumber.map { "S\($0)" }, next.indexNumber.map { "E\($0)" }]
            .compactMap { $0 }.joined(separator: " ")
        Button(resume > 0 ? "Resume \(code)" : "Play \(code)") { startPlaylistPlayback(from: next, startTicks: resume) }
        if next != episodes[0] {
            Button("Play from the First Episode") { startPlaylistPlayback(from: episodes[0], startTicks: 0) }
        }
        if let seriesId = episodes[0].seriesId {
            Button("Show Details") {
                randomPick = MediaItem(id: seriesId, name: episodes[0].seriesName ?? episodes[0].name, type: .series,
                                       primaryImageTag: episodes[0].seriesPrimaryImageTag)
            }
        }
    }

    @ViewBuilder
    private func playlistActions(_ item: MediaItem) -> some View {
        let resume = item.userData?.played == true ? 0 : (item.userData?.playbackPositionTicks ?? 0)
        if item.type == .movie || item.type == .episode {
            if resume > 0 {
                Button("Resume") { startPlaylistPlayback(from: item, startTicks: resume) }
                Button("Play from Beginning") { startPlaylistPlayback(from: item, startTicks: 0) }
            } else {
                Button("Play") { startPlaylistPlayback(from: item, startTicks: 0) }
            }
        }
        Button("Show Details") { randomPick = item }
    }

    /// A playlist's page opens like a collection's: the first title's artwork as the hero,
    /// its first posters fanned out with the name and length, then Play and Shuffle.
    private var playlistHeader: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeroBackdrop(url: playlistHeroURL, height: 300)
                HStack(alignment: .bottom, spacing: 14) {
                    FannedPosters(urls: items.prefix(3).map { cardPosterURL($0) })
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PLAYLIST")
                            .font(.system(.caption2, weight: .bold))
                            .tracking(1.5)
                            .foregroundStyle(DT.Color.accent)
                        Text(playlistName ?? library.name)
                            .font(.system(.title2, weight: .heavy))
                            .foregroundStyle(DT.Color.textPrimary)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                        Text(items.count == 1 ? "1 title" : "\(items.count) titles")
                            .font(.caption)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.top, -96)
            }
            playlistButtons
        }
    }

    #if os(tvOS)
    /// What the toolbar holds elsewhere; tvOS screens have no toolbar.
    private var tvActionRow: some View {
        HStack(spacing: 20) {
            if playlist != nil {
                Button { showAddTitles = true } label: { tvActionLabel("Add Titles", systemImage: "plus") }
                Button { renameText = playlistName ?? library.name; showRename = true } label: {
                    tvActionLabel("Rename", systemImage: "pencil")
                }
                Button { confirmDeletePlaylist = true } label: { tvActionLabel("Delete", systemImage: "trash") }
            } else if isPlaylistsLibrary {
                Button { showNewPlaylist = true } label: { tvActionLabel("New Playlist", systemImage: "plus") }
            }
            Button { showFilterSheet = true } label: {
                tvActionLabel("Filter & Sort", systemImage: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            if playlist == nil {
                Button { Task { await pickRandom() } } label: { tvActionLabel("Surprise Me", systemImage: "dice") }
                    .disabled(isPickingRandom)
            }
            Spacer()
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, DT.Spacing.md)
        .focusSection()
    }

    private func tvActionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        TVHeroButtonLabel(icon: systemImage, text: title)
            .background(Capsule().fill(DT.Color.textPrimary.opacity(0.06)))
    }
    #endif

    private var playlistHeroURL: URL? {
        guard let first = items.first else { return nil }
        return mediaRepo.imageURL(for: first, type: .backdrop, fillWidth: 1200)
    }

    private var playlistButtons: some View {
        HStack(spacing: 12) {
            Button { playAllFromStart() } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.glassProminent)
            .tint(DT.Color.accent)
            .foregroundStyle(DT.Color.onAccent)
            Button { shufflePlaylist() } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.glass)
        }
        .controlSize(.large)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, DT.Spacing.sm)
    }

    private var playableItems: [MediaItem] {
        items.filter { $0.type == .movie || $0.type == .episode }
    }

    private func playAllFromStart() {
        guard let first = playableItems.first else { return }
        let ticks = first.userData?.played == true ? 0 : (first.userData?.playbackPositionTicks ?? 0)
        startPlaylistPlayback(from: first, startTicks: ticks)
    }

    private func shufflePlaylist() {
        let shuffled = playableItems.shuffled()
        guard let first = shuffled.first else { return }
        PlayQueue.start(shuffled)
        playlistPlayback = MediaDetailView.PlaybackRequest(item: first, startTicks: 0)
    }

    /// Plays from `item` through the rest of the playlist in the order shown.
    private func startPlaylistPlayback(from item: MediaItem, startTicks: Int64) {
        let playable = playableItems
        let start = playable.firstIndex(of: item) ?? 0
        PlayQueue.start(playable.isEmpty ? [item] : Array(playable[start...]))
        playlistPlayback = MediaDetailView.PlaybackRequest(item: item, startTicks: startTicks)
    }

    private func removeFromPlaylist(_ item: MediaItem) {
        removeFromPlaylist([item])
    }

    private func removeFromPlaylist(_ removed: [MediaItem]) {
        let entries = removed.compactMap { entryIds[$0.id] }
        guard let playlist, !entries.isEmpty, let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let removedIds = Set(removed.map(\.id))
        items.removeAll { removedIds.contains($0.id) }
        Task {
            do {
                try await client.removeFromPlaylist(credential: cred, authHeader: header, playlistId: playlist.id, entryIds: entries)
                ContainingSets.shared.invalidate()
                await PlaylistStore.shared.load(credential: cred, authHeader: header)
            } catch {
                playlistError = error.localizedDescription
                await reload()
            }
        }
    }

    private func renamePlaylist(_ name: String) {
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let playlist, !newName.isEmpty, let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let oldName = playlistName
        playlistName = newName
        Task {
            do {
                try await client.renamePlaylist(credential: cred, authHeader: header, playlistId: playlist.id, name: newName)
                ContainingSets.shared.invalidate()
                await PlaylistStore.shared.load(credential: cred, authHeader: header)
            } catch {
                playlistName = oldName
                playlistError = error.localizedDescription
            }
        }
    }

    private func deletePlaylist() {
        guard let playlist, let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        Task {
            do {
                try await client.deletePlaylist(credential: cred, authHeader: header, playlistId: playlist.id)
                ContainingSets.shared.invalidate()
                await PlaylistStore.shared.load(credential: cred, authHeader: header)
                dismiss()
            } catch {
                playlistError = error.localizedDescription
            }
        }
    }

    @State private var showFilterSheet = false

    private func navTarget(for item: MediaItem) -> LibraryNavTarget {
        switch item.type {
        case .boxSet: .collection(item)
        case .playlist: .playlist(item)
        default: .media(item)
        }
    }

    private func shouldLoadMore(after item: MediaItem) -> Bool {
        item.id == items.last?.id && hasMore && !isLoadingMore
    }

    private func libraryItemCard(_ item: MediaItem) -> some View {
        LibraryItemCard(
            imageURL: cardPosterURL(item),
            title: cardTitle(item),
            year: cardSubtitle(item)
        )
    }

    /// An episode (a playlist holds a show as its episodes) is shown as its show, with the
    /// season, episode and its own name underneath.
    private func cardTitle(_ item: MediaItem) -> String {
        item.type == .episode ? (item.seriesName ?? item.name) : item.name
    }

    private func cardSubtitle(_ item: MediaItem) -> String? {
        guard item.type == .episode else { return item.productionYear.map { String($0) } }
        let code = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }].compactMap { $0 }
        return (code + (item.seriesName == nil ? [] : [item.name])).joined(separator: " · ").nilIfEmpty
    }

    private func cardPosterURL(_ item: MediaItem) -> URL? {
        guard item.type == .episode, let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag,
              let base = mediaRepo.baseURL, let token = mediaRepo.accessToken
        else { return mediaRepo.imageURL(for: item) }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: seriesId, tag: tag, type: .primary, fillWidth: 300, token: token)
    }

    private func libraryItemPreview(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CachedAsyncImage(url: mediaRepo.imageURL(for: item)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: DT.Color.backgroundSecondary
                }
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))

            Text(item.name)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .frame(width: 200, alignment: .leading)
        }
        .padding(DT.Spacing.sm)
    }

    @ViewBuilder
    private func libraryMenu(_ item: MediaItem) -> some View {
        if playlist != nil, entryIds[item.id] != nil {
            Button(role: .destructive) { removeFromPlaylist(item) } label: {
                Label("Remove from Playlist", systemImage: "minus.circle")
            }
        }
        #if !os(tvOS)
        if item.type == .movie || item.type == .episode {
            let ticks = (item.userData?.played == true) ? 0 : (item.userData?.playbackPositionTicks ?? 0)
            Button { quickPlayRequest = PlaybackRequest(item: item, startTicks: ticks) } label: {
                Label(ticks > 0 ? "Resume" : "Play", systemImage: "play.fill")
            }
        }
        Button { trailerLaunchItem = item } label: {
            Label("Play Trailer", systemImage: "play.rectangle")
        }
        #endif
        quickLookMenu(item)
    }

    @ViewBuilder
    private func quickLookMenu(_ item: MediaItem) -> some View {
        ItemQuickActions(item: item)
        Label(item.name, systemImage: item.type == .series ? "tv" : "film")
        if let year = item.productionYear {
            Label(String(year), systemImage: "calendar")
        }
        if let rating = item.communityRating {
            Label(String(format: "%.1f / 10", rating), systemImage: "star.fill")
        }
    }

    private func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        if playlistName == nil { playlistName = playlist?.name }
        let saved = UserDefaults.standard.string(forKey: sortDefaultsKey).flatMap(LibrarySortOption.init(rawValue:))
            ?? (playlist != nil ? .playlistOrder : nil)
        if let saved, saved != sortOption, sortOptions.contains(saved) {
            restoringSort = true
            sortOption = saved
        }
        if startsAddingTitles { showAddTitles = true }
        await fetchFirstPage()
    }

    /// Re-fetches from the top with the current filter/sort selection — used whenever a
    /// filter or sort option changes, not just on first appearance.
    private func reload() async {
        await fetchFirstPage()
    }

    private func fetchFirstPage() async {
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        isLoading = true
        fetchGeneration += 1
        let generation = fetchGeneration
        // try? previously swallowed whatever went wrong here outright — a filter/sort
        // combination that made the server reject the request (or any other failure) just
        // silently rendered an empty grid with nothing to point at. Logged now so a real
        // report of that has something concrete behind it instead of another guess.
        var fetched: (items: [MediaItem], nextOffset: Int, total: Int)?
        if let playlist,
           let entries = try? await client.getPlaylistEntries(credential: cred, authHeader: header, playlistId: playlist.id) {
            entryIds = Dictionary(entries.map { ($0.item.id, $0.entryId) }, uniquingKeysWith: { first, _ in first })
            // Playlist order with no filters is the playlist itself, as it was put together.
            if sortOption == .playlistOrder, !filtersActive {
                guard generation == fetchGeneration else { return }
                items = entries.map(\.item)
                serverOffset = items.count
                totalItems = items.count
                isLoading = false
                return
            }
        }
        do {
            fetched = try await fetchPage(credential: cred, header: header, startIndex: 0)
        } catch {
            let nsError = error as NSError
            Telemetry.logger(category: "LibraryView").error(
                "getLibraryItems failed for library \(library.id, privacy: .public): domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .public)"
            )
        }
        // A newer filter/sort change already started another fetch while this one was still
        // in flight — applying this now-stale response would overwrite that newer request's
        // correct result with whatever this older, possibly narrower selection matched.
        guard generation == fetchGeneration else { return }
        items = fetched?.items ?? []
        serverOffset = fetched?.nextOffset ?? 0
        totalItems = fetched?.total ?? 0
        mediaRepo.prefetchQuickLookAssets(for: items)
        isLoading = false
    }

    /// One page under the current filters. With "match all genres" the server can only
    /// return titles matching *any* selected genre, so pages are narrowed here and further
    /// server pages are pulled until this one is reasonably full.
    private func fetchPage(
        credential: ServerCredential, header: String, startIndex: Int,
        limit: Int? = nil, sortBy: String? = nil, sortOrder: String? = nil
    ) async throws -> (items: [MediaItem], nextOffset: Int, total: Int) {
        let limit = limit ?? pageSize
        var offset = startIndex
        var collected: [MediaItem] = []
        var total = 0
        var requests = 0
        repeat {
            let page = try await client.getLibraryItems(
                credential: credential, authHeader: header,
                libraryId: parentId, startIndex: offset, limit: limit,
                recursive: true,
                includeItemTypes: includeTypes,
                genres: Array(selectedGenres), requireAllGenres: matchesAllGenres,
                years: Array(selectedYears),
                officialRatings: Array(extraFilters.officialRatings), minCommunityRating: extraFilters.minRating,
                tags: Array(extraFilters.tags),
                isHD: extraFilters.quality == .hd ? true : nil,
                is4K: extraFilters.quality == .uhd ? true : nil,
                hasSubtitles: extraFilters.hasSubtitles ? true : nil,
                isPlayed: watchedFilter == .all ? nil : watchedFilter == .watched,
                isFavorite: favoritesOnly ? true : nil,
                sortBy: sortBy ?? sortOption.sortBy, sortOrder: sortOrder ?? sortOption.sortOrder
            )
            total = page.total
            offset += page.consumed
            collected += page.items
            requests += 1
            if page.consumed == 0 { offset = total }
        } while matchesAllGenres && collected.count < limit / 2 && offset < total && requests < 5
        return (collected, offset, total)
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        isLoadingMore = true
        let fetched = try? await fetchPage(credential: cred, header: header, startIndex: serverOffset)
        items.append(contentsOf: fetched?.items ?? [])
        if let fetched {
            serverOffset = fetched.nextOffset
            totalItems = fetched.total
        }
        isLoadingMore = false
    }

    /// Honors the active filters, so "Surprise me" on an unwatched-only view picks something
    /// unwatched.
    private func pickRandom() async {
        guard let cred = authManager.state.credential else { return }
        isPickingRandom = true
        defer { isPickingRandom = false }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let result = try? await fetchPage(
            credential: cred, header: header, startIndex: 0, limit: matchesAllGenres ? pageSize : 1,
            sortBy: "Random", sortOrder: "Ascending")
        if let pick = result?.items.first {
            HapticManager.impact(.light)
            randomPick = pick
        }
    }

    private func loadFilterOptions() async {
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let options: (genres: [String], years: [Int], officialRatings: [String], tags: [String])?
        do {
            options = try await client.getLibraryFilterOptions(
                credential: cred, authHeader: header, libraryId: parentId, includeItemTypes: includeTypes
            )
        } catch {
            Telemetry.logger(category: "LibraryView").error(
                "getLibraryFilterOptions failed for library \(library.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            options = nil
        }
        availableGenres = options?.genres ?? []
        availableYears = options?.years ?? []
        availableRatings = options?.officialRatings ?? []
        availableTags = options?.tags ?? []
    }
}

// MARK: - Playlist dialogs

/// A playlist's page runs up under the status bar with an artwork-tinted background, like
/// a collection's; every other library keeps its plain background.
private struct PlaylistPageStyle: ViewModifier {
    let isPlaylist: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        if isPlaylist {
            content
                .detailPageBackground(tint: tint)
                .ignoresSafeArea(edges: .top)
        } else {
            content.screenBackground()
        }
    }
}

/// A playlist's choices and sheets, kept out of LibraryDetailView's already long chain.
private struct PlaylistModifiers: ViewModifier {
    let isPlaylist: Bool
    @Binding var playback: MediaDetailView.PlaybackRequest?
    @Binding var showAddTitles: Bool
    @Binding var showRename: Bool
    @Binding var renameText: String
    @Binding var confirmDelete: Bool
    @Binding var error: String?
    let playlistId: String
    let playlistName: String
    let existingIds: Set<String>
    let onRename: (String) -> Void
    let onDelete: () -> Void
    let onChanged: () -> Void

    func body(content: Content) -> some View {
        if isPlaylist {
            content
                .sheet(isPresented: $showAddTitles) {
                    AddTitlesToPlaylistSheet(playlistId: playlistId, existingIds: existingIds, onAdded: onChanged)
                }
                .alert("Rename Playlist", isPresented: $showRename) {
                    TextField("Name", text: $renameText)
                    Button("Cancel", role: .cancel) {}
                    Button("Save") { onRename(renameText) }
                }
                .confirmationDialog("Delete \(playlistName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete Playlist", role: .destructive, action: onDelete)
                } message: {
                    Text("The titles stay in your library.")
                }
                .alert("Playlist", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(error ?? "")
                }
        } else {
            content
        }
    }
}

// MARK: - Library filter sheet

/// Shared list content between the iOS/iPadOS sheet and the macOS in-place overlay panel
/// below — .sheet(isPresented:) has now failed to render reliably on macOS twice in this
/// app (the other case was PlayerView's track/chapter menus), so rather than keep chasing
/// why, macOS gets its own chrome around this same content instead of relying on .sheet.
struct LibraryFilterList: View {
    let availableGenres: [String]
    let availableYears: [Int]
    let availableRatings: [String]
    let availableTags: [String]
    @Binding var selectedGenres: Set<String>
    @Binding var selectedYears: Set<Int>
    @Binding var watchedFilter: LibraryWatchedFilter
    @Binding var favoritesOnly: Bool
    @Binding var sortOption: LibrarySortOption
    @Binding var extraFilters: LibraryExtraFilters
    var sortOptions: [LibrarySortOption] = LibrarySortOption.standard

    var body: some View {
        List {
            // A Picker with .pickerStyle(.inline) here rendered as an empty section on
            // macOS — a known-unreliable style inside a List on that platform. Plain
            // tappable rows, same pattern as the Genre/Year sections below, work
            // identically everywhere since nothing depends on a platform picker style.
            Section {
                FilterGroup(title: "Sort By", value: sortOption.rawValue) {
                    ForEach(sortOptions) { option in
                        filterRow(option.rawValue, isSelected: sortOption == option) {
                            sortOption = option
                        }
                    }
                }
            }

            Section("Status") {
                Picker("Status", selection: $watchedFilter) {
                    ForEach(LibraryWatchedFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Favourites Only", isOn: $favoritesOnly)
            }

            if !availableGenres.isEmpty {
                Section {
                    FilterGroup(title: "Genre", value: Self.summary(selectedGenres)) {
                        if selectedGenres.count > 1 {
                            Picker("Match", selection: $extraFilters.matchAllGenres) {
                                Text("Any").tag(false)
                                Text("All").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                        ForEach(availableGenres, id: \.self) { genre in
                            filterRow(genre, isSelected: selectedGenres.contains(genre)) {
                                toggle(genre, in: &selectedGenres)
                            }
                        }
                    }
                }
            }

            if !availableYears.isEmpty {
                Section {
                    FilterGroup(title: "Year", value: Self.summary(Set(selectedYears.map(String.init)))) {
                        ForEach(availableYears, id: \.self) { year in
                            filterRow(String(year), isSelected: selectedYears.contains(year)) {
                                toggle(year, in: &selectedYears)
                            }
                        }
                    }
                }
            }

            Section("Minimum Score") {
                let score = extraFilters.minRating ?? 0
                #if os(tvOS)
                Picker("Score", selection: Binding(
                    get: { extraFilters.minRating ?? 0 },
                    set: { extraFilters.minRating = $0 > 0 ? $0 : nil }
                )) {
                    Text("Any").tag(0.0)
                    ForEach([5.0, 6.0, 7.0, 7.5, 8.0, 8.5, 9.0], id: \.self) { Text(String(format: "%.1f+", $0)).tag($0) }
                }
                #else
                LabeledContent("Score", value: score > 0 ? String(format: "%.1f+", score) : "Any")
                Slider(
                    value: Binding(
                        get: { extraFilters.minRating ?? 0 },
                        set: { extraFilters.minRating = $0 > 0 ? $0 : nil }
                    ),
                    in: 0...9, step: 0.5
                )
                .accessibilityLabel("Minimum score")
                .accessibilityValue(score > 0 ? String(format: "%.1f or higher", score) : "Any")
                #endif
            }

            if !availableRatings.isEmpty {
                let ordered = LibraryExtraFilters.ordered(availableRatings)
                let step = LibraryExtraFilters.ratingStep(extraFilters.officialRatings, in: ordered)
                let label = step >= ordered.count ? "Any" : "Up to \(ordered[step])"
                Section("Content Rating") {
                    #if os(tvOS)
                    Picker("Maturity", selection: Binding(
                        get: { step },
                        set: { extraFilters.officialRatings = LibraryExtraFilters.ratings(upToStep: $0, in: ordered) }
                    )) {
                        ForEach(0..<ordered.count, id: \.self) { Text("Up to \(ordered[$0])").tag($0) }
                        Text("Any").tag(ordered.count)
                    }
                    #else
                    LabeledContent("Maturity", value: label)
                    Slider(
                        value: Binding(
                            get: { Double(step) },
                            set: { extraFilters.officialRatings = LibraryExtraFilters.ratings(upToStep: Int($0), in: ordered) }
                        ),
                        in: 0...Double(ordered.count), step: 1
                    )
                    .accessibilityLabel("Maximum content rating")
                    .accessibilityValue(label)
                    #endif
                }
            }

            Section("Quality") {
                Picker("Resolution", selection: $extraFilters.quality) {
                    ForEach(LibraryQualityFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Has Subtitles", isOn: $extraFilters.hasSubtitles)
            }

            if !availableTags.isEmpty {
                Section {
                    FilterGroup(title: "Tags", value: Self.summary(extraFilters.tags)) {
                        ForEach(availableTags, id: \.self) { tag in
                            filterRow(tag, isSelected: extraFilters.tags.contains(tag)) {
                                toggle(tag, in: &extraFilters.tags)
                            }
                        }
                    }
                }
            }

            if !selectedGenres.isEmpty || !selectedYears.isEmpty || watchedFilter != .all || favoritesOnly
                || extraFilters.isActive {
                Section {
                    Button(role: .destructive) {
                        selectedGenres.removeAll()
                        selectedYears.removeAll()
                        extraFilters = LibraryExtraFilters()
                        watchedFilter = .all
                        favoritesOnly = false
                    } label: {
                        Text("Clear All Filters").frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
    }

    private static func summary(_ selected: Set<String>) -> String {
        switch selected.count {
        case 0: "Any"
        case 1: selected.first ?? "Any"
        default: "\(selected.count) selected"
        }
    }

    private func filterRow(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(DT.Color.accent)
                }
            }
        }
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

#if !os(macOS)
struct LibraryFilterSheet: View {
    let availableGenres: [String]
    let availableYears: [Int]
    let availableRatings: [String]
    let availableTags: [String]
    @Binding var selectedGenres: Set<String>
    @Binding var selectedYears: Set<Int>
    @Binding var watchedFilter: LibraryWatchedFilter
    @Binding var favoritesOnly: Bool
    @Binding var sortOption: LibrarySortOption
    @Binding var extraFilters: LibraryExtraFilters
    var sortOptions: [LibrarySortOption] = LibrarySortOption.standard

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LibraryFilterList(
                availableGenres: availableGenres, availableYears: availableYears, availableRatings: availableRatings, availableTags: availableTags,
                selectedGenres: $selectedGenres, selectedYears: $selectedYears,
                watchedFilter: $watchedFilter, favoritesOnly: $favoritesOnly, sortOption: $sortOption,
                extraFilters: $extraFilters, sortOptions: sortOptions
            )
            .navigationTitle("Filter & Sort")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif

/// A filter's choices: expanding in place where lists can, its own page on tvOS.
private struct FilterGroup<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(tvOS)
        NavigationLink {
            List { content() }
                .navigationTitle(title)
        } label: {
            LabeledContent(title, value: value)
        }
        #else
        DisclosureGroup {
            content()
        } label: {
            LabeledContent(title, value: value)
        }
        #endif
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
