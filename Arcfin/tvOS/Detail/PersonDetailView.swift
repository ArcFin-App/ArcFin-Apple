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
    @State private var requestingCredit: SeerrItem?
    @State private var openCredit: SeerrItem?

    private let columns = [GridItem(.adaptive(minimum: DT.Size.posterCard.width), spacing: 40)]

    init(person: MediaPerson) {
        self.person = person
        _model = State(initialValue: PersonDetailModel(person: person))
    }

    var body: some View {
        PersonDetailContent(model: model, columns: columns, creditScale: 1.8) { item, poster in
            Button { selectedItem = item } label: { poster }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
        } creditLink: { credit, card in
            Button { openCredit = credit.asSeerrItem } label: { card }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .tvFocusRing(cornerRadius: DT.Radius.md)
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
            MediaDetailView(item: item)
        }
        .navigationDestination(item: $openCredit) { TVSeerrItemDetailView(item: $0) }
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
