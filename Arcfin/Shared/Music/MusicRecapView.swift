// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import ImageIO
import AuthCore
import JellyfinAPI

/// The year in music: from ListenBrainz when the profile sends its listens there, which
/// knows when each play was; otherwise from Jellyfin's play counts, which only know how
/// many, so that one covers all time.
@MainActor @Observable
final class MusicRecapModel {
    struct Entry: Hashable {
        var name: String
        var detail: String?
        var listens: Int
    }

    enum Source { case listenBrainz, playCounts }

    private(set) var source: Source?
    private(set) var songs: [Entry] = []
    private(set) var artists: [Entry] = []
    private(set) var albums: [Entry] = []
    private(set) var totalListens = 0
    private(set) var minutes: Int?
    private(set) var busiestMonth: Date?
    private(set) var isLoading = true
    private(set) var isPreparingPlay = false
    /// The library's own songs, when the recap came from them.
    private var librarySongs: [MusicSong] = []

    let year = Calendar.current.component(.year, from: .now)

    func load(libraryID: String?) async {
        isLoading = true
        defer { isLoading = false }
        if await loadListenBrainz() { return }
        await loadPlayCounts(libraryID: libraryID)
    }

    private func loadListenBrainz() async -> Bool {
        guard let profile = AppServices.authManager.state.credential?.id,
              let token = ListenBrainzCredential.load(profile: profile) else { return false }
        let client = ListenBrainzClient(token: token, clientVersion: "")
        guard let userName = try? await client.validate(), let year = try? await client.thisYear(userName: userName),
              !year.songs.isEmpty else { return false }
        source = .listenBrainz
        songs = year.songs.map { Entry(name: $0.name, detail: $0.artist, listens: $0.listens) }
        artists = year.artists.map { Entry(name: $0.name, listens: $0.listens) }
        albums = year.albums.map { Entry(name: $0.name, detail: $0.artist, listens: $0.listens) }
        totalListens = year.totalListens
        busiestMonth = year.busiestMonth?.start
        return true
    }

    private func loadPlayCounts(libraryID: String?) async {
        guard let page = try? await MusicAPI.call({
            try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, sort: .playCount,
                                        ascending: false, filter: .init(playedOnly: true), limit: 500)
        }) else { return }
        source = .playCounts
        librarySongs = page.tracks
        songs = page.tracks.map { Entry(name: $0.name, detail: $0.artistLine, listens: $0.playCount) }
        artists = Self.top(page.tracks) { $0.artistLine }
        albums = Self.top(page.tracks) { $0.albumName }
        totalListens = page.tracks.reduce(0) { $0 + $1.playCount }
        minutes = Int(page.tracks.reduce(0) { $0 + Double($1.playCount) * ($1.duration ?? 0) } / 60)
    }

    private static func top(_ songs: [MusicSong], by key: (MusicSong) -> String?) -> [Entry] {
        Dictionary(grouping: songs.filter { key($0) != nil }) { key($0)! }
            .map { Entry(name: $0.key, listens: $0.value.reduce(0) { $0 + $1.playCount }) }
            .sorted { $0.listens > $1.listens }
    }

    /// The top songs as a queue: the library's own, or ListenBrainz's found in the library.
    func playTopSongs() async {
        isPreparingPlay = true
        defer { isPreparingPlay = false }
        let found = await librarySongs(upTo: 25)
        if !found.isEmpty { MusicActions.play(found) }
    }

    /// Covers of the top songs' albums, up to four different ones, for the picture to share.
    func shareCovers() async -> [CGImage] {
        var seen = Set<String>()
        var covers: [CGImage] = []
        for song in await librarySongs(upTo: 12) where covers.count < 4 && seen.insert(song.albumId ?? song.id).inserted {
            guard let url = MusicAPI.artworkURL(song, width: 400) else { continue }
            let data = url.isFileURL ? try? Data(contentsOf: url) : await URLSession.arcfin.imageData(from: url)
            if let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                covers.append(image)
            }
        }
        return covers
    }

    private func librarySongs(upTo limit: Int) async -> [MusicSong] {
        if source == .playCounts { return Array(librarySongs.prefix(limit)) }
        var found: [MusicSong] = []
        for entry in songs.prefix(limit) {
            let name = entry.name.lowercased(), artist = entry.detail?.lowercased() ?? ""
            let results = try? await MusicAPI.call { try await $0.searchMusic(credential: $1, authHeader: $2, term: entry.name, limit: 10) }
            if let song = results?.songs.first(where: {
                $0.name.lowercased() == name && ($0.artistLine?.lowercased().contains(artist) ?? artist.isEmpty)
            }) { found.append(song) }
        }
        return found
    }
}

struct MusicRecapView: View {
    let libraryID: String?
    @State private var model = MusicRecapModel()
    @State private var shareImage: Image?

    private var title: String {
        model.source == .playCounts ? String(localized: "All Time in Music") : String(localized: "Your \(String(model.year)) in Music")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                } else if model.source == nil || model.songs.isEmpty {
                    ContentUnavailableView("Nothing Played Yet", systemImage: "chart.bar",
                                           description: Text("Your recap fills in as you listen."))
                } else {
                    figures
                    HStack {
                        Button {
                            Task { await model.playTopSongs() }
                        } label: {
                            Label("Play Top Songs", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DT.Color.accent)
                        .disabled(model.isPreparingPlay)
                        if let shareImage {
                            ShareLink(item: shareImage, preview: SharePreview(title, image: shareImage)) {
                                Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    ranked("Top Songs", model.songs.prefix(10))
                    ranked("Top Artists", model.artists.prefix(5))
                    ranked("Top Albums", model.albums.prefix(5))
                    Text(model.source == .listenBrainz
                         ? "From your ListenBrainz listens this year. ListenBrainz updates its stats once a day."
                         : "From Jellyfin's play counts, which don't say when each play was, so this covers all time. Add your ListenBrainz token in Settings › Integrations for a recap of each year.")
                        .font(.footnote)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.xl)
        }
        .screenBackground()
        .navigationTitle(title)
        .task {
            await model.load(libraryID: libraryID)
            await renderShareImage()
        }
    }

    private var figures: some View {
        HStack(spacing: DT.Spacing.sm) {
            figure(model.totalListens.formatted(), "Listens")
            if let minutes = model.minutes { figure(minutes.formatted(), "Minutes") }
            if let month = model.busiestMonth {
                figure(month.formatted(.dateTime.month(.wide)), "Busiest Month")
            }
        }
    }

    private func figure(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .font(.title2.weight(.bold))
                .foregroundStyle(DT.Color.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label).font(.footnote).foregroundStyle(DT.Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DT.Spacing.sm)
        .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
    }

    @ViewBuilder
    private func ranked(_ title: LocalizedStringKey, _ entries: ArraySlice<MusicRecapModel.Entry>) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text(title)
                    .font(DT.Font.sectionTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    HStack(spacing: DT.Spacing.sm) {
                        Text(verbatim: "\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(DT.Color.accent)
                            .frame(width: 28, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: entry.name).foregroundStyle(DT.Color.textPrimary)
                            if let detail = entry.detail {
                                Text(verbatim: detail).font(.footnote).foregroundStyle(DT.Color.textSecondary)
                            }
                        }
                        .lineLimit(1)
                        Spacer()
                        Text("\(entry.listens) plays").font(.footnote.monospacedDigit()).foregroundStyle(DT.Color.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    /// The card to share, drawn once the recap and its covers have loaded.
    private func renderShareImage() async {
        guard !model.songs.isEmpty else { return }
        let covers = await model.shareCovers()
        let period = model.source == .playCounts ? String(localized: "All Time") : String(model.year)
        let renderer = ImageRenderer(content: MusicRecapCard(period: period, model: model, covers: covers))
        renderer.scale = 3
        if let image = renderer.cgImage { shareImage = Image(decorative: image, scale: 3) }
    }
}

/// The recap as a picture for a story: the top cover blurred behind, the top albums' covers,
/// the year large, the figures, and the top songs and artists.
private struct MusicRecapCard: View {
    let period: String
    let model: MusicRecapModel
    let covers: [CGImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(verbatim: "Arcfin").font(.system(size: 15, weight: .heavy))
                Spacer()
                Text("Year in Music").font(.system(size: 13, weight: .semibold)).opacity(0.8)
            }
            Text(verbatim: period)
                .font(.system(size: period.count > 4 ? 46 : 72, weight: .black))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if !covers.isEmpty { coverGrid }
            HStack(spacing: 10) {
                figure(model.totalListens.formatted(), Text("Plays"))
                if let minutes = model.minutes { figure(minutes.formatted(), Text("Minutes")) }
            }
            HStack(alignment: .top, spacing: 16) {
                ranked(Text("Top Songs"), model.songs.prefix(5).map(\.name))
                ranked(Text("Top Artists"), model.artists.prefix(5).map(\.name))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(width: 360, height: 640, alignment: .topLeading)
        .background { background }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.12, green: 0.05, blue: 0.04)
            if let first = covers.first {
                Image(decorative: first, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 360, height: 640)
                    .blur(radius: 50)
                    .saturation(1.4)
                    .clipped()
            } else {
                LinearGradient(colors: [DT.Color.palette("FF6A4D"), Color(red: 0.35, green: 0.08, blue: 0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var coverGrid: some View {
        let side: CGFloat = covers.count >= 4 ? 148 : 304
        let shown = covers.count >= 4 ? Array(covers.prefix(4)) : [covers[0]]
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: 8), count: shown.count >= 4 ? 2 : 1),
                         spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, cover in
                Image(decorative: cover, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: covers.count >= 4 ? side : 150)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            }
        }
    }

    private func figure(_ value: String, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value).font(.system(size: 26, weight: .heavy)).minimumScaleFactor(0.6).lineLimit(1)
            label.font(.system(size: 12, weight: .semibold)).opacity(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func ranked(_ title: Text, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            title.font(.system(size: 12, weight: .bold)).opacity(0.75)
            ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "\(index + 1)").font(.system(size: 13, weight: .heavy)).foregroundStyle(DT.Color.palette("FF6A4D"))
                    Text(verbatim: name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
