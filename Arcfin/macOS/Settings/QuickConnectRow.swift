// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Signs another device in with this account, typed straight into Settings under Your Profile.
struct QuickConnectRow: View {
    @Environment(AuthManager.self) private var authManager
    @State private var quickConnect = QuickConnectModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "number.square")
                    .foregroundStyle(DT.Color.accent)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                TextField("Quick Connect", text: $quickConnect.code)
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
        }
    }
}
