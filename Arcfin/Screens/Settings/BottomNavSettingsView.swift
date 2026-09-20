import SwiftUI

struct BottomNavSettingsView: View {
    @AppStorage(BottomNavPrefs.orderKey) private var orderString = ""
    @AppStorage(BottomNavPrefs.activeKey) private var activeString = ""
    #if canImport(UIKit) && !os(tvOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var order: [BottomNavItem] { BottomNavPrefs.order(from: orderString) }
    private var active: Set<BottomNavItem> { BottomNavPrefs.active(from: activeString) }

    /// Same reasoning as AppearanceView.usesBottomBar — iPad/Mac show this exact order as
    /// a sidebar, not a bottom bar, so the screen title needs to stop claiming otherwise.
    private var usesBottomBar: Bool {
        #if os(macOS)
        false
        #elseif os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var navTitle: String { usesBottomBar ? "Bottom Navigation" : "Navigation" }

    var body: some View {
        List {
            Section {
                ForEach(order) { tab in
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(active.contains(tab) ? DT.Color.accent : DT.Color.textSecondary)
                            .frame(width: 24)
                        Text(tab.title)
                            .foregroundStyle(DT.Color.textPrimary)
                        Spacer()
                        Button {
                            toggle(tab)
                        } label: {
                            Image(systemName: active.contains(tab) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(active.contains(tab) ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove(perform: move)
            } header: {
                Text(navTitle)
            } footer: {
                Text("Drag to reorder. Up to \(BottomNavPrefs.maxActive) tabs can be active at once — the rest stay hidden but keep their place in the order if you turn them back on.")
            }
        }
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
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
            guard items.count < BottomNavPrefs.maxActive else { return }
            items.insert(tab)
        }
        activeString = BottomNavPrefs.encode(items)
    }
}
