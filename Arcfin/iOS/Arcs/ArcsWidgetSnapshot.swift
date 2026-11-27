// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation
import JellyfinAPI
import LiveActivityKit
import WidgetKit

/// Hands the Scene of the Day to its widget: the text, the title's poster saved in the App Group
/// container, and the clip's id for the link back in.
@MainActor
enum ArcsWidgetPublisher {
    static var isTurnedOn: Bool {
        UserDefaults.standard.object(forKey: ArcsSettings.clipOfTheDayKey) as? Bool ?? true
    }

    /// `clip` is today's scene, or nil when there's none or Arcs or its setting is off: the
    /// widget then shows its placeholder.
    static func publish(_ clip: ArcClip?, credential: ServerCredential) async {
        // Like Siri, Spotlight and the other widgets, nothing from a profile with an app-lock PIN.
        guard let clip, isTurnedOn, IntentSession.credential()?.id == credential.id else {
            clear()
            return
        }
        let name = "scene-\(clip.titleID).jpg"
        var fileName: String? = name
        if !ArcsWidgetStore.hasImage(fileName: name) {
            let url = JellyfinMediaClient.imageURL(baseURL: credential.baseURL, itemID: clip.titleID, tag: "", type: .primary,
                                                   fillWidth: 400, token: credential.accessToken)
            if let data = await URLSession.arcfin.imageData(from: url) {
                ArcsWidgetStore.writeImage(data, fileName: name)
            } else {
                fileName = nil
            }
        }
        guard IntentSession.credential()?.id == credential.id else { return }
        var snapshot = ArcsWidgetSnapshot(clipID: clip.id, title: clip.seriesName ?? clip.name, sceneLine: ArcText.sceneLine(clip),
                                          overview: clip.overview, imageFileName: fileName)
        if let previous = ArcsWidgetStore.load() {
            snapshot.updatedAt = previous.updatedAt
            guard snapshot != previous else { return }
            snapshot.updatedAt = .now
        }
        ArcsWidgetStore.save(snapshot)
        ArcsWidgetStore.pruneImages(keeping: fileName)
        WidgetCenter.shared.reloadTimelines(ofKind: ArcsWidgetStore.kind)
    }

    /// From the background check: moves a widget already showing a scene on to today's.
    static func refresh() async {
        guard ArcsWidgetStore.load() != nil else { return }
        if let status = AppServices.authManager.arcfinSyncStatus, !status.isOn("arcs") {
            clear()
            return
        }
        guard let credential = IntentSession.credential(), isTurnedOn else {
            clear()
            return
        }
        do {
            let clip = try await ArcsClient().clipOfTheDay(credential: credential, authHeader: IntentSession.authHeader(for: credential))
            await publish(clip, credential: credential)
        } catch {
            // Offline or the server didn't answer: yesterday's scene stays rather than a blank widget.
        }
    }

    static func clear() {
        let hadScene = ArcsWidgetStore.load() != nil
        ArcsWidgetStore.clear()
        if hadScene { WidgetCenter.shared.reloadTimelines(ofKind: ArcsWidgetStore.kind) }
    }
}
