// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// Home's Live TV shelves: favourite channels, what's on now and the channels watched lately.
/// Each loads when its shelf appears, at most once a minute.
@MainActor @Observable
final class HomeLiveTVShelves {
    private(set) var favorites: [LiveTVChannel] = []
    private(set) var onNow: [LiveTVProgram] = []
    private(set) var recents: [LiveTVChannel] = []
    @ObservationIgnored private var loadedAt: [HomeShelf: Date] = [:]
    @ObservationIgnored private let client = JellyfinMediaClient()

    func load(_ shelf: HomeShelf, authManager: AuthManager) async {
        guard let credential = authManager.state.credential else { return }
        if shelf == .liveRecentChannels {
            recents = LiveTVRecents.channels(for: credential.userID)
            return
        }
        if let at = loadedAt[shelf], Date().timeIntervalSince(at) < 60 { return }
        loadedAt[shelf] = Date()
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        switch shelf {
        case .liveFavoriteChannels:
            if let page = try? await client.getLiveTVChannels(credential: credential, authHeader: header,
                                                              limit: 30, favoritesOnly: true) {
                favorites = page.channels
            }
        case .liveOnNow:
            if let programs = try? await client.getLiveTVOnNow(credential: credential, authHeader: header) {
                onNow = programs
            }
        default:
            break
        }
    }

    /// Plays a channel from a shelf, with the shelf's other channels a channel up or down away.
    func play(_ channel: LiveTVChannel, among list: [LiveTVChannel], model: HomeModel) {
        let queue = list.contains(where: { $0.id == channel.id }) ? list : [channel]
        PlayQueue.start(queue.map(\.mediaItem))
        LiveTVQueue.channels = queue
        model.playbackRequest = PlaybackRequest(item: channel.mediaItem, startTicks: 0)
    }

    /// On Now's channels, in its order, for channel up and down from one of them.
    var onNowChannels: [LiveTVChannel] {
        onNow.map { LiveTVChannel(id: $0.channelId, name: $0.channelName ?? "", currentProgram: $0) }
    }
}

/// A channel or what's on it, as a landscape card for Home.
struct LiveTVHomeCard: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let channel: LiveTVChannel
    /// What's on; a programme card shows its own still and name.
    var program: LiveTVProgram?

    private var width: CGFloat { DT.Size.wideCard.width }
    private var height: CGFloat { DT.Size.wideCard.height }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            artwork
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if program?.isAiring() == true { LiveBadge().padding(8) }
                }
                .overlay(alignment: .bottom) {
                    if let program, program.isAiring() {
                        ProgramProgressLine(program: program, now: .now)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 8)
                    }
                }
                .tvLabelFocusRing(cornerRadius: DT.Radius.card)
            VStack(alignment: .leading, spacing: 2) {
                Text(program?.name ?? channel.name)
                    .contentFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .contentFont(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: width, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays the channel")
    }

    private var subtitle: String {
        if program != nil { return [channel.number, channel.name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
        if let current = channel.currentProgram, current.isAiring() { return current.name }
        return channel.number ?? String(localized: "Live TV")
    }

    @ViewBuilder
    private var artwork: some View {
        if let program, let url = mediaRepo.primaryImageURL(itemID: program.id, tag: program.primaryImageTag, fillWidth: 480) {
            CachedAsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: logoPlate
                }
            }
        } else {
            logoPlate
        }
    }

    private var logoPlate: some View {
        ZStack {
            LinearGradient(colors: [DT.Color.backgroundTertiary, DT.Color.backgroundSecondary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ChannelLogo(channel: channel, size: CGSize(width: width * 0.55, height: height * 0.55))
        }
    }
}

/// One of Home's Live TV shelves on iPhone, iPad and Mac: its cards, or nothing while empty.
struct HomeLiveTVShelf: View {
    let shelf: HomeShelf
    let model: HomeModel

    @Environment(AuthManager.self) private var authManager

    var body: some View {
        // A stack even when empty, so the load below runs.
        VStack(spacing: 0) {
            switch shelf {
            case .liveFavoriteChannels:
                channelRow(model.liveTV.favorites)
            case .liveRecentChannels:
                channelRow(model.liveTV.recents)
            case .liveOnNow:
                if !model.liveTV.onNow.isEmpty {
                    ShelfRow(title: shelf.title) {
                        ForEach(model.liveTV.onNow) { program in
                            let channel = LiveTVChannel(id: program.channelId, name: program.channelName ?? "", currentProgram: program)
                            Button { model.liveTV.play(channel, among: model.liveTV.onNowChannels, model: model) } label: {
                                LiveTVHomeCard(channel: channel, program: program)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                }
            default:
                EmptyView()
            }
        }
        .task { await model.liveTV.load(shelf, authManager: authManager) }
    }

    @ViewBuilder
    private func channelRow(_ channels: [LiveTVChannel]) -> some View {
        if !channels.isEmpty {
            ShelfRow(title: shelf.title) {
                ForEach(channels) { channel in
                    Button { model.liveTV.play(channel, among: channels, model: model) } label: {
                        LiveTVHomeCard(channel: channel)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
    }
}
