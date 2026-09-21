// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(UIKit) && !os(tvOS)
import UIKit
import CastKit

/// Two unrelated reasons this exists, both needing a real AppDelegate rather than a
/// SwiftUI-only hook:
/// 1. A true background URLSession (used for downloads, so a large video keeps
///    transferring after the app is backgrounded or even terminated) needs iOS to relaunch
///    the app and hand back a completion handler here.
/// 2. GCKCastContext must be set up exactly once, as early as possible at launch, before
///    any Cast button/session code runs — Google's own documented requirement.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        CastManager.shared.start()
        return true
    }

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
