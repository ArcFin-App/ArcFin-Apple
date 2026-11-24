// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

struct LibraryView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @State private var watchParty: WatchPartyLaunch?
    @State private var playbackRequest: Arcfin.PlaybackRequest?

    private let columns = [GridItem(.adaptive(minimum: 400), spacing: 20)]

    private var libraries: [JellyfinLibrary] { LibraryModel.libraries(in: mediaRepo, includeLiveTV: ProfileRules.shared.canWatchLiveTV, includeMusic: true) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if libraries.isEmpty, mediaRepo.connectionFailed || !mediaRepo.loaded {
                        BrowseLibrariesStatus()
                            .frame(maxWidth: .infinity, minHeight: 400)
                    } else if libraries.isEmpty {
                        ContentUnavailableView(
                            "No Libraries",
                            systemImage: "square.grid.2x2",
                            description: Text("Your Jellyfin libraries will appear here.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 400)
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(libraries) { library in
                                NavigationLink(value: library) {
                                    LibraryCard(library: library, imageURL: mediaRepo.libraryBackdropURL(for: library, fillWidth: 960))
                                }
                                .buttonStyle(TVCardButtonStyle())
                                .focusEffectDisabled()
                            }
                            if WatchPartyDetailButton.isAvailable(authManager) {
                                Button { watchParty = WatchPartyLaunch(.join(code: nil)) } label: {
                                    BrowseIconTile(systemImage: "person.3.sequence", title: "Watch Party")
                                }
                                .buttonStyle(TVCardButtonStyle())
                                .focusEffectDisabled()
                            }
                        }
                        .padding(.horizontal, 80)
                        .padding(.top, 48)
                        .padding(.bottom, 60)
                        .focusSection()
                    }
                }
            }
            .screenBackground()
            .watchPartyCover($watchParty) { playbackRequest = $0 }
            .fullScreenCover(item: $playbackRequest) { request in
                PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                    playbackRequest = Arcfin.PlaybackRequest(item: next, startTicks: 0)
                }
                .id(request.item.id)
            }
            .navigationDestination(for: JellyfinLibrary.self) { library in
                if library.collectionType == .livetv {
                    LiveTVView(library: library)
                } else if library.collectionType == .music {
                    TVMusicLibraryView(library: library)
                } else {
                    LibraryDetailView(library: library)
                }
            }
            .navigationDestination(for: MediaItem.self) { item in
                MediaDetailView(item: item)
            }
            .musicDestinations()
            .navigationDestination(for: LibraryNavTarget.self) { target in
                switch target {
                case .media(let item):       MediaDetailView(item: item)
                case .collection(let item):  CollectionDetailView(collection: item)
                case .playlist(let item):    LibraryDetailView(playlistItem: item)
                }
            }
        }
    }
}
