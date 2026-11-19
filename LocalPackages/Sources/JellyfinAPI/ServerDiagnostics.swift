// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation

/// What a device can play without the server converting it, read from the profile it sends.
public struct DirectPlaySummary: Sendable, Equatable {
    public var containers: [String]
    /// Nil when any codec plays.
    public var videoCodecs: [String]?
    public var audioCodecs: [String]?
    public var decodesAV1InHardware: Bool
    public var isCompatibilityMode: Bool
}

extension JellyfinMediaClient {
    /// The profile the player sends: the native decoder's (Aether), or AVFoundation's.
    public static func directPlaySummary(nativeDecoder: Bool, baseURL: URL) -> DirectPlaySummary {
        let profile = nativeDecoder ? nativeDecoderProfile(baseURL: baseURL) : deviceProfile(forCast: false, baseURL: baseURL)
        let direct = profile["DirectPlayProfiles"] as? [[String: Any]] ?? []
        func list(_ key: String) -> [String]? {
            let values = direct.map { $0[key] as? String }
            guard !values.contains(where: { $0 == nil }) else { return nil }
            return ordered(values.compactMap { $0 })
        }
        return DirectPlaySummary(
            containers: ordered(direct.compactMap { $0["Container"] as? String }),
            videoCodecs: list("VideoCodec"), audioCodecs: list("AudioCodec"),
            decodesAV1InHardware: decodesAV1InHardware,
            isCompatibilityMode: UserDefaults.standard.bool(forKey: "codecCompatibilityMode"))
    }

    /// "mp4,m4v" and "mov" as one list in order, without repeats.
    private static func ordered(_ lists: [String]) -> [String] {
        var seen = Set<String>()
        return lists.flatMap { $0.split(separator: ",").map(String.init) }.filter { seen.insert($0).inserted }
    }

    /// How long the server takes to answer, in milliseconds: the middle of three pings, or nil
    /// when it doesn't answer.
    public func responseTime(baseURL: URL, timeout: TimeInterval = 5) async -> Double? {
        var times: [Double] = []
        for _ in 0..<3 {
            var request = URLRequest(url: baseURL.appendingPathComponent("System/Ping"))
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let start = ContinuousClock.now
            guard let (_, response) = try? await Self.diagnosticsSession.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
            let elapsed = ContinuousClock.now - start
            times.append(Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15)
        }
        guard !times.isEmpty else { return nil }
        return times.sorted()[times.count / 2]
    }

    /// Doesn't wait for a connection: an address that can't be reached should say so now.
    private static let diagnosticsSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForResource = 15
        let headers = CustomHTTPHeaders.current
        config.httpAdditionalHeaders = headers.isEmpty ? nil : headers
        return URLSession(configuration: config)
    }()
}
