// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

struct CollectionDetailView: View {
    let collection: MediaItem

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(PlaybackPresenter.self) private var playbackPresenter

    @State private var model = CollectionModel()
    @AppStorage("collectionSort") private var sort = CollectionSort.release
    @AppStorage("collectionShowsGrid") private var showsGrid = false
    @Namespace private var zoomNamespace

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        CollectionContent(collection: collection, model: model, sort: $sort, showsGrid: $showsGrid,
                          columns: columns, zoomNamespace: zoomNamespace)
        .detailPageBackground(tint: model.heroTint)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
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
        .onChange(of: model.playbackRequest) { _, request in
            guard let request else { return }
            playbackPresenter.present(request.item, startTicks: request.startTicks)
            model.playbackRequest = nil
        }
        .onChange(of: playbackPresenter.request == nil) { _, closed in
            if closed { PlayQueue.clear(); Task { await model.load(collection, authManager: authManager) } }
        }
    }
}
