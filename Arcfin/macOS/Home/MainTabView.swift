// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AppKit
import JellyfinAPI
import SeerrAPI

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
                         isAdmin: authManager.isAdmin, limit: tabLimit)
    }

    private var tabLimit: Int { BottomNavPrefs.maxActiveRegular }

    @ViewBuilder
    private func tabDestination(_ tab: BottomNavItem) -> some View {
        switch tab {
        case .home:      HomeView()
        case .browse:    LibraryView()
        case .stats:     StatsView()
        case .requests:  SeerrView()
        case .watchlist: NavigationStack { WatchlistView() }
        case .admin:     NavigationStack { AdminView() }
        case .arcs:      EmptyView()
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if AppServices.music.isActive { MusicPlayerBar() }
            }
            // The tab sidebar's own toggle ends up in the toolbar's overflow menu at the far
            // right, and `.toolbar(removing: .sidebarToggle)` doesn't reach it, so it's taken
            // off the window's toolbar and Arcfin's own sits at the leading edge instead.
            .background(WindowAccessor { SystemSidebarToggle.remove(from: $0) })
            // Artwork runs up under a clear toolbar, as in Apple's own media apps, with a soft
            // fade at the edge rather than the default hard strip.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                    } label: {
                        Image(systemName: "sidebar.leading")
                    }
                    .accessibilityLabel("Toggle Sidebar")
                    .help("Show or hide the sidebar")
                }
            }
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
                // A route that came in before the tabs were up: Library and Home take it from here.
                if UserDefaults.standard.bool(forKey: "arcfin.pendingShowDownloads") { selectedTab = .browse }
                if UserDefaults.standard.string(forKey: "arcfin.pendingPlayID") != nil { selectedTab = .home }
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
            .onReceive(NotificationCenter.default.publisher(for: .arcfinSelectTab)) { note in
                guard let raw = note.userInfo?["tab"] as? String, let tab = BottomNavItem(rawValue: raw),
                      visibleTabs.contains(tab) else { return }
                selectedTab = tab
            }
            .onReceive(NotificationCenter.default.publisher(for: .arcfinOpenFile)) { _ in
                UserDefaults.standard.set(true, forKey: "arcfin.pendingOpenFile")
                selectedTab = .browse
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
        .environment(MediaRepository())
        .environment(SeerrRepository())
}

/// Takes the tab sidebar's own toggle off the window's toolbar, and again whenever SwiftUI
/// rebuilds the toolbar (switching tabs does).
@MainActor
private enum SystemSidebarToggle {
    private static var observer: NSObjectProtocol?

    static func remove(from window: NSWindow?) {
        if let toolbar = window?.toolbar { removeItems(from: toolbar) }
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: NSToolbar.willAddItemNotification, object: nil, queue: .main) { note in
            // Delivered on the main queue: the toolbar and its items are the main actor's.
            MainActor.assumeIsolated {
                guard let item = note.userInfo?["item"] as? NSToolbarItem, isSystemToggle(item),
                      let toolbar = note.object as? NSToolbar
                else { return }
                // Still being added at this point; take it off once it's in.
                DispatchQueue.main.async { removeItems(from: toolbar) }
            }
        }
    }

    private static func removeItems(from toolbar: NSToolbar) {
        for index in toolbar.items.indices.reversed() where isSystemToggle(toolbar.items[index]) {
            toolbar.removeItem(at: index)
        }
    }

    private static func isSystemToggle(_ item: NSToolbarItem) -> Bool {
        item.itemIdentifier == .toggleSidebar
            || item.itemIdentifier.rawValue.localizedCaseInsensitiveContains("togglesidebar")
            || item.itemIdentifier.rawValue.localizedCaseInsensitiveContains("sidebartoggle")
            || item.action == #selector(NSSplitViewController.toggleSidebar(_:))
    }
}
