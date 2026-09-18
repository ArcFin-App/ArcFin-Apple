import SwiftUI
import AuthCore
import JellyfinAPI

struct ServerSettingsView: View {
    @Environment(AuthManager.self) private var authManager

    @AppStorage("serverRemoteURL") private var remoteURL = ""
    @AppStorage("serverLocalURL")  private var localURL = ""
    @AppStorage("serverHomeSSID")  private var homeSSID = ""

    @State private var publicInfo: JellyfinPublicServerInfo?
    @State private var isLoadingInfo = true
    @State private var infoError: String?
    @State private var isCapturingSSID = false

    private let client = JellyfinMediaClient()

    private var activeBaseURL: URL? { authManager.state.credential?.baseURL }

    private var currentlyUsing: String {
        guard let host = activeBaseURL?.host else { return "Unknown" }
        if let localHost = URL(string: localURL)?.host, localHost == host { return "Local URL" }
        if let remoteHost = URL(string: remoteURL)?.host, remoteHost == host { return "Remote URL" }
        return "Custom"
    }

    var body: some View {
        List {
            Section {
                if isLoadingInfo {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let info = publicInfo {
                    LabeledContent("Server Name", value: info.serverName ?? "—")
                    LabeledContent("Version", value: info.version ?? "—")
                    LabeledContent("Product", value: info.productName ?? "—")
                    LabeledContent("Operating System", value: info.operatingSystem ?? "—")
                    LabeledContent("Local Address", value: info.localAddress ?? "—")
                        .lineLimit(1)
                    LabeledContent("Setup Completed", value: (info.startupWizardCompleted ?? false) ? "Yes" : "No")
                } else if let infoError {
                    Text(infoError)
                        .font(.caption)
                        .foregroundStyle(Color(hex: "EF4444"))
                }
            } header: {
                Label("Public Server Info", systemImage: "server.rack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            }

            Section {
                TextField("https://your-server.example.com", text: $remoteURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            } header: {
                Label("Remote URL", systemImage: "globe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Used when you're not on the saved home Wi-Fi network below.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                TextField("http://10.0.1.50:8096", text: $localURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Home Wi-Fi Network")
                            .font(.system(size: 15))
                        Text(homeSSID.isEmpty ? "Not set" : homeSSID)
                            .font(.caption)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    Spacer()
                    Button {
                        captureCurrentSSID()
                    } label: {
                        if isCapturingSSID { ProgressView().scaleEffect(0.8) }
                        else { Text("Use Current") }
                    }
                    .disabled(isCapturingSSID)
                }
            } header: {
                Label("Local URL", systemImage: "wifi")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Used automatically when this device is connected to the saved home Wi-Fi network. Requires the Access Wi-Fi Information capability.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                LabeledContent("Currently Using", value: currentlyUsing)
            } footer: {
                Text("Close and reopen the app for URL or Wi-Fi network changes to take effect.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Server Settings")
        .task {
            guard let base = activeBaseURL else { isLoadingInfo = false; return }
            do {
                publicInfo = try await client.getPublicInfo(baseURL: base)
            } catch {
                infoError = "Couldn't reach the server for its public info."
            }
            isLoadingInfo = false
        }
    }

    private func captureCurrentSSID() {
        isCapturingSSID = true
        Task {
            if let ssid = await AuthManager.currentWiFiSSID() {
                homeSSID = ssid
            } else {
                homeSSID = ""
            }
            isCapturingSSID = false
        }
    }
}
