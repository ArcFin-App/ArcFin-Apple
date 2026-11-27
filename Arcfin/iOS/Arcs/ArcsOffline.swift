// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation
import JellyfinAPI
import Observation

/// Scenes saved on the device, for watching Arcs without a connection: a pack picked from For
/// You, kept per profile, replaced as a whole when it's saved again.
@MainActor @Observable
final class ArcsOfflineStore {
    static let shared = ArcsOfflineStore()
    static let packSize = 20

    private(set) var clips: [ArcClip] = []
    private(set) var isSaving = false
    /// How many of the pack are saved so far, while saving.
    private(set) var saved = 0
    private(set) var failed = false
    private(set) var bytes: Int64 = 0
    private var profile: UUID?

    private struct Manifest: Codable {
        var clips: [ArcClipRecord]
    }

    /// An ArcClip as JSON it can be read back from (ArcClip itself only decodes the server's form).
    private struct ArcClipRecord: Codable {
        let json: Data
    }

    func load(profile: UUID) {
        guard self.profile != profile else { return }
        self.profile = profile
        clips = readManifest(profile)
        bytes = folderSize(folder(profile))
    }

    func localURL(for clip: ArcClip) -> URL? {
        guard let profile else { return nil }
        let url = folder(profile).appendingPathComponent(fileName(clip))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Saves a new pack of scenes, replacing the last one once the new one is in.
    func save(authManager: AuthManager, spoilerSafe: Bool, seconds: Int, quality: ArcsClient.Quality) async {
        guard !isSaving, let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        load(profile: credential.id)
        isSaving = true
        failed = false
        saved = 0
        defer { isSaving = false }
        let client = ArcsClient()
        var picked: [ArcClip] = []
        var cursor: String?
        // Scenes only: request trailers can't be saved.
        while picked.count < Self.packSize {
            guard let page = try? await client.feed(.forYou, count: Self.packSize, cursor: cursor, spoilerSafe: spoilerSafe, seconds: seconds,
                                                    exclude: picked.map(\.id), quality: quality, credential: credential, authHeader: header) else { break }
            picked += page.clips.filter { !$0.isRequest && $0.sentBy == nil }
            cursor = page.cursor
            if cursor == nil || page.clips.isEmpty { break }
        }
        picked = Array(picked.prefix(Self.packSize))
        guard !picked.isEmpty else {
            failed = true
            return
        }
        let staging = folder(credential.id).deletingLastPathComponent().appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var kept: [ArcClip] = []
        for clip in picked {
            guard let url = ArcsClient.videoURL(for: clip, seconds: Int(clip.seconds.rounded()), quality: quality, baseURL: credential.baseURL) else { continue }
            var request = URLRequest(url: url)
            request.setValue(header, forHTTPHeaderField: "Authorization")
            for (name, value) in CustomHTTPHeaders.headers(for: url) { request.setValue(value, forHTTPHeaderField: name) }
            request.timeoutInterval = 180
            guard let (file, response) = try? await URLSession.arcfin.download(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            try? FileManager.default.moveItem(at: file, to: staging.appendingPathComponent(fileName(clip)))
            kept.append(clip)
            saved = kept.count
        }
        guard !kept.isEmpty else {
            try? FileManager.default.removeItem(at: staging)
            failed = true
            return
        }
        writeManifest(kept, in: staging)
        let target = folder(credential.id)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: staging, to: target)
        clips = kept
        bytes = folderSize(target)
    }

    func removeAll() {
        guard let profile else { return }
        try? FileManager.default.removeItem(at: folder(profile))
        clips = []
        bytes = 0
    }

    // MARK: Files

    private func folder(_ profile: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ArcsOffline", isDirectory: true).appendingPathComponent(profile.uuidString, isDirectory: true)
    }

    private func fileName(_ clip: ArcClip) -> String {
        clip.id.filter { $0.isLetter || $0.isNumber || $0 == "-" } + ".mp4"
    }

    private func readManifest(_ profile: UUID) -> [ArcClip] {
        guard let data = try? Data(contentsOf: folder(profile).appendingPathComponent("pack.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return [] }
        return manifest.clips.compactMap { try? ArcsClient.decodeClip($0.json) }
    }

    private func writeManifest(_ clips: [ArcClip], in folder: URL) {
        let records = clips.compactMap { clip in (try? ArcsClient.encodeClip(clip)).map(ArcClipRecord.init) }
        if let data = try? JSONEncoder().encode(Manifest(clips: records)) {
            try? data.write(to: folder.appendingPathComponent("pack.json"))
        }
    }

    private func folderSize(_ url: URL) -> Int64 {
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
