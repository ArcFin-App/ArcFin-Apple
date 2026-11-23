// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import AVFoundation
import UIKit

/// Muted, seamlessly-looping video behind the Home hero — the "video backdrop" idea some
/// Jellyfin hero-enhancement plugins offer, built here on stock Jellyfin local-trailer data
/// (Items/{id}/LocalTrailers, a real video file the server already has indexed) rather than
/// depending on any specific plugin's own config, which no third-party client can read
/// anyway. Falls back to nothing whenever a title has no local trailer — most won't, and
/// the static backdrop image already showing underneath just stays as-is.
struct HeroVideoBackdropView: UIViewRepresentable {
    let url: URL
    var loops = true
    var muted = true
    /// Called once, when the video is actually playing and has faded in.
    var onStart: (() -> Void)? = nil
    /// Called when a trailer that doesn't loop reaches its end.
    var onEnd: (() -> Void)? = nil

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url, loops: loops, muted: muted, onStart: onStart, onEnd: onEnd)
    }
    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {}
    // A .transition(.opacity) crossfade can keep the outgoing view (and this one's ARC
    // lifetime) alive well past when SwiftUI actually removes it from the hierarchy, during
    // which the incoming hero slide's own player is already starting — two players briefly
    // competing for the same audio render chain, independent of deinit timing.
    // dismantleUIView runs synchronously at removal time, not whenever ARC gets around to
    // it, so stop the player here instead of relying on deinit alone.
    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.stop()
    }
}

final class LoopingPlayerUIView: UIView {
    // A sublayer rather than the view's own layer, so it can grow past the view's edges to
    // crop black bars baked into the trailer (see measureLetterbox).
    private let playerLayer = AVPlayerLayer()
    private let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    private var picture = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var letterboxTask: Task<Void, Never>?
    private var player: AVPlayer?
    private var loopObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var hasFadedIn = false
    /// A silent backdrop's audio track is off, so playing it can't take the audio from another app.
    private var audioIsSettled = false
    private let loops: Bool
    private let onStart: (() -> Void)?
    private let onEnd: (() -> Void)?

    init(url: URL, loops: Bool, muted: Bool, onStart: (() -> Void)?, onEnd: (() -> Void)?) {
        self.loops = loops
        self.onStart = onStart
        self.onEnd = onEnd
        super.init(frame: .zero)
        let headers = CustomHTTPHeaders.headers(for: url)
        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.add(videoOutput)
        let player = AVPlayer(playerItem: item)
        player.isMuted = muted
        // A backdrop: never sent to AirPlay, where it would take over from music or a video.
        player.allowsExternalPlayback = false
        player.actionAtItemEnd = loops ? .none : .pause
        player.automaticallyWaitsToMinimizeStalling = false
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
        clipsToBounds = true
        backgroundColor = .clear
        // Stay invisible until playback is actually running — showing this view as soon
        // as the URL resolves means a frozen first frame sits over the hero for however
        // long the HLS transcode takes to start, which looks broken. Fade in only once
        // timeControlStatus below confirms real playback.
        alpha = 0
        self.player = player

        // AVPlayerLooper doesn't support HLS player items at all (an explicitly
        // documented AVFoundation limitation) — and Jellyfin serves this backdrop as an
        // HLS transcode whenever the trailer file's own codec/container isn't natively
        // playable, which is most of the time for trailers. With AVPlayerLooper in the
        // pipeline the asset never even finished loading (0 video tracks, status stuck
        // at .unknown, empty loadedTimeRanges, confirmed via direct instrumentation) —
        // that's the actual cause of the reported freeze on frame 1, not audio or a
        // buffering heuristic. Loop manually by seeking back to zero on end instead — a
        // small hitch at the loop point beats a silent decorative video never playing.
        loopObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemDidEnd() }
        }

        // isMuted only zeroes the output — the player still opens a CoreAudio HAL slot
        // for the audio track. Deselecting it outright means there's no audio render
        // pipeline at all when the backdrop is silent.
        // Played only after that: playing first, even muted, could make the audio session
        // active for a moment and pause music playing in another app.
        if muted {
            Task { @MainActor [weak self] in
                if let group = try? await asset.loadMediaSelectionGroup(for: .audible) {
                    item.select(nil, in: group)
                }
                guard let self, self.player === player else { return }
                self.audioIsSettled = true
                player.play()
            }
        } else {
            audioIsSettled = true
            player.play()
        }

        // readyToPlay only means the asset is minimally parsed, not that enough has
        // buffered to run smoothly — re-issuing play() here (on top of the init-time
        // call) is what actually got every rotated hero item playing reliably, instead
        // of just the one that happened to be ready by the time play() was first called.
        statusObservation = item.observe(\.status, options: [.new]) { [weak self, weak player] item, _ in
            if item.status == .readyToPlay, self?.audioIsSettled == true {
                player?.play()
            }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard player.timeControlStatus == .playing, let self, !self.hasFadedIn else { return }
            self.hasFadedIn = true
            UIView.animate(withDuration: 0.3) { self.alpha = 1 }
            Task { @MainActor [weak self] in
                self?.onStart?()
                self?.measureLetterbox()
            }
        }
    }

    /// Looks at the playing picture until two frames a moment apart agree on its black bars
    /// (fades to black in between don't count), then zooms so the picture fills the view.
    private func measureLetterbox() {
        letterboxTask = Task { [weak self] in
            var previous: CGRect?
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self, let item = self.player?.currentItem else { return }
                guard let buffer = self.videoOutput.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: nil),
                      let picture = TrailerLetterbox.pictureRect(in: buffer) else { continue }
                if let previous, TrailerLetterbox.matches(previous, picture) {
                    item.remove(self.videoOutput)
                    self.picture = picture
                    CATransaction.begin()
                    CATransaction.setAnimationDuration(0.4)
                    self.playerLayer.frame = self.videoFrame()
                    CATransaction.commit()
                    return
                }
                previous = picture
            }
            if let self { self.player?.currentItem?.remove(self.videoOutput) }
        }
    }

    private func videoFrame() -> CGRect {
        guard let size = player?.currentItem?.presentationSize, size != .zero else { return bounds }
        return TrailerLetterbox.frame(videoSize: size, picture: picture, filling: bounds.size)
    }

    private func itemDidEnd() {
        guard loops else {
            onEnd?()
            return
        }
        player?.seek(to: .zero)
        player?.play()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Letting ARC deallocate the player without an explicit stop first is a known source
    // of CoreAudio HAL teardown races — pause and break the reference chain ourselves so
    // AVFoundation tears the audio render chain down cleanly. Also called explicitly from
    // dismantleUIView, which runs at the actual moment SwiftUI removes this view, since a
    // crossfade transition can delay this deinit well past that point.
    func stop() {
        letterboxTask?.cancel()
        letterboxTask = nil
        player?.pause()
        player = nil
        if let loopObserver { NotificationCenter.default.removeObserver(loopObserver) }
        loopObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        timeControlObservation?.invalidate()
        timeControlObservation = nil
    }

    deinit {
        stop()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = videoFrame()
        CATransaction.commit()
    }
}
