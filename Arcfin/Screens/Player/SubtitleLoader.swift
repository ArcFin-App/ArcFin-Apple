import Foundation
import JellyfinAPI
import AuthCore

struct SubtitleCue: Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

/// Fetches and parses a Jellyfin-served WebVTT subtitle track. A raw AVPlayerLayer (used
/// here instead of AVPlayerViewController, for full custom-control ownership) doesn't render
/// subtitles on its own, so cues are looked up by position and drawn as a SwiftUI overlay.
enum SubtitleLoader {
    static func loadCues(deliveryUrl: String, credential: ServerCredential) async -> [SubtitleCue] {
        guard let relative = URLComponents(string: deliveryUrl),
              var combined = URLComponents(url: credential.baseURL, resolvingAgainstBaseURL: false)
        else { return [] }
        let basePath = combined.path.hasSuffix("/") ? String(combined.path.dropLast()) : combined.path
        let relativePath = relative.path.hasPrefix("/") ? relative.path : "/" + relative.path
        combined.path = basePath + relativePath
        var query = relative.queryItems ?? []
        query.append(.init(name: "api_key", value: credential.accessToken))
        combined.queryItems = query
        guard let url = combined.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        return parseVTT(text)
    }

    static func cue(at seconds: TimeInterval, in cues: [SubtitleCue]) -> String? {
        cues.first { $0.start <= seconds && seconds < $0.end }?.text
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
        return cues
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
