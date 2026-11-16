// SPDX-License-Identifier: AGPL-3.0-or-later

import Accelerate
import AVFoundation
import Darwin
import MediaToolbox
import os

/// The last few thousand samples of what's playing, copied off the audio as it renders, for
/// a visualizer to read.
public final class MusicLevels: @unchecked Sendable {
    public static let capacity = 2048

    private let lock = OSAllocatedUnfairLock()
    private let ring = UnsafeMutablePointer<Float>.allocate(capacity: MusicLevels.capacity)
    private var writeIndex = 0
    private var sampleRate: Double = 44_100
    private var lastWrite: UInt64 = 0

    public init() {
        ring.initialize(repeating: 0, count: Self.capacity)
    }

    deinit { ring.deallocate() }

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

    /// An audio mix that taps `track` into these levels.
    public func audioMix(for track: AVAssetTrack) -> AVAudioMix? {
        let context = TapContext(levels: self)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque()),
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .format = format.pointee
            },
            unprepare: nil,
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr else { return }
                let context = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                context.levels.write(UnsafeMutableAudioBufferListPointer(buffers), frames: Int(framesOut.pointee),
                                     format: context.format)
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
    private func write(_ buffers: UnsafeMutableAudioBufferListPointer, frames: Int, format: AudioStreamBasicDescription?) {
        guard let format, format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32,
              let first = buffers.first, let data = first.mData else { return }
        let samples = data.assumingMemoryBound(to: Float.self)
        let stride = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 1 : Int(max(first.mNumberChannels, 1))
        let available = min(frames, Int(first.mDataByteSize) / MemoryLayout<Float>.size / stride)
        lock.lock()
        for frame in 0..<available {
            ring[writeIndex] = samples[frame * stride]
            writeIndex = (writeIndex + 1) % Self.capacity
        }
        sampleRate = format.mSampleRate
        lastWrite = mach_absolute_time()
        lock.unlock()
    }

    private static let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    private static func seconds(since time: UInt64) -> Double {
        Double(mach_absolute_time() &- time) * timebase
    }

    /// Per tap: its levels and the format `prepare` was given.
    private final class TapContext: @unchecked Sendable {
        let levels: MusicLevels
        var format: AudioStreamBasicDescription?
        init(levels: MusicLevels) { self.levels = levels }
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
