import BackgroundTasks
import Foundation
import Telemetry

// MARK: - Task identifiers

public enum BackgroundTaskIdentifier {
    public static let syncSettings = "com.psmattas.arcfin.sync-settings"
    public static let prefetchContent = "com.psmattas.arcfin.prefetch-content"
}

// MARK: - Scheduler

public final class BackgroundScheduler: Sendable {

    private static let log = Telemetry.logger(category: "BackgroundKit")

    public static let shared = BackgroundScheduler()
    private init() {}

    public func scheduleSettingsSync() {
        let request = BGProcessingTaskRequest(identifier: BackgroundTaskIdentifier.syncSettings)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Self.log.error("Failed to schedule settings sync: \(error)")
        }
    }
}
