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

    /// A shortcut item can arrive in the launch options of a cold start or through the scene
    /// delegate on a warm one; SwiftUI's WindowGroup still owns the window either way, this
    /// only exists to receive the item.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = QuickActionSceneDelegate.self
        return config
    }
}

@MainActor
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let item = connectionOptions.shortcutItem else { return }
        // The views listening for the Downloads route aren't mounted yet on a cold launch
        // (the play route survives via its UserDefaults buffer), so give them a moment.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            QuickActions.handle(item)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(QuickActions.handle(shortcutItem))
    }
}

/// Home Screen long-press actions: a static Downloads entry plus a dynamic "Resume <title>"
/// for the most recent Continue Watching item. Both reuse the arcfin:// routes' plumbing
/// (the pending-play buffer and the Downloads notification) rather than a second path.
enum QuickActions {
    private static let resumeType = "com.psmattas.arcfin.resume"
    private static let downloadsType = "com.psmattas.arcfin.downloads"

    @MainActor
    static func update(resumeItemID: String?, title: String?) {
        var items = [
            UIApplicationShortcutItem(
                type: downloadsType, localizedTitle: "Downloads", localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "arrow.down.circle"), userInfo: nil)
        ]
        if let resumeItemID, let title {
            items.insert(
                UIApplicationShortcutItem(
                    type: resumeType, localizedTitle: "Continue Watching", localizedSubtitle: title,
                    icon: UIApplicationShortcutIcon(systemImageName: "play.fill"),
                    userInfo: ["itemID": resumeItemID as NSString]),
                at: 0)
        }
        UIApplication.shared.shortcutItems = items
    }

    @discardableResult
    @MainActor
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        switch item.type {
        case resumeType:
            guard let itemID = item.userInfo?["itemID"] as? String else { return false }
            UserDefaults.standard.set(itemID, forKey: "arcfin.pendingPlayID")
            NotificationCenter.default.post(name: .arcfinPlayItem, object: nil, userInfo: ["itemID": itemID])
            return true
        case downloadsType:
            NotificationCenter.default.post(name: .arcfinShowDownloads, object: nil)
            return true
        default:
            return false
        }
    }
}
#endif
