// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit

extension PlaybackPresenter {
    func handBackFirstResponder() {
        // PlayerView grabs first responder via .focusable()/@FocusState for its keyboard
        // shortcuts (space, arrows, f, Escape). Because it's a manually-toggled ZStack
        // overlay rather than a real sheet/window AppKit tears down itself, removing it
        // doesn't hand first responder back to the main window on its own — left as-is,
        // every click after closing the player silently hits a torn-down responder and
        // nothing behind it (Home's tiles, the sidebar, everything) reacts. Clearing it
        // lets the window re-establish first responder from the next actual click.
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}
