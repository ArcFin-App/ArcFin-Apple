// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

extension BottomNavPrefs {
    /// Turns `tab` on, or says it can't because `limit` tabs are already on.
    static func turnOn(_ tab: BottomNavItem, limit: Int) -> Bool {
        var active = active(from: UserDefaults.standard.string(forKey: activeKey) ?? "")
        guard !active.contains(tab) else { return true }
        guard active.count < limit else { return false }
        active.insert(tab)
        UserDefaults.standard.set(encode(active), forKey: activeKey)
        return true
    }

    /// Turns `tab` on in `replaced`'s place.
    static func turnOn(_ tab: BottomNavItem, replacing replaced: BottomNavItem) {
        var active = active(from: UserDefaults.standard.string(forKey: activeKey) ?? "")
        active.remove(replaced)
        active.insert(tab)
        UserDefaults.standard.set(encode(active), forKey: activeKey)
    }
}

extension View {
    /// Asks which tab gives way when `pending` is turned on with the bar already full.
    func tabReplacementAlert(pending: Binding<BottomNavItem?>) -> some View {
        modifier(TabReplacementAlert(pending: pending))
    }

    /// Asks an admin, once per profile on this device, whether to add the Admin tab.
    func adminTabOffer(limit: Int) -> some View {
        modifier(AdminTabOffer(limit: limit))
    }
}

private struct TabReplacementAlert: ViewModifier {
    @Binding var pending: BottomNavItem?
    @AppStorage(BottomNavPrefs.orderKey) private var orderString = ""
    @AppStorage(BottomNavPrefs.activeKey) private var activeString = ""

    private var replaceable: [BottomNavItem] {
        let active = BottomNavPrefs.active(from: activeString)
        return BottomNavPrefs.order(from: orderString).filter { active.contains($0) && $0 != .home && $0 != pending }
    }

    func body(content: Content) -> some View {
        content.alert(
            "Replace Which Tab?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { tab in
            ForEach(replaceable) { old in
                Button(old.title) { BottomNavPrefs.turnOn(tab, replacing: old) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { tab in
            Text("The tab bar is full. \(tab.title) takes the place of the tab you pick.")
        }
    }
}

private struct AdminTabOffer: ViewModifier {
    let limit: Int

    @Environment(AuthManager.self) private var authManager
    @AppStorage(BottomNavPrefs.activeKey) private var activeString = ""
    @State private var isOffering = false
    @State private var replacing: BottomNavItem?

    /// Once per device, whichever admin profile is first: asking at every sign-in or switch
    /// would be a nag.
    private static let offeredKey = "arcfin.adminTabOffered"

    func body(content: Content) -> some View {
        content
            .onChange(of: authManager.isAdmin, initial: true) { offerIfNeeded() }
            .alert("Add the Admin Tab?", isPresented: $isOffering) {
                Button("Add Tab") { add() }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Manage this server from Arcfin: its dashboard, sessions, tasks and activity. You can turn the Admin tab on or off any time in Settings › Appearance › Navigation.")
            }
            .tabReplacementAlert(pending: $replacing)
    }

    private func offerIfNeeded() {
        guard authManager.isAdmin, !UserDefaults.standard.bool(forKey: Self.offeredKey),
              !BottomNavPrefs.active(from: activeString).contains(.admin) else { return }
        UserDefaults.standard.set(true, forKey: Self.offeredKey)
        isOffering = true
    }

    /// Where the bar is full (iPhone's five), Admin takes Stats' place when Stats is on;
    /// otherwise it's added, or the admin picks which tab it replaces.
    private func add() {
        let active = BottomNavPrefs.active(from: activeString)
        if active.count >= limit, active.contains(.stats) {
            BottomNavPrefs.turnOn(.admin, replacing: .stats)
        } else if !BottomNavPrefs.turnOn(.admin, limit: limit) {
            replacing = .admin
        }
    }
}
