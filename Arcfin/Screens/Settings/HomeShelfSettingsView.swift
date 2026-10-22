// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct HomeShelfSettingsView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @AppStorage(HomeShelfPrefs.orderKey) private var orderString = ""
    @AppStorage(HomeShelfPrefs.activeKey) private var activeString = ""
    @AppStorage(HomeShelfPrefs.shuffleKey) private var shuffleShelves = false

    private var order: [HomeShelf] { HomeShelfPrefs.order(from: orderString) }
    private var active: Set<HomeShelf> { HomeShelfPrefs.active(from: activeString) }

    #if os(iOS)
    private var editMode: EditMode { shuffleShelves ? .inactive : .active }
    #endif

    private var footerText: String {
        #if os(tvOS)
        let reorder = "Press and hold a shelf to move it."
        #else
        let reorder = "Drag to reorder."
        #endif
        return shuffleShelves
            ? "Turning a shelf off hides it from Home — it still only shows when it actually has content."
            : "\(reorder) Turning a shelf off hides it from Home — it still only shows when it actually has content, same as before."
    }

    var body: some View {
        List {
            Section {
                Toggle("Shuffle Shelves", isOn: $shuffleShelves)
            } footer: {
                Text("Mixes up the order of your shelves every time you open Home. Continue Watching and Next Up stay at the top. Reordering is turned off while this is on.")
            }

            Section {
                #if os(tvOS)
                // No dragging on tvOS: select turns a shelf on or off, and a long press moves it.
                ForEach(Array(order.enumerated()), id: \.element) { index, shelf in
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
                            Button("Move Down") { moveShelf(at: index, by: 1) }.disabled(index == order.count - 1)
                        }
                    }
                }
                #else
                ForEach(order) { shelf in
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
                        .buttonStyle(.plain)
                    }
                }
                .onMove(perform: move)
                .moveDisabled(shuffleShelves)
                #endif
            } header: {
                Text("Home Shelves")
            } footer: {
                Text(footerText)
            }

            if seerrRepo.hasCatalog {
                Section {
                    NavigationLink("Streaming Services") { StreamingServicesView() }
                } footer: {
                    Text("Pick the services you use to get a row of what's popular on each, from Seerr or TMDB.")
                }
            }
        }
        #if os(iOS)
        .environment(\.editMode, Binding<EditMode>.constant(editMode))
        #endif
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Home Shelves")
        .onAppear {
            if orderString.isEmpty { orderString = HomeShelfPrefs.encode(order) }
            if activeString.isEmpty { activeString = HomeShelfPrefs.encode(active) }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var items = order
        items.move(fromOffsets: source, toOffset: destination)
        orderString = HomeShelfPrefs.encode(items)
    }

    private func moveShelf(at index: Int, by offset: Int) {
        var items = order
        let target = index + offset
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
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
