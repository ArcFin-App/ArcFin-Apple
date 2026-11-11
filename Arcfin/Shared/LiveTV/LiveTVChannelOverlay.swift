// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// The channel list over the playing channel: what's on each, the current one marked and
/// scrolled to. Picking one switches to it without leaving the player.
struct LiveTVChannelOverlay: View {
    let channels: [LiveTVChannel]
    let currentID: String
    /// The channel watched before this one, offered first as a way straight back.
    var lastChannel: LiveTVChannel?
    let select: (LiveTVChannel) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Channels")
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36 * DT.Scale.font, height: 36 * DT.Scale.font)
                        .background(.white.opacity(0.15), in: Circle())
                }
                .arcfinPlainButton(cornerRadius: 18 * DT.Scale.font)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            if let lastChannel, lastChannel.id != currentID {
                Button { select(lastChannel) } label: {
                    Label("Back to \(lastChannel.name)", systemImage: "arrow.uturn.backward")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
                }
                .arcfinPlainButton(cornerRadius: DT.Radius.md, prominent: false)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            TimelineView(.everyMinute) { context in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(channels) { channel in
                                row(channel, now: context.date)
                                    .id(channel.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 20)
                    }
                    .onAppear { proxy.scrollTo(currentID, anchor: .center) }
                }
            }
        }
        .frame(maxWidth: 460 * DT.Scale.font, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(0.95))
        .background(Color.black.opacity(0.45))
        .environment(\.colorScheme, .dark)
        .tvFocusSection()
    }

    private func row(_ channel: LiveTVChannel, now: Date) -> some View {
        let isCurrent = channel.id == currentID
        return Button { select(channel) } label: {
            HStack(spacing: 12) {
                ChannelLogo(channel: channel, size: CGSize(width: 56 * DT.Scale.font, height: 38 * DT.Scale.font))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if let number = channel.number {
                            Text(number)
                                .font(.system(.caption, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Text(channel.name)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    if let program = channel.currentProgram, program.isAiring(at: now) {
                        Text(program.name)
                            .font(.system(.caption))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                        ProgramProgressLine(program: program, now: now)
                            .frame(maxWidth: 160 * DT.Scale.font)
                    }
                }
                Spacer(minLength: 0)
                if isCurrent {
                    LiveBadge()
                }
            }
            .padding(10)
            .background(isCurrent ? DT.Color.accent.opacity(0.22) : Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.md, prominent: false)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// The channel list as a layer of the player, sliding in from the trailing edge.
struct PlayerChannelListLayer: View {
    let model: PlayerModel

    var body: some View {
        if model.showChannelList, model.hasChannelList {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                LiveTVChannelOverlay(channels: model.liveChannels, currentID: model.item.id,
                                     lastChannel: model.lastChannel) { channel in
                    model.switchChannel(to: channel)
                } close: {
                    withAnimation(DT.Animation.fast) { model.showChannelList = false }
                }
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}
