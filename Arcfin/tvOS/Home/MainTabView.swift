// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI

struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(MediaRepository.self) private var mediaRepo
    @Bindable private var playlistStore = PlaylistStore.shared
    @State private var searchQuery = ""
    @AppStorage(BottomNavPrefs.activeKey) private var activeString = ""

    var body: some View {
        if mediaRepo.connectionFailed && !mediaRepo.hasAnyContent {
            NoConnectionView()
        } else {
            TabView {
                Tab("Home", systemImage: "house") {
                    HomeView()
                }
                Tab("Library", systemImage: "square.grid.2x2") {
                    LibraryView()
                }
                // Declared right after Library so it renders right after Library — on-device
                // testing showed role: .search does NOT always pin to the far end of the bar
                // regardless of declaration order the way it was previously assumed to.
                Tab("Search", systemImage: "magnifyingglass", role: .search) {
                    NavigationStack {
                        SearchView(query: $searchQuery)
                            .searchable(text: $searchQuery, prompt: "Movies, shows, people…")
                            .screenBackground()
                            .navigationDestination(for: MediaItem.self) { item in
                                MediaDetailView(item: item)
                            }
                            .navigationDestination(for: SeerrItem.self) { item in
                                SeerrItemDetailView(item: item)
                            }
                    }
                }
                Tab("Requests", systemImage: "clock") {
                    SeerrView()
                }
                if BottomNavPrefs.active(from: activeString).contains(.stats) {
                    Tab("Stats", systemImage: "chart.xyaxis.line") {
                        StatsView()
                    }
                }
                Tab("Settings", systemImage: seerrRepo.authFailed ? "person.crop.circle.badge.exclamationmark" : "person.circle") {
                    NavigationStack { SettingsView() }
                }
            }
            // Suppress the system white focus halo across all screens.
            // The focus ENGINE still works (remote nav, isFocused env); only
            // the system visual highlight is replaced by per-element custom styling.
            .focusEffectDisabled()
            .appSheet(item: $playlistStore.addingItem) { item in
                AddToPlaylistSheet(item: item)
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
