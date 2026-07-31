import Foundation

/// 信任存储：JSON 文件，无 Keychain 依赖
final class TrustStore {
    static let shared = TrustStore()
    private let url = SyncConfig.trustStoreURL
    private var trusted: [String: Device] = [:]
    private let lock = NSLock()

    private init() { load() }

    var allDevices: [Device] {
        lock.lock(); defer { lock.unlock() }
        return Array(trusted.values)
    }

    func isTrusted(_ deviceID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return trusted[deviceID] != nil
    }

    func trust(_ device: Device) {
        lock.lock()
        var d = device
        d.isTrusted = true
        d.lastSeen = Date()
        trusted[device.deviceID] = d
        lock.unlock()
        save()
    }

    func remove(_ deviceID: String) {
        lock.lock()
        trusted.removeValue(forKey: deviceID)
        lock.unlock()
        save()
    }

    func touch(_ deviceID: String) {
        lock.lock()
        trusted[deviceID]?.lastSeen = Date()
        lock.unlock()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let devices = try? JSONDecoder().decode([Device].self, from: data) else { return }
        lock.lock()
        for d in devices { trusted[d.deviceID] = d }
        lock.unlock()
    }

    private func save() {
        lock.lock()
        let list = Array(trusted.values)
        lock.unlock()
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: url)
    }
}
