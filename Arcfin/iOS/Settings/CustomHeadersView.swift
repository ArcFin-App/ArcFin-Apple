// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

/// Extra headers sent to the Jellyfin server, for one behind an access gateway such as
/// Cloudflare Access or Pangolin.
struct CustomHeadersView: View {
    @State private var model: CustomHeadersModel

    /// `serverAddress`: the address being signed in to; without one, the profile in use's server.
    init(serverAddress: String? = nil) {
        _model = State(initialValue: CustomHeadersModel(serverAddress: serverAddress))
    }

    var body: some View {
        List {
            if model.needsAddress {
                Text("Enter your server's address first. These headers are only sent to that server.")
                    .font(.footnote)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                ForEach($model.headers) { $header in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Header name", text: $header.name)
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        SecureField("Value", text: $header.value)
                            .font(.system(.subheadline, design: .monospaced))
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.vertical, 4)
                }
                .onDelete { model.headers.remove(atOffsets: $0); model.save() }

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
