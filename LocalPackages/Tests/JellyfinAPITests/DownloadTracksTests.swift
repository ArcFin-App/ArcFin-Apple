// SPDX-License-Identifier: AGPL-3.0-or-later

import Testing
@testable import JellyfinAPI

@Suite("Download tracks")
struct DownloadTracksTests {
    private func audio(_ index: Int, _ language: String, _ title: String, isDefault: Bool = false) -> JellyfinMediaStream {
        JellyfinMediaStream(index: index, type: "Audio", codec: "eac3", language: language, displayTitle: title,
                            isDefault: isDefault, isForced: false, isExternal: false, deliveryUrl: nil,
                            width: nil, height: nil, videoRange: nil, bitRate: nil, profile: nil, bitDepth: nil, level: nil)
    }

    private func subtitle(_ index: Int, _ language: String) -> JellyfinMediaStream {
        JellyfinMediaStream(index: index, type: "Subtitle", codec: "srt", language: language, displayTitle: language,
                            isDefault: false, isForced: false, isExternal: true, deliveryUrl: "/sub/\(index)",
                            width: nil, height: nil, videoRange: nil, bitRate: nil, profile: nil, bitDepth: nil, level: nil)
    }

    @Test func allKeepsEveryTrackDefaultFirst() {
        let streams = [audio(1, "jpn", "Japanese"), audio(2, "eng", "English - Default", isDefault: true)]
        let kept = DownloadTracks.all.audioStreams(from: streams, defaultIndex: 2)
        #expect(kept.map(\.index) == [2, 1])
        #expect(DownloadTracks.all.subtitleStreams(from: [subtitle(3, "eng")]) == nil)
    }

    @Test func picksTheSameTracksOnAnotherEpisode() {
        let first = [audio(1, "eng", "English - Default", isDefault: true), audio(2, "jpn", "Japanese")]
        let tracks = DownloadTracks(audio: [DownloadTracks.key(first[1])], subtitles: [])
        // The next episode numbers its streams differently and marks no default.
        let next = [audio(4, "jpn", "Japanese"), audio(5, "eng", "English")]
        #expect(tracks.audioStreams(from: next, defaultIndex: nil).map(\.index) == [4])
        #expect(tracks.subtitleStreams(from: [subtitle(6, "eng")]) == [])
    }

    @Test func fallsBackToLanguageThenDefault() {
        let tracks = DownloadTracks(audio: [DownloadTracks.key(audio(1, "jpn", "Japanese - AAC - Stereo"))])
        let other = [audio(7, "eng", "English", isDefault: true), audio(8, "jpn", "Japanese - FLAC - 5.1")]
        #expect(tracks.audioStreams(from: other, defaultIndex: 7).map(\.index) == [8])
        let noJapanese = [audio(9, "fra", "French"), audio(10, "eng", "English")]
        #expect(tracks.audioStreams(from: noJapanese, defaultIndex: 10).map(\.index) == [10])
    }
}
