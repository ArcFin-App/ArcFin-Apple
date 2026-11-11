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
    private(set) var channels: [LiveTVChannel] = []
    private(set) var isLoadingChannels = true
    private(set) var channelsFailed = false
    var favoritesOnly = false

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

    var visibleChannels: [LiveTVChannel] {
        favoritesOnly ? channels.filter(\.isFavorite) : channels
    }

    var hasFavorites: Bool { channels.contains(where: \.isFavorite) }

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
        do {
            channels = try await client.getLiveTVChannels(credential: credential, authHeader: header)
            channelsFailed = false
        } catch {
            if channels.isEmpty { channelsFailed = true }
        }
        isLoadingChannels = false
    }

    /// What's on now moves on every few minutes; called on a timer while the screen is open.
    func refreshNowPlaying(authManager: AuthManager) async {
        guard let (credential, header) = session(authManager),
              let fresh = try? await client.getLiveTVChannels(credential: credential, authHeader: header) else { return }
        channels = fresh
        let start = Self.halfHour(before: .now)
        if start != guideStart {
            guideStart = start
            reloadGuide()
        }
    }

    func toggleFavorite(_ channel: LiveTVChannel, authManager: AuthManager) {
        guard let (credential, header) = session(authManager),
              let index = channels.firstIndex(where: { $0.id == channel.id }) else { return }
        let newValue = !channel.isFavorite
        channels[index].isFavorite = newValue
        HapticManager.impact(.light)
        Task {
            do {
                try await client.markFavorite(credential: credential, authHeader: header, itemId: channel.id, favorite: newValue)
            } catch {
                if let i = channels.firstIndex(where: { $0.id == channel.id }) { channels[i].isFavorite = !newValue }
            }
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
        channels.first { $0.id == program.channelId }
    }

    // MARK: - Guide

    /// Loads the guide for a block of channels around one that's coming on screen.
    func loadGuide(around channel: LiveTVChannel, authManager: AuthManager) async {
        guard !requestedGuideChannels.contains(channel.id),
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
