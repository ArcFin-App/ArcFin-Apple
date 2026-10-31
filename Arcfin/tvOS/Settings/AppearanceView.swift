// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct AppearanceView: View {
    @AppStorage("mergeContinueWatchingAndUpNext") private var mergeContinueWatchingAndUpNext = false
    @AppStorage("heroVideoBackdropsEnabled") private var heroVideoBackdropsEnabled = true
    @AppStorage("heroTrailerSound") private var heroTrailerSound = false
    @AppStorage("modernHome") private var modernHome = false
    @AppStorage("libraryScreensaverEnabled") private var screensaverEnabled = true
    @AppStorage("libraryScreensaverMinutes") private var screensaverMinutes = 3
    @AppStorage(BottomNavPrefs.activeKey) private var activeTabs = ""
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        List {
            Section {
                Toggle(isOn: $mergeContinueWatchingAndUpNext) {
                    TVRowLabelText(title: "Merge Continue Watching & Up Next", detail: "Shows them as one row instead of two.")
                }
                .tvListRow()
                .syncLocked("mergeContinueWatchingAndUpNext", authManager)
                Toggle(isOn: $modernHome) {
                    TVRowLabelText(title: "Modern Home", detail: "Keeps the featured title on screen while the rows slide up beneath it. Off scrolls the whole page.")
                }
                .tvListRow()
                .syncLocked("modernHome", authManager)
                Toggle(isOn: $heroVideoBackdropsEnabled) {
                    TVRowLabelText(title: "Hero Video Backdrops", detail: "Plays a muted trailer behind the featured title when the server has one.")
                }
                .tvListRow()
                .syncLocked("heroVideoBackdropsEnabled", authManager)
                Toggle(isOn: $heroTrailerSound) {
                    TVRowLabelText(title: "Hero Trailer Sound", detail: "Plays the trailer behind the featured title with sound.")
                }
                .tvListRow()
                .disabled(!heroVideoBackdropsEnabled)
                .syncLocked("heroTrailerSound", authManager)
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
                Toggle(isOn: $screensaverEnabled) {
                    TVRowLabelText(title: "Library Screensaver", detail: "Shows your library's artwork when the remote hasn't been used for a while, except during playback. Press any button to go back.")
                }
                .tvListRow()
                if screensaverEnabled {
                    SettingsPicker("Start After", detail: "After 30 minutes the Apple TV's own screensaver and sleep settings take over.",
                                   selection: $screensaverMinutes, options: [2, 3, 5, 10]) { Text("\($0) Minutes") }
                }
            } header: {
                Text("Screensaver")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            }

            Section {
                Toggle(isOn: Binding(
                    get: { BottomNavPrefs.active(from: activeTabs).contains(.stats) },
                    set: { isOn in
                        var active = BottomNavPrefs.active(from: activeTabs)
                        if isOn { active.insert(.stats) } else { active.remove(.stats) }
                        activeTabs = BottomNavPrefs.encode(active)
                    }
                )) {
                    TVRowLabelText(title: "Stats", detail: "Adds a Stats tab with your watch time, habits and favourites.")
                }
                .tvListRow()
            } header: {
                Text("Tabs")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            }

            AppearanceMotionSection()
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
