// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import MediaEngine
import JellyfinAPI
import SeerrAPI
import CastKit

struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(MediaRepository.self) private var mediaRepo
    @Bindable private var playlistStore = PlaylistStore.shared
    @Bindable private var musicPlaylists = MusicPlaylistEditor.shared
    @Bindable private var tagEditor = TagEditor.shared
    @Bindable private var metadataEditor = MetadataEditor.shared
    @AppStorage(BottomNavPrefs.orderKey) private var orderString = ""
    @AppStorage(BottomNavPrefs.activeKey) private var activeString = ""
    @AppStorage(StreamBadge.key) private var showsStreamBadge = false
    @State private var selectedTab = BottomNavItem(rawValue: UserDefaults.standard.string(forKey: BottomNavPrefs.launchTabKey) ?? "") ?? .home

    private var visibleTabs: [BottomNavItem] {
        MainTabs.visible(orderString: orderString, activeString: activeString, seerrConfigured: seerrRepo.isConfigured,
                         isAdmin: authManager.isAdmin, arcsAvailable: authManager.arcfinSyncStatus?.isOn("arcs") == true,
                         limit: tabLimit)
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    private var tabLimit: Int { sizeClass == .compact ? BottomNavPrefs.maxActiveCompact : BottomNavPrefs.maxActiveRegular }

    @ViewBuilder
    private func tabDestination(_ tab: BottomNavItem) -> some View {
        switch tab {
        case .home:      HomeView()
        case .browse:    LibraryView()
        case .stats:     StatsView()
        case .requests:  SeerrView()
        case .watchlist: NavigationStack { WatchlistView() }
        case .admin:     NavigationStack { AdminView() }
        case .arcs:      ArcsTab()
        }
    }

    var body: some View {
        if mediaRepo.connectionFailed && !mediaRepo.hasAnyContent {
            NoConnectionView()
        } else {
            TabView(selection: $selectedTab) {
                ForEach(visibleTabs) { tab in
                    Tab(tab.title, systemImage: tab.icon, value: tab) {
                        tabDestination(tab)
                    }
                    // Scenes friends sent that haven't been watched.
                    .badge(tab == .arcs ? ArcsBadge.shared.unseen : 0)
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .adminTabOffer(limit: tabLimit)
            .arcsTabOffer(limit: tabLimit)
            .task(id: visibleTabs.contains(.arcs)) {
                if visibleTabs.contains(.arcs) { ArcsPrefetch.shared.start(authManager: authManager) }
            }
            .task(id: ArcsBadgeKey(arcs: visibleTabs.contains(.arcs), active: scenePhase == .active)) {
                if visibleTabs.contains(.arcs), scenePhase == .active { await ArcsBadge.shared.refresh(authManager: authManager) }
            }
            // The playing-streams badge, kept current while Arcfin is open.
            .task(id: showsStreamBadge && authManager.isAdmin) {
                if showsStreamBadge && authManager.isAdmin { await StreamBadge.keepCurrent() } else { await StreamBadge.refresh() }
            }
            .onChange(of: visibleTabs) { if !visibleTabs.contains(selectedTab) { selectedTab = .home } }
            .sheet(item: $tagEditor.item) { item in
                EditTagsSheet(item: item)
            }
            .sheet(item: $metadataEditor.item) { item in
                AdminMetadataEditor(item: item)
            }
            .sheet(item: $playlistStore.addingItem) { item in
                AddToPlaylistSheet(item: item)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $musicPlaylists.request) { request in
                MusicAddToPlaylistSheet(songs: request.songs)
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: selectedTab) { old, _ in
                if old == .home { NotificationCenter.default.post(name: .arcfinHomeTabLeft, object: nil) }
            }
            // The launch tab can be one that's since been turned off, or needs Seerr.
            .onAppear {
                if !visibleTabs.contains(selectedTab) { selectedTab = .home }
            }
            // Arcs fills the screen with its own video; the bar would sit over its controls.
            .modifier(CastMiniControllerAccessory(hidden: selectedTab == .arcs))
            // arcfin://downloads — from the download Live Activity's tap target.
            .onReceive(NotificationCenter.default.publisher(for: .arcfinShowMusic)) { _ in
                selectedTab = .browse
            }
            .onReceive(NotificationCenter.default.publisher(for: .arcfinShowDownloads)) { _ in
                selectedTab = .browse
            }
            // A Seerr notification tap: Discover when that tab is on, otherwise Browse.
            .onReceive(NotificationCenter.default.publisher(for: .arcfinShowDiscover)) { _ in
                UserDefaults.standard.removeObject(forKey: "arcfin.pendingDiscover")
                selectedTab = visibleTabs.contains(.requests) ? .requests : .browse
            }
            .onAppear {
                if UserDefaults.standard.bool(forKey: "arcfin.pendingDiscover") {
                    UserDefaults.standard.removeObject(forKey: "arcfin.pendingDiscover")
                    selectedTab = visibleTabs.contains(.requests) ? .requests : .browse
                }
                // A route that came in before the tabs were up: Library and Home take it from here.
                if UserDefaults.standard.bool(forKey: "arcfin.pendingShowDownloads") { selectedTab = .browse }
                if UserDefaults.standard.string(forKey: "arcfin.pendingPlayID") != nil { selectedTab = .home }
                if UserDefaults.standard.string(forKey: ArcsDeepLink.pendingKey) != nil
                    || UserDefaults.standard.string(forKey: ArcsDeepLink.pendingFriendKey) != nil { selectedTab = .home }
            }
            // Siri / Shortcuts search: results are shown by the Browse tab.
            .onReceive(NotificationCenter.default.publisher(for: .arcfinSearch)) { _ in
                selectedTab = .browse
            }
            // The Resume Watching control plays from Home.
            .onReceive(NotificationCenter.default.publisher(for: .arcfinResume)) { _ in
                selectedTab = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: WatchRoute.notification)) { _ in
                selectedTab = .home
            }
            // A title to play from a notification, widget, Siri or another device: Home plays it.
            .onReceive(NotificationCenter.default.publisher(for: .arcfinPlayItem)) { _ in
                selectedTab = .home
            }
            // The Scene of the Day widget: Home opens the scene in Arcs.
            .onReceive(NotificationCenter.default.publisher(for: .arcfinOpenArcs)) { _ in
                selectedTab = .home
            }
        }
    }
}

private struct ArcsBadgeKey: Equatable {
    let arcs: Bool
    let active: Bool
}

/// `isEnabled:` arrived in iOS 26.1; the older overload can't hide the bar, so on 26.0
/// there is no mini controller rather than a permanently empty accessory.
private struct CastMiniControllerAccessory: ViewModifier {
    var hidden = false
    /// A video on a Chromecast; music on one keeps the music bar.
    private var casting: Bool {
        CastManager.shared.isConnected && CastManager.shared.nowPlayingTitle != nil && !AppServices.music.isCasting
    }
    @Namespace private var musicTransition
    /// Music playing here goes first; paused, it gives the bar to another device that's playing.
    private var showsMusicBar: Bool {
        AppServices.music.isActive && (AppServices.music.isPlaying || AppServices.remoteSessions.selected == nil)
    }

    func body(content: Content) -> some View {
        accessory(content)
            .onChange(of: AppServices.remoteSessions.refreshCount) {
                Task { await RemotePlaybackActivity.shared.sync() }
            }
    }

    @ViewBuilder
    private func accessory(_ content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: !hidden && (casting || AppServices.music.isActive
                                           || AppServices.remoteSessions.selected != nil)) {
                // Casting from here comes first, then music on this device, then another
                // device playing on this profile.
                if casting {
                    CastMiniController()
                } else if showsMusicBar || AppServices.remoteSessions.selected == nil {
                    MusicMiniPlayer(isExpanded: Binding(get: { AppServices.music.isNowPlayingOpen },
                                                        set: { AppServices.music.isNowPlayingOpen = $0 }))
                        .matchedTransitionSource(id: "music", in: musicTransition)
                } else {
                    RemoteMiniController()
                }
            }
            .sheet(isPresented: Binding(get: { AppServices.music.isNowPlayingOpen },
                                        set: { AppServices.music.isNowPlayingOpen = $0 })) {
                MusicNowPlayingView()
                    .navigationTransition(.zoom(sourceID: "music", in: musicTransition))
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(.black)
            }
            .fullScreenCover(isPresented: Binding(get: { AppServices.remoteSessions.isShowingRemote },
                                                  set: { AppServices.remoteSessions.isShowingRemote = $0 })) {
                RemoteControllerView()
            }
        } else {
            content
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
        .environment(MediaRepository())
        .environment(SeerrRepository())
}
