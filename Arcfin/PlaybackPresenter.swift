import Foundation
import JellyfinAPI
#if os(macOS)
import AppKit
#endif

/// Shared, app-wide "what's currently playing" state — only actually used on macOS, where
/// PlayerView is rendered as a full-window ZStack overlay in ContentView (the same pattern
/// AppLockView already uses to cover the whole window) instead of each screen presenting it
/// locally via .sheet/.fullScreenCover. A .sheet on macOS is an inherently small, modal,
/// parent-attached panel that can't properly fill or fullscreen a window — which is exactly
/// why the player looked stuck small with a non-functional fullscreen button. iOS/tvOS keep
/// using their existing per-screen .fullScreenCover, which already behaves correctly there.
@MainActor
@Observable
final class PlaybackPresenter {
    struct Request: Identifiable {
        let id = UUID()
        let item: MediaItem
        let startTicks: Int64
        let onPlayNext: (MediaItem) -> Void
    }

    var request: Request?

    func present(_ item: MediaItem, startTicks: Int64 = 0, onPlayNext: @escaping (MediaItem) -> Void = { _ in }) {
        request = Request(item: item, startTicks: startTicks, onPlayNext: onPlayNext)
    }

    func dismiss() {
        request = nil
        #if os(macOS)
        // PlayerView grabs first responder via .focusable()/@FocusState for its keyboard
        // shortcuts (space, arrows, f, Escape). Because it's a manually-toggled ZStack
        // overlay rather than a real sheet/window AppKit tears down itself, removing it
        // doesn't hand first responder back to the main window on its own — left as-is,
        // every click after closing the player silently hits a torn-down responder and
        // nothing behind it (Home's tiles, the sidebar, everything) reacts. Clearing it
        // lets the window re-establish first responder from the next actual click.
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }
}
