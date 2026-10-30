// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The open player's actions, for the Playback menu.
struct PlayerCommands {
    let isPlaying: Bool
    let togglePlay: () -> Void
    let skip: (Int) -> Void
    let volume: (Double) -> Void
    let toggleFullScreen: () -> Void
    let close: () -> Void
    let isMuted: Bool
    let toggleMute: () -> Void
    let hasSubtitles: Bool
    let subtitlesOn: Bool
    let toggleSubtitles: () -> Void
    let showTracks: () -> Void
    let showInfo: () -> Void
    let stepSpeed: (Int) -> Void
    let resetSpeed: () -> Void
    let skipSegmentLabel: String?
    let skipSegment: () -> Void
    let next: (() -> Void)?
    let previous: (() -> Void)?
}

extension FocusedValues {
    @Entry var playerCommands: PlayerCommands?
}

/// Every player control from the menu bar, each with the key the player already answers to.
struct PlaybackCommands: Commands {
    @FocusedValue(\.playerCommands) private var player

    var body: some Commands {
        CommandMenu("Playback") {
            Group {
                Button(player?.isPlaying == true ? "Pause" : "Play") { player?.togglePlay() }
                    .keyboardShortcut(.space, modifiers: [])
                Divider()
                Button("Skip Forward") { player?.skip(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Skip Back") { player?.skip(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Divider()
                Button("Volume Up") { player?.volume(0.05) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("Volume Down") { player?.volume(-0.05) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button(player?.isMuted == true ? "Unmute" : "Mute") { player?.toggleMute() }
                    .keyboardShortcut("m", modifiers: [])
                Divider()
                Button(player?.skipSegmentLabel ?? "Skip Intro") { player?.skipSegment() }
                    .keyboardShortcut("s", modifiers: [])
                    .disabled(player?.skipSegmentLabel == nil)
                Button("Next") { player?.next?() }
                    .keyboardShortcut(.rightArrow, modifiers: [.shift, .command])
                    .disabled(player?.next == nil)
                Button("Previous") { player?.previous?() }
                    .keyboardShortcut(.leftArrow, modifiers: [.shift, .command])
                    .disabled(player?.previous == nil)
                Divider()
                Button(player?.subtitlesOn == true ? "Turn Subtitles Off" : "Turn Subtitles On") { player?.toggleSubtitles() }
                    .keyboardShortcut("c", modifiers: [])
                    .disabled(player?.hasSubtitles != true)
                Button("Audio & Subtitles…") { player?.showTracks() }
                    .keyboardShortcut("t", modifiers: [])
                Divider()
                Button("Faster") { player?.stepSpeed(1) }
                    .keyboardShortcut("]", modifiers: [])
                Button("Slower") { player?.stepSpeed(-1) }
                    .keyboardShortcut("[", modifiers: [])
                Button("Normal Speed") { player?.resetSpeed() }
                    .keyboardShortcut("0", modifiers: [])
                Divider()
                Button("Media Info") { player?.showInfo() }
                    .keyboardShortcut("i", modifiers: .command)
                Divider()
                Button("Toggle Full Screen") { player?.toggleFullScreen() }
                    .keyboardShortcut("f", modifiers: [])
                Button("Close Player") { player?.close() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .disabled(player == nil)
        }
    }
}
