// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

/// Extra headers sent to the Jellyfin server, for one behind an access gateway such as
/// Cloudflare Access or Pangolin.
struct CustomHeadersView: View {
    @State private var model = CustomHeadersModel()

    var body: some View {
        SettingsForm {
            Section {
                ForEach($model.headers) { $header in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Header name", text: $header.name)
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        SecureField("Value", text: $header.value)
                            .font(.system(.subheadline, design: .monospaced))
                        // No swipe or Delete key for a row here, so each has its own button.
                        Button("Remove Header", systemImage: "minus.circle", role: .destructive) {
                            model.remove(header.id)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    model.headers.append(.init(name: "", value: ""))
                } label: {
                    Label("Add Header", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Sent with every request to your Jellyfin server, its images and video streams. Use this for a server behind an access gateway, for example a Cloudflare Access service token (CF-Access-Client-Id and CF-Access-Client-Secret). Values are stored in the Keychain. The VLC player and casting can't send them.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(DT.Color.palette("F43F5E"))
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Custom Headers")
        .onDisappear(perform: model.save)
        .onSubmit(model.save)
    }
}
