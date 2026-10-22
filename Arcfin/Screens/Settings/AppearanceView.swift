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

    var body: some View {
        List {
            Section {
                Toggle(isOn: $mergeContinueWatchingAndUpNext) {
                    TVRowLabelText(title: "Merge Continue Watching & Up Next")
                }
                .tvListRow()
                .syncLocked("mergeContinueWatchingAndUpNext", authManager)
                Toggle(isOn: $heroVideoBackdropsEnabled) {
                    TVRowLabelText(title: "Hero Video Backdrops")
                }
                .tvListRow()
                .syncLocked("heroVideoBackdropsEnabled", authManager)
                NavigationLink {
                    HomeShelfSettingsView()
                } label: {
                    Text("Home Shelves")
                }
                .tvListRow()
            } header: {
                Text("Home")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Shows Continue Watching and Up Next as a single combined row instead of two separate ones. Hero Video Backdrops autoplays a muted trailer behind the featured title when the server has one available. Home Shelves lets you reorder or hide individual rows.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle(isOn: $spoilerProtection) {
                    TVRowLabelText(title: "Spoiler Protection")
                }
                .tvListRow()
                .syncLocked("spoilerProtection", authManager)
                Toggle(isOn: $libraryHideWatched) {
                    TVRowLabelText(title: "Hide Watched in Libraries")
                }
                .tvListRow()
                .syncLocked("libraryHideWatched", authManager)
                Toggle(isOn: $saveSearchHistory) {
                    TVRowLabelText(title: "Save Search History")
                }
                .tvListRow()
                .syncLocked("saveSearchHistory", authManager)
                .onChange(of: saveSearchHistory) { _, isOn in
                    if !isOn { UserDefaults.standard.removeObject(forKey: "recentSearches") }
                }
                NavigationLink {
                    LibraryVisibilityView()
                } label: {
                    Text("Libraries")
                }
                .tvListRow()
            } header: {
                Text("Browsing")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Spoiler Protection blurs the pictures and hides the descriptions of episodes you haven't started. Hide Watched in Libraries starts library grids filtered to unwatched; you can still change it there. Turning off Save Search History also clears it. Libraries chooses which show in Browse and in Recently Added.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            // tvOS has a fixed set of tabs.
            #if !os(tvOS)
            Section {
                NavigationLink {
                    BottomNavSettingsView()
                } label: {
                    Text(navSectionTitle)
                }
                .tvListRow()
            } header: {
                Text(navSectionTitle)
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Choose which tabs show and in what order. Discover and Watchlist only appear when Seerr is connected, even if active here.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            #endif

            Section {
                Toggle(isOn: $reduceMotion) {
                    TVRowLabelText(title: "Reduce Motion")
                }
                .tvListRow()
                .syncLocked("reduceMotion", authManager)
            } header: {
                Text("Motion")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Minimizes animations and transitions throughout the app.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }


            #if os(iOS)
            Section {
                Toggle(isOn: $hapticsEnabled) {
                    TVRowLabelText(title: "Haptic Feedback")
                }
                .tvListRow()
                .syncLocked("hapticsEnabled", authManager)
            } header: {
                Text("Feedback")
                    .font(.system(.caption, design: .default, weight: .semibold))
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
                        TVRowLabelText(title: library.name)
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
                        TVRowLabelText(title: library.name)
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
