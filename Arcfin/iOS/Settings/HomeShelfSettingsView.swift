// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct HomeShelfSettingsView: View {
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

    private var editMode: EditMode { shuffleShelves ? .inactive : .active }

    private var footerText: String {
        let reorder = "Drag to reorder."
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
            }

            HomeEpisodeArtworkSection()

            Section {
                ForEach(shown) { shelf in
                    HStack(spacing: 12) {
                        Image(systemName: shelf.icon)
                            .font(.system(.callout))
                            .foregroundStyle(active.contains(shelf) ? DT.Color.accent : DT.Color.textSecondary)
                            .frame(width: 24)
                        Text(shelf.title)
                            .foregroundStyle(DT.Color.textPrimary)
                        Spacer()
                        Button {
                            toggle(shelf)
                        } label: {
                            Image(systemName: active.contains(shelf) ? "checkmark.circle.fill" : "circle")
                                .font(.system(.title3))
                                .foregroundStyle(active.contains(shelf) ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5))
                        }
                        .accessibilityLabel(active.contains(shelf) ? "Hide \(shelf.title)" : "Show \(shelf.title)")
                        .buttonStyle(.plain)
                    }
                }
                .onMove(perform: move)
                .moveDisabled(shuffleShelves)
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
        .environment(\.editMode, Binding<EditMode>.constant(editMode))
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Home Shelves")
        .onAppear {
            if orderString.isEmpty { orderString = HomeShelfPrefs.encode(order) }
            if activeString.isEmpty { activeString = HomeShelfPrefs.encode(active) }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        let items = HomeShelfPrefs.reorder(order, shown: shown) { $0.move(fromOffsets: source, toOffset: destination) }
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
