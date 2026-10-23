// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Auto quality's decisions, kept apart from the player so they can be tested: where to
/// start from a bandwidth measurement, and whether a run of stalls should lower quality.
public enum AutoQuality {
    /// Steps the cap moves between. The width only drops with the low steps, so a high cap
    /// never forces a transcode just for resolution (a 4K file at 10 Mb/s fits a 12 Mb/s cap).
    public static let ladder: [StreamQualityCap] = [
        StreamQualityCap(maxBitrate: 20_000_000, maxWidth: nil),
        StreamQualityCap(maxBitrate: 15_000_000, maxWidth: nil),
        StreamQualityCap(maxBitrate: 12_000_000, maxWidth: nil),
        StreamQualityCap(maxBitrate: 8_000_000, maxWidth: 1920),
        StreamQualityCap(maxBitrate: 4_000_000, maxWidth: 1280),
        StreamQualityCap(maxBitrate: 2_000_000, maxWidth: 960),
        StreamQualityCap(maxBitrate: 1_000_000, maxWidth: 720),
        StreamQualityCap(maxBitrate: 500_000, maxWidth: 480),
    ]

    /// Share of a measured rate that's safe to stream at, leaving room for overhead and dips.
    static let headroom = 0.75

    /// The cap to start with. Nil means uncapped: the server sends the file as it is.
    /// A probe that failed says nothing about the connection (a proxy can block the test
    /// endpoint), so it starts at a middle step instead of the bottom one.
    public static func startingCap(measuredBps: Int?) -> StreamQualityCap? {
        guard let measuredBps else { return StreamQualityCap(maxBitrate: 8_000_000, maxWidth: 1920) }
        let safe = Double(measuredBps) * headroom
        guard let top = ladder.first?.maxBitrate, safe < Double(top) else { return nil }
        let step = ladder.first { Double($0.maxBitrate ?? 0) <= safe } ?? ladder[ladder.count - 1]
        // The measured rate itself, not the step below it: a 6 Mb/s file on a 7 Mb/s link
        // should play as is rather than be squeezed under a 4 Mb/s step.
        return StreamQualityCap(maxBitrate: Int(safe), maxWidth: step.maxWidth)
    }

    public enum StallDecision: Equatable, Sendable {
        /// The connection measures fast enough for what's playing; the stall had another cause.
        case keep
        case lower(StreamQualityCap)
        /// Already at the bottom step.
        case exhausted
    }

    /// What to do after repeated stalls, given the cap in use (nil = uncapped), the source's
    /// own bitrate when known, and a fresh measurement when one could be taken.
    public static func afterStalls(current: StreamQualityCap?, sourceBitrate: Int?, measuredBps: Int?) -> StallDecision {
        let playing = current?.maxBitrate ?? sourceBitrate ?? ladder[0].maxBitrate ?? 0
        if let measuredBps, Double(measuredBps) * headroom >= Double(playing) { return .keep }
        var target = Double(playing) * 0.7
        if let measuredBps { target = min(target, Double(measuredBps) * headroom) }
        if let step = ladder.first(where: { Double($0.maxBitrate ?? 0) <= target }) { return .lower(step) }
        let bottom = ladder[ladder.count - 1]
        return (current?.maxBitrate ?? .max) > (bottom.maxBitrate ?? 0) ? .lower(bottom) : .exhausted
    }

    public enum RecoveryDecision: Equatable, Sendable {
        case keep
        /// Raise to this cap; nil lifts the cap and plays the file as it is.
        case raise(StreamQualityCap?)
    }

    /// Whether a lowered cap can come back up, from a fresh measurement taken during smooth
    /// playback. Raising costs a reload, so it only happens for a clear gain: the new cap
    /// must be at least half again the current one, or let the source through untouched.
    public static func afterRecovery(current: StreamQualityCap?, sourceBitrate: Int?, measuredBps: Int?) -> RecoveryDecision {
        guard let current, let currentBitrate = current.maxBitrate, let measuredBps else { return .keep }
        let safe = Double(measuredBps) * headroom
        if let sourceBitrate, safe >= Double(sourceBitrate) { return .raise(nil) }
        guard let candidate = startingCap(measuredBps: measuredBps) else { return .raise(nil) }
        guard let candidateBitrate = candidate.maxBitrate, Double(candidateBitrate) >= Double(currentBitrate) * 1.5 else { return .keep }
        return .raise(candidate)
    }

    /// Whether a stall should count towards lowering quality. A load or seek buffers by
    /// design, and a paused player isn't waiting on the network.
    public static func countsStall(at now: Date, lastLoad: Date?, lastSeek: Date?, isPaused: Bool) -> Bool {
        if isPaused { return false }
        if let lastLoad, now.timeIntervalSince(lastLoad) < 12 { return false }
        if let lastSeek, now.timeIntervalSince(lastSeek) < 8 { return false }
        return true
    }
}
