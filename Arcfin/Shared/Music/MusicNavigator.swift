// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Opens an album or artist from somewhere with no navigation of its own, such as Now
/// Playing: Browse comes to the front and the page is pushed there once the sheet is down.
@MainActor @Observable
final class MusicNavigator {
    static let shared = MusicNavigator()

    /// What Browse should push next; cleared when it's been shown.
    var route: MusicRoute?

    func open(_ route: MusicRoute) {
        NotificationCenter.default.post(name: .arcfinShowMusic, object: nil)
        Task {
            // Long enough for Now Playing to finish closing.
            try? await Task.sleep(for: .milliseconds(450))
            self.route = route
        }
    }
}
