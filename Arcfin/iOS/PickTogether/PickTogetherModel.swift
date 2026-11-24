// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import os
import Telemetry
import AuthCore
import JellyfinAPI

/// One Pick Together session as this device sees it. The session itself lives in the Arcfin
/// Sync plugin: this asks it for the next titles, sends each swipe, and checks every couple of
/// seconds for other people's progress and new matches.
@MainActor
@Observable
final class PickTogetherModel {
    var availability: PickAvailability?
    var state: PickSessionState?
    var genres: [String] = []
    var setup = PickCreateBody()
    var error: String?
    var isBusy = false
    /// A match this person hasn't been shown yet.
    var newMatch: PickMatch?

    private let client = PickTogetherClient()
    @ObservationIgnored private let log = Telemetry.logger(category: "PickTogether")
    private let authManager: AuthManager
    private var pollTask: Task<Void, Never>?
    /// Swipes sent but not yet reflected in a state from the server, so a card doesn't come back.
    private var pending: Set<String> = []
    private var shownMatches: Set<String> = []
    /// A watch-together invite this person said no to, so it isn't shown again.
    private var declinedTogether: String?
    /// The SyncPlay group is being set up or joined, so it happens once.
    private var startingTogether = false

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    var cards: [PickCard] { (state?.cards ?? []).filter { !pending.contains($0.id) } }

    var others: [PickPerson] { state?.people.filter { !$0.isMe } ?? [] }

    // MARK: Loading

    @ObservationIgnored private var started = false

    /// Loads once, and joins a scanned code, in a task of the model's own: a SwiftUI .task ends
    /// when the view is rebuilt (opening full screen does that), which cancelled the requests.
    func start(joinCode: String?) {
        guard !started else { return }
        started = true
        Task {
            await load()
            if let joinCode, availability?.enabled == true, state == nil {
                await join(code: joinCode)
            }
        }
    }

    func load() async {
        guard let (credential, header) = auth() else { return }
        do {
            availability = try await client.availability(credential: credential, authHeader: header)
        } catch {
            show(error)
        }
        guard availability?.enabled == true, genres.isEmpty else { return }
        let types = [setup.movies ? "Movie" : nil, setup.shows ? "Series" : nil].compactMap(\.self).joined(separator: ",")
        genres = (try? await JellyfinMediaClient().getLibraryFilterOptions(
            credential: credential, authHeader: header, libraryId: "", includeItemTypes: types.isEmpty ? nil : types).genres) ?? []
    }

    func create() async {
        await run { credential, header in
            try await self.client.create(self.setup, credential: credential, authHeader: header)
        }
    }

    func join(code: String) async {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }
        await run { credential, header in
            try await self.client.join(code: clean, credential: credential, authHeader: header)
        }
    }

    func swipe(_ card: PickCard, like: Bool) {
        guard let code = state?.code, let (credential, header) = auth() else { return }
        pending.insert(card.id)
        Task {
            do {
                apply(try await client.swipe(code: code, itemID: card.id, like: like, credential: credential, authHeader: header))
            } catch {
                pending.remove(card.id)
                show(error)
            }
        }
    }

    // MARK: Watching together

    /// This person wants to watch the match with everyone, in sync over SyncPlay.
    func watchTogether(_ card: PickCard) async {
        guard let code = state?.code else { return }
        declinedTogether = nil
        await run { credential, header in
            try await self.client.watchTogether(code: code, itemID: card.id, credential: credential, authHeader: header)
        }
    }

    /// "Keep swiping" on a watch-together invite: it isn't shown again for that title.
    func dismissMatch() {
        if let plan = state?.together, plan.itemId == newMatch?.item.id, !plan.iAmIn { declinedTogether = plan.itemId }
        newMatch = nil
    }

    func notTogether() async {
        guard let code = state?.code else { return }
        declinedTogether = state?.together?.itemId
        await run { credential, header in
            try await self.client.notTogether(code: code, credential: credential, authHeader: header)
        }
    }

    /// Once everyone here is in: the leader's device makes the SyncPlay group with the title to
    /// play (a show's next episode, from the leader's own progress), and the others join it.
    /// Returns what this device should then open in its player.
    func advanceTogether(syncPlay: SyncPlayManager) async -> (id: String, startTicks: Int64)? {
        guard let plan = state?.together, plan.iAmIn, !startingTogether, let code = state?.code,
              let (credential, header) = auth() else { return nil }
        if plan.iAmLeader, plan.ready, plan.groupId == nil {
            startingTogether = true
            guard let request = await WatchRoute.resolve(id: plan.itemId, credential: credential, authHeader: header) else {
                startingTogether = false
                error = String(localized: "Couldn't find what to play for that title.")
                return nil
            }
            await syncPlay.createGroup(credential: credential, authHeader: header,
                                       groupName: String(localized: "Pick Together \(code)"),
                                       itemId: request.item.id, startPositionTicks: request.startTicks)
            guard let groupID = syncPlay.currentGroupId else {
                startingTogether = false
                error = syncPlay.lastError ?? String(localized: "Couldn't start SyncPlay. Your profile may not be allowed to make a group.")
                return nil
            }
            do {
                apply(try await client.togetherGroup(code: code, groupID: groupID, playItemID: request.item.id,
                                                     startTicks: request.startTicks, credential: credential, authHeader: header))
            } catch {
                show(error)
            }
            return (request.item.id, request.startTicks)
        }
        if !plan.iAmLeader, let groupID = plan.groupId, let playID = plan.playItemId {
            startingTogether = true
            await syncPlay.refreshGroups(credential: credential, authHeader: header)
            guard let group = syncPlay.availableGroups.first(where: { $0.id == groupID }) else {
                startingTogether = false
                error = String(localized: "The SyncPlay group has already ended.")
                return nil
            }
            await syncPlay.joinGroup(group, credential: credential, authHeader: header)
            guard syncPlay.isInGroup else {
                startingTogether = false
                error = syncPlay.lastError
                return nil
            }
            return (playID, plan.startTicks)
        }
        return nil
    }

    // MARK: Host controls

    var isHost: Bool { state?.isHost == true }

    var hostName: String? { state?.people.first(where: \.isHost)?.name }

    func setLocked(_ locked: Bool) async {
        guard let code = state?.code else { return }
        await run { credential, header in
            try await self.client.lock(code: code, locked: locked, credential: credential, authHeader: header)
        }
    }

    func remove(_ person: PickPerson) async {
        guard let code = state?.code else { return }
        await run { credential, header in
            try await self.client.remove(code: code, personID: person.id, credential: credential, authHeader: header)
        }
    }

    func restart() async {
        guard let code = state?.code else { return }
        await run { credential, header in
            try await self.client.restart(code: code, credential: credential, authHeader: header)
        }
    }

    func leave() {
        pollTask?.cancel()
        guard let code = state?.code, let (credential, header) = auth() else { return }
        state = nil
        Task { await client.leave(code: code, credential: credential, authHeader: header) }
    }

    // MARK: Joining

    /// What the session's QR code holds: only the code.
    var joinLink: URL? { state.map { PickTogetherClient.joinLink(code: $0.code) } }

    // MARK: Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let code = self.state?.code, let (credential, header) = self.auth() else { return }
                do {
                    self.apply(try await self.client.state(code: code, credential: credential, authHeader: header))
                } catch let error as PickTogetherError where error.status == 404 {
                    self.error = error.message ?? String(localized: "This session has ended.")
                    self.state = nil
                    return
                } catch {
                    // A missed check is fine; the next one catches up.
                }
            }
        }
    }

    private func apply(_ new: PickSessionState) {
        if new.round != state?.round { pending.removeAll() }
        pending.formIntersection(Set(new.cards.map(\.id)))
        state = new
        let key = { (m: PickMatch) in "\(m.round)-\(m.item.id)" }
        if let fresh = new.matches.first(where: { !shownMatches.contains(key($0)) }) {
            new.matches.forEach { shownMatches.insert(key($0)) }
            newMatch = fresh
        }
        // Someone asked to watch a match together: show it to everyone who hasn't answered.
        if newMatch == nil, let plan = new.together, !plan.iAmIn, plan.groupId == nil, plan.itemId != declinedTogether,
           let match = new.matches.last(where: { $0.item.id == plan.itemId }) {
            newMatch = match
        }
    }

    // MARK: Plumbing

    private func run(_ call: @escaping (ServerCredential, String) async throws -> PickSessionState) async {
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

    /// What to tell the person, and the whole error in the log for working out what happened.
    private func message(for error: Error) -> String {
        log.error("Pick Together failed: \(String(describing: error), privacy: .public)")
        switch error {
        case let error as PickTogetherError where error.message != nil:
            return error.message!
        case let error as PickTogetherError where error.status == 404:
            return String(localized: "Pick Together needs the Arcfin Sync plugin, version 0.5 or later, on your server.")
        case let error as PickTogetherError where error.status == 401:
            return String(localized: "Your sign-in to this server has expired. Sign in again, then try once more.")
        case let error as PickTogetherError where error.status > 0:
            return String(localized: "Your server couldn't do that (error \(error.status)). Try again in a moment.")
        case is DecodingError:
            return String(localized: "Arcfin couldn't read your server's answer. Make sure the Arcfin Sync plugin is up to date.")
        default:
            return String(localized: "Couldn't reach your server. Check your connection and try again.")
        }
    }
}
