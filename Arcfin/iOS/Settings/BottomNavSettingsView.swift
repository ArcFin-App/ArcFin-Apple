// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct BottomNavSettingsView: View {
    @AppStorage(BottomNavPrefs.orderKey) private var orderString = ""
    @AppStorage(BottomNavPrefs.activeKey) private var activeString = ""
    @AppStorage(BottomNavPrefs.launchTabKey) private var launchTab = BottomNavItem.home
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Environment(AuthManager.self) private var authManager
    @State private var replacing: BottomNavItem?

    /// Admin is only listed for an admin profile.
    private var order: [BottomNavItem] {
        BottomNavPrefs.order(from: orderString).filter { $0 != .admin || authManager.isAdmin }
    }
    private var limit: Int { usesBottomBar ? BottomNavPrefs.maxActiveCompact : BottomNavPrefs.maxActiveRegular }
    private var active: Set<BottomNavItem> { BottomNavPrefs.active(from: activeString) }

    /// Same reasoning as AppearanceView.usesBottomBar — iPad/Mac show this exact order as
    /// a sidebar, not a bottom bar, so the screen title needs to stop claiming otherwise.
    private var usesBottomBar: Bool {
        sizeClass == .compact
    }

    private var navTitle: String { usesBottomBar ? "Bottom Navigation" : "Navigation" }

    var body: some View {
        List {
            Section {
                ForEach(order) { tab in
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon)
                            .font(.system(.callout))
                            .foregroundStyle(active.contains(tab) ? DT.Color.accent : DT.Color.textSecondary)
                            .frame(width: 24)
                        Text(tab.title)
                            .foregroundStyle(DT.Color.textPrimary)
                        Spacer()
                        Button {
                            toggle(tab)
                        } label: {
                            Image(systemName: active.contains(tab) ? "checkmark.circle.fill" : "circle")
                                .font(.system(.title3))
                                .foregroundStyle(active.contains(tab) ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5))
                        }
                        .accessibilityLabel(active.contains(tab) ? "Hide \(tab.title)" : "Show \(tab.title)")
                        .buttonStyle(.plain)
                    }
                }
                .onMove(perform: move)
            } header: {
                Text(navTitle)
            } footer: {
                Text("Drag to reorder. Up to \(limit) tabs can be active at once — the rest stay hidden but keep their place in the order if you turn them back on.")
            }

            Section {
                Picker(selection: $launchTab) {
                    ForEach(order.filter(active.contains)) { tab in
                        Text(tab.title).tag(tab)
                    }
                } label: {
                    TVRowLabelText(title: "Open On", detail: "The tab Arcfin opens on. Discover and Watchlist need Seerr; without it, Home.")
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .tabReplacementAlert(pending: $replacing)
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(navTitle)
        .onAppear {
            // Persist the resolved default explicitly so an empty stored string only ever
            // means "not configured yet", never "user turned everything off".
            if orderString.isEmpty { orderString = BottomNavPrefs.encode(order) }
            if activeString.isEmpty { activeString = BottomNavPrefs.encode(active) }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var items = order
        items.move(fromOffsets: source, toOffset: destination)
        orderString = BottomNavPrefs.encode(items)
    }

    private func toggle(_ tab: BottomNavItem) {
        var items = active
        if items.contains(tab) {
            guard items.count > 1 else { return }
            items.remove(tab)
        } else {
            guard items.count < limit else {
                replacing = tab
                return
            }
            items.insert(tab)
        }
        activeString = BottomNavPrefs.encode(items)
    }
}
