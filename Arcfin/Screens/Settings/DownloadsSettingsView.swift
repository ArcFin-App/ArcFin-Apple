import SwiftUI

struct DownloadsSettingsView: View {
    @AppStorage("wifiOnly")        private var wifiOnly        = true
    @AppStorage("downloadQuality") private var downloadQuality = VideoQuality.max
    #if os(iOS)
    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false
    #endif

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
