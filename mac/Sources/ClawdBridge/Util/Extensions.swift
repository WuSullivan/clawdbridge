import Foundation

// MARK: - Extensions

extension Data {
    /// XOR 快速混淆（轻量加密辅助，不替代正式加密算法）
    func xor(with key: Data) -> Data {
        var result = Data(count: self.count)
        for i in 0..<self.count {
            result[i] = self[i] ^ key[i % key.count]
        }
        return result
    }
}

extension String {
    /// 截断到指定长度（用于日志输出剪贴板预览）
    func truncated(_ maxLen: Int) -> String {
        self.count <= maxLen ? self : String(self.prefix(maxLen)) + "..."
    }
}

extension FileManager {
    /// 确保目录存在
    func ensureDirectory(at url: URL) throws {
        if !fileExists(atPath: url.path) {
            try createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Application Support 根目录
    static var appSupportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClawdBridge")
        try? FileManager.default.ensureDirectory(at: dir)
        return dir
    }
}

/// 信号处理入口
func setupSignalHandlers() {
    signal(SIGINT) { _ in
        Logger.info("Received SIGINT, shutting down...")
        exit(0)
    }
    signal(SIGTERM) { _ in
        Logger.info("Received SIGTERM, shutting down...")
        exit(0)
    }
}
