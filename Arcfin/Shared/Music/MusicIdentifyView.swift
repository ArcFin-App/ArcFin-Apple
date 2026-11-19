// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AVFoundation
import JellyfinAPI
import ShazamKit

/// What's Playing?: listens with ShazamKit, names the song, and finds it in the library to
/// play here, or says it isn't there.
@MainActor @Observable
final class MusicIdentifyModel {
    enum Phase: Equatable {
        case listening
        case found(title: String, artist: String?, artwork: URL?, appleMusic: URL?)
        case noMatch
        case failed(String)
    }

    private(set) var phase = Phase.listening
    private(set) var inLibrary: [MusicSong] = []
    @ObservationIgnored private var session: SHManagedSession?

    func listen() async {
        phase = .listening
        inLibrary = []
        guard await AVAudioApplication.requestRecordPermission() else {
            phase = .failed(String(localized: "Allow the microphone for Arcfin in Settings to name songs."))
            return
        }
        let session = SHManagedSession()
        self.session = session
        // What plays here would drown out the song in the room.
        let wasPlaying = AppServices.music.isPlaying
        if wasPlaying { AppServices.music.pause() }
        let result = await session.result()
        if wasPlaying { AppServices.music.resume() }
        self.session = nil
        switch result {
        case .match(let match):
            guard let item = match.mediaItems.first, let title = item.title else { return phase = .noMatch }
            phase = .found(title: title, artist: item.artist, artwork: item.artworkURL, appleMusic: item.appleMusicURL)
            await findInLibrary(title: title, artist: item.artist)
        case .noMatch:
            phase = .noMatch
        case .error(let error, _):
            phase = .failed(String(localized: "Shazam couldn't listen. \(error.localizedDescription)"))
        }
    }

    func cancel() { session?.cancel() }

    private func findInLibrary(title: String, artist: String?) async {
        let name = title.lowercased(), artist = artist?.lowercased() ?? ""
        let results = try? await MusicAPI.call { try await $0.searchMusic(credential: $1, authHeader: $2, term: title, limit: 12) }
        inLibrary = (results?.songs ?? []).filter {
            $0.name.lowercased() == name && (artist.isEmpty || ($0.artistLine?.lowercased().contains(artist) ?? false))
        }
    }
}

struct MusicIdentifyView: View {
    @State private var model = MusicIdentifyModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(spacing: DT.Spacing.md) {
                switch model.phase {
                case .listening:
                    Image(systemName: "shazam.logo.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(DT.Color.accent)
                        .symbolEffect(.pulse)
                        .accessibilityHidden(true)
                    Text("Listening…").font(.title2.bold())
                    Text("Hold your iPhone near the music.").foregroundStyle(DT.Color.textSecondary)
                case .found(let title, let artist, let artwork, let appleMusic):
                    MusicArtwork(url: artwork, cornerRadius: DT.Radius.md).frame(width: 180, height: 180)
                    Text(verbatim: title).font(.title2.bold()).multilineTextAlignment(.center)
                    if let artist { Text(verbatim: artist).font(.title3).foregroundStyle(DT.Color.textSecondary) }
                    if let song = model.inLibrary.first {
                        Button {
                            MusicActions.play([song])
                            dismiss()
                        } label: {
                            Label("Play from Your Library", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DT.Color.accent)
                    } else {
                        Text("It isn't in your library.").foregroundStyle(DT.Color.textSecondary)
                    }
                    if let appleMusic {
                        Button("Open in Apple Music", systemImage: "applelogo") { openURL(appleMusic) }
                            .buttonStyle(.bordered)
                    }
                    Button("Listen Again") { Task { await model.listen() } }
                case .noMatch:
                    ContentUnavailableView {
                        Label("No Match", systemImage: "questionmark.circle")
                    } description: {
                        Text("Shazam couldn't name it. Try again closer to the music.")
                    } actions: {
                        Button("Listen Again") { Task { await model.listen() } }
                    }
                case .failed(let reason):
                    ContentUnavailableView {
                        Label("Couldn't Listen", systemImage: "mic.slash")
                    } description: {
                        Text(reason)
                    } actions: {
                        Button("Try Again") { Task { await model.listen() } }
                    }
                }
            }
            .padding(DT.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle("What's Playing?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        model.cancel()
                        dismiss()
                    }
                }
            }
        }
        .task { await model.listen() }
    }
}
