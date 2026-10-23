// SPDX-License-Identifier: AGPL-3.0-or-later

import Testing
@testable import MediaEngine

@Suite("PlaybackEngineSelector")
struct EngineSelectorTests {

    @Test("Auto resolves to Aether", arguments: [nil, "mkv", "mov,mp4,m4a,3gp,3g2,mj2"])
    func autoIsAether(container: String?) {
        #expect(PlaybackEngineSelector.choose(preference: .auto, container: container, videoStream: nil) == .aether)
    }

    @Test("A picked engine is kept", arguments: [PlaybackEngineKind.aether, .avFoundation, .vlc])
    func pickedEngineKept(engine: PlaybackEngineKind) {
        #expect(PlaybackEngineSelector.choose(preference: engine, container: "mkv", videoStream: nil) == engine)
    }

    @Test("The fallback reads ffprobe's alias list for mp4")
    func fallbackMP4Aliases() {
        #expect(PlaybackEngineSelector.legacyFallback(container: "mov,mp4,m4a,3gp,3g2,mj2", videoStream: nil) == .avFoundation)
    }

    @Test("The fallback sends mkv and unknown containers to VLC", arguments: ["mkv", "matroska,webm", nil])
    func fallbackMKVToVLC(container: String?) {
        #expect(PlaybackEngineSelector.legacyFallback(container: container, videoStream: nil) == .vlc)
    }
}
