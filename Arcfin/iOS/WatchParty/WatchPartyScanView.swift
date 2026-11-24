// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Joins a watch party from its QR code, scanned with the camera.
struct WatchPartyScanView: View {
    @Bindable var model: WatchPartyModel
    var joined: () -> Void

    @State private var scanned = false

    var body: some View {
        ZStack(alignment: .bottom) {
            PickCodeScanner(parse: ArcfinCompanionClient.partyCode(from:)) { code in
                guard !scanned else { return }
                scanned = true
                Task {
                    await model.join(code: code)
                    if model.state != nil { joined() } else { scanned = false }
                }
            }
            .ignoresSafeArea()
            Text(scanned ? "Joining…" : "Point the camera at the QR code on the host's screen.")
                .font(DT.Font.callout)
                .multilineTextAlignment(.center)
                .padding(DT.Spacing.md)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                .padding(DT.Spacing.lg)
        }
        .navigationTitle("Scan the Code")
        .navigationBarTitleDisplayMode(.inline)
    }
}
