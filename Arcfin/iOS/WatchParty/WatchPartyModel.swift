// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import os
import Telemetry
import AuthCore
import JellyfinAPI

/// One watch party as this device sees it. The party lives in the Arcfin Sync plugin: the host
/// picks a title, everyone gathers in the lobby, and on Start the host's device makes a
/// SyncPlay group that the others join.
@MainActor
@Observable
final class WatchPartyModel {
    var availability: PickAvailability?
    var state: WatchPartyState?
    /// Every party this device is in, soonest first, for getting back to one.
    var myParties: [WatchPartyState] = []
    var error: String?
    var isBusy = false
    /// The host's device is making the SyncPlay group, or this one is joining it.
    private(set) var isConnecting = false
    /// Joining the host's group failed; Try Again starts it over.
    private(set) var joinFailed = false

    private let client = ArcfinCompanionClient()
    @ObservationIgnored private let log = Telemetry.logger(category: "WatchParty")
    private let authManager: AuthManager
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// The group this device already joined, so a poll doesn't join it twice.
    @ObservationIgnored private var joinedGroup: String?
    @ObservationIgnored private var started = false
    /// When each party's notification was last set for, so a poll doesn't set it again.
    @ObservationIgnored private var reminded: [String: Date] = [:]

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    var isHost: Bool { state?.isHost == true }

    var others: [PartyPerson] { state?.people.filter { !$0.isMe } ?? [] }

    var hostName: String? { state?.people.first(where: \.isHost)?.name }

    var link: URL? { state.map { ArcfinCompanionClient.partyLink(code: $0.code) } }

    var posterURL: URL? {
        guard let itemID = state?.itemId, let credential = authManager.state.credential else { return nil }
        return JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: itemID, tag: "", type: .primary,
                                            fillWidth: 700, token: credential.accessToken)
    }

    // MARK: Loading

    /// Loads once, then joins a scanned code, in a task of the model's own: a SwiftUI .task
    /// ends when the view is rebuilt (opening full screen does that), which cancelled the requests.
    /// A host picks Now or a time before the party is made.
    func start(joinCode: String?) {
        guard !started else { return }
        started = true
        Task {
            await load()
            guard availability?.enabled == true, state == nil else { return }
            if let joinCode {
                await join(code: joinCode)
            }
            await loadMyParties()
        }
    }

    func loadMyParties() async {
        guard let (credential, header) = auth(),
              let parties = try? await client.myParties(credential: credential, authHeader: header) else { return }
        myParties = parties
        await syncReminders(parties)
    }

    /// Back into a party this device is already in.
    func reopen(_ party: WatchPartyState) async {
        await run { credential, header in
            try await self.client.party(code: party.code, timeZone: TimeZone.current.identifier, credential: credential, authHeader: header)
        }
    }

    func load() async {
        guard let (credential, header) = auth() else { return }
        do {
            availability = try await client.partyAvailability(credential: credential, authHeader: header)
        } catch {
            show(error)
        }
    }

    /// A party on now, or one for `scheduledFor`.
    func create(itemID: String, scheduledFor: Date?) async {
        await run { credential, header in
            try await self.client.createParty(itemID: itemID, scheduledFor: scheduledFor, timeZone: TimeZone.current.identifier, credential: credential, authHeader: header)
        }
    }

    /// The host moves the start; nil makes it on now.
    func schedule(_ date: Date?) async {
        guard let code = state?.code else { return }
        await run { credential, header in
            try await self.client.scheduleParty(date, code: code, credential: credential, authHeader: header)
        }
    }

    /// The host calls it off for everyone. True once it's over.
    func end() async -> Bool {
        guard let code = state?.code, let (credential, header) = auth() else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.endParty(code: code, credential: credential, authHeader: header)
        } catch {
            show(error)
            return false
        }
        stopPolling()
        forget(code)
        state = nil
        return true
    }

    func join(code: String) async {
        guard let clean = ArcfinCompanionClient.partyCode(from: code) else {
            error = String(localized: "That isn't a watch party code. It's the six letters and numbers under the QR code.")
            return
        }
        await run { credential, header in
            try await self.client.joinParty(code: clean, timeZone: TimeZone.current.identifier, credential: credential, authHeader: header)
        }
    }

    // MARK: Lobby

    func setReady(_ ready: Bool) async {
        guard let code = state?.code else { return }
        await run { credential, header in
            try await self.client.setReady(ready, code: code, credential: credential, authHeader: header)
        }
    }

    func setLocked(_ locked: Bool) async {
        guard let code = state?.code else { return }
        await run { credential, header in
            try await self.client.setPartyLocked(locked, code: code, credential: credential, authHeader: header)
        }
    }

    func remove(_ person: PartyPerson) async {
        guard let code = state?.code else { return }
        await run { credential, header in
            try await self.client.removeFromParty(personID: person.id, code: code, credential: credential, authHeader: header)
        }
    }

    /// Back to the lobby, for a start that never got going.
    func reset() async {
        guard let code = state?.code else { return }
        await run { credential, header in
            try await self.client.resetParty(code: code, credential: credential, authHeader: header)
        }
    }

    func leave() {
        stopPolling()
        guard let code = state?.code, let (credential, header) = auth() else { return }
        forget(code)
        state = nil
        Task { await client.leaveParty(code: code, credential: credential, authHeader: header) }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Starting

    /// The host says go: from the host's own resume position, the host's device makes the
    /// SyncPlay group and posts it for the others. Returns what to open in this device's player.
    func startWatching(syncPlay: SyncPlayManager) async -> PlaybackRequest? {
        guard let party = state, party.isHost, party.isLobby || party.isWaiting, !isConnecting, let (credential, header) = auth() else { return nil }
        isConnecting = true
        defer { isConnecting = false }
        guard let request = await WatchRoute.resolve(id: party.itemId, credential: credential, authHeader: header) else {
            error = String(localized: "Couldn't find what to play for that title.")
            return nil
        }
        do {
            apply(try await client.startParty(code: party.code, startTicks: request.startTicks,
                                              credential: credential, authHeader: header))
        } catch {
            show(error)
            return nil
        }
        if syncPlay.isInGroup { await syncPlay.leaveGroupAndWait(credential: credential, authHeader: header) }
        syncPlay.lastError = nil
        // Found again by name, so each start gets its own: an earlier one may still be open.
        let groupName = String(localized: "Watch Party \(party.code)") + " · "
            + Date.now.formatted(.dateTime.hour().minute().second())
        await syncPlay.createGroup(credential: credential, authHeader: header, groupName: groupName,
                                   itemId: request.item.id, startPositionTicks: request.startTicks)
        guard let groupID = syncPlay.currentGroupId else {
            let message = syncPlay.lastError ?? String(localized: "Couldn't start SyncPlay. Your profile may not be allowed to make a group.")
            await reset()
            error = message
            return nil
        }
        do {
            apply(try await client.partyGroup(groupID, name: syncPlay.groupName ?? groupName, code: party.code, credential: credential, authHeader: header))
        } catch {
            await syncPlay.leaveGroupAndWait(credential: credential, authHeader: header)
            show(error)
            let message = self.error
            await reset()
            self.error = message
            return nil
        }
        joinedGroup = groupID
        return request
    }

    /// Once the host's group is up, everyone else joins it. Returns what to open in the player:
    /// the party's title from the host's position, never this person's own.
    func joinStarted(syncPlay: SyncPlayManager) async -> PlaybackRequest? {
        guard let party = state, !party.isHost, party.isStarted, let groupID = party.groupId,
              groupID != joinedGroup, !isConnecting, !joinFailed, let (credential, header) = auth() else { return nil }
        isConnecting = true
        defer { isConnecting = false }
        guard let request = await WatchRoute.resolve(id: party.itemId, startTicks: party.startTicks,
                                                     credential: credential, authHeader: header) else {
            fail(String(localized: "Couldn't find what to play for that title."))
            return nil
        }
        await syncPlay.refreshGroups(credential: credential, authHeader: header)
        guard let group = syncPlay.availableGroups.first(where: { $0.id == groupID }) else {
            fail(String(localized: "The SyncPlay group has already ended."))
            return nil
        }
        if syncPlay.isInGroup, syncPlay.currentGroupId != groupID {
            await syncPlay.leaveGroupAndWait(credential: credential, authHeader: header)
        }
        if !syncPlay.isInGroup {
            syncPlay.lastError = nil
            await syncPlay.joinGroup(group, credential: credential, authHeader: header)
        }
        guard syncPlay.currentGroupId == groupID else {
            fail(syncPlay.lastError ?? String(localized: "Couldn't join the watch party's SyncPlay group."))
            return nil
        }
        joinedGroup = groupID
        return PlaybackRequest(item: request.item, startTicks: party.startTicks)
    }

    func retryJoin() {
        joinFailed = false
        error = nil
    }

    private func fail(_ message: String) {
        joinFailed = true
        error = message
    }

    // MARK: Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.pollInterval ?? 2))
                guard let self, let code = self.state?.code, let (credential, header) = self.auth() else { return }
                do {
                    self.apply(try await self.client.party(code: code, timeZone: TimeZone.current.identifier, credential: credential, authHeader: header))
                } catch let error as PickTogetherError where error.status == 404 {
                    self.error = error.message ?? String(localized: "This watch party has ended.")
                    self.forget(code)
                    self.state = nil
                    return
                } catch {
                    // A missed check is fine; the next one catches up.
                }
            }
        }
    }

    /// Every 15 seconds while a scheduled party waits for its lobby, or sooner when it's about to open.
    private var pollInterval: Double {
        guard let party = state, party.isWaiting else { return 2 }
        let untilOpen = party.lobbyOpens.map { $0.timeIntervalSinceNow + 1 } ?? 15
        return min(15, max(2, untilOpen))
    }

    private func apply(_ new: WatchPartyState) {
        if new.isLobby {
            joinedGroup = nil
            joinFailed = false
        }
        state = new
        Task { await remind(new) }
    }

    // MARK: Notifications

    /// A notification for when the lobby opens, while the party is still waiting; none otherwise.
    private func remind(_ party: WatchPartyState) async {
        guard party.isWaiting, let opens = party.lobbyOpens, opens > .now else {
            if reminded[party.code] != .distantPast {
                NotificationManager.cancelPartyReminder(code: party.code)
                reminded[party.code] = .distantPast
            }
            return
        }
        guard reminded[party.code] != opens else { return }
        reminded[party.code] = opens
        await NotificationManager.remindParty(code: party.code, title: party.itemName, lobbyOpens: opens,
                                              link: ArcfinCompanionClient.partyLink(code: party.code))
    }

    /// Matches the notifications to the parties this device is in.
    private func syncReminders(_ parties: [WatchPartyState]) async {
        let codes = Set(parties.map(\.code))
        for code in await NotificationManager.partyReminderCodes() where !codes.contains(code) {
            forget(code)
        }
        for party in parties { await remind(party) }
    }

    private func forget(_ code: String) {
        reminded[code] = nil
        NotificationManager.cancelPartyReminder(code: code)
    }

    // MARK: Plumbing

    private func run(_ call: @escaping (ServerCredential, String) async throws -> WatchPartyState) async {
        guard let (credential, header) = auth() else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let first = state == nil
            apply(try await call(credential, header))
            error = nil
            if first { startPolling() }
        } catch {
            show(error)
        }
    }

    private func auth() -> (ServerCredential, String)? {
        guard let credential = authManager.state.credential else { return nil }
        return (credential, authManager.authClient.authHeader(token: credential.accessToken))
    }

    /// Shows what went wrong, except a cancelled request: nothing failed, it just wasn't needed.
    private func show(_ error: Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        self.error = message(for: error)
    }

    private func message(for error: Error) -> String {
        log.error("Watch party failed: \(String(describing: error), privacy: .public)")
        switch error {
        case let error as PickTogetherError where error.message != nil:
            return error.message!
        case let error as PickTogetherError where error.status == 404:
            return String(localized: "Watch parties need the latest Arcfin Sync plugin on your server.")
        case let error as PickTogetherError where error.status == 401:
            return String(localized: "Your sign-in to this server has expired. Sign in again, then try once more.")
        case let error as PickTogetherError where error.status == 403:
            return String(localized: "Your server's admin has turned off watch parties for you.")
        case let error as PickTogetherError where error.status > 0:
            return String(localized: "Your server couldn't do that (error \(error.status)). Try again in a moment.")
        case is DecodingError:
            return String(localized: "Arcfin couldn't read your server's answer. Make sure the Arcfin Sync plugin is up to date.")
        default:
            return String(localized: "Couldn't reach your server. Check your connection and try again.")
        }
    }
}
