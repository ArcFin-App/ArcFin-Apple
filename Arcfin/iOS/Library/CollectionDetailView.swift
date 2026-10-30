// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

struct CollectionDetailView: View {
    let collection: MediaItem

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var model = CollectionModel()
    @AppStorage("collectionSort") private var sort = CollectionSort.release
    @AppStorage("collectionShowsGrid") private var showsGrid = false
    @Namespace private var zoomNamespace

    private var isWide: Bool { horizontalSizeClass == .regular }

    private var columns: [GridItem] {
        if isWide {
            return [GridItem(.adaptive(minimum: 150), spacing: 12)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    }

    var body: some View {
        CollectionContent(collection: collection, model: model, sort: $sort, showsGrid: $showsGrid,
                          columns: columns, zoomNamespace: zoomNamespace)
        .detailPageBackground(tint: model.heroTint)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationDestination(item: $model.selectedItem) { item in
            MediaDetailView(item: item, zoomNamespace: zoomNamespace)
                .zoomNavigationTransition(id: item.id, in: zoomNamespace)
        }
        .navigationDestination(item: $model.selectedPerson) { person in
            PersonDetailView(person: person)
        }
        .task { await model.load(collection, authManager: authManager) }
        .task(id: collection.id) {
            await model.loadHeroTint(collection, mediaRepo: mediaRepo)
        }
        .fullScreenCover(item: $model.playbackRequest, onDismiss: {
            PlayQueue.clear()
            Task { await model.load(collection, authManager: authManager) }
        }) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                PlayerView.keepOrientationOnNextDisappear = true
                model.playbackRequest = MediaDetailView.PlaybackRequest(item: next, startTicks: 0)
            }
            .id(request.item.id)
        }
    }
}
