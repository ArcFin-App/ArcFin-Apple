// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

extension View {
    /// Asks before a profile is signed out or removed, since its PIN and Seerr sign-in go
    /// with it. Apple TV gets an alert, which keeps focus on the prompt.
    func confirmingProfileRemoval(_ profile: Binding<ServerCredential?>, signingOut: Bool, isLastProfile: Bool,
                                  perform: @escaping (ServerCredential) -> Void) -> some View {
        modifier(ProfileRemovalConfirmation(profile: profile, signingOut: signingOut,
                                            isLastProfile: isLastProfile, perform: perform))
    }
}

private struct ProfileRemovalConfirmation: ViewModifier {
    @Binding var profile: ServerCredential?
    let signingOut: Bool
    let isLastProfile: Bool
    let perform: (ServerCredential) -> Void

    private var isPresented: Binding<Bool> {
        Binding(get: { profile != nil }, set: { if !$0 { profile = nil } })
    }

    private var title: Text {
        let name = profile?.displayName ?? ""
        return signingOut ? Text("Sign Out of \(name)?") : Text("Remove \(name)?")
    }

    private var message: Text {
        isLastProfile
            ? Text("This is the last profile on this device, so its PIN, the Seerr sign-in, the TMDB key and the custom headers are all removed. Downloads stay.")
            : Text("This profile's PIN and Seerr sign-in are removed from this device. Downloads stay.")
    }

    @ViewBuilder
    private func actions(_ target: ServerCredential) -> some View {
        if signingOut {
            Button("Sign Out", role: .destructive) { perform(target) }
        } else {
            Button("Remove Profile", role: .destructive) { perform(target) }
        }
        Button("Cancel", role: .cancel) {}
    }

    func body(content: Content) -> some View {
        content.confirmationPrompt(title, isPresented: isPresented, presenting: profile) { actions($0) } message: { _ in message }
    }
}
