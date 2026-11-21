// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI

struct PersonDetailView: View {
    let person: MediaPerson

    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var model: PersonDetailModel
    @State private var selectedItem: MediaItem?
    @Namespace private var zoomNamespace
    @State private var requestingCredit: SeerrItem?
    @State private var openedCredit: SeerrItem?

    // Fixed 3-up stretches cards absurdly wide on a resizable Mac window — adaptive
    // reflows the grid as the window resizes instead.
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    init(person: MediaPerson) {
        self.person = person
        _model = State(initialValue: PersonDetailModel(person: person))
    }

    var body: some View {
        PersonDetailContent(model: model, columns: columns, creditScale: 1) { item, poster in
            Button { selectedItem = item } label: { poster }
                .buttonStyle(PressableButtonStyle())
                .zoomTransitionSource(id: item.id, in: zoomNamespace)
        } creditLink: { credit, card in
            Button { openCredit(credit.asSeerrItem) } label: { card }
                .buttonStyle(PressableButtonStyle())
        }
        .screenBackground()
        .navigationTitle(person.name)
        .sheet(item: $requestingCredit) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingCredit)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .navigationDestination(item: $selectedItem) { item in
            MediaDetailView(item: item, zoomNamespace: zoomNamespace)
                .zoomNavigationTransition(id: item.id, in: zoomNamespace)
        }
        .navigationDestination(item: $openedCredit) { SeerrItemDetailView(item: $0) }
        .task { await model.load(authManager: authManager, seerrRepo: seerrRepo) }
    }

    /// The request sheet, or the title's Seerr page when this Seerr account can't request it.
    private func openCredit(_ item: SeerrItem) {
        if seerrRepo.mayRequest(item.mediaType) { requestingCredit = item } else { openedCredit = item }
    }
}

#Preview {
    NavigationStack {
        PersonDetailView(person: MediaPerson(id: "1", name: "Timothée Chalamet", role: "Paul Atreides"))
            .environment(MediaRepository())
            .environment(AuthManager())
            .environment(SeerrRepository())
    }
}
