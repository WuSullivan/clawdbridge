import Foundation

/// 信任设备持久化存储
/// 保存已配对设备列表、加密密钥等
final class TrustStore {
    private let fileURL: URL
    private var entries: [String: TrustEntry] = [:]

    struct TrustEntry: Codable {
        let deviceID: String
        let deviceName: String
        let platform: String
        let sharedKey: Data   // 配对后交换的对称密钥（256-bit）
        let pairedAt: Date
    }

    init() {
        self.fileURL = FileManager.appSupportDir.appendingPathComponent("trusted.json")
        load()
    }

    // MARK: - CRUD

    func add(deviceID: String, name: String, platform: String, key: Data) {
        entries[deviceID] = TrustEntry(
            deviceID: deviceID,
            deviceName: name,
            platform: platform,
            sharedKey: key,
            pairedAt: Date()
        )
        save()
        Logger.info("TrustStore: added device \(name) [\(deviceID)]")
    }

    func remove(deviceID: String) {
        entries.removeValue(forKey: deviceID)
        save()
        Logger.info("TrustStore: removed device [\(deviceID)]")
    }

    func isTrusted(_ deviceID: String) -> Bool {
        entries[deviceID] != nil
    }

    func getKey(for deviceID: String) -> Data? {
        entries[deviceID]?.sharedKey
    }

    func allDevices() -> [TrustEntry] {
        Array(entries.values)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let loaded = try? JSONDecoder().decode([String: TrustEntry].self, from: data) else {
            Logger.info("TrustStore: no existing trust entries, starting fresh")
            return
        }
        entries = loaded
        Logger.info("TrustStore: loaded \(entries.count) trusted device(s)")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else {
            Logger.error("TrustStore: failed to encode entries")
            return
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Logger.error("TrustStore: failed to save: \(error)")
        }
    }
}
