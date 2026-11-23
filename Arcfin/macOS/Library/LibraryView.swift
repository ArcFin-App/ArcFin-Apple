// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(MediaRepository.self) private var mediaRepo

    @State private var model = LibraryModel()
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool

    private var gridColumns: [GridItem] {
        // Fixed 2-up stretches library cards absurdly wide on a resizable Mac window —
        // adaptive reflows into more columns as it grows instead.
        [GridItem(.adaptive(minimum: 220), spacing: 12)]
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
            .navigationTitle("Browse")
            .toolbar { browseFilesButton }
            .searchable(text: $model.searchQuery, isPresented: $isSearchPresented, prompt: "Movies, shows, music, live TV, people…")
            .searchFocused($isSearchFocused)
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
            .onReceive(NotificationCenter.default.publisher(for: .arcfinOpenFile)) { _ in
                model.openFileRequested()
            }
            .onAppear {
                model.openPendingFile()
            }
            .fileImporter(isPresented: $model.showDocPicker, allowedContentTypes: UTType.playableVideo) { result in
                guard case .success(let url) = result else { return }
                model.play(url)
            }
            .navigationDestination(isPresented: $model.navigateToLocalPlayer) {
                if let url = model.pickedURL {
                    PlayerView(fileURL: url)
                }
            }
            .navigationDestination(isPresented: $model.navigateToDownloadsDeepLink) {
                DownloadsView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .arcfinSearch)) { note in
                model.search(from: note)
                focusSearchIfPending()
            }
            .onAppear {
                focusSearchIfPending()
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
    }

    private func focusSearchIfPending() {
        if model.takePendingFindFocus() { isSearchFocused = true }
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
        Button { model.openedLibrary = library } label: { label() }
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
