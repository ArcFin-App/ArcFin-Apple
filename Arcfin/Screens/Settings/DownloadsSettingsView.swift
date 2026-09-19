import SwiftUI

struct DownloadsSettingsView: View {
    @AppStorage("wifiOnly")        private var wifiOnly        = true
    @AppStorage("downloadQuality") private var downloadQuality = VideoQuality.max
    #if os(iOS)
    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false
    #endif
    @AppStorage("smartDownloadsEnabled")       private var smartDownloadsEnabled       = false
    @AppStorage("smartDownloadsEpisodeCount")  private var smartDownloadsEpisodeCount  = 2
    @AppStorage("smartDownloadsStorageBudgetGB") private var smartDownloadsStorageBudgetGB = 10

    var body: some View {
        List {
            Section {
                Toggle("Wi-Fi Only", isOn: $wifiOnly)
                Picker("Download Quality", selection: $downloadQuality) {
                    ForEach(VideoQuality.allCases.filter { $0 != .auto }) { q in
                        Text(q.label).tag(q)
                    }
                }
            }

            Section {
                NavigationLink("Manage Storage") {
                    StorageManagementView()
                }
            }

            Section {
                Toggle("Smart Downloads", isOn: $smartDownloadsEnabled)
                if smartDownloadsEnabled {
                    Picker("Episodes to Keep", selection: $smartDownloadsEpisodeCount) {
                        ForEach(1...5, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    Picker("Storage Budget", selection: $smartDownloadsStorageBudgetGB) {
                        ForEach([5, 10, 25, 50], id: \.self) { gb in
                            Text("\(gb) GB").tag(gb)
                        }
                    }
                }
            } footer: {
                Text("Smart Downloads keeps the next unwatched episodes of your shows downloaded automatically, removing watched ones to stay under your storage budget.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            #if os(iOS)
            Section {
                Toggle("Offline Mode", isOn: $offlineModeEnabled)
            } footer: {
                Text("Offline Mode shows only your downloaded content — no connection to your server is used or needed.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            #endif
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Downloads")
    }
}

#Preview {
    NavigationStack { DownloadsSettingsView() }
}
