// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

enum LiveTVTab: String, CaseIterable, Identifiable {
    case channels, guide, recordings
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .channels: "Channels"
        case .guide: "Guide"
        case .recordings: "Recordings"
        }
    }
}

/// Channels, the guide, recordings and timers for the Live TV screen on every platform.
@MainActor @Observable
final class LiveTVModel {
    /// The channels loaded so far, in the server's order; more come a page at a time.
    private(set) var channels: [LiveTVChannel] = []
    private(set) var totalChannels = 0
    private(set) var favoriteChannels: [LiveTVChannel] = []
    private(set) var isLoadingChannels = true
    private(set) var isLoadingMore = false
    private(set) var channelsFailed = false
    var favoritesOnly = false
    /// False when the server has channels but no guide (an M3U playlist with no listings
    /// provider); nil until it's known.
    private(set) var hasGuide: Bool?
    static let pageSize = 200

    /// The guide's programmes by channel, filled in as rows come on screen.
    private(set) var programs: [String: [LiveTVProgram]] = [:]
    private var requestedGuideChannels: Set<String> = []
    /// Goes up when the loaded guide is thrown away, so rows on screen ask again.
    private(set) var guideGeneration = 0
    /// The guide starts on the half hour before now and runs this long.
    static let guideHours = 24
    private(set) var guideStart = LiveTVModel.halfHour(before: .now)
    var guideEnd: Date { guideStart.addingTimeInterval(Double(Self.guideHours) * 3600) }

    private(set) var recordings: [LiveTVRecording] = []
    private(set) var timers: [LiveTVTimer] = []
    private(set) var seriesTimers: [LiveTVSeriesTimer] = []
    private(set) var isLoadingRecordings = true

    var selectedProgram: LiveTVProgram?
    var playbackRequest: MediaDetailView.PlaybackRequest?
    var actionError: String?

    private let client = JellyfinMediaClient()

    var visibleChannels: [LiveTVChannel] { favoritesOnly ? favoriteChannels : channels }

    var hasFavorites: Bool { !favoriteChannels.isEmpty }

    var canLoadMore: Bool { !favoritesOnly && channels.count < totalChannels }

    private func session(_ authManager: AuthManager) -> (credential: ServerCredential, authHeader: String)? {
        guard let credential = authManager.state.credential else { return nil }
        return (credential, authManager.authClient.authHeader(token: credential.accessToken))
    }

    static func halfHour(before date: Date) -> Date {
        let interval = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (interval / 1800).rounded(.down) * 1800)
    }

    // MARK: - Channels

    func loadChannels(authManager: AuthManager) async {
        guard let (credential, header) = session(authManager) else { return }
        let client = client
        async let firstPage = client.getLiveTVChannels(credential: credential, authHeader: header, limit: Self.pageSize)
        async let favorites = try? client.getLiveTVChannels(credential: credential, authHeader: header,
                                                             limit: 1000, favoritesOnly: true)
        async let guide = client.hasLiveTVGuide(credential: credential, authHeader: header)
        do {
            let page = try await firstPage
            channels = page.channels
            totalChannels = page.total
            channelsFailed = false
        } catch {
            if channels.isEmpty { channelsFailed = true }
        }
        if let favorites = await favorites { favoriteChannels = favorites.channels }
        hasGuide = await guide
        isLoadingChannels = false
    }

    /// Loads the next page once a row near the end of what's loaded comes on screen.
    func loadMoreIfNeeded(after channel: LiveTVChannel, authManager: AuthManager) async {
        guard canLoadMore, !isLoadingMore,
              let index = channels.lastIndex(where: { $0.id == channel.id }), index >= channels.count - 40,
              let (credential, header) = session(authManager) else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await client.getLiveTVChannels(credential: credential, authHeader: header,
                                                             startIndex: channels.count, limit: Self.pageSize)
        else { return }
        let known = Set(channels.map(\.id))
        channels += page.channels.filter { !known.contains($0.id) }
        // An empty page with more still reported would ask again forever.
        totalChannels = page.channels.isEmpty ? channels.count : page.total
    }

    /// What's on now moves on every few minutes; called on a timer while the screen is open.
    /// Without a guide there's nothing to move on.
    func refreshNowPlaying(authManager: AuthManager) async {
        guard hasGuide == true, let (credential, header) = session(authManager),
              let fresh = try? await client.getLiveTVChannels(credential: credential, authHeader: header,
                                                              limit: min(max(channels.count, Self.pageSize), 1000))
        else { return }
        let programs = Dictionary(fresh.channels.map { ($0.id, $0.currentProgram) }, uniquingKeysWith: { a, _ in a })
        for i in channels.indices where programs[channels[i].id] != nil {
            channels[i].currentProgram = programs[channels[i].id] ?? nil
        }
        for i in favoriteChannels.indices where programs[favoriteChannels[i].id] != nil {
            favoriteChannels[i].currentProgram = programs[favoriteChannels[i].id] ?? nil
        }
        let start = Self.halfHour(before: .now)
        if start != guideStart {
            guideStart = start
            reloadGuide()
        }
    }

    func toggleFavorite(_ channel: LiveTVChannel, authManager: AuthManager) {
        guard let (credential, header) = session(authManager) else { return }
        let newValue = !channel.isFavorite
        setFavorite(newValue, on: channel)
        HapticManager.impact(.light)
        Task {
            do {
                try await client.markFavorite(credential: credential, authHeader: header, itemId: channel.id, favorite: newValue)
            } catch {
                setFavorite(!newValue, on: channel)
            }
        }
    }

    private func setFavorite(_ favorite: Bool, on channel: LiveTVChannel) {
        if let i = channels.firstIndex(where: { $0.id == channel.id }) { channels[i].isFavorite = favorite }
        if favorite {
            guard !favoriteChannels.contains(where: { $0.id == channel.id }) else { return }
            var updated = channel
            updated.isFavorite = true
            favoriteChannels.append(updated)
        } else {
            favoriteChannels.removeAll { $0.id == channel.id }
        }
    }

    /// Plays a channel, with the others in the list a channel up or down away.
    func play(_ channel: LiveTVChannel) {
        let list = visibleChannels.contains(where: { $0.id == channel.id }) ? visibleChannels : channels
        PlayQueue.start(list.map(\.mediaItem))
        playbackRequest = MediaDetailView.PlaybackRequest(item: channel.mediaItem, startTicks: 0)
    }

    func play(_ recording: LiveTVRecording) {
        PlayQueue.clear()
        let resume = recording.item.userData?.played == true ? 0 : (recording.item.userData?.playbackPositionTicks ?? 0)
        playbackRequest = MediaDetailView.PlaybackRequest(item: recording.item, startTicks: resume)
    }

    func channel(for program: LiveTVProgram) -> LiveTVChannel? {
        channels.first { $0.id == program.channelId } ?? favoriteChannels.first { $0.id == program.channelId }
    }

    // MARK: - Guide

    /// Loads the guide for a block of channels around one that's coming on screen.
    func loadGuide(around channel: LiveTVChannel, authManager: AuthManager) async {
        guard hasGuide != false, !requestedGuideChannels.contains(channel.id),
              let index = visibleChannels.firstIndex(where: { $0.id == channel.id }),
              let (credential, header) = session(authManager) else { return }
        let block = visibleChannels[index..<min(index + 25, visibleChannels.count)]
            .map(\.id).filter { !requestedGuideChannels.contains($0) }
        guard !block.isEmpty else { return }
        requestedGuideChannels.formUnion(block)
        do {
            let found = try await client.getLiveTVPrograms(credential: credential, authHeader: header,
                                                           channelIds: block, from: guideStart, to: guideEnd)
            let grouped = Dictionary(grouping: found, by: \.channelId)
            for id in block { programs[id] = grouped[id] ?? [] }
        } catch {
            requestedGuideChannels.subtract(block)
        }
    }

    func guidePrograms(for channel: LiveTVChannel) -> [LiveTVProgram]? {
        programs[channel.id]
    }

    // MARK: - Recordings

    func loadRecordings(authManager: AuthManager) async {
        guard let (credential, header) = session(authManager) else { return }
        async let recordingsResult = try? client.getLiveTVRecordings(credential: credential, authHeader: header)
        async let timersResult = try? client.getLiveTVTimers(credential: credential, authHeader: header)
        async let seriesResult = try? client.getLiveTVSeriesTimers(credential: credential, authHeader: header)
        if let value = await recordingsResult { recordings = value }
        if let value = await timersResult { timers = value }
        if let value = await seriesResult { seriesTimers = value }
        isLoadingRecordings = false
    }

    var scheduledTimers: [LiveTVTimer] { timers.filter { !$0.isRecording } }
    var activeTimers: [LiveTVTimer] { timers.filter(\.isRecording) }

    // MARK: - Recording a programme

    func record(_ program: LiveTVProgram, series: Bool, authManager: AuthManager) async {
        guard let (credential, header) = session(authManager) else { return }
        do {
            if series {
                try await client.recordLiveTVSeries(credential: credential, authHeader: header, programId: program.id)
            } else {
                try await client.recordLiveTVProgram(credential: credential, authHeader: header, programId: program.id)
            }
            HapticManager.impact(.medium)
            await refresh(program, authManager: authManager)
        } catch {
            actionError = series
                ? String(localized: "Couldn't record the series. Check that your server has a tuner and a recording folder set up.")
                : String(localized: "Couldn't record this programme. Check that your server has a tuner and a recording folder set up.")
        }
    }

    func cancelRecording(of program: LiveTVProgram, series: Bool, authManager: AuthManager) async {
        guard let (credential, header) = session(authManager) else { return }
        do {
            if series, let id = program.seriesTimerId {
                try await client.cancelLiveTVSeriesTimer(credential: credential, authHeader: header, seriesTimerId: id)
            } else if let id = program.timerId {
                try await client.cancelLiveTVTimer(credential: credential, authHeader: header, timerId: id)
            }
            await refresh(program, authManager: authManager)
        } catch {
            actionError = String(localized: "Couldn't cancel the recording. Try again.")
        }
    }

    func cancel(_ timer: LiveTVTimer, authManager: AuthManager) async {
        guard let (credential, header) = session(authManager) else { return }
        do {
            try await client.cancelLiveTVTimer(credential: credential, authHeader: header, timerId: timer.id)
            timers.removeAll { $0.id == timer.id }
            clearTimer(id: timer.id)
        } catch {
            actionError = String(localized: "Couldn't cancel the recording. Try again.")
        }
    }

    func cancel(_ seriesTimer: LiveTVSeriesTimer, authManager: AuthManager) async {
        guard let (credential, header) = session(authManager) else { return }
        do {
            try await client.cancelLiveTVSeriesTimer(credential: credential, authHeader: header, seriesTimerId: seriesTimer.id)
            seriesTimers.removeAll { $0.id == seriesTimer.id }
            await loadRecordings(authManager: authManager)
            reloadGuide()
        } catch {
            actionError = String(localized: "Couldn't cancel the series recording. Try again.")
        }
    }

    /// Picks up the programme's new timer state, in the open sheet and the guide.
    private func refresh(_ program: LiveTVProgram, authManager: AuthManager) async {
        guard let (credential, header) = session(authManager) else { return }
        if let fresh = try? await client.getLiveTVProgram(credential: credential, authHeader: header, programId: program.id) {
            if selectedProgram?.id == program.id { selectedProgram = fresh }
            if var list = programs[program.channelId], let i = list.firstIndex(where: { $0.id == program.id }) {
                list[i] = fresh
                programs[program.channelId] = list
            }
        }
        // A series timer marks other showings too.
        if program.isSeries { reloadGuide() }
        await loadRecordings(authManager: authManager)
    }

    private func clearTimer(id: String) {
        for (channelId, list) in programs where list.contains(where: { $0.timerId == id }) {
            programs[channelId] = list.map { var p = $0; if p.timerId == id { p.timerId = nil }; return p }
        }
    }

    /// Forgets the loaded guide so the rows on screen fetch it again.
    private func reloadGuide() {
        requestedGuideChannels = []
        programs = [:]
        guideGeneration += 1
    }
}
