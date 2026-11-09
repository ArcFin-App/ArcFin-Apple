// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Signs another device in with this account. Listed under Your Profile in Settings.
struct QuickConnectView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var quickConnect = QuickConnectModel()

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    TextField("Code", text: $quickConnect.code)
                        .keyboardType(.numberPad)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button {
                        quickConnect.authorize(authManager: authManager)
                    } label: {
                        if quickConnect.isAuthorizing { ProgressView().scaleEffect(0.8) }
                        else { Text("Authorize") }
                    }
                    .disabled(quickConnect.code.isEmpty || quickConnect.isAuthorizing)
                }
                if let quickConnectResult = quickConnect.result {
                    Text(quickConnectResult)
                        .font(.caption)
                        .foregroundStyle(quickConnectResult.hasPrefix("✓") ? DT.Color.palette("10b981") : DT.Color.palette("F43F5E"))
                }
            } footer: {
                Text("Enter the code shown on another device to sign it in instantly using this account.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(String(localized: "Quick Connect"))
    }
}
