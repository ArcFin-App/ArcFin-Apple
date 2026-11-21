// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct HomeShelfSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(MediaRepository.self) private var mediaRepo
    @AppStorage(HomeShelfPrefs.orderKey) private var orderString = ""
    @AppStorage(HomeShelfPrefs.activeKey) private var activeString = ""
    @AppStorage(HomeShelfPrefs.shuffleKey) private var shuffleShelves = false

    private var order: [HomeShelf] { HomeShelfPrefs.order(from: orderString) }
    private var shown: [HomeShelf] {
        order.filter { $0.isOffered(seerrConfigured: seerrRepo.isConfigured, hasCatalog: seerrRepo.hasCatalog,
                                hasLiveTV: HomeShelf.hasLiveTV(in: mediaRepo)) }
    }
    private var active: Set<HomeShelf> { HomeShelfPrefs.active(from: activeString) }

    private var footerText: String {
        let reorder = "Press and hold a shelf to move it."
        return shuffleShelves
            ? "Turning a shelf off hides it from Home — it still only shows when it actually has content."
            : "\(reorder) Turning a shelf off hides it from Home — it still only shows when it actually has content, same as before."
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $shuffleShelves) {
                    TVRowLabelText(title: "Shuffle Shelves", detail: "New order each time you open Home; Continue Watching and Next Up stay on top. Turns off reordering.")
                }
                .syncLocked(HomeShelfPrefs.shuffleKey, authManager)
            }

            HomeEpisodeArtworkSection()

            Section {
                // No dragging on tvOS: select turns a shelf on or off, and a long press moves it.
                ForEach(Array(shown.enumerated()), id: \.element) { index, shelf in
                    Button { toggle(shelf) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: shelf.icon).frame(width: 40)
                            Text(shelf.title)
                            Spacer()
                            Image(systemName: active.contains(shelf) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    .tvListRow()
                    .contextMenu {
                        if !shuffleShelves {
                            Button("Move Up") { moveShelf(at: index, by: -1) }.disabled(index == 0)
                            Button("Move Down") { moveShelf(at: index, by: 1) }.disabled(index == shown.count - 1)
                        }
                    }
                }
            } header: {
                Text("Home Shelves")
            } footer: {
                Text(footerText)
            }

            if seerrRepo.hasCatalog {
                Section {
                    NavigationLink("Popular Elsewhere") { StreamingServicesView().tvSettingsPage() }
                } footer: {
                    Text("Pick the services you use for a row of what's popular on each. Arcfin doesn't play these services: open a title to find it in your library or request it with Seerr.")
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Home Shelves")
        .onAppear {
            if orderString.isEmpty { orderString = HomeShelfPrefs.encode(order) }
            if activeString.isEmpty { activeString = HomeShelfPrefs.encode(active) }
        }
    }

    private func moveShelf(at index: Int, by offset: Int) {
        let target = index + offset
        guard shown.indices.contains(target) else { return }
        let items = HomeShelfPrefs.reorder(order, shown: shown) { $0.swapAt(index, target) }
        orderString = HomeShelfPrefs.encode(items)
    }

    private func toggle(_ shelf: HomeShelf) {
        var items = active
        if items.contains(shelf) {
            items.remove(shelf)
        } else {
            items.insert(shelf)
        }
        activeString = HomeShelfPrefs.encode(items)
    }
}
