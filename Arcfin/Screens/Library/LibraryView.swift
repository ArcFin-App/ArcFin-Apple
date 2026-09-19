import SwiftUI
import AVKit
import JellyfinAPI
import AuthCore
import MediaEngine
import Persistence
import SwiftVLC

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Library screen

struct LibraryView: View {
    @Environment(MediaRepository.self) private var mediaRepo

    @State private var showDocPicker = false
    @State private var pickedURL: URL?
    @State private var navigateToLocalPlayer = false
    @State private var navigateToDownloadsDeepLink = false
    @State private var searchQuery = ""

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

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
                    LibraryDetailView(library: JellyfinLibrary(
                        id: item.id, name: item.name,
                        collectionType: .unknown,
                        primaryImageTag: item.primaryImageTag))
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

    // MARK: - Jellyfin downloads section

    #if os(iOS)
    @ViewBuilder
    private var jellyfinDownloadsSection: some View {
        NavigationLink {
            DownloadsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DT.Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloads")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("Movies and episodes saved for offline playback")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
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
                        .font(.system(size: 18))
                        .foregroundStyle(DT.Color.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Browse Files")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DT.Color.textPrimary)
                        Text("Pick a video file from Files app")
                            .font(.system(size: 12))
                            .foregroundStyle(DT.Color.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
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
                    .font(.system(size: 40 * DT.Scale.font, weight: .light))
                    .foregroundStyle(Color(hex: library.collectionType.accentHex))

                Text(library.name)
                    .font(.system(size: 14 * DT.Scale.font, weight: .semibold))
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

    var body: some View {
        ZStack {
            background

            Rectangle()
                .fill(.black.opacity(0.35))

            VStack(spacing: 10) {
                Image(systemName: library.collectionType.systemIcon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6)

                Text(library.name)
                    .font(.system(size: 13, weight: .semibold))
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
                .stroke(Color(hex: library.collectionType.accentHex).opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }

    @ViewBuilder
    private var background: some View {
        if let imageURL {
            AsyncImage(url: imageURL) { phase in
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
        #if canImport(UIKit) && !os(tvOS)
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            #if canImport(UIKit) && !os(tvOS)
            AirPlayButton().frame(width: 30, height: 30)
            if AVPictureInPictureController.isPictureInPictureSupported() {
                Button { vlcPipController?.toggle() } label: {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
            }
            Button { togglePlayerOrientation() } label: {
                Image(systemName: "rotate.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            Button { isFillScreen.toggle() } label: {
                Image(systemName: isFillScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isFillScreen ? DT.Color.accent : .white)
                    .frame(width: 32, height: 32)
            }
            #endif
            if !player.availableSubtitleTracks.isEmpty {
                Button { showTrackMenu = true } label: {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
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
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                HStack(spacing: 28) {
                    Button { seek(by: -10) } label: {
                        Image(systemName: "gobackward.10").font(.system(size: 20)).foregroundStyle(.white)
                    }
                    Button { togglePlayPause() } label: {
                        Image(systemName: player.status == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    Button { seek(by: 10) } label: {
                        Image(systemName: "goforward.10").font(.system(size: 20)).foregroundStyle(.white)
                    }
                }
                Spacer()
                Text(remainingLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
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
            #if canImport(UIKit) && !os(tvOS)
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

struct LibraryDetailView: View {
    let library: JellyfinLibrary

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(StreamystatsRepository.self) private var statsRepo

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var totalItems = 0
    @State private var hasLoaded = false
    @State private var scrolledItemID: MediaItem.ID? = nil
    private let pageSize = 100

    private var hasMore: Bool { items.count < totalItems }
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
#else
    @AppStorage("compactLibraryGrid") private var compactGrid = false
    private var columns: [GridItem] {
        let count = compactGrid ? 4 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
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
#if !os(macOS) && !os(tvOS)
                    Text(library.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(DT.Color.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DT.Spacing.pagePad)
                        .padding(.top, DT.Spacing.pagePad)
#endif
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
                            .contextMenu { quickLookMenu(item) }
#else
                            .buttonStyle(.plain)
                            .contextMenu { quickLookMenu(item) }
#endif
                            .onAppear {
                                if item.id == items.last?.id && hasMore && !isLoadingMore {
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
        .navigationTitle("")
#if !os(macOS) && !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
#endif
        .task { await load() }
    }

    private func navTarget(for item: MediaItem) -> LibraryNavTarget {
        item.type == .boxSet ? .collection(item) : .media(item)
    }

    private func libraryItemCard(_ item: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let url = mediaRepo.imageURL(for: item) {
                AsyncImage(url: url) { phase in
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
                Text(item.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let year = item.productionYear {
                    Text(String(year))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(8)
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    @ViewBuilder
    private func quickLookMenu(_ item: MediaItem) -> some View {
        if statsRepo.isConfigured {
            Button {
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
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        isLoading = true
        let fetched = try? await client.getLibraryItems(
            credential: cred, authHeader: header,
            libraryId: library.id, startIndex: 0, limit: pageSize,
            recursive: true,
            includeItemTypes: includeTypes
        )
        items = fetched?.items ?? []
        totalItems = fetched?.total ?? 0
        mediaRepo.prefetchQuickLookAssets(for: items)
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        isLoadingMore = true
        let fetched = try? await client.getLibraryItems(
            credential: cred, authHeader: header,
            libraryId: library.id, startIndex: items.count, limit: pageSize,
            recursive: true,
            includeItemTypes: includeTypes
        )
        items.append(contentsOf: fetched?.items ?? [])
        if let total = fetched?.total { totalItems = total }
        isLoadingMore = false
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
