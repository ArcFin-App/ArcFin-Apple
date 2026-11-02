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
    @FocusState private var focus: FocusTarget?

    /// Where focus sits on this page: a small placeholder while there's nothing to select, then the
    /// first card once the page has loaded.
    private enum FocusTarget: Hashable {
        case placeholder
        case card(String)
    }

    private let columns = [GridItem(.adaptive(minimum: DT.Size.posterCard.width), spacing: 40)]

    init(person: MediaPerson) {
        self.person = person
        _model = State(initialValue: PersonDetailModel(person: person))
    }

    private var hasCards: Bool {
        !model.isLoading && firstCard != nil
    }

    /// The card focus lands on: the first library title, else the first credit.
    private var firstCard: FocusTarget? {
        if let item = model.items.first { return .card("item-\(item.id)") }
        if let credit = model.missingCredits(seerrRepo: seerrRepo).first { return .card("credit-\(credit.id)") }
        return nil
    }

    var body: some View {
        PersonDetailContent(model: model, columns: columns, creditScale: 1.8) { item, poster in
            Button { selectedItem = item } label: { poster }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .focused($focus, equals: .card("item-\(item.id)"))
        } creditLink: { credit, card in
            Button { openCredit = credit.asSeerrItem } label: { card }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .tvFocusRing(cornerRadius: DT.Radius.md)
                .focused($focus, equals: .card("credit-\(credit.id)"))
        }
        // While it loads, or when nothing loaded, the page has nothing to select, so focus went to
        // the tab bar, where Back doesn't return to the previous page. This small placeholder keeps
        // focus on the page until there are cards.
        .overlay(alignment: .top) {
            if !hasCards {
                Color.clear
                    .frame(width: 2, height: 2)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focus, equals: .placeholder)
            }
        }
        .defaultFocus($focus, .placeholder)
        .onChange(of: hasCards) { _, has in
            if has { focus = firstCard }
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
        .navigationDestination(item: $openCredit) { SeerrItemDetailView(item: $0) }
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
