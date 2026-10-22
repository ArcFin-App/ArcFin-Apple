// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import ImageCache

struct DownloadsSettingsView: View {
    @AppStorage("wifiOnly")        private var wifiOnly        = true
    @AppStorage("downloadQuality") private var downloadQuality = VideoQuality.max
    #if !os(tvOS)
    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false
    #endif
    @AppStorage("deleteDownloadsAfterWatching") private var deleteAfterWatching = false
    @AppStorage("smartDownloadsEnabled")       private var smartDownloadsEnabled       = false
    @AppStorage("smartDownloadsEpisodeCount")  private var smartDownloadsEpisodeCount  = 2
    @AppStorage("smartDownloadsStorageBudgetGB") private var smartDownloadsStorageBudgetGB = 10
    @AppStorage("smartDownloadsAllowMobileData") private var smartDownloadsAllowMobileData = false
    @AppStorage("concurrentDownloads") private var concurrentDownloads = 1
    @AppStorage("downloadSubtitles") private var downloadSubtitles = "all"
    @AppStorage("downloadTrickplay") private var downloadTrickplay = true
    @AppStorage("seasonDownloadUnwatchedOnly") private var seasonDownloadUnwatchedOnly = false
    @AppStorage("pauseDownloadsInLowPowerMode") private var pauseInLowPowerMode = false
    @AppStorage("pauseDownloadsInLowDataMode") private var pauseInLowDataMode = false
    @AppStorage("removeDownloadsAfterDays") private var removeAfterDays = 0
    @AppStorage("removeWatchedWhenLowOnSpace") private var removeWatchedWhenLow = false
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadManager.self) private var downloadManager
    @State private var imageCacheBytes = ImageCache.diskCacheSize
    @State private var keptShows = DownloadManager.keptShows

    var body: some View {
        List {
            Section {
                // Stored as "wifiOnly" so the existing, synced setting carries over.
                Toggle("Download on Mobile Data", isOn: Binding(get: { !wifiOnly }, set: { wifiOnly = !$0 }))
                    .syncLocked("wifiOnly", authManager)
                Picker("Download Quality", selection: $downloadQuality) {
                    ForEach(VideoQuality.allCases.filter { $0 != .auto }) { q in
                        Text(q.label).tag(q)
                    }
                }
                .syncLocked("downloadQuality", authManager)
            } footer: {
                Text("When this is off, downloads wait for Wi-Fi. You can still start them from Downloads; mobile data charges may apply.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            .onChange(of: wifiOnly) { downloadManager.recheckQueueHold() }

            Section {
                Picker("Downloads at Once", selection: $concurrentDownloads) {
                    ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                }
                .syncLocked("concurrentDownloads", authManager)
                Picker("Subtitles", selection: $downloadSubtitles) {
                    Text("All").tag("all")
                    Text("Preferred Language").tag("preferred")
                    Text("None").tag("none")
                }
                .syncLocked("downloadSubtitles", authManager)
                Toggle("Scrubbing Previews", isOn: $downloadTrickplay)
                    .syncLocked("downloadTrickplay", authManager)
                Toggle("Season Downloads Skip Watched", isOn: $seasonDownloadUnwatchedOnly)
                    .syncLocked("seasonDownloadUnwatchedOnly", authManager)
            } footer: {
                Text("Preferred Language uses the subtitle language in Playback settings, or saves all when none is set. Scrubbing previews are the thumbnails shown while you scrub; leaving them out saves space.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle("Pause in Low Power Mode", isOn: $pauseInLowPowerMode)
                    .syncLocked("pauseDownloadsInLowPowerMode", authManager)
                    .onChange(of: pauseInLowPowerMode) { downloadManager.recheckQueueHold() }
                Toggle("Pause in Low Data Mode", isOn: $pauseInLowDataMode)
                    .syncLocked("pauseDownloadsInLowDataMode", authManager)
                    .onChange(of: pauseInLowDataMode) { downloadManager.recheckQueueHold() }
            } footer: {
                Text("Downloads wait until the mode is off. You can still start them from Downloads.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle("Delete After Watching", isOn: $deleteAfterWatching)
                    .syncLocked("deleteDownloadsAfterWatching", authManager)
                Picker("Remove Downloads After", selection: $removeAfterDays) {
                    Text("Never").tag(0)
                    Text("7 Days").tag(7)
                    Text("30 Days").tag(30)
                }
                .syncLocked("removeDownloadsAfterDays", authManager)
                Toggle("Remove Watched When Low on Space", isOn: $removeWatchedWhenLow)
                    .syncLocked("removeWatchedWhenLowOnSpace", authManager)
            } footer: {
                Text("Delete After Watching removes a movie or episode once you finish it, here or on another device. Remove Downloads After counts from the day it downloaded, watched or not. When the device has under 2 GB free, the oldest watched downloads go first.")
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
                    .onChange(of: smartDownloadsEnabled) { _, isOn in
                        if isOn { downloadManager.refreshSmartDownloads() }
                    }
                if smartDownloadsEnabled {
                    Picker("Episodes to Keep", selection: $smartDownloadsEpisodeCount) {
                        ForEach(1...5, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .syncLocked("smartDownloadsEpisodeCount", authManager)
                    .onChange(of: smartDownloadsEpisodeCount) { downloadManager.refreshSmartDownloads() }
                    Picker("Storage Budget", selection: $smartDownloadsStorageBudgetGB) {
                        ForEach([5, 10, 25, 50], id: \.self) { gb in
                            Text("\(gb) GB").tag(gb)
                        }
                    }
                    .syncLocked("smartDownloadsStorageBudgetGB", authManager)
                    .onChange(of: smartDownloadsStorageBudgetGB) { downloadManager.refreshSmartDownloads() }
                    Toggle("Use Mobile Data", isOn: $smartDownloadsAllowMobileData)
                        .syncLocked("smartDownloadsAllowMobileData", authManager)
                        .onChange(of: smartDownloadsAllowMobileData) { _, isOn in
                            downloadManager.recheckQueueHold()
                            if isOn { downloadManager.refreshSmartDownloads() }
                        }
                }
            } footer: {
                Text("Smart Downloads keeps the episode you're up to and the next ones of each show with downloads, removing ones watched here or anywhere else to stay under your storage budget. It checks after a download finishes, when you open the app or come back to it, when the connection returns, and when you close the player. It only uses mobile data with Use Mobile Data on; charges may apply.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            if !keptShows.isEmpty {
                Section {
                    ForEach(keptShows.sorted { $0.value.name < $1.value.name }, id: \.key) { seriesId, show in
                        LabeledContent(show.name, value: show.episodeCount == 1 ? "Next episode" : "Next \(show.episodeCount)")
                            #if !os(tvOS)
                            .swipeActions {
                                Button("Stop", role: .destructive) {
                                    downloadManager.setKeptShow(seriesId: seriesId, name: show.name, episodeCount: nil)
                                    keptShows = DownloadManager.keptShows
                                }
                            }
                            #endif
                    }
                } header: {
                    Text("Kept Downloaded")
                } footer: {
                    Text("Shows set to Keep Downloaded from their page. They download as soon as you choose, and the Smart Downloads storage budget doesn't apply to them; they stop when the device is under 2 GB free. Swipe to stop; episodes already downloaded stay until watched.")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }

            #if !os(tvOS)
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
