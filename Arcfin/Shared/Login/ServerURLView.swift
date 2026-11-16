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
        Group {
            if PlatformMetrics.loginSideBySide { splitPage } else { columnPage }
        }
        .task { await runDiscovery() }
        .appSheet(isPresented: $showSetupGuide) { SetupGuideSheet() }
        .appSheet(isPresented: $showCustomHeaders) {
            NavigationStack {
                CustomHeadersView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showCustomHeaders = false } }
                    }
            }
        }
    }

    /// One readable column, with Continue pinned at the bottom.
    private var columnPage: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let onBack { LoginBackButton(title: String(localized: "Back"), action: onBack) }

            LoginHeader(
                title: "Connect to Your Server",
                message: "Enter the address of your Jellyfin server, or pick one found on your network."
            )
            .padding(.top, onBack == nil ? 24 : 0)

            addressField
            serverLists

            // Side by side where they fit on one line each, otherwise one above the other.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { helpLinks }
                VStack(spacing: 12) { helpLinks }
            }
            .font(.subheadline)
            .foregroundStyle(DT.Color.accent)
            .frame(maxWidth: .infinity)
        }
        .loginLayout { continueButton }
    }

    /// Apple TV: the welcome and help on the left; the address, Continue and the servers
    /// found on the right.
    private var splitPage: some View {
        LoginSplitPage {
            if let onBack { LoginBackButton(title: String(localized: "Back"), action: onBack) }
            LoginSplitHeader(title: "Connect to Your Server",
                             message: Text("Enter the address of your Jellyfin server, or pick one found on your network."))
            if PlatformMetrics.hostsAppleTVSetup {
                Label("Or set this Apple TV up from Arcfin on an iPhone or iPad on this network. It's quicker than typing with the remote.",
                      systemImage: "iphone")
                    .font(.callout)
                    .foregroundStyle(DT.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) { helpLinks }
                .font(.callout)
                .foregroundStyle(DT.Color.accent)
        } trailing: {
            addressField
            continueButton
            serverLists
        }
    }

    private var addressField: some View {
        LoginTextField(
            title: "Server Address",
            prompt: Text(verbatim: "jellyfin.example.com"),
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
    }

    private var continueButton: some View {
        LoginPrimaryButton(title: "Continue", busyTitle: "Connecting…", isBusy: connecting,
                           isDisabled: serverURL.trimmingCharacters(in: .whitespaces).isEmpty) {
            Task { await handleConnect() }
        }
    }

    @ViewBuilder
    private var serverLists: some View {
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

    @ViewBuilder
    private var helpLinks: some View {
        Button { showSetupGuide = true } label: {
            Label("Setup Guide", systemImage: "questionmark.circle")
                .lineLimit(1)
                .fixedSize()
                .loginLinkPadding()
        }
        // On each button, not the stack: on Apple TV the focus ring follows focus anywhere
        // inside the view it's on, so one ring covered both.
        .arcfinPlainButton(cornerRadius: DT.Radius.pill)
        Button { showCustomHeaders = true } label: {
            Label("Custom Headers", systemImage: "key.horizontal")
                .lineLimit(1)
                .fixedSize()
                .loginLinkPadding()
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.pill)
        .accessibilityHint("For a server behind an access gateway")
    }

    private func handleConnect() async {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showError = true; errorMessage = String(localized: "Enter a server address."); return
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
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? JellyfinAuthError {
        case .notJellyfin?:
            return String(localized: "This address answered, but it isn't a Jellyfin server. If Jellyfin is set up under a path like /jellyfin, add it to the address.")
        case .serverError(let statusCode)?:
            return String(localized: "The server answered with an error (HTTP \(statusCode)). If Jellyfin is behind a reverse proxy, check that Jellyfin is running.")
        case .certificateProblem?:
            return String(localized: "The server's security certificate isn't trusted. Use an address with a valid certificate, or http:// on your home network.")
        case .hostNotFound?:
            return String(localized: "Couldn't find a server with that name. Check the spelling, or try its IP address.")
        case .connectionRefused?:
            return String(localized: "Nothing answered at that address. Check the port (Jellyfin uses 8096 unless it's been changed) and that the server is running.")
        case .timedOut?:
            return String(localized: "The server didn't answer in time. Check that it's on and reachable from this network.")
        case .offline?:
            return String(localized: "This device isn't connected to the internet.")
        case .invalidServerURL?:
            return String(localized: "That doesn't look like a server address.")
        case .unsupportedScheme(let scheme)?:
            return String(localized: "Server addresses start with http:// or https://, not “\(scheme)://”. Check how it's typed, or leave it off and Arcfin will try both.")
        default:
            return String(localized: "Can't reach the server. Check the address and try again.")
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
