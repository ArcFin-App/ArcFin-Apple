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

    private var gridColumns: [GridItem] {
#if os(macOS)
        // Fixed 2-up stretches library cards absurdly wide on a resizable Mac window —
        // adaptive reflows into more columns as it grows instead.
        [GridItem(.adaptive(minimum: 220), spacing: 12)]
#else
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
#endif
    }

    var body: some View {
        NavigationStack {
            Group {
                if searchQuery.isEmpty {
                    browseContent
                } else {
                    SearchView(query: $searchQuery)
                }
            }
            .background(DT.Color.backgroundPrimary)
            .navigationTitle("Browse")
            .searchable(text: $searchQuery, prompt: "Movies, shows, people…")
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
            #if os(iOS)
            .navigationDestination(isPresented: $navigateToDownloadsDeepLink) {
                DownloadsView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .arcfinSearch)) { note in
                if let term = note.userInfo?["term"] as? String { searchQuery = term }
            }
            .onAppear {
                if let term = UserDefaults.standard.string(forKey: "arcfin.pendingSearch") {
                    UserDefaults.standard.removeObject(forKey: "arcfin.pendingSearch")
                    searchQuery = term
                }
            }
            // arcfin://downloads — tapping the download Live Activity.
            .onReceive(NotificationCenter.default.publisher(for: .arcfinShowDownloads)) { _ in
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
                #if os(iOS)
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
        mediaRepo.libraries.filter { $0.collectionType != .livetv && $0.collectionType != .music }
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

    #if os(iOS)
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
                    .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).stroke(Color.white.opacity(0.06), lineWidth: 1))
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
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
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
        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isFocused)
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
        ZStack(alignment: .bottomLeading) {
            if let imageURL {
                CachedAsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Color(DT.Color.backgroundSecondary)
                    }
                }
                .clipped()
            } else {
                DT.Color.backgroundSecondary
            }
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
                }
            }
            .padding(8)
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(hovered ? DT.Color.accent.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
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
        ZStack {
            Color.black.ignoresSafeArea()

            #if canImport(UIKit) && !os(tvOS)
            GeometryReader { proxy in
                // See PlayerView/OfflinePlayerView's own comment on why hit-testing is
                // disabled here — PiPVideoView's native drawable is itself interactive and
                // would otherwise swallow the tap before the toggleControls gesture sees it.
                ZStack {
                    PiPVideoView(player.vlcPlayer, controller: $vlcPipController, managesAudioSession: false)
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
        .task {
            _ = url.startAccessingSecurityScopedResource()
            try? await player.load(url: url, startPositionTicks: 0)
            await player.play()
        }
        .onDisappear {
            Task { await player.stop() }
            url.stopAccessingSecurityScopedResource()
        }
        .onChange(of: player.status) { _, status in
            if status == .playing { scheduleAutoHide() }
            if status == .ended { dismiss() }
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
            Button { dismiss() } label: {
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
            if AVPictureInPictureController.isPictureInPictureSupported() {
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

    var id: String { rawValue }

    var sortBy: String {
        switch self {
        case .nameAsc, .nameDesc: return "SortName"
        case .dateAddedDesc: return "DateCreated"
        case .releaseDateDesc, .releaseDateAsc: return "PremiereDate"
        case .ratingDesc: return "CommunityRating"
        case .genreAsc: return "Genres"
        }
    }

    var sortOrder: String {
        switch self {
        case .nameAsc, .releaseDateAsc: return "Ascending"
        case .nameDesc, .dateAddedDesc, .releaseDateDesc, .ratingDesc: return "Descending"
        case .genreAsc: return "Ascending"
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

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(StreamystatsRepository.self) private var statsRepo

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
    private var columns: [GridItem] {
        // iPad's much larger screen stretched a fixed 3-flexible-column grid into
        // oversized posters — the same adaptive, density-driven sizing as macOS keeps
        // cards a sane size there instead, with iPhone left on its fixed column count.
        if UIDevice.current.userInterfaceIdiom == .pad {
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
                    .background(DT.Color.backgroundPrimary)
            } else if items.isEmpty {
                ContentUnavailableView(library.name,
                                      systemImage: library.collectionType.systemIcon,
                                      description: Text("Nothing found in this library."))
                .background(DT.Color.backgroundPrimary)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: DT.Spacing.shelfGap) {
                        ForEach(items) { item in
                            NavigationLink(value: navTarget(for: item)) {
#if os(tvOS)
                                PosterCard(
                                    title: item.name,
                                    subtitle: item.productionYear.map { String($0) },
                                    imageURL: mediaRepo.imageURL(for: item, type: .primary, fillWidth: 400),
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
                            .contextMenu(menuItems: { quickLookMenu(item) }, preview: { libraryItemPreview(item) })
#else
                            .buttonStyle(PressableButtonStyle())
                            .contextMenu(menuItems: { libraryMenu(item) }, preview: { libraryItemPreview(item) })
#endif
                            .onAppear {
                                if shouldLoadMore(after: item) {
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
                .background(DT.Color.backgroundPrimary)
            }
        }
#if os(macOS)
        .navigationTitle(library.name)
#elseif os(tvOS)
        .navigationTitle("")
#else
        // Large + pinned-on-scroll, matching Browse (the parent screen) — this used to fake
        // its own title with a plain Text inside the ScrollView content instead, which just
        // scrolled away with nothing left pinned once you scrolled past it.
        .navigationTitle(library.name)
        .navigationBarTitleDisplayMode(.large)
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
        }
#if !os(macOS)
        .sheet(isPresented: $showFilterSheet) {
            LibraryFilterSheet(
                availableGenres: availableGenres, availableYears: availableYears, availableRatings: availableRatings, availableTags: availableTags,
                selectedGenres: $selectedGenres, selectedYears: $selectedYears,
                watchedFilter: $watchedFilter, favoritesOnly: $favoritesOnly, sortOption: $sortOption,
                extraFilters: $extraFilters
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
                extraFilters: $extraFilters
                        )
                    }
                    .frame(width: 380, height: 480)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.3), radius: 30)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showFilterSheet)
#endif
        .onChange(of: selectedGenres) { _, _ in Task { await reload() } }
        .onChange(of: selectedYears) { _, _ in Task { await reload() } }
        .onChange(of: extraFilters) { _, _ in Task { await reload() } }
        .onChange(of: watchedFilter) { _, _ in Task { await reload() } }
        .onChange(of: favoritesOnly) { _, _ in Task { await reload() } }
        #if os(iOS)
        .fullScreenCover(item: $trailerLaunchItem) { TrailerLauncher(item: $0) }
        #endif
        .navigationDestination(item: $randomPick) { pick in
            if pick.type == .boxSet {
                CollectionDetailView(collection: pick)
            } else {
                MediaDetailView(item: pick)
            }
        }
        .onChange(of: sortOption) { _, newValue in
            UserDefaults.standard.set(newValue.rawValue, forKey: sortDefaultsKey)
            if restoringSort { restoringSort = false; return }
            Task { await reload() }
        }
#endif
        .task { await load() }
        .task { await loadFilterOptions() }
    }

    #if !os(tvOS)
    @State private var showFilterSheet = false
    #endif

    private func navTarget(for item: MediaItem) -> LibraryNavTarget {
        item.type == .boxSet ? .collection(item) : .media(item)
    }

    private func shouldLoadMore(after item: MediaItem) -> Bool {
        item.id == items.last?.id && hasMore && !isLoadingMore
    }

    private func libraryItemCard(_ item: MediaItem) -> some View {
        LibraryItemCard(
            imageURL: mediaRepo.imageURL(for: item),
            title: item.name,
            year: item.productionYear.map { String($0) }
        )
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
        #if os(iOS)
        Button { trailerLaunchItem = item } label: {
            Label("Play Trailer", systemImage: "play.rectangle")
        }
        #endif
        quickLookMenu(item)
    }

    @ViewBuilder
    private func quickLookMenu(_ item: MediaItem) -> some View {
        ItemQuickActions(item: item)
        if statsRepo.isConfigured {
            Button {
                HapticManager.impact(.light)
                Task { try? await statsRepo.addToWatchlist(itemId: item.id) }
            } label: {
                Label("Add to Watchlist", systemImage: "bookmark")
            }
        }
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
        if let raw = UserDefaults.standard.string(forKey: sortDefaultsKey),
           let saved = LibrarySortOption(rawValue: raw), saved != sortOption {
            restoringSort = true
            sortOption = saved
        }
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
                libraryId: library.id, startIndex: offset, limit: limit,
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

    #if !os(tvOS)
    private func loadFilterOptions() async {
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let options: (genres: [String], years: [Int], officialRatings: [String], tags: [String])?
        do {
            options = try await client.getLibraryFilterOptions(
                credential: cred, authHeader: header, libraryId: library.id, includeItemTypes: includeTypes
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
    #else
    private func loadFilterOptions() async {}
    #endif
}

// MARK: - Library filter sheet

#if !os(tvOS)
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

    var body: some View {
        List {
            // A Picker with .pickerStyle(.inline) here rendered as an empty section on
            // macOS — a known-unreliable style inside a List on that platform. Plain
            // tappable rows, same pattern as the Genre/Year sections below, work
            // identically everywhere since nothing depends on a platform picker style.
            Section {
                DisclosureGroup {
                    ForEach(LibrarySortOption.allCases) { option in
                        filterRow(option.rawValue, isSelected: sortOption == option) {
                            sortOption = option
                        }
                    }
                } label: {
                    LabeledContent("Sort By", value: sortOption.rawValue)
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
                    DisclosureGroup {
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
                    } label: {
                        LabeledContent("Genre", value: Self.summary(selectedGenres))
                    }
                }
            }

            if !availableYears.isEmpty {
                Section {
                    DisclosureGroup {
                        ForEach(availableYears, id: \.self) { year in
                            filterRow(String(year), isSelected: selectedYears.contains(year)) {
                                toggle(year, in: &selectedYears)
                            }
                        }
                    } label: {
                        LabeledContent("Year", value: Self.summary(Set(selectedYears.map(String.init))))
                    }
                }
            }

            Section("Minimum Score") {
                let score = extraFilters.minRating ?? 0
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
            }

            if !availableRatings.isEmpty {
                let ordered = LibraryExtraFilters.ordered(availableRatings)
                let step = LibraryExtraFilters.ratingStep(extraFilters.officialRatings, in: ordered)
                let label = step >= ordered.count ? "Any" : "Up to \(ordered[step])"
                Section("Content Rating") {
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
                    DisclosureGroup {
                        ForEach(availableTags, id: \.self) { tag in
                            filterRow(tag, isSelected: extraFilters.tags.contains(tag)) {
                                toggle(tag, in: &extraFilters.tags)
                            }
                        }
                    } label: {
                        LabeledContent("Tags", value: Self.summary(extraFilters.tags))
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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LibraryFilterList(
                availableGenres: availableGenres, availableYears: availableYears, availableRatings: availableRatings, availableTags: availableTags,
                selectedGenres: $selectedGenres, selectedYears: $selectedYears,
                watchedFilter: $watchedFilter, favoritesOnly: $favoritesOnly, sortOption: $sortOption,
                extraFilters: $extraFilters
            )
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
#endif

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
