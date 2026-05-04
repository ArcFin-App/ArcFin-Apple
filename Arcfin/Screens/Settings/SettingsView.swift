import SwiftUI
import AuthCore

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager

    // MARK: - Persisted preferences

    @AppStorage("videoQuality")       private var videoQuality    = VideoQuality.auto
    @AppStorage("autoPlayNext")       private var autoPlayNext    = true
    @AppStorage("skipIntro")          private var skipIntro       = false
    @AppStorage("skipCredits")        private var skipCredits     = false
    @AppStorage("subtitleDefault")    private var subtitleDefault = false

    @AppStorage("wifiOnly")           private var wifiOnly          = true
    @AppStorage("downloadQuality")    private var downloadQuality   = VideoQuality.p1080

    @AppStorage("notifyNewContent")   private var notifyNewContent  = true
    @AppStorage("notifyDownload")     private var notifyDownload    = true

    var body: some View {
        List {
            profileSection

            // ── Playback ─────────────────────────────────────────────────
            Section {
                Picker("Video Quality", selection: $videoQuality) {
                    ForEach(VideoQuality.allCases) { q in
                        Text(q.label).tag(q)
                    }
                }
                Toggle("Auto-play Next Episode", isOn: $autoPlayNext)
                Toggle("Skip Intro Automatically", isOn: $skipIntro)
                Toggle("Skip Credits Automatically", isOn: $skipCredits)
                Toggle("Show Subtitles by Default", isOn: $subtitleDefault)
            } header: {
                sectionHeader("Playback", icon: "play.circle")
            }

            // ── Downloads ────────────────────────────────────────────────
            Section {
                Toggle("Wi-Fi Only", isOn: $wifiOnly)
                Picker("Download Quality", selection: $downloadQuality) {
                    ForEach(VideoQuality.allCases.filter { $0 != .auto }) { q in
                        Text(q.label).tag(q)
                    }
                }
            } header: {
                sectionHeader("Downloads", icon: "arrow.down.circle")
            }

            // ── Notifications ────────────────────────────────────────────
            Section {
                Toggle("New Content Added", isOn: $notifyNewContent)
                Toggle("Download Complete", isOn: $notifyDownload)
            } header: {
                sectionHeader("Notifications", icon: "bell")
            }

            // ── Account & Server ─────────────────────────────────────────
            Section {
                serverRow
                NavigationLink {
                    placeholderDetail("Switch Server")
                } label: {
                    Label("Switch Server", systemImage: "server.rack")
                }
                NavigationLink {
                    placeholderDetail("Add Server")
                } label: {
                    Label("Add Server", systemImage: "plus.circle")
                }
            } header: {
                sectionHeader("Account & Server", icon: "person.badge.key")
            }

            // ── About ────────────────────────────────────────────────────
            Section {
                LabeledContent("Version") {
                    Text(appVersion).foregroundStyle(.secondary)
                }
                LabeledContent("Build") {
                    Text(buildNumber).foregroundStyle(.secondary)
                }
                Link(destination: URL(string: "https://jellyfin.org")!) {
                    Label("Jellyfin Website", systemImage: "safari")
                }
                NavigationLink {
                    placeholderDetail("Open Source Licenses")
                } label: {
                    Label("Open Source Licenses", systemImage: "doc.text")
                }
            } header: {
                sectionHeader("About", icon: "info.circle")
            }

            // ── Sign Out ─────────────────────────────────────────────────
            Section {
                Button(role: .destructive) {
                    authManager.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(DT.Color.backgroundPrimary)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        // Hide tab bar on this screen
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Profile section

    @ViewBuilder
    private var profileSection: some View {
        if case .authenticated(let cred) = authManager.state {
            Section {
                profileCard(cred: cred)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowSeparator(.hidden)
            }
        }
    }

    private func profileCard(cred: ServerCredential) -> some View {
        let initials = cred.displayName
            .split(separator: " ").prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()

        return HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [DT.Color.accent, DT.Color.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .shadow(color: DT.Color.accent.opacity(0.4), radius: 12, y: 4)
                Text(initials)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cred.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                HStack(spacing: 4) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 11))
                        .foregroundStyle(DT.Color.accent)
                    Text(cred.baseURL.host ?? cred.baseURL.absoluteString)
                        .font(.system(size: 13))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: "10b981"))
                        .frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: "10b981"))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.lg)
                .fill(DT.Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.lg)
                        .stroke(DT.Color.accent.opacity(0.18), lineWidth: 1)
                )
        )
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    // MARK: - Row builders

    @ViewBuilder
    private var serverRow: some View {
        if case .authenticated(let cred) = authManager.state {
            LabeledContent("Server") {
                Text(cred.baseURL.host ?? "—")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DT.Color.textSecondary)
            .textCase(nil)
    }

    @ViewBuilder
    private func placeholderDetail(_ title: String) -> some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()
            ContentUnavailableView(
                title,
                systemImage: "hammer",
                description: Text("Coming soon.")
            )
        }
        .navigationTitle(title)
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

// MARK: - Settings models

enum VideoQuality: String, CaseIterable, Identifiable {
    case auto, p4k = "4K", p1080 = "1080p", p720 = "720p", p480 = "480p"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto:  "Auto (Recommended)"
        case .p4k:   "4K Ultra HD"
        case .p1080: "1080p HD"
        case .p720:  "720p"
        case .p480:  "480p"
        }
    }
}
