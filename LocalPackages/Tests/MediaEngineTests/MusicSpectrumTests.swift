// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import MediaEngine

@Suite("MusicSpectrum")
struct MusicSpectrumTests {
    private func tone(_ frequency: Double, amplitude: Float = 0.5, rate: Double = 44_100) -> [Float] {
        (0..<1024).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    @Test func silenceIsEmpty() {
        let bands = MusicSpectrum().bands(16, of: [Float](repeating: 0, count: 1024), sampleRate: 44_100)
        #expect(bands.count == 16)
        #expect(bands.allSatisfy { $0 == 0 })
    }

    @Test func aToneFillsItsOwnBand() {
        let bands = MusicSpectrum().bands(16, of: tone(1000), sampleRate: 44_100)
        let loudest = bands.indices.max { bands[$0] < bands[$1] }!
        // 1 kHz sits about 55% of the way, in pitch, from 50 Hz to 12 kHz.
        #expect(loudest == 8)
        #expect(bands[loudest] > 0.6)
        #expect(bands[0] == 0)
        #expect(bands[15] == 0)
    }

    @Test func higherTonesMoveRight() {
        let spectrum = MusicSpectrum()
        func loudest(_ frequency: Double) -> Int {
            let bands = spectrum.bands(24, of: tone(frequency), sampleRate: 44_100)
            return bands.indices.max { bands[$0] < bands[$1] }!
        }
        #expect(loudest(120) < loudest(800))
        #expect(loudest(800) < loudest(6000))
    }

    @Test func louderIsTaller() {
        let spectrum = MusicSpectrum()
        let quiet = spectrum.bands(16, of: tone(1000, amplitude: 0.05), sampleRate: 44_100).max()!
        let loud = spectrum.bands(16, of: tone(1000, amplitude: 0.8), sampleRate: 44_100).max()!
        #expect(quiet < loud)
        #expect(loud <= 1)
    }

    @Test func wrongSizeGivesEmptyBands() {
        #expect(MusicSpectrum().bands(8, of: [0.5, 0.2], sampleRate: 44_100) == [Float](repeating: 0, count: 8))
    }

    @Test func levelsAreStaleBeforeAnythingPlays() {
        var buffer: [Float] = []
        #expect(MusicLevels().latest(1024, into: &buffer) == nil)
    }
}
