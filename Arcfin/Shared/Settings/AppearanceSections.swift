// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Settings › Appearance › Browsing.
struct AppearanceBrowsingSection: View {
    @AppStorage("spoilerProtection") private var spoilerProtection = false
    @AppStorage("libraryHideWatched") private var libraryHideWatched = false
    @AppStorage("showUnwatchedCount") private var showUnwatchedCount = true
    @AppStorage("saveSearchHistory") private var saveSearchHistory = true
    @AppStorage("modernSearch") private var modernSearch = true
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Section {
            Toggle(isOn: $spoilerProtection) {
                TVRowLabelText(title: "Spoiler Protection", detail: "Blurs the pictures and hides the descriptions of episodes you haven't started.")
            }
            .tvListRow()
            .syncLocked("spoilerProtection", authManager)
            Toggle(isOn: $libraryHideWatched) {
                TVRowLabelText(title: "Hide Watched in Libraries", detail: "Library grids start filtered to unwatched; you can still change it there.")
            }
            .tvListRow()
            .syncLocked("libraryHideWatched", authManager)
            Toggle(isOn: $showUnwatchedCount) {
                TVRowLabelText(title: "Show Unwatched Count", detail: "How many episodes are left, on the posters of shows, seasons and collections.")
            }
            .tvListRow()
            .syncLocked("showUnwatchedCount", authManager)
            Toggle(isOn: $modernSearch) {
                TVRowLabelText(title: "Modern Search", detail: "A top result, shelves by kind and a Discover list. Off shows plain poster grids.")
            }
            .tvListRow()
            .syncLocked("modernSearch", authManager)
            Toggle(isOn: $saveSearchHistory) {
                TVRowLabelText(title: "Save Search History", detail: "Turning it off also clears it.")
            }
            .tvListRow()
            .syncLocked("saveSearchHistory", authManager)
            .onChange(of: saveSearchHistory) { _, isOn in
                if !isOn { UserDefaults.standard.removeObject(forKey: "recentSearches") }
            }
            NavigationLink {
                LibraryVisibilityView().tvSettingsPage()
            } label: {
                TVRowLabelText(title: "Libraries", detail: "Which libraries show in Browse and in Recently Added.")
            }
            .tvListRow()
        } header: {
            Text("Browsing")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        }
    }
}

/// Settings › Appearance › Motion.
struct AppearanceMotionSection: View {
    @AppStorage("reduceMotion") private var reduceMotion = false
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Section {
            Toggle(isOn: $reduceMotion) {
                TVRowLabelText(title: "Reduce Motion", detail: "Fewer animations and transitions throughout the app.")
            }
            .tvListRow()
            .syncLocked("reduceMotion", authManager)
        } header: {
            Text("Motion")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        }
    }
}
