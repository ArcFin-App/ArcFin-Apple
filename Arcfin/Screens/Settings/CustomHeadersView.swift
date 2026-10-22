// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

/// Extra headers sent to the Jellyfin server, for one behind an access gateway such as
/// Cloudflare Access or Pangolin.
struct CustomHeadersView: View {
    @State private var headers = CustomHTTPHeaders.all
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach($headers) { $header in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Header name", text: $header.name)
                            .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        SecureField("Value", text: $header.value)
                            .font(.system(.subheadline, design: .monospaced))
                    }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .padding(.vertical, 4)
                }
                .onDelete { headers.remove(atOffsets: $0); save() }

                Button {
                    headers.append(.init(name: "", value: ""))
                } label: {
                    Label("Add Header", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Sent with every request to your Jellyfin server, its images and video streams. Use this for a server behind an access gateway, for example a Cloudflare Access service token (CF-Access-Client-Id and CF-Access-Client-Secret). Values are stored in the Keychain. The VLC player and casting can't send them.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Custom Headers")
        .onDisappear(perform: save)
        .onSubmit(save)
    }

    private func save() {
        let kept = headers.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty || !$0.value.isEmpty }
        do {
            try CustomHTTPHeaders.save(kept)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't save the headers: \(error.localizedDescription)"
        }
    }
}
