import Foundation

struct Device: Codable, Equatable, Hashable {
    let deviceID: String
    let deviceName: String
    let platform: Platform
    var isTrusted: Bool
    var lastSeen: Date?

    enum Platform: String, Codable {
        case mac, ios, android
    }

    static func == (lhs: Device, rhs: Device) -> Bool { lhs.deviceID == rhs.deviceID }
    func hash(into hasher: inout Hasher) { hasher.combine(deviceID) }

    static func localDevice() -> Device {
        let id = UserDefaults.standard.string(forKey: "device_id") ?? {
            let new = UUID().uuidString
            UserDefaults.standard.set(new, forKey: "device_id")
            return new
        }()
        return Device(
            deviceID: id,
            deviceName: UIDevice.current.name,
            platform: .ios,
            isTrusted: true,
            lastSeen: Date()
        )
    }
}
