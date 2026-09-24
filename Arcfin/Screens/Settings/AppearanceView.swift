// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct AppearanceView: View {
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("mergeContinueWatchingAndUpNext") private var mergeContinueWatchingAndUpNext = false
    @AppStorage("heroVideoBackdropsEnabled") private var heroVideoBackdropsEnabled = true
    @Environment(AuthManager.self) private var authManager
    #if canImport(UIKit) && !os(tvOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    /// The tab strip only renders at the bottom on a compact-width iPhone — iPad and Mac
    /// render the exact same order/visibility as a sidebar instead, so the settings label
    /// calling it "Bottom Navigation" there was just wrong, not merely imprecise.
    private var usesBottomBar: Bool {
        #if os(macOS)
        false
        #elseif os(iOS)
        sizeClass == .compact
        #else
        false
        #endif
    }

    private var navSectionTitle: String { usesBottomBar ? "Bottom Navigation" : "Navigation" }
    private var navSectionIcon: String { usesBottomBar ? "rectangle.bottomthird.inset.filled" : "sidebar.left" }

    var body: some View {
        List {
            Section {
                Toggle("Merge Continue Watching & Up Next", isOn: $mergeContinueWatchingAndUpNext)
                    .tvListRow()
                    .syncLocked("mergeContinueWatchingAndUpNext", authManager)
                Toggle("Hero Video Backdrops", isOn: $heroVideoBackdropsEnabled)
                    .tvListRow()
                    .syncLocked("heroVideoBackdropsEnabled", authManager)
                NavigationLink {
                    HomeShelfSettingsView()
                } label: {
                    Text("Home Shelves")
                }
                .tvListRow()
            } header: {
                Label("Home", systemImage: "house")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Shows Continue Watching and Up Next as a single combined row instead of two separate ones. Hero Video Backdrops autoplays a muted trailer behind the featured title when the server has one available. Home Shelves lets you reorder or hide individual rows.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                NavigationLink {
                    BottomNavSettingsView()
                } label: {
                    Text(navSectionTitle)
                }
                .tvListRow()
            } header: {
                Label(navSectionTitle, systemImage: navSectionIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Choose which tabs show and in what order. Requests and Watchlist only appear when Seerr is connected, even if active here.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle("Reduce Motion", isOn: $reduceMotion)
                    .tvListRow()
                    .syncLocked("reduceMotion", authManager)
            } header: {
                Label("Motion", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Minimizes animations and transitions throughout the app.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }


            #if !os(macOS)
            Section {
                Toggle("Haptic Feedback", isOn: $hapticsEnabled)
                    .tvListRow()
                    .syncLocked("hapticsEnabled", authManager)
            } header: {
                Label("Feedback", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Taps a light vibration on key interactions like requesting a title.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            #endif
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Appearance")
    }
}

#Preview {
    NavigationStack { AppearanceView() }
        .environment(AuthManager())
}
