// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI

struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(MediaRepository.self) private var mediaRepo
    @Bindable private var playlistStore = PlaylistStore.shared
    @Bindable private var musicPlaylists = MusicPlaylistEditor.shared
    @Bindable private var tagEditor = TagEditor.shared
    @State private var searchQuery = ""
    @AppStorage(BottomNavPrefs.activeKey) private var activeString = ""
    @Bindable private var music = TVMusicPresenter.shared
    /// Each tab by name, so Now Playing coming and going doesn't move the selection.
    @State private var selection = "home"
    /// Asked for before the music had started, so its tab wasn't there yet.
    @State private var wantsNowPlaying = false

    var body: some View {
        if mediaRepo.connectionFailed && !mediaRepo.hasAnyContent {
            NoConnectionView()
        } else {
            TabView(selection: $selection) {
                // While music is playing or paused, its Now Playing is a tab of its own.
                if AppServices.music.isActive {
                    Tab("Now Playing", systemImage: "waveform", value: "nowPlaying") {
                        TVMusicNowPlaying()
                    }
                }
                Tab("Home", systemImage: "house", value: "home") {
                    HomeView()
                }
                Tab("Library", systemImage: "square.grid.2x2", value: "library") {
                    LibraryView()
                }
                // Declared right after Library so it renders right after Library — on-device
                // testing showed role: .search does NOT always pin to the far end of the bar
                // regardless of declaration order the way it was previously assumed to.
                Tab("Search", systemImage: "magnifyingglass", value: "search", role: .search) {
                    NavigationStack {
                        SearchView(query: $searchQuery)
                            .searchable(text: $searchQuery, prompt: "Movies, shows, music, live TV, people…")
                            .screenBackground()
                            .navigationDestination(for: MediaItem.self) { item in
                                MediaDetailView(item: item)
                            }
                            .navigationDestination(for: SeerrItem.self) { item in
                                SeerrItemDetailView(item: item)
                            }
                            .musicDestinations()
                    }
                }
                Tab(BottomNavItem.requests.title, systemImage: BottomNavItem.requests.icon, value: "requests") {
                    SeerrView()
                }
                if BottomNavPrefs.active(from: activeString).contains(.stats) {
                    Tab("Stats", systemImage: "chart.xyaxis.line", value: "stats") {
                        StatsView()
                    }
                }
                Tab("Settings", systemImage: seerrRepo.authFailed ? "person.crop.circle.badge.exclamationmark" : "person.circle",
                    value: "settings") {
                    NavigationStack { SettingsView() }
                }
            }
            // Suppress the system white focus halo across all screens.
            // The focus ENGINE still works (remote nav, isFocused env); only
            // the system visual highlight is replaced by per-element custom styling.
            .focusEffectDisabled()
            .onPlayPauseCommand { music.playPausePressed() }
            // The music stopped while its tab was showing: back to Home.
            .onChange(of: AppServices.music.isActive) { _, active in
                if active, wantsNowPlaying { selection = "nowPlaying" }
                wantsNowPlaying = false
                if !active, selection == "nowPlaying" { selection = "home" }
            }
            // Starting a song, or Play/Pause on the remote, brings the Now Playing tab forward.
            .onChange(of: music.isShowingNowPlaying) { _, show in
                guard show else { return }
                music.isShowingNowPlaying = false
                if AppServices.music.isActive { selection = "nowPlaying" } else { wantsNowPlaying = true }
            }
            // A title to play from Siri, the Top Shelf or another device: Home plays it.
            .onReceive(NotificationCenter.default.publisher(for: .arcfinPlayItem)) { _ in
                selection = "home"
            }
            .onAppear {
                if UserDefaults.standard.string(forKey: "arcfin.pendingPlayID") != nil { selection = "home" }
            }
            .appSheet(item: $tagEditor.item, title: "Tags", systemImage: "tag") { item in
                EditTagsSheet(item: item)
            }
            .appSheet(item: $playlistStore.addingItem, title: "Add to Playlist", systemImage: "text.badge.plus") { item in
                AddToPlaylistSheet(item: item)
            }
            .appSheet(item: $musicPlaylists.request, title: "Add to Playlist", systemImage: "text.badge.plus") { request in
                MusicAddToPlaylistSheet(songs: request.songs)
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
