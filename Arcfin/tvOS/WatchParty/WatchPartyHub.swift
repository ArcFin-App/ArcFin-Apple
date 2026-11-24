// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Starting a watch party, or joining one with its code: what it is on the left, and the
/// buttons and the code field on the right. The code is typed or dictated with the remote.
struct WatchPartyHub: View {
    let model: WatchPartyModel
    var start: () -> Void
    var scan: () -> Void
    var enterCode: () -> Void

    private enum Field: Hashable { case start, code, join }

    @State private var code = ""
    @FocusState private var focus: Field?

    var body: some View {
        LoginSplitPage {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 80))
                .foregroundStyle(DT.Color.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                Text("Watch Together")
                    .font(.title.bold())
                    .foregroundStyle(DT.Color.textPrimary)
                WatchPartyPlatform.joinBlurb
                    .font(.callout)
                    .foregroundStyle(DT.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Everyone needs to be signed in to this server. Others can join from any app with SyncPlay; you need Arcfin to host.")
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } trailing: {
            Button(action: start) {
                TVDetailButtonLabel(icon: "plus", text: "Start a Watch Party", isPrimary: true)
            }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .focused($focus, equals: .start)
            joinSection
            if !model.myParties.isEmpty {
                yourParties
            }
        }
        .defaultFocus($focus, .start)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var joinSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Join a Watch Party")
                .font(.headline)
                .foregroundStyle(DT.Color.textPrimary)
            TextField("Code", text: $code)
                .partyCodeInput()
                .focused($focus, equals: .code)
                .onSubmit(join)
            Button(action: join) {
                TVDetailButtonLabel(icon: "arrow.right", text: "Join")
            }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .focused($focus, equals: .join)
            .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
            Text("It's shown under the QR code on the host's screen.")
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var yourParties: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Your Watch Parties")
                .font(.headline)
                .foregroundStyle(DT.Color.textPrimary)
            ForEach(model.myParties, id: \.code) { party in
                Button { Task { await model.reopen(party) } } label: {
                    PartyRow(party: party)
                        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                }
                .arcfinPlainButton(cornerRadius: DT.Radius.lg, prominent: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func join() {
        guard !code.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task { await model.join(code: code) }
    }
}
