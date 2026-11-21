// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation

/// The audio session while What's Playing? listens. Music keeps a long-form playback session,
/// which doesn't record; this one does, and the music's comes back after.
enum ListeningSession {
    static func begin() async throws {
        try await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        }.value
    }

    static func end() async {
        await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        }.value
    }
}
