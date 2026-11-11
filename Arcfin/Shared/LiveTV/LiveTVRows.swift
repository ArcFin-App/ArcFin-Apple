// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Play, favourite and what's on, for a channel's context menu.
struct LiveTVChannelMenu: View {
    let model: LiveTVModel
    let channel: LiveTVChannel

    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Button { model.play(channel) } label: { Label("Watch", systemImage: "play.fill") }
        if let program = channel.currentProgram {
            Button { model.selectedProgram = program } label: { Label("About This Programme", systemImage: "info.circle") }
        }
        Button { model.toggleFavorite(channel, authManager: authManager) } label: {
            Label(channel.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: channel.isFavorite ? "star.slash" : "star")
        }
    }
}

struct LiveTVChannelRow: View {
    let channel: LiveTVChannel
    let now: Date
    /// Off when the server has no guide, so rows don't all say there's no information.
    var showsGuide = true

    var body: some View {
        HStack(spacing: 14) {
            ChannelLogo(channel: channel)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let number = channel.number {
                        Text(number)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    Text(channel.name)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(1)
                    if channel.isRadio {
                        Image(systemName: "radio")
                            .font(.caption2)
                            .foregroundStyle(DT.Color.textSecondary)
                            .accessibilityLabel("Radio")
                    }
                    if channel.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(DT.Color.palette("F59E0B"))
                            .accessibilityLabel("Favorite")
                    }
                }

                if let program = channel.currentProgram, program.isAiring(at: now) {
                    HStack(spacing: 6) {
                        Text(program.name)
                            .font(.system(.footnote))
                            .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                            .lineLimit(1)
                        RecordingMark(program: program).font(.caption2)
                    }
                    HStack(spacing: 8) {
                        ProgramProgressLine(program: program, now: now)
                            .frame(maxWidth: 140)
                        Text(program.timeRange)
                            .font(.system(.caption2))
                            .monospacedDigit()
                            .foregroundStyle(DT.Color.textSecondary)
                            .lineLimit(1)
                    }
                } else if showsGuide {
                    Text("No programme information")
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(DT.Color.accent)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays the channel")
    }
}

struct LiveTVEmptyChannels: View {
    let favoritesOnly: Bool

    var body: some View {
        if favoritesOnly {
            ContentUnavailableView("No Favorite Channels", systemImage: "star",
                                   description: Text("Channels you add to your favorites show up here."))
        } else {
            ContentUnavailableView("No Channels", systemImage: "antenna.radiowaves.left.and.right",
                                   description: Text("Your server hasn't found any channels. Add a tuner or an M3U playlist in the Jellyfin dashboard under Live TV."))
        }
    }
}
