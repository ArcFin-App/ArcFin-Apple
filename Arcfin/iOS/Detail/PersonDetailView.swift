// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI

struct PersonDetailView: View {
    let person: MediaPerson

    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var model: PersonDetailModel
    @State private var selectedItem: MediaItem?
    @Namespace private var zoomNamespace
    @State private var requestingCredit: SeerrItem?

    init(person: MediaPerson) {
        self.person = person
        _model = State(initialValue: PersonDetailModel(person: person))
    }

    private var isWide: Bool { horizontalSizeClass == .regular }

    private var columns: [GridItem] {
        if isWide {
            return [GridItem(.adaptive(minimum: 150), spacing: 12)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
    }

    var body: some View {
        PersonDetailContent(model: model, columns: columns, creditScale: 1) { item, poster in
            Button { selectedItem = item } label: { poster }
                .buttonStyle(PressableButtonStyle())
                .zoomTransitionSource(id: item.id, in: zoomNamespace)
        } creditLink: { credit, card in
            Button { requestingCredit = credit.asSeerrItem } label: { card }
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedItem) { item in
            MediaDetailView(item: item, zoomNamespace: zoomNamespace)
                .zoomNavigationTransition(id: item.id, in: zoomNamespace)
        }
        .task { await model.load(authManager: authManager, seerrRepo: seerrRepo) }
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
