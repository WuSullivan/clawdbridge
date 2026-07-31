import Foundation

/// 统一日志模块：无 UI 弹窗，输出到系统日志 + 文件
enum Logger {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.timeZone = TimeZone.current
        return f
    }()

    /// 开发阶段可使用日志文件路径
    static var logFileURL: URL? = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClawdBridge/Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("clawdbridge.log")
        // Rotate if > 1MB
        if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64, size > 1_000_000 {
            try? FileManager.default.removeItem(at: file)
        }
        return file
    }()

    static func info(_ message: String, file: String = #file, function: String = #function) {
        log(level: "INFO", message: message, file: file, function: function)
    }

    static func warn(_ message: String, file: String = #file, function: String = #function) {
        log(level: "WARN", message: message, file: file, function: function)
    }

    static func error(_ message: String, file: String = #file, function: String = #function) {
        log(level: "ERROR", message: message, file: file, function: function)
    }

    static func debug(_ message: String, file: String = #file, function: String = #function) {
        #if DEBUG
        log(level: "DEBUG", message: message, file: file, function: function)
        #endif
    }

    private static func log(level: String, message: String, file: String, function: String) {
        let timestamp = dateFormatter.string(from: Date())
        let fileName = (file as NSString).lastPathComponent
        let line = "[\(timestamp)] [\(level)] [\(fileName):\(function)] \(message)"

        // Console (stderr, readable by Console.app)
        fputs(line + "\n", stderr)

        // File
        if let url = logFileURL, let data = (line + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
