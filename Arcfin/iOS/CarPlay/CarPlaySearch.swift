// SPDX-License-Identifier: AGPL-3.0-or-later

import CarPlay
import JellyfinAPI
import MediaEngine
import UIKit

/// CarPlay's search: recent searches until something's typed or said, then artists, albums and
/// songs from the server as it's entered. A result plays or opens; Search shows them all.
@MainActor
final class CarPlaySearch: NSObject, CPSearchTemplateDelegate {
    /// What a result does: play, or push its page.
    private final class Action: NSObject {
        let run: @MainActor () async -> Void
        init(_ run: @escaping @MainActor () async -> Void) { self.run = run }
    }

    private static let recentsKey = "carplay.recentSearches"
    private let template = CPSearchTemplate()
    private var term = ""
    private weak var scene: CarPlaySceneDelegate?

    init(scene: CarPlaySceneDelegate) {
        self.scene = scene
        super.init()
        template.delegate = self
    }

    func show(in interface: CPInterfaceController?) {
        interface?.pushTemplate(template, animated: true, completion: nil)
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate, updatedSearchText searchText: String,
                        completionHandler: @escaping ([CPListItem]) -> Void) {
        term = searchText.trimmingCharacters(in: .whitespaces)
        guard term.count >= 2 else { return completionHandler(recentItems()) }
        let asked = term
        Task {
            let results = await Self.results(for: asked)
            completionHandler(items(for: results, term: asked, limit: 4))
        }
    }

    func searchTemplate(_ searchTemplate: CPSearchTemplate, selectedResult item: CPListItem,
                        completionHandler: @escaping () -> Void) {
        guard let action = item.userInfo as? Action else { return completionHandler() }
        Task {
            await action.run()
            completionHandler()
        }
    }

    func searchTemplateSearchButtonPressed(_ searchTemplate: CPSearchTemplate) {
        guard term.count >= 2 else { return }
        let asked = term
        Task { await pushResults(for: asked) }
    }

    // MARK: Results

    private static func results(for term: String) async -> MusicSearchResults {
        (try? await MusicAPI.call { try await $0.searchMusic(credential: $1, authHeader: $2, term: term) }) ?? MusicSearchResults()
    }

    /// A few of each kind, artists first, as the search shows them.
    private func items(for results: MusicSearchResults, term: String, limit: Int) -> [CPListItem] {
        artistItems(results.artists.prefix(limit), term: term)
            + albumItems(results.albums.prefix(limit), term: term)
            + songItems(Array(results.songs.prefix(limit)), term: term)
    }

    private func artistItems(_ artists: ArraySlice<MusicArtist>, term: String) -> [CPListItem] {
        artists.map { artist in
            item(artist.name, String(localized: "Artist"), image: MusicAPI.artworkURL(artist, width: 120), term: term) { [weak self] in
                await self?.scene?.openArtist(artist)
            }
        }
    }

    private func albumItems(_ albums: ArraySlice<MusicAlbum>, term: String) -> [CPListItem] {
        albums.map { album in
            item(album.name, album.albumArtist, image: MusicAPI.artworkURL(album, width: 120), term: term) { [weak self] in
                await self?.scene?.openAlbum(album)
            }
        }
    }

    private func songItems(_ songs: [MusicSong], term: String) -> [CPListItem] {
        songs.enumerated().map { index, song in
            item(song.name, song.artistLine, image: MusicAPI.artworkURL(song, width: 120), term: term) { [weak self] in
                self?.scene?.play(songs, from: index)
            }
        }
    }

    private func item(_ text: String, _ detail: String?, image: URL?, term: String,
                      run: @escaping @MainActor () async -> Void) -> CPListItem {
        let item = CPListItem(text: text, detailText: detail)
        item.userInfo = Action { [weak self] in
            self?.remember(term)
            await run()
        }
        scene?.loadImage(image, into: item)
        return item
    }

    /// Every result for the term, a section for each kind.
    func pushResults(for term: String) async {
        remember(term)
        let results = await Self.results(for: term)
        let all = items(for: results, term: term, limit: CPListTemplate.maximumItemCount)
        for item in all {
            let action = item.userInfo as? Action
            item.handler = { _, done in Task { await action?.run(); done() } }
        }
        let artists = all.prefix(results.artists.count)
        let albums = all.dropFirst(results.artists.count).prefix(results.albums.count)
        let songs = all.dropFirst(results.artists.count + results.albums.count)
        let sections = [(String(localized: "Artists"), Array(artists)), (String(localized: "Albums"), Array(albums)),
                        (String(localized: "Songs"), Array(songs))]
            .filter { !$0.1.isEmpty }
            .map { CPListSection(items: $0.1, header: $0.0, sectionIndexTitle: nil) }
        scene?.pushList(term, sections, empty: String(localized: "No Results"))
    }

    // MARK: Recent searches

    var recents: [String] { UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? [] }

    private func recentItems() -> [CPListItem] {
        recents.map { recent in
            let item = CPListItem(text: recent, detailText: nil, image: UIImage(systemName: "clock.arrow.circlepath"))
            item.userInfo = Action { [weak self] in await self?.pushResults(for: recent) }
            return item
        }
    }

    private func remember(_ term: String) {
        var recents = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
        recents.removeAll { $0.compare(term, options: .caseInsensitive) == .orderedSame }
        recents.insert(term, at: 0)
        UserDefaults.standard.set(Array(recents.prefix(8)), forKey: Self.recentsKey)
    }
}
