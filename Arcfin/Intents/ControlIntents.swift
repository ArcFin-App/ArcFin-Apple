// SPDX-License-Identifier: AGPL-3.0-or-later

#if !os(tvOS)
import AppIntents
import Foundation

// Compiled into both the app and the widget extension. A control's button runs its intent,
// and an intent that opens the app runs inside the app, so the system needs the same type in
// both binaries: the extension only declares it, the app performs it.

/// Hands an arcfin:// link to the app's own routing (ContentView). Buffered as well, because
/// on a cold launch nothing is listening yet when the intent runs.
enum ControlRoute {
    static let pendingKey = "arcfin.pendingControlLink"
    static let notification = Notification.Name("arcfinControlLink")

    @MainActor
    static func open(_ link: String) {
        UserDefaults.standard.set(link, forKey: pendingKey)
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

struct ResumeWatchingIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Watching"
    static let description = IntentDescription("Plays whatever you were watching last.")
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ControlRoute.open("arcfin://resume")
        return .result()
    }
}

struct OpenDownloadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Downloads"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ControlRoute.open("arcfin://downloads")
        return .result()
    }
}

struct OpenDiscoverIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Discover"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        ControlRoute.open("arcfin://discover")
        return .result()
    }
}
#if os(iOS)
/// A button on the Live Activity for another device playing (#457).
enum RemotePlaybackAction: String, AppEnum {
    case playPause, skipBackward, skipForward, volumeDown, volumeUp

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Remote Button"
    static let caseDisplayRepresentations: [RemotePlaybackAction: DisplayRepresentation] = [
        .playPause: "Play or Pause",
        .skipBackward: "Skip Back",
        .skipForward: "Skip Forward",
        .volumeDown: "Volume Down",
        .volumeUp: "Volume Up",
    ]
}

/// Set by the app at launch. The extension only declares the intent: a Live Activity's
/// intent runs in the app, which sends the command to the device.
enum RemotePlaybackCommands {
    @MainActor static var handler: ((RemotePlaybackAction, String) async -> Void)?
}

struct RemotePlaybackIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Control Another Device"
    static let isDiscoverable = false

    @Parameter(title: "Button") var action: RemotePlaybackAction
    @Parameter(title: "Device") var sessionID: String

    init() {}

    init(action: RemotePlaybackAction, sessionID: String) {
        self.action = action
        self.sessionID = sessionID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await RemotePlaybackCommands.handler?(action, sessionID)
        return .result()
    }
}
#endif
#endif
