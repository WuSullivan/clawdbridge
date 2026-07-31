import Foundation

/// iOS 端同步配置常量
/// 所有值均来自 SyncConfig（由 build script 或 Xcode 注入）
/// 注意：iOS 端不参与 UDP/TCP 发现（纯蓝牙），故部分字段仅用于继承协议定义
enum SyncConfig {
    // ── 协议版本 ──
    static let version = 1

    // ── 文件传输 ──
    static let largeFileThreshold: Int64 = 3 * 1024 * 1024

    // ── 剪贴板轮询间隔（秒）──
    static let clipboardPollInterval: Double = 0.5
    static let clipboardPollLeeway: Double = 0.1

    // ── 蓝牙 ──
    static let bluetoothServiceUUID = "A1B2C3D4-5678-4ABC-9DEF-123456789ABC"
    static let bluetoothCharUUID = "B2C3D4E5-6789-5BCD-0EFG-234567890BCD"
    static let bluetoothNotifyUUID = "C3D4E5F6-7890-6CDE-1FGH-345678901CDE"

    // ── 中继 ──
    static let relayPort: UInt16 = 45456
    static let relayHost = "local" // Mac always advertises Bonjour

    // ── 信任存储 ──
    static let trustStoreName = "trusted.json"
    static var trustStoreURL: URL {
        try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent(trustStoreName)
    }

    // ── 同步缓存 ──
    static let syncDirectory: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClawdBridge/Files")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let deviceIDKey = "device_id"
    static let tutorialCompletedKey = "tutorial_completed"
}
