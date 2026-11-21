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

@Suite("MusicEqualizer")
struct MusicEqualizerTests {
    @Test func offHasNoFilters() {
        #expect(MusicEqualizer.off.coefficients(sampleRate: 44_100).isEmpty)
        #expect(MusicEqualizer.off.preampDB == 0)
    }

    @Test func bassBoosterLiftsTheLowsOnly() {
        let bass = MusicEqualizer.bassBooster
        #expect(abs(bass.response(atHz: 30, sampleRate: 44_100) - 6) < 0.5)
        #expect(abs(bass.response(atHz: 8000, sampleRate: 44_100)) < 0.3)
        #expect(bass.preampDB == -6)
    }

    @Test func trebleReducerCutsTheHighsOnly() {
        let treble = MusicEqualizer.trebleReducer
        #expect(abs(treble.response(atHz: 16_000, sampleRate: 48_000) + 6) < 0.6)
        #expect(abs(treble.response(atHz: 100, sampleRate: 48_000)) < 0.3)
        #expect(treble.preampDB == 0)
    }

    @Test func vocalBoosterPeaksInTheMiddle() {
        let vocal = MusicEqualizer.vocalBooster
        #expect(vocal.response(atHz: 2500, sampleRate: 44_100) > 3)
        #expect(vocal.response(atHz: 2500, sampleRate: 44_100) > vocal.response(atHz: 8000, sampleRate: 44_100))
    }

    @Test(arguments: MusicEqualizer.allCases)
    func everyPresetIsStable(preset: MusicEqualizer) {
        let c = preset.coefficients(sampleRate: 44_100)
        #expect(c.count % 5 == 0)
        for section in stride(from: 0, to: c.count, by: 5) {
            // Poles inside the unit circle: |a2| < 1 and |a1| < 1 + a2.
            #expect(abs(c[section + 4]) < 1)
            #expect(abs(c[section + 3]) < 1 + c[section + 4])
        }
    }
}
