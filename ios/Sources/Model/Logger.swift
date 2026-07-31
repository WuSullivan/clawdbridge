import Foundation
import OSLog

/// iOS Logger：统一日志输出
enum Logger {
    private static let log = OSLog(subsystem: "com.clawdbridge.ios", category: "bridge")

    static func info(_ msg: String) {
        os_log(.info, log: log, "%{public}@", msg)
    }

    static func warn(_ msg: String) {
        os_log(.error, log: log, "⚠️ %{public}@", msg)
    }

    static func error(_ msg: String) {
        os_log(.fault, log: log, "❌ %{public}@", msg)
    }

    static func debug(_ msg: String) {
        os_log(.debug, log: log, "%{public}@", msg)
    }
}
