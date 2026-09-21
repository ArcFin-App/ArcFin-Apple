// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

struct ServerAccountSettingsView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var showSwitchServerSheet = false
    @State private var quickConnectCode = ""
    @State private var isAuthorizingQC = false
    @State private var quickConnectResult: String?

    private var distinctServerCount: Int {
        Set(authManager.profiles.map { $0.baseURL.host ?? $0.baseURL.absoluteString }).count
    }

    var body: some View {
        List {
            Section {
                serverRow
                #if !os(tvOS)
                Button { showSwitchServerSheet = true } label: {
                    Text("Switch Server")
                }
                .disabled(distinctServerCount <= 1)
                #endif
                NavigationLink {
                    AddServerFlowView()
                } label: {
                    Text("Add Server")
                }
                if let activeID = authManager.state.credential?.id {
                    NavigationLink {
                        ServerSettingsView(profileID: activeID)
                    } label: {
                        Text("Server Settings")
                    }
                }
                if authManager.isAdmin {
                    NavigationLink {
                        AdminSessionsView()
                    } label: {
                        Text("Active Sessions")
                    }
                }
            }

            Section {
                HStack(spacing: 10) {
                    TextField("Code", text: $quickConnectCode)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .autocorrectionDisabled()
                    Button {
                        authorizeQuickConnect()
                    } label: {
                        if isAuthorizingQC { ProgressView().scaleEffect(0.8) }
                        else { Text("Authorize") }
                    }
                    .disabled(quickConnectCode.isEmpty || isAuthorizingQC)
                }
                if let quickConnectResult {
                    Text(quickConnectResult)
                        .font(.caption)
                        .foregroundStyle(quickConnectResult.hasPrefix("✓") ? Color(hex: "10b981") : Color(hex: "EF4444"))
                }
            } header: {
                Text("Quick Connect")
            } footer: {
                Text("Enter the code shown on another device to sign it in instantly using this account.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Server")
        #if !os(tvOS)
        .sheet(isPresented: $showSwitchServerSheet) {
            NavigationStack { SwitchServerView() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        #endif
    }

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

    private func authorizeQuickConnect() {
        guard case .authenticated(let cred) = authManager.state else { return }
        isAuthorizingQC = true
        quickConnectResult = nil
        let code = quickConnectCode
        Task {
            let header = authManager.authClient.authHeader(token: cred.accessToken)
            do {
                let ok = try await authManager.authClient.authorizeQuickConnect(
                    baseURL: cred.baseURL, authHeader: header, code: code
                )
                quickConnectResult = ok ? "✓ Device authorized" : "✗ Invalid or expired code"
                if ok { quickConnectCode = "" }
            } catch {
                quickConnectResult = "✗ \(error.localizedDescription)"
            }
            isAuthorizingQC = false
        }
    }
}

#Preview {
    NavigationStack { ServerAccountSettingsView() }
}
