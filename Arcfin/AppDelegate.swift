#if canImport(UIKit) && !os(tvOS)
import UIKit

/// Only reason this exists: a true background URLSession (used for downloads, so a large
/// video keeps transferring after the app is backgrounded or even terminated) needs iOS to
/// relaunch the app and hand back a completion handler here — there's no SwiftUI-only way
/// to receive that callback.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == DownloadManager.backgroundSessionIdentifier else {
            completionHandler()
            return
        }
        DownloadManager.pendingBackgroundCompletionHandler = completionHandler
    }
}
#endif
