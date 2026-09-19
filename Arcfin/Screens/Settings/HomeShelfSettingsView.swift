import SwiftUI

struct HomeShelfSettingsView: View {
    @AppStorage(HomeShelfPrefs.orderKey) private var orderString = ""
    @AppStorage(HomeShelfPrefs.activeKey) private var activeString = ""

    private var order: [HomeShelf] { HomeShelfPrefs.order(from: orderString) }
    private var active: Set<HomeShelf> { HomeShelfPrefs.active(from: activeString) }

    var body: some View {
        List {
            Section {
                ForEach(order) { shelf in
                    HStack(spacing: 12) {
                        Image(systemName: shelf.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(active.contains(shelf) ? DT.Color.accent : DT.Color.textSecondary)
                            .frame(width: 24)
                        Text(shelf.title)
                            .foregroundStyle(DT.Color.textPrimary)
                        Spacer()
                        Button {
                            toggle(shelf)
                        } label: {
                            Image(systemName: active.contains(shelf) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(active.contains(shelf) ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove(perform: move)
            } header: {
                Text("Home Shelves")
            } footer: {
                Text("Drag to reorder. Turning a shelf off hides it from Home — it still only shows when it actually has content, same as before.")
            }
        }
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
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
