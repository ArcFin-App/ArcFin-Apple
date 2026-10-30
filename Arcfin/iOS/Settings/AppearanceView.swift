// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct AppearanceView: View {
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("mergeContinueWatchingAndUpNext") private var mergeContinueWatchingAndUpNext = false
    @AppStorage("heroVideoBackdropsEnabled") private var heroVideoBackdropsEnabled = true
    @Environment(AuthManager.self) private var authManager
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// The tab strip only renders at the bottom on a compact-width iPhone — iPad and Mac
    /// render the exact same order/visibility as a sidebar instead, so the settings label
    /// calling it "Bottom Navigation" there was just wrong, not merely imprecise.
    private var usesBottomBar: Bool {
        sizeClass == .compact
    }

    private var navSectionTitle: LocalizedStringKey { usesBottomBar ? "Bottom Navigation" : "Navigation" }

    var body: some View {
        List {
            Section {
                Toggle(isOn: $mergeContinueWatchingAndUpNext) {
                    TVRowLabelText(title: "Merge Continue Watching & Up Next", detail: "Shows them as one row instead of two.")
                }
                .tvListRow()
                .syncLocked("mergeContinueWatchingAndUpNext", authManager)
                Toggle(isOn: $heroVideoBackdropsEnabled) {
                    TVRowLabelText(title: "Hero Video Backdrops", detail: "Plays a muted trailer behind the featured title when the server has one.")
                }
                .tvListRow()
                .syncLocked("heroVideoBackdropsEnabled", authManager)
                NavigationLink {
                    HomeShelfSettingsView().tvSettingsPage()
                } label: {
                    TVRowLabelText(title: "Home Shelves", detail: "Reorder or hide Home's rows.")
                }
                .tvListRow()
            } header: {
                Text("Home")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            }

            AppearanceBrowsingSection()

            Section {
                NavigationLink {
                    BottomNavSettingsView().tvSettingsPage()
                } label: {
                    TVRowLabelText(title: navSectionTitle, detail: "Which tabs show and in what order. Discover and Watchlist need Seerr connected.")
                }
                .tvListRow()
            } header: {
                Text(navSectionTitle)
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            }

            AppearanceMotionSection()

            Section {
                Toggle(isOn: $hapticsEnabled) {
                    TVRowLabelText(title: "Haptic Feedback", detail: "A light vibration on key actions, like requesting a title.")
                }
                .tvListRow()
                .syncLocked("hapticsEnabled", authManager)
            } header: {
                Text("Feedback")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Appearance")
    }
}

#Preview {
    NavigationStack { AppearanceView() }
        .environment(AuthManager())
}
