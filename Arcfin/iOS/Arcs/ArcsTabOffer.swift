// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

extension View {
    /// Asks once, on this device, whether to add the Arcs tab once the server has Arcs. Someone
    /// who set up their tabs before Arcs existed wouldn't otherwise find it.
    func arcsTabOffer(limit: Int) -> some View {
        modifier(ArcsTabOffer(limit: limit))
    }
}

private struct ArcsTabOffer: ViewModifier {
    let limit: Int

    @Environment(AuthManager.self) private var authManager
    @AppStorage(BottomNavPrefs.activeKey) private var activeString = ""
    @State private var isOffering = false
    @State private var replacing: BottomNavItem?

    private static let offeredKey = "arcfin.arcsTabOffered"

    private var arcsAvailable: Bool { authManager.arcfinSyncStatus?.isOn("arcs") == true }

    func body(content: Content) -> some View {
        content
            .onChange(of: arcsAvailable, initial: true) { offerIfNeeded() }
            .alert("Add the Arcs Tab?", isPresented: $isOffering) {
                Button("Add Tab") { add() }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Scroll through scenes from your own films and shows, picked for you. You can turn the Arcs tab on or off any time in Settings › Appearance › Navigation.")
            }
            .tabReplacementAlert(pending: $replacing)
    }

    private func offerIfNeeded() {
        guard arcsAvailable, !UserDefaults.standard.bool(forKey: Self.offeredKey) else { return }
        // A fresh layout already has Arcs; nothing to ask.
        guard !activeString.isEmpty, !BottomNavPrefs.active(from: activeString).contains(.arcs),
              !authManager.arcfinSyncLockedKeys.contains(BottomNavPrefs.activeKey) else {
            UserDefaults.standard.set(true, forKey: Self.offeredKey)
            return
        }
        UserDefaults.standard.set(true, forKey: Self.offeredKey)
        isOffering = true
    }

    private func add() {
        if !BottomNavPrefs.turnOn(.arcs, limit: limit) { replacing = .arcs }
    }
}
