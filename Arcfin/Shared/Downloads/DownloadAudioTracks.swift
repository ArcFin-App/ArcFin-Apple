// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import Foundation
import AuthCore
import JellyfinAPI
import Telemetry
import os

/// More than one audio track on a converted download. Jellyfin's conversion keeps one, so
/// each other track comes down on its own and is added to the video here, copied as it is.
enum DownloadAudioTracks {
    private static let log = Telemetry.logger(category: "DownloadAudio")

    /// Fetches `streams` and adds them to `video`. A track that can't be fetched or added is
    /// left out; the video always stays playable with the track it already has.
    static func add(_ streams: [JellyfinMediaStream], to video: URL, itemID: String, mediaSourceId: String,
                    credential: ServerCredential, authHeader: String) async {
        guard !streams.isEmpty else { return }
        let dir = video.deletingLastPathComponent()
        var usePlugin = true
        var fetched: [(url: URL, language: String?)] = []
        for stream in streams {
            let file = dir.appendingPathComponent("audio-\(stream.index).m4a")
            if usePlugin {
                let url = ArcfinSyncClient.audioTrackURL(baseURL: credential.baseURL, itemID: itemID, mediaSourceId: mediaSourceId,
                                                         audioStreamIndex: stream.index, token: credential.accessToken)
                switch await fetch(url, authHeader: authHeader, to: file) {
                case .saved: fetched.append((file, stream.language)); continue
                case .missing: usePlugin = false
                case .failed: continue
                }
            }
            let url = JellyfinMediaClient.audioTrackFallbackURL(baseURL: credential.baseURL, itemID: itemID, mediaSourceId: mediaSourceId,
                                                                audioStreamIndex: stream.index, token: credential.accessToken)
            if await fetch(url, authHeader: authHeader, to: file) == .saved { fetched.append((file, stream.language)) }
        }
        defer { fetched.forEach { try? FileManager.default.removeItem(at: $0.url) } }
        guard !fetched.isEmpty else { return }
        do {
            try await merge(fetched, into: video)
        } catch {
            log.error("Couldn't add \(fetched.count, privacy: .public) audio tracks: \(error.localizedDescription, privacy: .public)")
        }
    }

    private enum FetchResult { case saved, missing, failed }

    private static func fetch(_ url: URL, authHeader: String, to file: URL) async -> FetchResult {
        var req = URLRequest(url: url)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        // Arcfin Sync answers once the whole track is out, which can take a few minutes.
        req.timeoutInterval = 30 * 60
        guard let (temp, response) = try? await URLSession.arcfin.download(for: req),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return .failed }
        guard status == 200 else {
            try? FileManager.default.removeItem(at: temp)
            return status == 404 ? .missing : .failed
        }
        try? FileManager.default.removeItem(at: file)
        return (try? FileManager.default.moveItem(at: temp, to: file)) == nil ? .failed : .saved
    }

    /// The video's own tracks plus the first audio track of each file, without re-encoding.
    /// The tracks added are off by default, so the video's own audio still plays first.
    private static func merge(_ extras: [(url: URL, language: String?)], into video: URL) async throws {
        let base = AVURLAsset(url: video)
        let duration = try await base.load(.duration)
        let range = CMTimeRange(start: .zero, duration: duration)
        let composition = AVMutableComposition()
        for track in try await base.load(.tracks) where track.mediaType == .video || track.mediaType == .audio {
            guard let added = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            try added.insertTimeRange(range, of: track, at: .zero)
            added.preferredTransform = try await track.load(.preferredTransform)
            added.languageCode = try await track.load(.languageCode)
        }
        for extra in extras {
            let asset = AVURLAsset(url: extra.url)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first,
                  let added = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let length = min(try await asset.load(.duration), duration)
            try added.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: track, at: .zero)
            added.languageCode = extra.language
            added.isEnabled = false
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { return }
        let output = video.deletingLastPathComponent().appendingPathComponent("video-tracks.mp4")
        try? FileManager.default.removeItem(at: output)
        try await session.export(to: output, as: .mp4)
        _ = try FileManager.default.replaceItemAt(video, withItemAt: output)
    }
}
