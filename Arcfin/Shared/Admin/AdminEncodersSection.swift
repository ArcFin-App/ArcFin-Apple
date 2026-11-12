// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

@MainActor @Observable
final class AdminEncodersModel {
    private(set) var result: ArcfinSyncEncoders?
    private(set) var isLoading = true
    private(set) var isTesting = false
    /// No Arcfin Sync 0.3 or later on the server, so nothing tests the encoders.
    private(set) var unavailable = false

    func load(authManager: AuthManager, refresh: Bool = false) async {
        guard let access = AdminAccess.session(authManager) else { return }
        if refresh { isTesting = true }
        defer { isLoading = false; isTesting = false }
        guard let encoders = await ArcfinSyncClient().fetchEncoders(credential: access.credential, authHeader: access.header, refresh: refresh) else {
            unavailable = result == nil
            return
        }
        result = encoders
        unavailable = false
        if let av1 = encoders.encoders["av1"] { AV1Encoding.apply(serverEncodesAV1: av1, on: access.credential.baseURL) }
    }
}

/// What the Arcfin Sync plugin found the server's hardware can encode, from a test encode per
/// codec, with Test Again for after a GPU, driver or setting change.
struct AdminEncodersSection: View {
    @Environment(AuthManager.self) private var authManager
    @State private var model = AdminEncodersModel()

    private static let codecs: [(key: String, label: String)] = [("h264", "H.264"), ("hevc", "HEVC"), ("av1", "AV1")]

    var body: some View {
        Section {
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let result = model.result {
                ForEach(Self.codecs, id: \.key) { codec in
                    let works = result.encoders[codec.key]
                    HStack {
                        Text(codec.label)
                        Spacer()
                        Label(works == true ? String(localized: "Works") : String(localized: "Not Available"),
                              systemImage: works == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(works == true ? DT.Color.palette("10b981") : DT.Color.palette("F43F5E"))
                    }
                }
                Button {
                    Task { await model.load(authManager: authManager, refresh: true) }
                } label: {
                    if model.isTesting {
                        HStack { ProgressView(); Text("Testing…") }
                    } else {
                        Label("Test Again", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isTesting)
            } else if model.unavailable {
                Text("Install Arcfin Sync 0.3 or later on the server to see which encoders its hardware can use.")
                    .font(.system(.footnote))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        } header: {
            Text("Hardware Encoders")
        } footer: {
            if let result = model.result {
                Text(footer(result))
            }
        }
        .task { await model.load(authManager: authManager) }
    }

    private func footer(_ result: ArcfinSyncEncoders) -> String {
        let tested = result.probedAt.map { String(localized: "Tested \($0.formatted(.relative(presentation: .named)))") }
        let accel = String(localized: "Hardware acceleration: \(result.hardwareAcceleration)")
        let note = String(localized: "From a short test encode on the server. Arcfin only asks for AV1 where it works. Test again after changing the graphics card, its driver or the acceleration setting.")
        return [accel, tested, note].compactMap { $0 }.joined(separator: " · ")
    }
}
