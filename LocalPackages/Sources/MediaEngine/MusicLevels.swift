// SPDX-License-Identifier: AGPL-3.0-or-later

import Accelerate
import AVFoundation
import Darwin
import MediaToolbox
import os
import Synchronization

/// What a tap on each song does as it renders: evens out its loudness (Sound Check), shapes it
/// (the equalizer), and keeps the last few thousand samples for a visualizer to read.
public final class MusicLevels: Sendable {
    public static let capacity = 2048

    private let lock = OSAllocatedUnfairLock()
    private nonisolated(unsafe) let ring = UnsafeMutablePointer<Float>.allocate(capacity: MusicLevels.capacity)
    private nonisolated(unsafe) var writeIndex = 0
    private nonisolated(unsafe) var sampleRate: Double = 44_100
    private nonisolated(unsafe) var lastWrite: UInt64 = 0
    private let equalizerIndex = Atomic<Int>(0)
    private let soundCheck = Atomic<Bool>(false)

    public init() {
        ring.initialize(repeating: 0, count: Self.capacity)
    }

    deinit { ring.deallocate() }

    public func setEqualizer(_ preset: MusicEqualizer) {
        equalizerIndex.store(MusicEqualizer.allCases.firstIndex(of: preset) ?? 0, ordering: .relaxed)
    }

    public func setSoundCheck(_ on: Bool) {
        soundCheck.store(on, ordering: .relaxed)
    }

    /// The newest `count` samples, oldest first, and their rate; nil when nothing has
    /// played for a moment (paused, casting, or the tap never started).
    public func latest(_ count: Int, into buffer: inout [Float]) -> Double? {
        let count = min(count, Self.capacity)
        if buffer.count != count { buffer = [Float](repeating: 0, count: count) }
        lock.lock()
        defer { lock.unlock() }
        guard lastWrite != 0, Self.seconds(since: lastWrite) < 0.25 else { return nil }
        var read = (writeIndex - count + Self.capacity) % Self.capacity
        for index in 0..<count {
            buffer[index] = ring[read]
            read = (read + 1) % Self.capacity
        }
        return sampleRate
    }

    /// An audio mix that taps `track`. `gain` is the song's Sound Check change in dB.
    public func audioMix(for track: AVAssetTrack, gain: Double?) -> AVAudioMix? {
        let context = TapContext(levels: self, gainDB: gain)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque()),
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, maxFrames, format in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .prepare(format.pointee, maxFrames: Int(maxFrames))
            },
            unprepare: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().unprepare()
            },
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr else { return }
                let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                context.process(UnsafeMutableAudioBufferListPointer(buffers), frames: Int(framesOut.pointee))
            })
        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects,
                                         &tap) == noErr, let tap else {
            Unmanaged<TapContext>.fromOpaque(callbacks.clientInfo!).release()
            return nil
        }
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    /// Runs on the audio render thread: copies the first channel in and nothing else.
    fileprivate func write(_ samples: UnsafePointer<Float>, frames: Int, stride: Int, sampleRate rate: Double) {
        lock.lock()
        for frame in 0..<frames {
            ring[writeIndex] = samples[frame * stride]
            writeIndex = (writeIndex + 1) % Self.capacity
        }
        sampleRate = rate
        lastWrite = mach_absolute_time()
        lock.unlock()
    }

    fileprivate var currentEqualizer: Int { equalizerIndex.load(ordering: .relaxed) }
    fileprivate var isSoundCheckOn: Bool { soundCheck.load(ordering: .relaxed) }

    private static let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    private static func seconds(since time: UInt64) -> Double {
        Double(mach_absolute_time() &- time) * timebase
    }
}

/// One tap's state: its song's gain, and filters for every equalizer preset, made in
/// `prepare` so the render thread never allocates.
private final class TapContext: @unchecked Sendable {
    let levels: MusicLevels
    let soundCheckGain: Float
    private var format: AudioStreamBasicDescription?
    private var setups: [vDSP_biquad_Setup?] = []
    /// Per preset, per channel.
    private var delays: [[UnsafeMutablePointer<Float>]] = []
    private var preamps: [Float] = []
    private var scratch: UnsafeMutablePointer<Float>?
    private var scratchSize = 0

    init(levels: MusicLevels, gainDB: Double?) {
        self.levels = levels
        let decibels = min(max(gainDB ?? 0, -20), 8)
        soundCheckGain = Float(pow(10, decibels / 20))
    }

    deinit { unprepare() }

    func prepare(_ format: AudioStreamBasicDescription, maxFrames: Int) {
        unprepare()
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32 else { return }
        self.format = format
        let channels = Int(max(format.mChannelsPerFrame, 1))
        for preset in MusicEqualizer.allCases {
            let coefficients = preset.coefficients(sampleRate: format.mSampleRate)
            let sections = coefficients.count / 5
            setups.append(sections > 0 ? vDSP_biquad_CreateSetup(coefficients, vDSP_Length(sections)) : nil)
            delays.append((0..<channels).map { _ in
                let delay = UnsafeMutablePointer<Float>.allocate(capacity: 2 * sections + 2)
                delay.initialize(repeating: 0, count: 2 * sections + 2)
                return delay
            })
            preamps.append(Float(pow(10, preset.preampDB / 20)))
        }
        scratchSize = max(maxFrames, 4096)
        scratch = .allocate(capacity: scratchSize)
    }

    func unprepare() {
        setups.compactMap { $0 }.forEach(vDSP_biquad_DestroySetup)
        delays.joined().forEach { $0.deallocate() }
        scratch?.deallocate()
        setups = []; delays = []; preamps = []; scratch = nil; scratchSize = 0
        format = nil
    }

    /// On the render thread: gain, filters, a clip to full scale, then the visualizer's copy.
    func process(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int) {
        guard let format, let scratch, frames > 0, frames <= scratchSize else { return }
        let preset = levels.currentEqualizer
        let setup = preset < setups.count ? setups[preset] : nil
        var gain = (levels.isSoundCheckOn ? soundCheckGain : 1) * (setup != nil ? preamps[preset] : 1)
        var low: Float = -1, high: Float = 1
        let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        var channel = 0
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let stride = interleaved ? Int(max(buffer.mNumberChannels, 1)) : 1
            let available = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / stride)
            for offset in 0..<stride {
                let samples = data + offset
                if let setup, channel < delays[preset].count {
                    vDSP_biquad(setup, delays[preset][channel], samples, stride, scratch, 1, vDSP_Length(available))
                    vDSP_vsmul(scratch, 1, &gain, samples, stride, vDSP_Length(available))
                } else if gain != 1 {
                    vDSP_vsmul(samples, stride, &gain, samples, stride, vDSP_Length(available))
                }
                if setup != nil || gain > 1 {
                    vDSP_vclip(samples, stride, &low, &high, samples, stride, vDSP_Length(available))
                }
                if channel == 0 {
                    levels.write(samples, frames: available, stride: stride, sampleRate: format.mSampleRate)
                }
                channel += 1
            }
        }
    }
}

/// Equalizer presets, each a few standard (RBJ) shelf and peak filters.
public enum MusicEqualizer: String, CaseIterable, Sendable, Identifiable {
    case off, bassBooster, bassReducer, trebleBooster, trebleReducer, vocalBooster, loudness, smallSpeakers

    public var id: String { rawValue }

    enum Filter {
        case lowShelf(hz: Double, dB: Double)
        case highShelf(hz: Double, dB: Double)
        case peak(hz: Double, dB: Double, q: Double)

        var gain: Double {
            switch self {
            case .lowShelf(_, let dB), .highShelf(_, let dB), .peak(_, let dB, _): dB
            }
        }
    }

    var filters: [Filter] {
        switch self {
        case .off: []
        case .bassBooster: [.lowShelf(hz: 120, dB: 6)]
        case .bassReducer: [.lowShelf(hz: 120, dB: -6)]
        case .trebleBooster: [.highShelf(hz: 6000, dB: 6)]
        case .trebleReducer: [.highShelf(hz: 6000, dB: -6)]
        case .vocalBooster: [.lowShelf(hz: 150, dB: -2), .peak(hz: 2500, dB: 4, q: 0.9)]
        case .loudness: [.lowShelf(hz: 100, dB: 5), .highShelf(hz: 10_000, dB: 4)]
        case .smallSpeakers: [.lowShelf(hz: 180, dB: 6), .peak(hz: 3500, dB: 2, q: 1)]
        }
    }

    /// Lowered by the biggest boost, so a boosted band doesn't clip.
    var preampDB: Double { -max(filters.map(\.gain).max() ?? 0, 0) }

    /// vDSP's order: b0, b1, b2, a1, a2 for each section, divided through by a0.
    public func coefficients(sampleRate: Double) -> [Double] {
        filters.flatMap { filter -> [Double] in
            let hz: Double, dB: Double
            switch filter {
            case .lowShelf(let f, let g), .highShelf(let f, let g), .peak(let f, let g, _): (hz, dB) = (f, g)
            }
            let a = pow(10, dB / 40)
            let w = 2 * Double.pi * min(hz, sampleRate * 0.45) / sampleRate
            let cosw = cos(w), sinw = sin(w)
            let b0, b1, b2, a0, a1, a2: Double
            switch filter {
            case .peak(_, _, let q):
                let alpha = sinw / (2 * q)
                (b0, b1, b2) = (1 + alpha * a, -2 * cosw, 1 - alpha * a)
                (a0, a1, a2) = (1 + alpha / a, -2 * cosw, 1 - alpha / a)
            case .lowShelf:
                let beta = 2 * sqrt(a) * sinw / 2 * sqrt(2)
                b0 = a * ((a + 1) - (a - 1) * cosw + beta)
                b1 = 2 * a * ((a - 1) - (a + 1) * cosw)
                b2 = a * ((a + 1) - (a - 1) * cosw - beta)
                a0 = (a + 1) + (a - 1) * cosw + beta
                a1 = -2 * ((a - 1) + (a + 1) * cosw)
                a2 = (a + 1) + (a - 1) * cosw - beta
            case .highShelf:
                let beta = 2 * sqrt(a) * sinw / 2 * sqrt(2)
                b0 = a * ((a + 1) + (a - 1) * cosw + beta)
                b1 = -2 * a * ((a - 1) + (a + 1) * cosw)
                b2 = a * ((a + 1) + (a - 1) * cosw - beta)
                a0 = (a + 1) - (a - 1) * cosw + beta
                a1 = 2 * ((a - 1) - (a + 1) * cosw)
                a2 = (a + 1) - (a - 1) * cosw - beta
            }
            return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
        }
    }

    /// The filters' change in dB at a frequency, before the preamp.
    func response(atHz hz: Double, sampleRate: Double) -> Double {
        let c = coefficients(sampleRate: sampleRate)
        let w = 2 * Double.pi * hz / sampleRate
        var total = 0.0
        for section in stride(from: 0, to: c.count, by: 5) {
            func magnitude(_ x0: Double, _ x1: Double, _ x2: Double) -> Double {
                let re = x0 + x1 * cos(w) + x2 * cos(2 * w)
                let im = -(x1 * sin(w) + x2 * sin(2 * w))
                return sqrt(re * re + im * im)
            }
            let top = magnitude(c[section], c[section + 1], c[section + 2])
            let bottom = magnitude(1, c[section + 3], c[section + 4])
            total += 20 * log10(top / bottom)
        }
        return total
    }
}

/// Turns samples into bar heights: a windowed FFT, grouped into bands spaced evenly in
/// pitch, each scaled from -60 dB (empty) to 0 dB (full).
public final class MusicSpectrum {
    public let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var magnitudes: [Float]

    public init(size: Int = 1024) {
        self.size = size
        log2n = vDSP_Length(log2(Double(size)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        real = [Float](repeating: 0, count: size / 2)
        imaginary = [Float](repeating: 0, count: size / 2)
        magnitudes = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// `bands` heights from 0 to 1, from about 50 Hz to 12 kHz.
    public func bands(_ bands: Int, of samples: [Float], sampleRate: Double) -> [Float] {
        guard samples.count == size, bands > 0 else { return [Float](repeating: 0, count: max(bands, 0)) }
        let windowed = vDSP.multiply(samples, window)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // The packed Nyquist term isn't a real bin.
                split.imagp[0] = 0
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(size / 2))
            }
        }
        // zrip's output is twice the true amplitude, and a Hann window halves it again.
        let scale = 1 / Float(size)
        let binWidth = sampleRate / Double(size)
        let low = 50.0, high = min(12_000, sampleRate / 2)
        return (0..<bands).map { band in
            let from = low * pow(high / low, Double(band) / Double(bands))
            let to = low * pow(high / low, Double(band + 1) / Double(bands))
            let first = max(1, Int(from / binWidth))
            let last = max(first, min(size / 2 - 1, Int(to / binWidth)))
            var peak: Float = 0
            for bin in first...last { peak = max(peak, magnitudes[bin]) }
            let decibels = 20 * log10(max(peak * scale, 1e-7))
            return min(max((decibels + 60) / 60, 0), 1)
        }
    }
}
