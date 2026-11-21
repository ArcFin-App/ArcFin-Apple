// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI
import AuthCore
import Telemetry
import os

struct SubtitleCue: Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

/// Fetches and parses a Jellyfin-served WebVTT subtitle track. A raw AVPlayerLayer (used
/// here instead of AVPlayerViewController, for full custom-control ownership) doesn't render
/// subtitles on its own, so cues are looked up by position and drawn as a SwiftUI overlay.
enum SubtitleLoader {
    private static let log = Telemetry.logger(category: "Subtitles")

    static func loadCues(deliveryUrl: String, credential: ServerCredential) async -> [SubtitleCue] {
        guard let data = await fetchRawVTTData(deliveryUrl: deliveryUrl, credential: credential),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        return parseVTT(text)
    }

    /// Raw VTT bytes, for saving to disk for offline playback — same URL construction as
    /// loadCues, just without parsing.
    static func absoluteURL(deliveryUrl: String, credential: ServerCredential) -> URL? {
        guard let relative = URLComponents(string: deliveryUrl),
              var combined = URLComponents(url: credential.baseURL, resolvingAgainstBaseURL: false)
        else { return nil }
        let basePath = combined.path.hasSuffix("/") ? String(combined.path.dropLast()) : combined.path
        let relativePath = relative.path.hasPrefix("/") ? relative.path : "/" + relative.path
        combined.path = basePath + relativePath
        var query = relative.queryItems ?? []
        query.append(.init(name: "api_key", value: credential.accessToken))
        combined.queryItems = query
        return combined.url
    }

    static func fetchRawVTTData(deliveryUrl: String, credential: ServerCredential) async -> Data? {
        guard let url = absoluteURL(deliveryUrl: deliveryUrl, credential: credential) else { return nil }
        do {
            let (data, response) = try await URLSession.arcfin.data(from: url)
            if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
                log.error("Subtitles: the server answered \(status, privacy: .public)")
                return nil
            }
            return data
        } catch {
            log.error("Subtitles: couldn't fetch them: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Parses a locally-saved VTT file — used by offline playback.
    static func loadCues(fileURL: URL) -> [SubtitleCue] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return parseVTT(text)
    }

    /// `cues` sorted by start, as parseVTT returns them. Called on every position tick, so it
    /// finds the last cue started by then with a binary search and looks back from there;
    /// overlapping cues are a few lines apart, so the look back is kept short.
    static func cue(at seconds: TimeInterval, in cues: [SubtitleCue]) -> String? {
        var low = 0, high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].start <= seconds { low = mid + 1 } else { high = mid }
        }
        var match: SubtitleCue?
        var index = low - 1
        while index >= 0, index >= low - 32 {
            if seconds < cues[index].end { match = cues[index] }
            index -= 1
        }
        return match?.text
    }

    private static func parseVTT(_ content: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = content.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")

        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timingLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timingLine = lines[timingLineIndex]
            let parts = timingLine.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseTimestamp(parts[0]),
                  let end = parseTimestamp(parts[1])
            else { continue }
            let text = lines[(timingLineIndex + 1)...]
                .joined(separator: "\n")
                .stripHTMLTags()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: text))
        }
        return cues.sorted { $0.start < $1.start }
    }

    private static func parseTimestamp(_ raw: String) -> TimeInterval? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ").first ?? raw
        let parts = cleaned.split(separator: ":").map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let secondsPart = parts.last!.replacingOccurrences(of: ",", with: ".")
        guard let seconds = Double(secondsPart) else { return nil }
        let minutes = Double(parts[parts.count - 2]) ?? 0
        let hours = parts.count == 3 ? (Double(parts[0]) ?? 0) : 0
        return hours * 3600 + minutes * 60 + seconds
    }
}

private extension String {
    func stripHTMLTags() -> String {
        replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }
}
