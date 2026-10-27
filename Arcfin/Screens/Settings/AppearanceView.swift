// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

struct AppearanceView: View {
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("mergeContinueWatchingAndUpNext") private var mergeContinueWatchingAndUpNext = false
    @AppStorage("heroVideoBackdropsEnabled") private var heroVideoBackdropsEnabled = true
    @AppStorage("spoilerProtection") private var spoilerProtection = false
    @AppStorage("libraryHideWatched") private var libraryHideWatched = false
    @AppStorage("saveSearchHistory") private var saveSearchHistory = true
    @AppStorage("modernSearch") private var modernSearch = true
    #if os(tvOS)
    @AppStorage("libraryScreensaverEnabled") private var screensaverEnabled = true
    @AppStorage("libraryScreensaverMinutes") private var screensaverMinutes = 3
    @AppStorage(BottomNavPrefs.activeKey) private var activeTabs = ""
    #endif
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
                    HomeShelfSettingsView()
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
                    LibraryVisibilityView()
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

            #if os(tvOS)
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
            #endif

            // tvOS has a fixed set of tabs.
            #if !os(tvOS)
            Section {
                NavigationLink {
                    BottomNavSettingsView()
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
            #endif

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


            #if os(iOS)
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
            #endif
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

/// Libraries hidden from Browse on this device.
enum LibraryVisibility {
    static let hiddenKey = "hiddenLibraryIDs"

    static var hiddenIDs: Set<String> {
        Set((UserDefaults.standard.string(forKey: hiddenKey) ?? "").split(separator: ",").map(String.init))
    }
}

/// Which libraries show in Browse (kept on this device) and in Recently Added (kept in the
/// Jellyfin account, so other apps follow it too).
struct LibraryVisibilityView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @AppStorage(LibraryVisibility.hiddenKey) private var hiddenString = ""
    @State private var latestExcluded: Set<String> = []
    @State private var latestLoaded = false
    @State private var errorMessage: String?

    private let client = JellyfinMediaClient()

    private var libraries: [JellyfinLibrary] {
        mediaRepo.libraries.filter { $0.collectionType != .livetv && $0.collectionType != .music }
    }

    private var hidden: Set<String> {
        Set(hiddenString.split(separator: ",").map(String.init))
    }

    var body: some View {
        List {
            Section {
                ForEach(libraries) { library in
                    Toggle(isOn: Binding(
                        get: { !hidden.contains(library.id) },
                        set: { shown in
                            var ids = hidden
                            if shown { ids.remove(library.id) } else { ids.insert(library.id) }
                            hiddenString = ids.sorted().joined(separator: ",")
                        }
                    )) {
                        TVRowLabelText(verbatim: library.name)
                    }
                    .tvListRow()
                }
            } header: {
                Text("Show in Browse")
            }

            Section {
                ForEach(libraries) { library in
                    Toggle(isOn: Binding(
                        get: { !latestExcluded.contains(library.id) },
                        set: { shown in setLatest(library.id, shown: shown) }
                    )) {
                        TVRowLabelText(verbatim: library.name)
                    }
                    .tvListRow()
                    .disabled(!latestLoaded)
                }
            } header: {
                Text("Show in Recently Added")
            } footer: {
                Text(errorMessage ?? "Saved to your Jellyfin account, so it applies in its other apps too. Home updates the next time it refreshes.")
                    .font(.caption)
                    .foregroundStyle(errorMessage == nil ? DT.Color.textSecondary : .red)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Libraries")
        .task {
            guard let credential = authManager.state.credential else { return }
            let header = authManager.authClient.authHeader(token: credential.accessToken)
            if let ids = try? await client.getLatestExcludedLibraries(credential: credential, authHeader: header) {
                latestExcluded = Set(ids)
                latestLoaded = true
            } else {
                errorMessage = "Couldn't load this from your server."
            }
        }
    }

    private func setLatest(_ id: String, shown: Bool) {
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let previous = latestExcluded
        if shown { latestExcluded.remove(id) } else { latestExcluded.insert(id) }
        let ids = Array(latestExcluded)
        Task {
            do {
                try await client.setLatestExcludedLibraries(ids, credential: credential, authHeader: header)
                errorMessage = nil
            } catch {
                latestExcluded = previous
                errorMessage = "Couldn't save this to your server."
            }
        }
    }
}
