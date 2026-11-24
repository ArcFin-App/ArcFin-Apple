// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Starting a watch party, or joining one by its QR code or code. There are no links to share.
struct WatchPartyJoinView: View {
    /// The parties this device is already in, to get back to.
    let parties: [WatchPartyState]
    var start: () -> Void
    var scan: () -> Void
    var enterCode: () -> Void
    var open: (WatchPartyState) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: DT.Spacing.lg) {
                if !parties.isEmpty {
                    yourParties
                }
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(DT.Color.accent)
                    .padding(.top, DT.Spacing.xxl)
                    .accessibilityHidden(true)
                VStack(spacing: DT.Spacing.xs) {
                    Text("Watch Together")
                        .font(DT.Font.hero)
                        .multilineTextAlignment(.center)
                    Text("Pick something and invite people with a code, or join someone else's party by scanning its QR code or typing the code under it. When the host starts, the title plays in sync on every device.")
                        .font(DT.Font.body)
                        .foregroundStyle(DT.Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: DT.Spacing.sm) {
                    Button(action: start) {
                        Label("Start a Watch Party", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text("Join a Watch Party")
                        .font(DT.Font.cardTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DT.Spacing.sm)
                    if PickScanView.isAvailable {
                        Button(action: scan) {
                            Label("Scan a Code", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    Button(action: enterCode) {
                        Label("Enter a Code", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .tint(DT.Color.accent)
                Text("Everyone needs to be signed in to this server. Others can join from any app with SyncPlay; you need Arcfin to host.")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private var yourParties: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.xs) {
            Text("Your Watch Parties")
                .font(DT.Font.cardTitle)
                .padding(.top, DT.Spacing.md)
            VStack(spacing: 0) {
                ForEach(parties, id: \.code) { party in
                    Button { open(party) } label: {
                        PartyRow(party: party)
                    }
                    .buttonStyle(.plain)
                    if party.code != parties.last?.code {
                        Divider().padding(.leading, DT.Spacing.md)
                    }
                }
            }
            .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
        }
    }
}

private struct PartyRow: View {
    let party: WatchPartyState

    var body: some View {
        HStack(spacing: DT.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(party.itemName)
                    .font(DT.Font.body)
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(WatchPartyTime.label(party))
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            Spacer()
            Text(party.isHost ? "Host" : "Guest")
                .font(DT.Font.caption)
                .padding(.horizontal, DT.Spacing.xs)
                .padding(.vertical, 2)
                .foregroundStyle(party.isHost ? DT.Color.accent : DT.Color.textSecondary)
                .background(DT.Color.backgroundTertiary, in: Capsule())
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DT.Spacing.md)
        .padding(.vertical, DT.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// How a party's start reads: "Starts Fri 20:00", or "On now".
enum WatchPartyTime {
    static func upcoming(_ party: WatchPartyState) -> Date? {
        guard let at = party.scheduledFor, party.isWaiting || (party.isLobby && at > .now) else { return nil }
        return at
    }

    static func label(_ party: WatchPartyState) -> String {
        guard let at = upcoming(party) else { return String(localized: "On now") }
        let soon = at.timeIntervalSinceNow < 6 * 24 * 3600
        let style: Date.FormatStyle = soon ? .dateTime.weekday(.abbreviated).hour().minute()
                                           : .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()
        return String(localized: "Starts \(at.formatted(style))")
    }
}

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
