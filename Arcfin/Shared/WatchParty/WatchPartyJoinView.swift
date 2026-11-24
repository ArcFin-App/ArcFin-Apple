// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Starting a watch party, or joining one by its QR code or code. There are no links to share.
struct WatchPartyJoinView: View {
    let model: WatchPartyModel
    var start: () -> Void
    var scan: () -> Void
    var enterCode: () -> Void

    /// The parties this device is already in, to get back to.
    private var parties: [WatchPartyState] { model.myParties }

    private func open(_ party: WatchPartyState) {
        Task { await model.reopen(party) }
    }

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
                    WatchPartyPlatform.joinBlurb
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
                    if WatchPartyPlatform.canScan {
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
                    .arcfinPlainButton(cornerRadius: DT.Radius.lg, prominent: false)
                    if party.code != parties.last?.code {
                        Divider().padding(.leading, DT.Spacing.md)
                    }
                }
            }
            .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
        }
    }
}

struct PartyRow: View {
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
