// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI
import CastKit

struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(MediaRepository.self) private var mediaRepo
    @Bindable private var playlistStore = PlaylistStore.shared
    @Bindable private var tagEditor = TagEditor.shared
    @Bindable private var metadataEditor = MetadataEditor.shared
    @AppStorage(BottomNavPrefs.orderKey) private var orderString = ""
    @AppStorage(BottomNavPrefs.activeKey) private var activeString = ""
    @AppStorage(StreamBadge.key) private var showsStreamBadge = false
    @State private var selectedTab = BottomNavItem(rawValue: UserDefaults.standard.string(forKey: BottomNavPrefs.launchTabKey) ?? "") ?? .home

    private var visibleTabs: [BottomNavItem] {
        MainTabs.visible(orderString: orderString, activeString: activeString, seerrConfigured: seerrRepo.isConfigured,
                         isAdmin: authManager.isAdmin, limit: tabLimit)
    }

    @Environment(\.horizontalSizeClass) private var sizeClass
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
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .adminTabOffer(limit: tabLimit)
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
            .onChange(of: selectedTab) { old, _ in
                if old == .home { NotificationCenter.default.post(name: .arcfinHomeTabLeft, object: nil) }
            }
            // The launch tab can be one that's since been turned off, or needs Seerr.
            .onAppear {
                if !visibleTabs.contains(selectedTab) { selectedTab = .home }
            }
            .modifier(CastMiniControllerAccessory())
            // arcfin://downloads — from the download Live Activity's tap target.
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
        }
    }
}

/// `isEnabled:` arrived in iOS 26.1; the older overload can't hide the bar, so on 26.0
/// there is no mini controller rather than a permanently empty accessory.
private struct CastMiniControllerAccessory: ViewModifier {
    private var casting: Bool { CastManager.shared.isConnected && CastManager.shared.nowPlayingTitle != nil }

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: casting || AppServices.remoteSessions.selected != nil) {
                // Casting from here comes first; otherwise another device playing on this profile.
                if casting { CastMiniController() } else { RemoteMiniController() }
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
