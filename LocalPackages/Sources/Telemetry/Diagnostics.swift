// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import OSLog
#if canImport(MetricKit) && !os(tvOS)
import MetricKit
#endif

/// Crash, hang and resource reports from MetricKit, kept on the device. They only leave it in
/// a report the user shares themselves; nothing is sent anywhere automatically.
public final class Diagnostics: NSObject, Sendable {
    public static let shared = Diagnostics()

    private static let directory = URL.applicationSupportDirectory
        .appending(path: "Diagnostics", directoryHint: .isDirectory)
    private static let reportsKept = 20
    private static let logLinesKept = 5000

    public func start() {
        #if canImport(MetricKit) && !os(tvOS)
        MXMetricManager.shared.add(self)
        Self.save(MXMetricManager.shared.pastDiagnosticPayloads)
        #endif
    }

    /// A plain-text report of this session's log and the saved crash and hang reports.
    @concurrent public static func makeReport() async -> URL {
        var text = header()
        text += "\n== Log (this session, last 24 hours)\n"
        text += recentLog()
        text += "\n== Crash and hang reports (\(savedReports().count))\n"
        for url in savedReports() {
            text += "\n-- \(url.deletingPathExtension().lastPathComponent)\n"
            text += (try? String(contentsOf: url, encoding: .utf8)) ?? "(unreadable)\n"
            text += "\n"
        }
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let url = URL.temporaryDirectory.appending(path: "Arcfin Diagnostics \(stamp).txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func header() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return """
        Arcfin \(version) (\(build))
        \(ProcessInfo.processInfo.operatingSystemVersionString), \(model)
        Generated \(Date.now.formatted(.iso8601))

        """
    }

    private static func recentLog() -> String {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let start = store.position(date: Date.now.addingTimeInterval(-24 * 60 * 60))
            let predicate = NSPredicate(format: "subsystem == %@", Telemetry.subsystem)
            let lines = try store.getEntries(at: start, matching: predicate)
                .compactMap { $0 as? OSLogEntryLog }
                .map { "\($0.date.formatted(.iso8601)) [\($0.category)] \(levelName($0.level)) \($0.composedMessage)" }
            return lines.suffix(logLinesKept).joined(separator: "\n") + "\n"
        } catch {
            return "(log unavailable: \(error.localizedDescription))\n"
        }
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "-"
        }
    }

    // File names start with the report's date, so name order is date order without reading
    // file timestamps.
    private static func savedReports() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    #if canImport(MetricKit) && !os(tvOS)
    private static func save(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for payload in payloads {
            let stamp = payload.timeStampEnd.formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
            let url = directory.appending(path: "\(stamp)-\(UUID().uuidString.prefix(8)).json")
            try? payload.jsonRepresentation().write(to: url)
        }
        for url in savedReports().dropLast(reportsKept) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    #endif
}

#if canImport(MetricKit) && !os(tvOS)
extension Diagnostics: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Self.save(payloads)
    }
}
#endif
