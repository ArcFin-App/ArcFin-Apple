// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AVFoundation
import Telemetry
import os

/// Muted, seamlessly-looping video behind the Home hero — the "video backdrop" idea some
/// Jellyfin hero-enhancement plugins offer, built here on stock Jellyfin local-trailer data
/// (Items/{id}/LocalTrailers, a real video file the server already has indexed) rather than
/// depending on any specific plugin's own config, which no third-party client can read
/// anyway. Falls back to nothing whenever a title has no local trailer — most won't, and
/// the static backdrop image already showing underneath just stays as-is.
#if canImport(UIKit)
import UIKit

struct HeroVideoBackdropView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url)
    }
    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {}
    // A .transition(.opacity) crossfade can keep the outgoing view (and this one's ARC
    // lifetime) alive well past when SwiftUI actually removes it from the hierarchy, during
    // which the incoming hero slide's own player is already starting — two AVQueuePlayers
    // briefly competing for the same audio render chain, independent of deinit timing.
    // dismantleUIView runs synchronously at removal time, not whenever ARC gets around to
    // it, so stop the player here instead of relying on deinit alone.
    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.stop()
    }
}

final class LoopingPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    // AVPlayerLooper needs its player/item kept alive for as long as looping should
    // continue — both held here, not just handed to the layer.
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var statusObservation: NSKeyValueObservation?
    private var stallObserver: NSObjectProtocol?

    init(url: URL) {
        super.init(frame: .zero)
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .clear
        looper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        player.play()

        // isMuted only zeroes the output — AVQueuePlayer still opens a CoreAudio HAL slot
        // for the audio track and drives its clock off that render thread. When HAL IO
        // fails to start (device contention, no route available), that clock never starts
        // and playback stalls on the first decoded video frame. Deselecting the audio
        // track entirely means there's no audio render pipeline to fail in the first
        // place, since this backdrop is always silent anyway.
        Task { @MainActor in
            guard let group = try? await asset.loadMediaSelectionGroup(for: .audible) else { return }
            item.select(nil, in: group)
        }

        // The reported "freezes on first frame" symptom has survived two prior fix
        // attempts with no AVFoundation error visible in the console — none of those
        // logs actually captured the AVPlayerItem's own status/error. Surface it
        // directly so the real failure (codec/container unsupported, stalled
        // buffering, etc.) shows up next time instead of guessing again.
        let log = Telemetry.logger(category: "HeroVideoBackdrop")
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            if item.status == .failed {
                log.error("player item failed: \(item.error?.localizedDescription ?? "unknown", privacy: .public)")
            }
        }
        stallObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didFailToPlayToEndTimeNotification, object: item, queue: .main
        ) { note in
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            log.error("didFailToPlayToEndTime: \(err?.localizedDescription ?? "unknown", privacy: .public)")
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Letting ARC deallocate queuePlayer/looper without an explicit stop first is a known
    // source of CoreAudio HAL teardown races — pause and break the reference chain
    // ourselves so AVFoundation tears the audio render chain down cleanly. Also called
    // explicitly from dismantleUIView, which runs at the actual moment SwiftUI removes this
    // view, since a crossfade transition can delay this deinit well past that point.
    func stop() {
        queuePlayer?.pause()
        looper = nil
        queuePlayer = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        stallObserver = nil
    }

    deinit {
        stop()
    }

    // See PlayerSurfaceView's own note in PlayerSupportViews.swift — this view's own backing
    // layer IS the AVPlayerLayer (layerClass above), so suppressing implicit animation has to
    // happen at the layer-delegate hook, not by wrapping a redundant frame reassignment in
    // CATransaction.setDisableActions in layoutSubviews.
    override func action(for layer: CALayer, forKey event: String) -> CAAction? {
        switch event {
        case "bounds", "position", "frame", "transform", "sublayerTransform":
            return NSNull()
        default:
            return super.action(for: layer, forKey: event)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

#elseif os(macOS)
import AppKit

// AppKit equivalent of LoopingPlayerUIView above — see PlayerSurfaceView in
// PlayerSupportViews.swift for the same layer-backing + action(for:forKey:) pattern and why
// it isn't an override here (NSView has no base implementation to call super on).
struct HeroVideoBackdropView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LoopingPlayerNSView {
        LoopingPlayerNSView(url: url)
    }
    func updateNSView(_ nsView: LoopingPlayerNSView, context: Context) {}
    // See the matching note on HeroVideoBackdropView's UIKit dismantleUIView above — a
    // .transition(.opacity) crossfade can keep this view (and its ARC lifetime) alive past
    // when SwiftUI actually removes it, while the next hero slide's own player is already
    // starting. dismantleNSView runs synchronously at removal time, so stop the player here
    // rather than relying on deinit timing — matches the reported crash signature of a
    // second player's audio engine failing to start while an old one is still active.
    static func dismantleNSView(_ nsView: LoopingPlayerNSView, coordinator: ()) {
        nsView.stop()
    }
}

final class LoopingPlayerNSView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var statusObservation: NSKeyValueObservation?
    private var stallObserver: NSObjectProtocol?

    init(url: URL) {
        super.init(frame: .zero)
        wantsLayer = true
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        looper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        player.play()

        // See LoopingPlayerUIView's matching note above — isMuted alone doesn't stop
        // AVQueuePlayer from opening a CoreAudio HAL slot and clocking playback off it.
        // Deselect the audio track outright so a HAL IO start failure can't stall video
        // on the first frame.
        Task { @MainActor in
            guard let group = try? await asset.loadMediaSelectionGroup(for: .audible) else { return }
            item.select(nil, in: group)
        }

        // See LoopingPlayerUIView's matching note above — surface the item's real
        // status/error instead of guessing at the freeze's cause blind again.
        let log = Telemetry.logger(category: "HeroVideoBackdrop")
        statusObservation = item.observe(\.status, options: [.new]) { item, _ in
            if item.status == .failed {
                log.error("player item failed: \(item.error?.localizedDescription ?? "unknown", privacy: .public)")
            }
        }
        stallObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didFailToPlayToEndTimeNotification, object: item, queue: .main
        ) { note in
            let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            log.error("didFailToPlayToEndTime: \(err?.localizedDescription ?? "unknown", privacy: .public)")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Letting ARC deallocate queuePlayer/looper without an explicit stop first is a known
    // source of CoreAudio HAL teardown races — pause and break the reference chain
    // ourselves so AVFoundation tears the audio render chain down cleanly. Also called
    // explicitly from dismantleNSView, which runs at the actual moment SwiftUI removes this
    // view, since a crossfade transition can delay this deinit well past that point.
    func stop() {
        queuePlayer?.pause()
        looper = nil
        queuePlayer = nil
        statusObservation?.invalidate()
        statusObservation = nil
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        stallObserver = nil
    }

    deinit {
        stop()
    }

    override func makeBackingLayer() -> CALayer { playerLayer }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        switch event {
        case "bounds", "position", "frame", "transform", "sublayerTransform":
            return NSNull()
        default:
            return nil
        }
    }
}
#endif
