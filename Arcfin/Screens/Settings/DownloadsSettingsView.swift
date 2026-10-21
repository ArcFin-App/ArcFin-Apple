// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import ImageCache

struct DownloadsSettingsView: View {
    @AppStorage("wifiOnly")        private var wifiOnly        = true
    @AppStorage("downloadQuality") private var downloadQuality = VideoQuality.max
    #if os(iOS)
    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false
    #endif
    @AppStorage("deleteDownloadsAfterWatching") private var deleteAfterWatching = false
    @AppStorage("smartDownloadsEnabled")       private var smartDownloadsEnabled       = false
    @AppStorage("smartDownloadsEpisodeCount")  private var smartDownloadsEpisodeCount  = 2
    @AppStorage("smartDownloadsStorageBudgetGB") private var smartDownloadsStorageBudgetGB = 10
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadManager.self) private var downloadManager
    @State private var imageCacheBytes = ImageCache.diskCacheSize
    @State private var keptShows = DownloadManager.keptShows

    var body: some View {
        List {
            Section {
                Toggle("Wi-Fi Only", isOn: $wifiOnly)
                    .syncLocked("wifiOnly", authManager)
                Picker("Download Quality", selection: $downloadQuality) {
                    ForEach(VideoQuality.allCases.filter { $0 != .auto }) { q in
                        Text(q.label).tag(q)
                    }
                }
                .syncLocked("downloadQuality", authManager)
            }

            Section {
                Toggle("Delete After Watching", isOn: $deleteAfterWatching)
                    .syncLocked("deleteDownloadsAfterWatching", authManager)
            } footer: {
                Text("Removes a downloaded movie or episode from this device once you finish it, freeing the space.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                NavigationLink("Manage Storage") {
                    StorageManagementView()
                }
                LabeledContent("Image Cache", value: ByteCountFormatter.string(fromByteCount: Int64(imageCacheBytes), countStyle: .file))
                Button("Clear Image Cache", role: .destructive) {
                    ImageCache.clear()
                    imageCacheBytes = ImageCache.diskCacheSize
                }
                .disabled(imageCacheBytes == 0)
            } footer: {
                Text("Posters and backdrops are cached to load faster. Clearing them never touches your downloads; they re-download as you browse.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle("Smart Downloads", isOn: $smartDownloadsEnabled)
                    .syncLocked("smartDownloadsEnabled", authManager)
                if smartDownloadsEnabled {
                    Picker("Episodes to Keep", selection: $smartDownloadsEpisodeCount) {
                        ForEach(1...5, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .syncLocked("smartDownloadsEpisodeCount", authManager)
                    Picker("Storage Budget", selection: $smartDownloadsStorageBudgetGB) {
                        ForEach([5, 10, 25, 50], id: \.self) { gb in
                            Text("\(gb) GB").tag(gb)
                        }
                    }
                    .syncLocked("smartDownloadsStorageBudgetGB", authManager)
                }
            } footer: {
                Text("Smart Downloads keeps the next unwatched episodes of your shows downloaded automatically, removing watched ones to stay under your storage budget.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            if !keptShows.isEmpty {
                Section {
                    ForEach(keptShows.sorted { $0.value.name < $1.value.name }, id: \.key) { seriesId, show in
                        LabeledContent(show.name, value: show.episodeCount == 1 ? "Next episode" : "Next \(show.episodeCount)")
                            .swipeActions {
                                Button("Stop", role: .destructive) {
                                    downloadManager.setKeptShow(seriesId: seriesId, name: show.name, episodeCount: nil)
                                    keptShows = DownloadManager.keptShows
                                }
                            }
                    }
                } header: {
                    Text("Kept Downloaded")
                } footer: {
                    Text("Shows set to Keep Downloaded from their page. Swipe to stop; episodes already downloaded stay until watched.")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }

            #if os(iOS)
            Section {
                Toggle("Offline Mode", isOn: $offlineModeEnabled)
                    .syncLocked("offlineModeEnabled", authManager)
            } footer: {
                Text("Offline Mode shows only your downloaded content — no connection to your server is used or needed.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            #endif
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Downloads")
    }
}

#Preview {
    NavigationStack { DownloadsSettingsView() }
        .environment(AuthManager())
}
