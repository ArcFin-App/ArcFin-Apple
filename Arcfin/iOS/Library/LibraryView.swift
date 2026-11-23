// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

struct LibraryView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var model = LibraryModel()
    @State private var isSearchPresented = false

    private var isWide: Bool { horizontalSizeClass == .regular }

    private var gridColumns: [GridItem] {
        if isWide {
            return [GridItem(.adaptive(minimum: 240), spacing: 12)]
        }
        return [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
    }

    private var supportedLibraries: [JellyfinLibrary] { LibraryModel.libraries(in: mediaRepo, includeLiveTV: ProfileRules.shared.canWatchLiveTV, includeMusic: true) }

    var body: some View {
        NavigationStack {
            Group {
                // Kept on screen while the field is active, so Recent Searches can show before
                // anything is typed.
                if model.searchQuery.isEmpty && !isSearchPresented {
                    browseContent
                } else {
                    SearchView(query: $model.searchQuery)
                }
            }
            .screenBackground()
            // An album or artist opened from Now Playing.
            .navigationDestination(item: Binding(get: { MusicNavigator.shared.route },
                                                 set: { MusicNavigator.shared.route = $0 })) { route in
                MusicDestination(route: route)
            }
            .navigationTitle("Browse")
            .toolbar { browseFilesButton }
            .searchable(text: $model.searchQuery, isPresented: $isSearchPresented, prompt: "Movies, shows, music, live TV, people…")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: JellyfinLibrary.self) { library in
                libraryDestination(library)
            }
            // On the Mac a tile's NavigationLink(value:) can't find the destination above.
            .navigationDestination(item: $model.openedLibrary) { library in
                libraryDestination(library)
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
            .sheet(isPresented: $model.showDocPicker) {
                DocumentPickerView { url in
                    model.play(url)
                }
            }
            .navigationDestination(isPresented: $model.navigateToLocalPlayer) {
                if let url = model.pickedURL {
                    PlayerView(fileURL: url)
                        .toolbar(.hidden, for: .navigationBar)
                        .toolbar(.hidden, for: .tabBar)
                }
            }
            .navigationDestination(isPresented: $model.navigateToDownloadsDeepLink) {
                DownloadsView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .arcfinSearch)) { note in
                model.search(from: note)
            }
            .onAppear {
                model.applyPendingRequests()
            }
            // arcfin://downloads — the download Live Activity or the Downloads control.
            .onReceive(NotificationCenter.default.publisher(for: .arcfinShowDownloads)) { _ in
                model.showDownloads()
            }
        }
    }

    @ViewBuilder
    private func libraryDestination(_ library: JellyfinLibrary) -> some View {
        if library.collectionType == .livetv {
            LiveTVView(library: library)
        } else if library.collectionType == .music {
            MusicLibraryView(library: library)
        } else {
            LibraryDetailView(library: library)
        }
    }

    private var browseContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                // ── Your Libraries ──────────────────────────────────────
                if !supportedLibraries.isEmpty {
                    librariesSection
                } else {
                    BrowseLibrariesStatus()
                }

                // ── Downloads ───────────────────────────────────────────
                downloadsSection
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        // Libraries added or removed on the server since Home last loaded.
        .refreshable {
            guard case .authenticated(let cred) = authManager.state else { return }
            await mediaRepo.load(credential: cred, authClient: authManager.authClient, force: true)
        }
    }

    // MARK: - Libraries section

    private var librariesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionHeader(title: "Your Libraries")
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(supportedLibraries) { library in
                    libraryLink(library) {
                        LibraryCard(library: library, imageURL: mediaRepo.libraryBackdropURL(for: library))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func libraryLink<Label: View>(_ library: JellyfinLibrary, @ViewBuilder label: () -> Label) -> some View {
        // A library opened from a binding sits above the path, so titles pushed onto the
        // path from inside it would land underneath.
        NavigationLink(value: library) { label() }
    }

    // MARK: - Downloads section

    private var downloadsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LibrarySectionHeader(title: "Downloads")
            LazyVGrid(columns: gridColumns, spacing: 12) {
                NavigationLink {
                    DownloadsView()
                } label: {
                    BrowseIconTile(systemImage: "arrow.down.circle.fill", title: "Movies & Shows")
                }
                .buttonStyle(.plain)
                if !MusicDownloads.shared.isEmpty {
                    NavigationLink {
                        MusicDownloadsView()
                    } label: {
                        BrowseIconTile(systemImage: "music.note", title: "Music")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // A video file on this device, played without the server.
    private var browseFilesButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.showDocPicker = true
            } label: {
                Label("Browse Files", systemImage: "folder")
            }
            .help("Play a video file from this device")
        }
    }
}
