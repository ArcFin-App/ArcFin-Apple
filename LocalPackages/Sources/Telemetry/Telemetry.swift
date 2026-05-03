import OSLog

public enum Telemetry: Sendable {

    static let subsystem = "com.psmattas.arcfin"

    public static func logger(category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
