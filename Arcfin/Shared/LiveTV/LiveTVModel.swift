// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// The channels a channel was played from, for the player's channel list: the same list the
/// play queue steps through with Previous and Next, with what's on each.
@MainActor
enum LiveTVQueue {
    static var channels: [LiveTVChannel] = []
}

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

    /// Search, on the Live TV screen and in Browse.
    var searchQuery = ""
    private(set) var searchChannels: [LiveTVChannel] = []
    private(set) var searchPrograms: [LiveTVProgram] = []
    private(set) var isSearching = false
    private var searchTask: Task<Void, Never>?

    var hasSearchResults: Bool { !searchChannels.isEmpty || !searchPrograms.isEmpty }

    var selectedProgram: LiveTVProgram?
    var playbackRequest: MediaDetailView.PlaybackRequest?
    var actionError: String?
    /// A series recording whose options are open for editing.
    var editingSeriesTimer: LiveTVSeriesTimer?
    /// Programmes with a reminder set on this device.
    private(set) var reminders: Set<String> = []

    func loadReminders() async {
        reminders = await NotificationManager.reminderProgramIDs()
    }

    func toggleReminder(for program: LiveTVProgram) async {
        if reminders.contains(program.id) {
            NotificationManager.cancelReminder(programID: program.id)
            reminders.remove(program.id)
            return
        }
        let channelName = channel(for: program)?.name ?? program.channelName ?? ""
        if await NotificationManager.remind(programID: program.id, title: program.name, channelName: channelName,
                                            channelID: program.channelId, startsAt: program.startDate) {
            reminders.insert(program.id)
            HapticManager.impact(.light)
        } else {
            actionError = String(localized: "Couldn't set a reminder. Check that Arcfin is allowed to send notifications in Settings.")
        }
    }

    private let client = JellyfinMediaClient()

    var visibleChannels: [LiveTVChannel] { favoritesOnly ? favoriteChannels : channels }

    /// The guide narrowed to one kind of programme; nil shows everything.
    private(set) var guideCategory: LiveTVCategory?
    /// The channels showing that kind of programme, as the server finds them.
    private(set) var categoryChannels: [LiveTVChannel] = []
    private(set) var isLoadingCategory = false
    private(set) var categoryFailed = false

    var guideChannels: [LiveTVChannel] {
        guard guideCategory != nil else { return visibleChannels }
        return favoritesOnly ? categoryChannels.filter(\.isFavorite) : categoryChannels
    }

    func selectCategory(_ category: LiveTVCategory?, authManager: AuthManager) {
        guard category != guideCategory else { return }
        guideCategory = category
        categoryChannels = []
        reloadGuide()
        loadCategory(authManager: authManager)
    }

    func retryCategory(authManager: AuthManager) {
        loadCategory(authManager: authManager)
    }

    private func loadCategory(authManager: AuthManager) {
        categoryFailed = false
        guard let category = guideCategory, let (credential, header) = session(authManager) else {
            isLoadingCategory = false
            return
        }
        isLoadingCategory = true
        Task {
            let page = try? await client.getLiveTVChannels(credential: credential, authHeader: header,
                                                           limit: 500, category: category)
            guard guideCategory == category else { return }
            categoryChannels = page?.channels ?? []
            categoryFailed = page == nil
            isLoadingCategory = false
        }
    }

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
        if let i = searchChannels.firstIndex(where: { $0.id == channel.id }) { searchChannels[i].isFavorite = favorite }
        if favorite {
            guard !favoriteChannels.contains(where: { $0.id == channel.id }) else { return }
            var updated = channel
            updated.isFavorite = true
            favoriteChannels.append(updated)
        } else {
            favoriteChannels.removeAll { $0.id == channel.id }
        }
    }

    /// Plays a channel, with the others in the list a channel up or down away: the list it
    /// was picked from, or else the channel list.
    func play(_ channel: LiveTVChannel, among list: [LiveTVChannel]? = nil) {
        let list = list ?? (visibleChannels.contains(where: { $0.id == channel.id }) ? visibleChannels : channels)
        let queue = list.contains(where: { $0.id == channel.id }) ? list : [channel]
        PlayQueue.start(queue.map(\.mediaItem))
        LiveTVQueue.channels = queue
        playbackRequest = MediaDetailView.PlaybackRequest(item: channel.mediaItem, startTicks: 0)
    }

    func play(_ recording: LiveTVRecording) {
        PlayQueue.clear()
        let resume = recording.item.userData?.played == true ? 0 : (recording.item.userData?.playbackPositionTicks ?? 0)
        playbackRequest = MediaDetailView.PlaybackRequest(item: recording.item, startTicks: resume)
    }

    /// The programme's channel, from whatever's loaded; a programme found by search can be on
    /// one that isn't, and its id and name are enough to play it.
    func channel(for program: LiveTVProgram) -> LiveTVChannel? {
        channels.first { $0.id == program.channelId }
            ?? favoriteChannels.first { $0.id == program.channelId }
            ?? searchChannels.first { $0.id == program.channelId }
            ?? LiveTVChannel(id: program.channelId, name: program.channelName ?? "")
    }

    // MARK: - Search

    /// Waits for a pause in typing and drops a search still running for an older query.
    func search(authManager: AuthManager) {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let (credential, header) = session(authManager) else {
            searchChannels = []
            searchPrograms = []
            isSearching = false
            return
        }
        isSearching = true
        let includePrograms = hasGuide != false
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let found = try? await client.searchLiveTV(credential: credential, authHeader: header,
                                                       query: query, includePrograms: includePrograms)
            guard !Task.isCancelled else { return }
            searchChannels = found?.channels ?? []
            searchPrograms = found?.programs ?? []
            isSearching = false
        }
    }

    // MARK: - Guide

    /// Loads the guide for a block of channels around one that's coming on screen.
    func loadGuide(around channel: LiveTVChannel, authManager: AuthManager) async {
        guard hasGuide != false, !requestedGuideChannels.contains(channel.id),
              let index = guideChannels.firstIndex(where: { $0.id == channel.id }),
              let (credential, header) = session(authManager) else { return }
        let block = guideChannels[index..<min(index + 25, guideChannels.count)]
            .map(\.id).filter { !requestedGuideChannels.contains($0) }
        guard !block.isEmpty else { return }
        requestedGuideChannels.formUnion(block)
        do {
            let found = try await client.getLiveTVPrograms(credential: credential, authHeader: header,
                                                           channelIds: block, from: guideStart, to: guideEnd,
                                                           category: guideCategory)
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

    func record(_ program: LiveTVProgram, series: Bool, options: LiveTVSeriesOptions? = nil, authManager: AuthManager) async {
        guard let (credential, header) = session(authManager) else { return }
        do {
            if series {
                try await client.recordLiveTVSeries(credential: credential, authHeader: header, programId: program.id, options: options)
            } else {
                try await client.recordLiveTVProgram(credential: credential, authHeader: header, programId: program.id)
            }
            HapticManager.impact(.medium)
            await refresh(program, authManager: authManager)
            warnIfClashing(program)
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

    /// The server marks a timer it can't fit on a free tuner as conflicted.
    private func warnIfClashing(_ program: LiveTVProgram) {
        guard timers.contains(where: { $0.programId == program.id && $0.hasProblem }) else { return }
        actionError = String(localized: "This clashes with another recording, and there isn't a free tuner for both. Cancel one of them in Recordings, or the server will only record one.")
    }

    /// The server's starting options for a series, for the options shown before recording it.
    func seriesDefaults(for program: LiveTVProgram, authManager: AuthManager) async -> LiveTVSeriesOptions {
        guard let (credential, header) = session(authManager),
              let options = try? await client.liveTVSeriesDefaults(credential: credential, authHeader: header, programId: program.id)
        else { return LiveTVSeriesOptions() }
        return options
    }

    func options(for seriesTimer: LiveTVSeriesTimer, authManager: AuthManager) async -> LiveTVSeriesOptions? {
        guard let (credential, header) = session(authManager) else { return nil }
        return try? await client.liveTVSeriesOptions(credential: credential, authHeader: header, seriesTimerId: seriesTimer.id)
    }

    /// Saves a series recording's changed options; true when the server took them.
    func save(_ options: LiveTVSeriesOptions, for seriesTimer: LiveTVSeriesTimer, authManager: AuthManager) async -> Bool {
        guard let (credential, header) = session(authManager) else { return false }
        do {
            try await client.updateLiveTVSeriesTimer(credential: credential, authHeader: header,
                                                     seriesTimerId: seriesTimer.id, options: options)
            await loadRecordings(authManager: authManager)
            reloadGuide()
            return true
        } catch {
            actionError = String(localized: "Couldn't save the series recording's options. Try again.")
            return false
        }
    }

    func delete(_ recording: LiveTVRecording, authManager: AuthManager) async {
        guard let (credential, header) = session(authManager) else { return }
        do {
            try await client.deleteLiveTVRecording(credential: credential, authHeader: header, recordingId: recording.id)
            recordings.removeAll { $0.id == recording.id }
        } catch {
            actionError = String(localized: "Couldn't delete the recording. Check that your profile is allowed to manage recordings.")
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
