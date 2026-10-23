// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import JellyfinAPI

@Suite("AutoQuality")
struct AutoQualityTests {

    @Test("A fast connection starts uncapped")
    func fastConnectionUncapped() {
        #expect(AutoQuality.startingCap(measuredBps: 100_000_000) == nil)
    }

    @Test("A slower connection is capped at the measured rate, not the step below it")
    func cappedAtMeasuredRate() throws {
        let cap = try #require(AutoQuality.startingCap(measuredBps: 10_000_000))
        #expect(cap.maxBitrate == 7_500_000)
        #expect(cap.maxWidth == 1280)
    }

    @Test("A high cap never limits resolution")
    func highCapKeepsResolution() throws {
        let cap = try #require(AutoQuality.startingCap(measuredBps: 18_000_000))
        #expect(cap.maxWidth == nil)
    }

    @Test("A failed probe starts at a middle step, not the bottom")
    func failedProbeMiddleStep() {
        #expect(AutoQuality.startingCap(measuredBps: nil) == StreamQualityCap(maxBitrate: 8_000_000, maxWidth: 1920))
    }

    @Test("Stalls on a connection that measures fast enough keep quality")
    func stallsOnFastConnectionKeep() {
        let decision = AutoQuality.afterStalls(current: nil, sourceBitrate: 10_000_000, measuredBps: 50_000_000)
        #expect(decision == .keep)
    }

    @Test("Stalls on a slow connection lower to a step below what the connection measures")
    func stallsOnSlowConnectionLower() {
        let decision = AutoQuality.afterStalls(current: nil, sourceBitrate: 30_000_000, measuredBps: 10_000_000)
        #expect(decision == .lower(StreamQualityCap(maxBitrate: 4_000_000, maxWidth: 1280)))
    }

    @Test("Without a measurement, stalls step down from what's playing")
    func stallsWithoutMeasurement() {
        let decision = AutoQuality.afterStalls(current: StreamQualityCap(maxBitrate: 8_000_000, maxWidth: 1920),
                                               sourceBitrate: nil, measuredBps: nil)
        #expect(decision == .lower(StreamQualityCap(maxBitrate: 4_000_000, maxWidth: 1280)))
    }

    @Test("Stalls at the bottom step are exhausted")
    func bottomStepExhausted() {
        let bottom = AutoQuality.ladder[AutoQuality.ladder.count - 1]
        #expect(AutoQuality.afterStalls(current: bottom, sourceBitrate: nil, measuredBps: 100_000) == .exhausted)
    }

    @Test("Stalls right after a load or seek, or while paused, don't count")
    func stallsThatDontCount() {
        let now = Date()
        #expect(!AutoQuality.countsStall(at: now, lastLoad: now.addingTimeInterval(-5), lastSeek: nil, isPaused: false))
        #expect(!AutoQuality.countsStall(at: now, lastLoad: nil, lastSeek: now.addingTimeInterval(-3), isPaused: false))
        #expect(!AutoQuality.countsStall(at: now, lastLoad: nil, lastSeek: nil, isPaused: true))
        #expect(AutoQuality.countsStall(at: now, lastLoad: now.addingTimeInterval(-60), lastSeek: now.addingTimeInterval(-60), isPaused: false))
    }
}
