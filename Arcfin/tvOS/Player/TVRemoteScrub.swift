// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import GameController

/// Follows a finger on the Siri Remote's touch surface while the scrubber is focused. The focus
/// engine turns a swipe into one fixed-size move command whatever its length, so free scrubbing
/// reads the surface's absolute position from GameController instead.
@MainActor
final class TVRemoteScrub {
    /// Horizontal travel since the touch began, as a fraction of the surface's full width.
    typealias Moved = @MainActor (Double) -> Void

    private var began: (@MainActor () -> Void)?
    private var moved: Moved?
    private var selected: (@MainActor () -> Void)?
    private var pads: [GCMicroGamepad: Bool] = [:]
    private var connectObserver: NSObjectProtocol?
    private var startX: Float?
    private var isPanning = false
    private var panEndedAt: Date?
    private var samples: [(time: Date, travel: Double)] = []
    private var lastX: Float = 0

    /// The swipe that ends a pan still arrives as a move command; it must not also step 10 s.
    var suppressesMoveCommands: Bool {
        if isPanning { return true }
        guard let panEndedAt else { return false }
        return Date().timeIntervalSince(panEndedAt) < 0.6
    }

    /// `selected` fires on a click of the touch surface's centre. SwiftUI's tap gesture doesn't
    /// reliably get the remote's click on a plain focusable view, so it's read here too.
    func start(began: @escaping @MainActor () -> Void, moved: @escaping Moved,
               selected: @escaping @MainActor () -> Void) {
        self.began = began
        self.moved = moved
        self.selected = selected
        GCController.controllers().forEach(attach)
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main
        ) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { self?.attach(controller) }
        }
    }

    func stop() {
        if let connectObserver { NotificationCenter.default.removeObserver(connectObserver) }
        connectObserver = nil
        for (pad, wasAbsolute) in pads {
            pad.dpad.valueChangedHandler = nil
            pad.buttonA.pressedChangedHandler = nil
            pad.reportsAbsoluteDpadValues = wasAbsolute
        }
        pads = [:]
        began = nil
        moved = nil
        selected = nil
        reset()
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.microGamepad, pads[pad] == nil else { return }
        pads[pad] = pad.reportsAbsoluteDpadValues
        pad.reportsAbsoluteDpadValues = true
        // GameController calls this on its handler queue, which is the main queue by default.
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.touch(x: x, y: y) }
        }
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            MainActor.assumeIsolated { self?.click() }
        }
    }

    // A click near the left or right edge is a 10-second step, handled as a move command.
    private func click() {
        guard abs(lastX) < 0.5 else { return }
        selected?()
    }

    private func touch(x: Float, y: Float) {
        if x != 0 || y != 0 { lastX = x }
        guard x != 0 || y != 0 else {
            if isPanning {
                // A lifting finger rolls back a little in its last few readings; settle on where
                // it was just before letting go so a quick flick doesn't land short.
                let now = Date()
                if let settled = samples.last(where: { now.timeIntervalSince($0.time) > 0.06 }),
                   settled.travel != samples.last?.travel {
                    moved?(settled.travel)
                }
                panEndedAt = now
            }
            reset()
            return
        }
        guard let startX else {
            self.startX = x
            return
        }
        // The surface spans -1...1, so this is the share of its width the finger has crossed.
        let travel = Double(x - startX) / 2
        if !isPanning {
            // A resting or clicking finger drifts a little; only a real slide becomes a pan.
            guard abs(travel) > 0.05 else { return }
            isPanning = true
            self.startX = x
            began?()
            return
        }
        samples.append((Date(), travel))
        if samples.count > 30 { samples.removeFirst(samples.count - 30) }
        moved?(travel)
    }

    private func reset() {
        startX = nil
        isPanning = false
        samples = []
    }
}
