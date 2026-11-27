// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation
import JellyfinAPI
import SwiftUI

/// A clip's subtitles: Jellyfin's own text track for that stretch, timed from the clip's start.
struct ArcSubtitleCue: Equatable {
    let start: Double
    let end: Double
    let text: String
}

enum ArcSubtitles {
    /// The track to show: the preferred subtitle language, else the file's default, else the first.
    static func track(for clip: ArcClip) -> ArcSubtitle? {
        let preferred = UserDefaults.standard.string(forKey: "preferredSubtitleLanguage") ?? ""
        if !preferred.isEmpty, let match = clip.subtitles.first(where: { $0.language?.lowercased() == preferred.lowercased() }) {
            return match
        }
        return clip.subtitles.first(where: \.isDefault) ?? clip.subtitles.first
    }

    static func load(for clip: ArcClip, credential: ServerCredential, authHeader: String) async -> [ArcSubtitleCue] {
        guard let track = track(for: clip),
              let url = ArcsClient.subtitleURL(for: clip, index: track.index, baseURL: credential.baseURL) else { return [] }
        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        for (name, value) in CustomHTTPHeaders.headers(for: url) { request.setValue(value, forHTTPHeaderField: name) }
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.arcfin.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text).filter { $0.end > 0 && $0.start < clip.seconds }
    }

    /// WebVTT's cues: "00:01:02.500 --> 00:01:04.000" and the lines under it, tags taken out.
    static func parse(_ vtt: String) -> [ArcSubtitleCue] {
        var cues: [ArcSubtitleCue] = []
        let blocks = vtt.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = seconds(parts[0]), let end = seconds(parts[1].split(separator: " ").first.map(String.init) ?? "") else { continue }
            let text = lines[(timing + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { cues.append(ArcSubtitleCue(start: start, end: end, text: text)) }
        }
        return cues
    }

    private static func seconds(_ raw: String) -> Double? {
        // "hh:mm:ss.fff" or "mm:ss.fff".
        let parts = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(parts.count) else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

/// The cue for the clip's time, over the picture.
struct ArcSubtitleOverlay: View {
    let cues: [ArcSubtitleCue]
    let time: Double

    var body: some View {
        if let cue = cues.first(where: { time >= $0.start && time < $0.end }) {
            Text(verbatim: cue.text)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        }
    }
}
