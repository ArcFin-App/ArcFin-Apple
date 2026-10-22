// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

struct ServerURLView: View {
    var onConnected: (URL, String) -> Void
    /// nil for the very first login (nothing to go back to) — set when this screen is
    /// reached from Settings > Add Server, where the system nav bar is hidden and this was
    /// the only step of that flow with no way back at all.
    var onBack: (() -> Void)? = nil

    @Environment(AuthManager.self) private var authManager

    @State private var serverURL: String = ""
    @State private var connecting: Bool = false
    @State private var connected: Bool = false
    @State private var showCustomHeaders = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var discoveredServers: [DiscoveredServer] = []
    @State private var discovering: Bool = false
    @State private var recentServers: [ServerCredential] = []
    @State private var showSetupGuide: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let onBack { LoginBackButton(title: "Back", action: onBack) }

            LoginHeader(
                title: "Connect to Your Server",
                message: "Enter the address of your Jellyfin server, or pick one found on your network."
            )
            .padding(.top, onBack == nil ? 24 : 0)

            LoginTextField(
                title: "Server Address",
                prompt: "jellyfin.example.com",
                text: $serverURL,
                kind: .url,
                isValid: connected,
                error: showError ? errorMessage : nil,
                onSubmit: { Task { await handleConnect() } }
            )
            .onChange(of: serverURL) {
                showError = false
                connected = false
            }

            if discovering || !discoveredServers.isEmpty {
                if discoveredServers.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for servers on your network…")
                            .font(.footnote)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                } else {
                    LoginRowGroup(title: "On Your Network") {
                        ForEach(discoveredServers) { server in
                            LoginRow(systemImage: "wifi", title: server.name, subtitle: server.address) {
                                connect(to: server.address)
                            }
                        }
                    }
                }
            }

            if !recentServers.isEmpty {
                LoginRowGroup(title: "Recent") {
                    ForEach(recentServers) { cred in
                        LoginRow(systemImage: "server.rack", title: cred.displayName, subtitle: cred.baseURL.absoluteString) {
                            connect(to: cred.baseURL.absoluteString)
                        }
                    }
                }
            }

            HStack(spacing: 20) {
                Button { showSetupGuide = true } label: {
                    Label("Setup Guide", systemImage: "questionmark.circle")
                }
                Button { showCustomHeaders = true } label: {
                    Label("Custom Headers", systemImage: "key.horizontal")
                }
                .accessibilityHint("For a server behind an access gateway")
            }
            .font(.subheadline)
            .foregroundStyle(DT.Color.accent)
            .arcfinPlainButton(cornerRadius: DT.Radius.pill)
            .frame(maxWidth: .infinity)
        }
        .loginLayout {
            LoginPrimaryButton(title: "Continue", busyTitle: "Connecting…", isBusy: connecting,
                               isDisabled: serverURL.trimmingCharacters(in: .whitespaces).isEmpty) {
                Task { await handleConnect() }
            }
        }
        .task { await runDiscovery() }
        .sheet(isPresented: $showSetupGuide) { SetupGuideSheet() }
        .sheet(isPresented: $showCustomHeaders) {
            NavigationStack {
                CustomHeadersView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showCustomHeaders = false } }
                    }
            }
        }
    }

    /// A found or recent server: fill it in and connect straight away.
    private func connect(to address: String) {
        serverURL = address
        showError = false
        connected = false
        Task { await handleConnect() }
    }

    // MARK: - Actions

    private func runDiscovery() async {
        // Load from keychain off main thread, then start UDP discovery in parallel
        async let stored = authManager.fetchStoredServers()
        async let found = ServerDiscovery.discover(timeout: 3.0)
        discovering = true
        recentServers = await stored
        discoveredServers = await found
        discovering = false
    }

    private func handleConnect() async {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showError = true; errorMessage = "Enter a server address."; return
        }
        connecting = true
        showError = false
        do {
            let (url, name) = try await authManager.authClient.validateServer(url: trimmed)
            connected = true
            try? await Task.sleep(for: .milliseconds(400))
            connecting = false
            onConnected(url, name)
        } catch {
            connecting = false
            showError = true
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ZStack {
        DT.Color.backgroundPrimary.ignoresSafeArea()
        ServerURLView(onConnected: { _, _ in })
            .environment(AuthManager())
    }
}
