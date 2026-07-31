import Foundation

/// 同步配置 & 常量
enum SyncConfig {
    /// 大文件阈值（字节）：超过此值弹窗确认
    static let largeFileThreshold: Int64 = 3 * 1024 * 1024

    /// 剪贴板轮询间隔（秒）
    static let clipboardPollInterval: TimeInterval = 0.5

    /// 文件传输分块大小（字节）
    static let fileChunkSize: Int = 64 * 1024

    /// 默认 TCP 端口
    static let tcpPort: UInt16 = 45455

    /// UDP 发现端口（Android ↔ Mac）
    static let udpDiscoveryPort: UInt16 = 45454

    /// Bonjour 服务类型
    static let bonjourType = "_clawdbridge._tcp"

    /// 蓝牙服务 UUID（Mac ↔ iOS）
    static let bluetoothServiceUUID = "A1B2C3D4-5678-4ABC-9DEF-123456789ABC"

    /// 蓝牙特征 UUID（数据传输）
    static let bluetoothCharUUID = "B2C3D4E5-6789-5BCD-0EFG-234567890BCD"

    /// 蓝牙 notify 特征 UUID（metadata 推送）
    static let bluetoothNotifyUUID = "C3D4E5F6-7890-6CDE-1FGH-345678901CDE"

    /// 同步目录（Mac）
    static var syncDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClawdBridge/Files")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 信任存储路径
    static var trustStorePath: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClawdBridge")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("trusted.json")
    }
}
