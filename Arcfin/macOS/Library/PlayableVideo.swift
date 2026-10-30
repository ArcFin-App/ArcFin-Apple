// SPDX-License-Identifier: AGPL-3.0-or-later

import UniformTypeIdentifiers

extension UTType {
    /// What the Mac's file picker offers for local playback: VLC opens containers AVFoundation can't, mkv and avi among them.
    static let playableVideo: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        + ["avi", "mkv"].compactMap { UTType(filenameExtension: $0) }
}
