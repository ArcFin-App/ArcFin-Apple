// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import ImageCache

struct DownloadsSettingsView: View {
    @AppStorage("wifiOnly")        private var wifiOnly        = true
    @AppStorage(DownloadQuality.key) private var downloadQuality = DownloadQuality.original
    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false
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
    @AppStorage(DownloadManager.downloadWhilePlayingKey) private var downloadWhilePlaying = false
    @AppStorage("pauseDownloadsInLowDataMode") private var pauseInLowDataMode = false
    @AppStorage("removeDownloadsAfterDays") private var removeAfterDays = 0
    @AppStorage("removeWatchedWhenLowOnSpace") private var removeWatchedWhenLow = false
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadManager.self) private var downloadManager
    @State private var imageCacheBytes = ImageCache.diskCacheSize

    var body: some View {
        List {
            Section {
                // Stored as "wifiOnly" so the existing, synced setting carries over.
                Toggle(isOn: Binding(get: { !wifiOnly }, set: { wifiOnly = !$0 })) {
                    TVRowLabelText(title: "Download on Mobile Data", detail: "Off, downloads wait for Wi-Fi. Charges may apply.")
                }
                .syncLocked("wifiOnly", authManager)
                Picker(selection: $downloadQuality) {
                    ForEach(DownloadQuality.allCases) { Text($0.label).tag($0) }
                } label: {
                    TVRowLabelText(title: "Download Quality", detail: "What downloads and Smart Downloads start at; you can change it for each download. Lower qualities are converted on your server, in HEVC or AV1 where it can, so they take less space.")
                }
                .syncLocked("downloadQuality", authManager)
            }
            .onChange(of: wifiOnly) { downloadManager.recheckQueueHold() }

            Section {
                Picker(selection: $concurrentDownloads) {
                    ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                } label: {
                    TVRowLabelText(title: "Downloads at Once", detail: "How many download at the same time.")
                }
                .syncLocked("concurrentDownloads", authManager)
                Picker(selection: $downloadSubtitles) {
                    Text("All").tag("all")
                    Text("Preferred Language").tag("preferred")
                    Text("None").tag("none")
                } label: {
                    TVRowLabelText(title: "Subtitles", detail: "Preferred Language uses the one from Playback settings, or saves all when none is set.")
                }
                .syncLocked("downloadSubtitles", authManager)
                Toggle(isOn: $downloadTrickplay) {
                    TVRowLabelText(title: "Scrubbing Previews", detail: "The thumbnails shown while you scrub. Leaving them out saves space.")
                }
                .syncLocked("downloadTrickplay", authManager)
                Toggle(isOn: $seasonDownloadUnwatchedOnly) {
                    TVRowLabelText(title: "Season Downloads Skip Watched", detail: "Downloading a season leaves out episodes you've watched.")
                }
                .syncLocked("seasonDownloadUnwatchedOnly", authManager)
            }

            Section {
                Toggle(isOn: $pauseInLowPowerMode) {
                    TVRowLabelText(title: "Pause in Low Power Mode", detail: "Downloads wait until Low Power Mode is off.")
                }
                .syncLocked("pauseDownloadsInLowPowerMode", authManager)
                .onChange(of: pauseInLowPowerMode) { downloadManager.recheckQueueHold() }
                Toggle(isOn: $pauseInLowDataMode) {
                    TVRowLabelText(title: "Pause in Low Data Mode", detail: "Downloads wait until Low Data Mode is off.")
                }
                .syncLocked("pauseDownloadsInLowDataMode", authManager)
                .onChange(of: pauseInLowDataMode) { downloadManager.recheckQueueHold() }
                Toggle(isOn: $downloadWhilePlaying) {
                    TVRowLabelText(title: "Keep Downloading While Playing", detail: "Otherwise downloads and Smart Downloads wait while a video streams, so it gets the whole connection, and carry on when you close the player.")
                }
                .syncLocked(DownloadManager.downloadWhilePlayingKey, authManager)
            }

            Section {
                Toggle(isOn: $deleteAfterWatching) {
                    TVRowLabelText(title: "Delete After Watching", detail: "Removes a movie or episode once you finish it, here or on another device.")
                }
                .syncLocked("deleteDownloadsAfterWatching", authManager)
                Picker(selection: $removeAfterDays) {
                    Text("Never").tag(0)
                    Text("7 Days").tag(7)
                    Text("30 Days").tag(30)
                } label: {
                    TVRowLabelText(title: "Remove Downloads After", detail: "Counts from the day it downloaded, watched or not.")
                }
                .syncLocked("removeDownloadsAfterDays", authManager)
                Toggle(isOn: $removeWatchedWhenLow) {
                    TVRowLabelText(title: "Remove Watched When Low on Space", detail: "Under 2 GB free, the oldest watched downloads go first.")
                }
                .syncLocked("removeWatchedWhenLowOnSpace", authManager)
            }

            Section {
                NavigationLink {
                    StorageManagementView()
                } label: {
                    TVRowLabelText(title: "Manage Storage", detail: "What's downloaded and how much space it takes.")
                }
                LabeledContent("Image Cache", value: ByteCountFormatter.string(fromByteCount: Int64(imageCacheBytes), countStyle: .file))
                Button("Clear Image Cache", role: .destructive) {
                    ImageCache.clear()
                    imageCacheBytes = ImageCache.diskCacheSize
                }
                .disabled(imageCacheBytes == 0)
            } footer: {
                Text("Posters and backdrops are kept to load faster. Clearing them never touches your downloads.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle(isOn: $smartDownloadsEnabled) {
                    TVRowLabelText(title: "Smart Downloads", detail: "Keeps what you're watching downloaded: the next episodes of shows in Continue Watching, Next Up or your downloads, and movies you're part-way through. Watched ones are removed.")
                }
                .syncLocked("smartDownloadsEnabled", authManager)
                .onChange(of: smartDownloadsEnabled) { _, isOn in
                    if isOn { downloadManager.refreshSmartDownloads() }
                }
                if smartDownloadsEnabled {
                    Picker(selection: $smartDownloadsEpisodeCount) {
                        ForEach(1...5, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    } label: {
                        TVRowLabelText(title: "Episodes to Keep", detail: "How many upcoming episodes of each show to keep.")
                    }
                    .syncLocked("smartDownloadsEpisodeCount", authManager)
                    .onChange(of: smartDownloadsEpisodeCount) { downloadManager.refreshSmartDownloads() }
                    Picker(selection: $smartDownloadsStorageBudgetGB) {
                        ForEach([5, 10, 25, 50], id: \.self) { gb in
                            Text("\(gb) GB").tag(gb)
                        }
                    } label: {
                        TVRowLabelText(title: "Storage Budget", detail: "The most space Smart Downloads uses.")
                    }
                    .syncLocked("smartDownloadsStorageBudgetGB", authManager)
                    .onChange(of: smartDownloadsStorageBudgetGB) { downloadManager.refreshSmartDownloads() }
                    Toggle(isOn: $smartDownloadsAllowMobileData) {
                        TVRowLabelText(title: "Use Mobile Data", detail: "Lets Smart Downloads download on mobile data. Charges may apply.")
                    }
                    .syncLocked("smartDownloadsAllowMobileData", authManager)
                    .onChange(of: smartDownloadsAllowMobileData) { _, isOn in
                        downloadManager.recheckQueueHold()
                        if isOn { downloadManager.refreshSmartDownloads() }
                    }
                    NavigationLink {
                        SmartDownloadsIgnoredView()
                    } label: {
                        LabeledContent("Ignored", value: "\(downloadManager.ignoredTitles.count)")
                    }
                }
                NavigationLink {
                    KeptDownloadedView()
                } label: {
                    let _ = downloadManager.keptShowsVersion
                    LabeledContent("Kept Downloaded", value: "\(DownloadManager.keptShows.count)")
                }
            } footer: {
                Text("Smart Downloads checks after a download finishes, when you open the app, when the connection returns and when you close the player.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle(isOn: $offlineModeEnabled) {
                    TVRowLabelText(title: "Offline Mode", detail: "Shows only what's downloaded, without connecting to your server.")
                }
            }
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
