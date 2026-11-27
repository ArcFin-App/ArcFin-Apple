// SPDX-License-Identifier: AGPL-3.0-or-later

import AVKit
import JellyfinAPI
import SeerrAPI
import SwiftUI
import AuthCore

/// The Arcs tab: the feed, with titles opening on top of it.
struct ArcsTab: View {
    @Environment(AuthManager.self) private var authManager
    @State private var model: ArcsModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model { ArcsFeedView(model: model, showsFeedPicker: true) } else { Color.black.ignoresSafeArea() }
            }
            .arcsDestinations()
        }
        .task { if model == nil { model = ArcsModel(authManager: authManager) } }
    }
}

/// Arcs over everything else: one show's scenes, the liked ones, or today's clip and on from it.
struct ArcsCover: View {
    let feed: ArcsFeed
    var seriesID: String? = nil
    var startingWith: [ArcClip] = []
    var offline = false

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var model: ArcsModel?

    var body: some View {
        NavigationStack {
            Group {
                if let model { ArcsFeedView(model: model, showsFeedPicker: false, close: { dismiss() }) } else { Color.black.ignoresSafeArea() }
            }
            .arcsDestinations()
        }
        // The cover going away, not a title page pushed inside it.
        .onDisappear { model?.close() }
        .task {
            if model == nil {
                model = ArcsModel(authManager: authManager, feed: feed, seriesID: seriesID, startingWith: startingWith, offline: offline)
            }
        }
    }
}

extension View {
    func arcsDestinations() -> some View {
        navigationDestination(for: MediaItem.self) { item in
            if item.type == .boxSet { CollectionDetailView(collection: item) } else { MediaDetailView(item: item) }
        }
    }
}

/// The feed: one clip to a screen, swiped up for the next.
struct ArcsFeedView: View {
    @Bindable var model: ArcsModel
    let showsFeedPicker: Bool
    var close: (() -> Void)? = nil

    @Environment(\.scenePhase) private var scenePhase
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo
    @State private var playback: PlaybackRequest?
    @State private var discoverItem: SeerrItem?
    @State private var sharing: ArcClip?
    @State private var openedItem: MediaItem?
    @State private var showShow: ArcClip?
    @State private var showLiked = false
    @State private var showHidden = false
    @State private var showSettings = false
    @State private var pictureInPicture = 0
    @State private var resumeAfterCover = false
    @State private var isOnScreen = false
    @State private var isLandscape = false
    @State private var airPlay = ArcsAirPlayTrigger()
    @State private var landscapeSkipped = false
    @State private var showSearch = false
    @State private var sendingClip: ArcClip?
    @State private var requestingItem: SeerrItem?
    @State private var showSaved = false
    @AppStorage(ArcsSettings.showRequestsKey) private var showRequests = true
    @AppStorage(ArcsSettings.youTubeTrailersKey) private var youTubeTrailers = true

    private var asksToRotate: Bool { isLandscape && !landscapeSkipped }

    /// One height for the top bar's switch and buttons.
    private static let barHeight: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black
                content(bottomInset: proxy.safeAreaInsets.bottom)
                VStack(spacing: 8) {
                    topBar
                    if showsFeedPicker, model.feed == .forYou { moodChips }
                }
                .padding(.top, proxy.safeAreaInsets.top + 4)
                if let toast = model.toast { toastView(toast).padding(.top, proxy.safeAreaInsets.top + 100) }
            }
            .ignoresSafeArea()
            .overlay {
                if asksToRotate { ArcsRotatePrompt { landscapeSkipped = true } }
            }
            .onChange(of: proxy.size.width > proxy.size.height, initial: true) { _, wide in isLandscape = wide }
        }
        .alwaysDarkPlayer()
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(false)
        .task {
            model.requestsAllowed = seerrRepo.isConfigured && showRequests
            model.trailersAllowed = youTubeTrailers
            await model.load()
        }
        .onAppear { isOnScreen = true; updateVisibility() }
        .onDisappear { isOnScreen = false; updateVisibility() }
        .onChange(of: scenePhase) { updateVisibility() }
        .onChange(of: asksToRotate) { updateVisibility() }
        .onChange(of: model.toast) { _, toast in
            guard toast != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation { model.toast = nil }
            }
        }
        .navigationDestination(item: $openedItem) { item in
            MediaDetailView(item: item)
        }
        .navigationDestination(item: $discoverItem) { item in SeerrItemDetailView(item: item) }
        .navigationDestination(isPresented: $showLiked) { ArcsLikedView() }
        .navigationDestination(isPresented: $showHidden) { ArcsHiddenView() }
        .navigationDestination(isPresented: $showSettings) { ArcsSettingsView() }
        .navigationDestination(isPresented: $showSearch) { ArcsSearchView(model: model) }
        .sheet(item: $sendingClip, onDismiss: resume) { clip in
            ArcsSendSheet(clip: clip, model: model)
        }
        .sheet(item: $requestingItem, onDismiss: resume) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingItem)
        }
        .fullScreenCover(isPresented: $showSaved, onDismiss: resume) {
            ArcsCover(feed: .forYou, startingWith: ArcsOfflineStore.shared.clips, offline: true)
        }
        .fullScreenCover(item: $playback, onDismiss: resume) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                PlayerView.keepOrientationOnNextDisappear = true
                playback = PlaybackRequest(item: next, startTicks: 0)
            }
            .id(request.item.id)
        }
        .sheet(item: $sharing, onDismiss: resume) { clip in
            ArcsShareView(clip: clip, model: model)
        }
        .fullScreenCover(item: $showShow, onDismiss: resume) { clip in
            ArcsCover(feed: .series, seriesID: clip.titleID)
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(bottomInset: Double) -> some View {
        switch model.phase {
        case .loading:
            ProgressView().tint(.white).controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            message(title: "No Scenes Yet", icon: "play.square.stack",
                    text: model.feed == .liked ? Text("Double-tap a scene to like it, and it shows here.")
                        : model.feed == .continue ? Text("Scenes from what you're in the middle of show here. Start a film or a show first.")
                        : Text("Your server hasn't found any scenes to show yet. Try again in a little while."))
        case .unavailable(let reason):
            message(title: "Arcs Isn't Available", icon: "play.slash",
                    text: reason.map { Text(verbatim: $0) } ?? Text("Your server's admin hasn't turned on Arcs for you."))
        case .failed:
            VStack(spacing: 14) {
                message(title: "Couldn't Load Arcs", icon: "wifi.exclamationmark", text: Text("Couldn't reach your server. Check your connection, then try again."))
                Button("Try Again") { Task { await model.reload() } }.buttonStyle(.glass)
                if !ArcsOfflineStore.shared.clips.isEmpty, !model.isOffline {
                    Button { showSaved = true } label: { Label("Watch Saved Scenes", systemImage: "arrow.down.circle") }
                        .buttonStyle(.glassProminent)
                        .tint(DT.Color.accent)
                        .foregroundStyle(DT.Color.onAccent)
                }
            }
        case .ready:
            feed(bottomInset: bottomInset)
        }
    }

    private func feed(bottomInset: Double) -> some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(model.clips) { clip in
                    Group {
                        if clip.isRequest {
                            ArcsRequestPage(clip: clip, model: model, isCurrent: clip.id == model.currentID, bottomInset: bottomInset, actions: actions)
                        } else {
                            ArcClipPage(clip: clip, model: model, isCurrent: clip.id == model.currentID, bottomInset: bottomInset,
                                        pictureInPictureRequest: pictureInPicture, actions: actions)
                        }
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(clip.id)
                }
                if model.isLoadingMore {
                    ProgressView().tint(.white).containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $model.currentID)
        .scrollIndicators(.hidden)
        .refreshable { await model.reload() }
    }

    private var actions: ArcClipActions {
        ArcClipActions(
            watchFromHere: { clip in
                Task {
                    guard let item = await model.mediaItem(for: clip) else { return }
                    let elapsed = model.playback(for: clip)?.elapsed ?? 0
                    model.noteWatchFromHere(clip)
                    pauseForCover()
                    playback = PlaybackRequest(item: item, startTicks: clip.startTicks + Int64(elapsed * 10_000_000))
                }
            },
            openTitle: { clip in
                Task {
                    guard let item = await model.seriesItem(for: clip) else { return }
                    model.noteOpenedTitle(clip)
                    openedItem = item
                }
            },
            share: { clip in
                pauseForCover()
                sharing = clip
            },
            addToPlaylist: { clip in
                Task {
                    guard let item = await model.mediaItem(for: clip) else { return }
                    PlaylistStore.shared.addingItem = item
                }
            },
            shuffleShow: { clip in
                pauseForCover()
                showShow = clip
            },
            pictureInPicture: { _ in pictureInPicture += 1 },
            discover: seerrRepo.isConfigured ? { clip in
                Task {
                    guard let item = await model.seriesItem(for: clip), let tmdb = item.tmdbId else {
                        model.toast = "This title isn't on Discover."
                        return
                    }
                    discoverItem = SeerrItem(id: tmdb, title: item.name, mediaType: item.type == .movie ? .movie : .tv)
                }
            } : nil,
            startEpisode: { clip in
                Task {
                    guard let item = await model.mediaItem(for: clip) else { return }
                    model.noteStartEpisode(clip)
                    pauseForCover()
                    playback = PlaybackRequest(item: item, startTicks: 0)
                }
            },
            // The server says if sending is off for this person, in the send sheet.
            send: model.isOffline || model.availability?.sending != true ? nil : { clip in
                pauseForCover()
                sendingClip = clip
            },
            request: { clip in
                guard let item = seerrItem(clip) else { return }
                model.noteRequested(clip)
                pauseForCover()
                requestingItem = item
            },
            requestDetails: { clip in
                guard let item = seerrItem(clip) else { return }
                discoverItem = item
            }
        )
    }

    private func seerrItem(_ clip: ArcClip) -> SeerrItem? {
        guard let tmdb = clip.tmdbId else { return nil }
        return SeerrItem(id: tmdb, title: clip.name, mediaType: clip.mediaType == "tv" ? .tv : .movie,
                         posterPath: clip.posterPath, backdropPath: clip.backdropPath, year: clip.year.map(String.init),
                         overview: clip.overview)
    }

    /// Plays only while the feed is on screen, the app is active and it isn't asking to be turned upright.
    private func updateVisibility() {
        model.isVisible = isOnScreen && scenePhase == .active && !asksToRotate
    }

    private func pauseForCover() {
        resumeAfterCover = !model.isPaused
        model.isPaused = true
    }

    private func resume() {
        if resumeAfterCover { model.isPaused = false }
        resumeAfterCover = false
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 10) {
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark").font(.subheadline.weight(.semibold))
                        .frame(width: Self.barHeight, height: Self.barHeight)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            } else if !model.isOffline, model.availability?.dialogueSearch == true {
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass").font(.subheadline.weight(.semibold))
                        .frame(width: Self.barHeight, height: Self.barHeight)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Search Scenes by What's Said"))
            } else {
                Color.clear.frame(width: Self.barHeight, height: Self.barHeight)
            }
            Spacer()
            if showsFeedPicker { feedPicker }
            Spacer()
            Menu {
                Button { airPlay.show() } label: { Label("AirPlay", systemImage: "airplay.video") }
                Divider()
                Button { showLiked = true } label: { Label("Liked Scenes", systemImage: "heart") }
                if !ArcsOfflineStore.shared.clips.isEmpty, !model.isOffline {
                    Button { pauseForCover(); showSaved = true } label: { Label("Saved Scenes", systemImage: "arrow.down.circle") }
                }
                Button { showHidden = true } label: { Label("Hidden Titles", systemImage: "eye.slash") }
                Button { showSettings = true } label: { Label("Arcs Settings", systemImage: "gearshape") }
            } label: {
                Image(systemName: "ellipsis").font(.subheadline.weight(.semibold))
                    .frame(width: Self.barHeight, height: Self.barHeight)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Arcs Menu"))
            // The system's AirPlay picker, out of sight: the menu's AirPlay item opens it.
            ArcsAirPlayButton(trigger: airPlay)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .foregroundStyle(.white)
    }

    private var feedPicker: some View {
        HStack(spacing: 22) {
            feedButton(.continue, "Continue")
            feedButton(.forYou, "For You")
            feedButton(.discover, "Discover")
        }
        .padding(.horizontal, 22)
        // As tall as the buttons beside it.
        .frame(height: Self.barHeight)
        .glassEffect(.regular, in: Capsule())
    }

    /// Narrows For You to a mood; tapping the chosen one again shows everything.
    private var moodChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(ArcsMood.allCases) { mood in
                    let chosen = model.mood == mood
                    Button {
                        HapticManager.selection()
                        model.switchMood(to: chosen ? nil : mood)
                    } label: {
                        Text(ArcText.label(mood))
                            .font(.caption.weight(chosen ? .bold : .medium))
                            .foregroundStyle(chosen ? DT.Color.onAccent : .white)
                            .padding(.horizontal, 12)
                            .frame(height: 30)
                            .background { if chosen { Capsule().fill(DT.Color.accent) } }
                            .glassEffect(chosen ? .identity : .regular, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollIndicators(.hidden)
    }

    private func feedButton(_ feed: ArcsFeed, _ title: LocalizedStringKey) -> some View {
        Button {
            HapticManager.selection()
            model.switchFeed(to: feed)
        } label: {
            Text(title)
                .font(.footnote.weight(model.feed == feed ? .bold : .medium))
                .foregroundStyle(.white.opacity(model.feed == feed ? 1 : 0.6))
                .overlay(alignment: .bottom) {
                    if model.feed == feed { Capsule().fill(.white).frame(width: 18, height: 2).offset(y: 5) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.feed == feed ? .isSelected : [])
    }

    private func toastView(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: Capsule())
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func message(title: LocalizedStringKey, icon: String, text: Text) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            text
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A film or show whose scenes open in Arcs.
struct ArcsTitle: Identifiable {
    let id: String
}

/// AirPlay for the scene on screen.
struct ArcsAirPlayButton: UIViewRepresentable {
    let trigger: ArcsAirPlayTrigger

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        trigger.picker = picker
        return picker
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}

/// Arcs is made for holding the device upright, as Pick Together is: this asks, and can be skipped.
private struct ArcsRotatePrompt: View {
    var skip: () -> Void

    private var device: String {
        UIDevice.current.userInterfaceIdiom == .pad ? String(localized: "iPad") : String(localized: "iPhone")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: DT.Spacing.md) {
                Image(systemName: "rectangle.portrait.rotate")
                    .font(.system(size: 56))
                    .foregroundStyle(DT.Color.accent)
                    .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2)))
                    .accessibilityHidden(true)
                Text("Turn Your \(device) Upright")
                    .font(DT.Font.sectionTitle)
                    .multilineTextAlignment(.center)
                Text("Arcs works best in portrait, with one scene at a time to swipe.")
                    .font(DT.Font.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                Button("Continue in Landscape", action: skip)
                    .buttonStyle(.bordered)
                    .tint(DT.Color.accent)
                    .padding(.top, DT.Spacing.xs)
            }
            .foregroundStyle(.white)
            .padding(DT.Spacing.xl)
            .frame(maxWidth: 480)
        }
    }
}

/// Opens the AirPlay picker from a menu item: the picker only opens from its own button.
@MainActor
final class ArcsAirPlayTrigger {
    weak var picker: AVRoutePickerView?

    func show() {
        picker?.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .touchUpInside)
    }
}
