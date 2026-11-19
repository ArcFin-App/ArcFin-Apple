// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers
import AuthCore
import JellyfinAPI
import os
import Telemetry

/// Brings listening history from Spotify, Apple Music or YouTube Music: from the export file
/// each one gives out, to ListenBrainz with the times of the plays, and to Jellyfin as songs
/// played.
@MainActor @Observable
final class MusicHistoryImportModel {
    enum Phase: Equatable { case choosing, ready, importing, done }

    private(set) var phase = Phase.choosing
    private(set) var plays: [ImportedPlay] = []
    private(set) var sources: Set<ListeningHistoryImport.Source> = []
    private(set) var unreadFiles: [String] = []
    var sendsToListenBrainz = true
    var marksInJellyfin = true
    private(set) var sent = 0
    private(set) var songsChecked = 0
    private(set) var matched = 0
    /// In the library and played there already, so left as they are.
    private(set) var alreadyPlayed = 0
    private(set) var wasCancelled = false
    @ObservationIgnored private var job: Task<Void, Never>?
    private(set) var notInLibrary: [String] = []
    private(set) var listenBrainzFailed = false
    private let log = Telemetry.logger(category: "HistoryImport")

    var listenBrainzToken: String? {
        AppServices.authManager.state.credential.flatMap { ListenBrainzCredential.load(profile: $0.id) }
    }

    /// Each song once, with when it was last played.
    var songs: [(play: ImportedPlay, last: Date)] {
        Dictionary(grouping: plays, by: \.songKey).values.compactMap { group in
            group.max { $0.playedAt < $1.playedAt }.map { ($0, $0.playedAt) }
        }
        .sorted { $0.last > $1.last }
    }

    var dateRange: ClosedRange<Date>? {
        guard let first = plays.map(\.playedAt).min(), let last = plays.map(\.playedAt).max() else { return nil }
        return first...last
    }

    func read(_ urls: [URL]) {
        var all = Set(plays)
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let result = try? ListeningHistoryImport.read(data) else {
                unreadFiles.append(url.lastPathComponent)
                continue
            }
            sources.insert(result.source)
            all.formUnion(result.plays)
        }
        plays = all.sorted { $0.playedAt < $1.playedAt }
        phase = plays.isEmpty ? .choosing : .ready
        sendsToListenBrainz = listenBrainzToken != nil
    }

    func start() {
        phase = .importing
        job = Task {
            if sendsToListenBrainz, let token = listenBrainzToken { await sendToListenBrainz(token: token) }
            if marksInJellyfin, !Task.isCancelled { await markInJellyfin() }
            wasCancelled = Task.isCancelled
            phase = .done
        }
    }

    func cancel() { job?.cancel() }

    private func sendToListenBrainz(token: String) async {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let client = ListenBrainzClient(token: token, clientVersion: version)
        let listens = plays.map {
            ListenBrainzListen(listenedAt: Int($0.playedAt.timeIntervalSince1970), artist: $0.artist, track: $0.track,
                               release: $0.album, durationMS: $0.playedMS)
        }
        var start = 0
        while start < listens.count, !Task.isCancelled {
            let batch = Array(listens[start..<min(start + ListenBrainzClient.maxListensPerRequest, listens.count)])
            do {
                try await client.submit(batch)
                sent += batch.count
                start += batch.count
                try? await Task.sleep(for: .milliseconds(500))
            } catch ListenBrainzError.rejected(status: 429) {
                // Too many at once: ListenBrainz asks to wait.
                try? await Task.sleep(for: .seconds(10))
            } catch {
                log.error("ListenBrainz took \(self.sent, privacy: .public) listens, then: \(error.localizedDescription, privacy: .public)")
                listenBrainzFailed = true
                return
            }
        }
    }

    /// Finds each song in the library by its title and artist, a few at a time.
    private func markInJellyfin() async {
        let songs = songs
        let chunks = stride(from: 0, to: songs.count, by: 4).map { Array(songs[$0..<min($0 + 4, songs.count)]) }
        for chunk in chunks where !Task.isCancelled {
            let found = await withTaskGroup(of: (String, Mark).self) { group in
                for song in chunk {
                    group.addTask { await (Self.label(song.play), Self.mark(song.play, at: song.last)) }
                }
                return await group.reduce(into: [(String, Mark)]()) { $0.append($1) }
            }
            for (label, mark) in found {
                songsChecked += 1
                switch mark {
                case .marked: matched += 1
                case .alreadyPlayed: alreadyPlayed += 1
                case .notFound: notInLibrary.append(label)
                }
            }
        }
    }

    private nonisolated static func label(_ play: ImportedPlay) -> String { "\(play.artist) – \(play.track)" }

    enum Mark: Sendable { case marked, alreadyPlayed, notFound }

    /// Only a song Jellyfin has never seen played is marked: one played there already keeps
    /// its own last-played date and count, so a second import doesn't count anything twice.
    private static func mark(_ play: ImportedPlay, at date: Date) async -> Mark {
        let track = play.track.lowercased(), artist = play.artist.lowercased()
        guard let results = try? await MusicAPI.call({
            try await $0.searchMusic(credential: $1, authHeader: $2, term: play.track, limit: 12)
        }), let song = results.songs.first(where: {
            $0.name.lowercased() == track && ($0.artistLine?.lowercased().contains(artist) ?? false)
        }) else { return .notFound }
        guard song.playCount == 0 else { return .alreadyPlayed }
        let marked = (try? await MusicAPI.call { try await $0.markPlayed(credential: $1, authHeader: $2, itemId: song.id, at: date) }) != nil
        return marked ? .marked : .notFound
    }
}

struct MusicHistoryImportView: View {
    @State private var model = MusicHistoryImportModel()
    @State private var isChoosing = false

    var body: some View {
        List {
            Section {
                step("Spotify", "spotify.com › Account › Privacy settings › Download your data: Extended streaming history. Pick the Streaming_History_Audio files.")
                step("Apple Music", "privacy.apple.com › Get a copy of your data › Apple Media Services. Pick Apple Music Play Activity.csv, or Play History Daily Tracks.csv.")
                step("YouTube Music", "takeout.google.com › YouTube and YouTube Music › history, as JSON. Pick watch-history.json.")
            } header: {
                Text("Get Your History")
            } footer: {
                Text("Each service emails a link when the file is ready, which can take a few days. Open the zip in Files, then pick the files inside.")
            }
            Section {
                Button("Choose Files…", systemImage: "doc.badge.plus") { isChoosing = true }
                    .disabled(model.phase == .importing)
                ForEach(model.unreadFiles, id: \.self) { name in
                    Label("\(name) isn't a history this can read", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(DT.Color.palette("F59E0B"))
                }
            }
            if model.phase != .choosing { summary }
        }
        .arcfinListStyle()
        .screenBackground()
        .navigationTitle("Import Listening History")
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.json, .commaSeparatedText, .plainText],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { model.read(urls) }
        }
    }

    private func step(_ title: String, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(DT.Color.textSecondary)
        }
    }

    @ViewBuilder
    private var summary: some View {
        Section {
            LabeledContent("Plays", value: model.plays.count.formatted())
            LabeledContent("Songs", value: model.songs.count.formatted())
            if let range = model.dateRange {
                LabeledContent("From", value: range.lowerBound.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("To", value: range.upperBound.formatted(date: .abbreviated, time: .omitted))
            }
        } header: {
            Text("Found")
        } footer: {
            Text("Plays under 30 seconds count as skips and are left out.")
        }
        Section {
            Toggle(isOn: $model.sendsToListenBrainz) {
                TVRowLabelText(title: "Send to ListenBrainz", detail: model.listenBrainzToken == nil
                               ? "Add your ListenBrainz token in Settings › Integrations first."
                               : "Every play, with the time it was played.")
            }
            .disabled(model.listenBrainzToken == nil || model.phase != .ready)
            Toggle(isOn: $model.marksInJellyfin) {
                TVRowLabelText(title: "Mark Played in Jellyfin", detail: "Songs in your library that you haven't played in Jellyfin yet are marked played on the day you last played them. Songs already played there keep their own count and date.")
            }
            .disabled(model.phase != .ready)
            if model.phase == .ready {
                Button("Import", systemImage: "square.and.arrow.down") { model.start() }
                    .disabled(!model.sendsToListenBrainz && !model.marksInJellyfin)
            }
        }
        if model.phase == .importing || model.phase == .done { progress }
    }

    @ViewBuilder
    private var progress: some View {
        Section {
            if model.sendsToListenBrainz {
                LabeledContent("Sent to ListenBrainz", value: String(localized: "\(model.sent.formatted()) of \(model.plays.count.formatted())"))
                if model.listenBrainzFailed {
                    Text("ListenBrainz stopped taking listens. Try again later; plays already sent aren't counted twice.")
                        .font(.footnote)
                        .foregroundStyle(DT.Color.palette("F43F5E"))
                }
            }
            if model.marksInJellyfin {
                LabeledContent("Checked in Your Library", value: String(localized: "\(model.songsChecked.formatted()) of \(model.songs.count.formatted())"))
                LabeledContent("Marked Played", value: model.matched.formatted())
                LabeledContent("Already Played in Jellyfin", value: model.alreadyPlayed.formatted())
            }
            if model.phase == .importing {
                HStack { Spacer(); ProgressView(); Spacer() }
                Button("Cancel", role: .destructive) { model.cancel() }
            }
        } header: {
            Text(model.phase == .done ? (model.wasCancelled ? "Cancelled" : "Done") : "Importing")
        } footer: {
            if model.phase == .importing { Text("Keep Arcfin open until it's done.") }
        }
        if model.phase == .done, !model.notInLibrary.isEmpty {
            Section("Not in Your Library") {
                ForEach(model.notInLibrary.prefix(200), id: \.self) { Text(verbatim: $0).font(.footnote) }
                if model.notInLibrary.count > 200 {
                    Text("And \(model.notInLibrary.count - 200) more").font(.footnote).foregroundStyle(DT.Color.textSecondary)
                }
            }
        }
    }
}
