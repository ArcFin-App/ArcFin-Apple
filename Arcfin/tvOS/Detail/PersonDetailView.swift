// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI

struct PersonDetailView: View {
    let person: MediaPerson

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var model: PersonDetailModel
    @State private var selectedItem: MediaItem?
    @State private var requestingCredit: SeerrItem?
    @State private var openCredit: SeerrItem?
    @FocusState private var focus: FocusTarget?

    /// Where focus sits on this page: the header while there's nothing else to select, then the
    /// first card once the page has loaded.
    private enum FocusTarget: Hashable {
        case header
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
        if let credit = model.missingCredits.first { return .card("credit-\(credit.id)") }
        return nil
    }

    var body: some View {
        // Apple TV's cards are landscape: the portrait poster was cropped to a strip.
        PersonDetailContent(model: model, columns: columns, creditScale: 1.8,
                            cardImageURL: { mediaRepo.tvImageURL(for: $0, fillWidth: 640) }) { item, poster in
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
        } header: { header in
            // Focusable so the page always has something on screen to select: while it loads,
            // when it's empty or failed, and when coming down from the tab bar while the first
            // card is still below the screen. Without it focus stayed on the tab bar, where
            // Back leaves the page's stack.
            header
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
                .tvFocusable(cornerRadius: DT.Radius.lg)
                .focused($focus, equals: .header)
        }
        .focusSection()
        .defaultFocus($focus, .header)
        .task(id: hasCards) {
            guard hasCards else { return }
            // The first card may not be laid out yet; leave focus on the header if it never is.
            for _ in 0..<10 where focus == .header {
                focus = firstCard
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .screenBackground()
        // The header already shows the name; a navigation title repeated it above the page.
        .toolbar(.hidden, for: .navigationBar)
        .appSheet(item: $requestingCredit) { item in
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
