// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The sleep timer's choices, for a menu or a dialog: a number of minutes, the end of the
/// song, or off.
struct MusicSleepTimerOptions: View {
    private var music: MusicPlayback { AppServices.music }

    var body: some View {
        ForEach([15, 30, 45, 60], id: \.self) { minutes in
            Button(Duration.seconds(minutes * 60).formatted(.units(allowed: [.minutes], width: .wide))) {
                music.setSleepTimer(.minutes(minutes))
            }
        }
        Button("End of Song") { music.setSleepTimer(.endOfSong) }
        if music.sleepTimer != nil {
            Button("Turn Off Sleep Timer", role: .destructive) { music.setSleepTimer(nil) }
        }
    }
}

/// What the timer is set to, for a menu's title or a label.
struct MusicSleepTimerStatus: View {
    var body: some View { Self.text }

    static var text: Text {
        let music = AppServices.music
        if let sleepsAt = music.sleepsAt {
            return Text("Stops at \(sleepsAt.formatted(date: .omitted, time: .shortened))")
        } else if music.sleepTimer == .endOfSong {
            return Text("Stops at the end of this song")
        }
        return Text("Sleep Timer")
    }
}
