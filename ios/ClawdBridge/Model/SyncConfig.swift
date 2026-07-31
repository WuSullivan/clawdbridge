import Foundation

struct Device: Codable {
    let deviceID: String
    let deviceName: String
    let platform: String

    static func localDevice() -> Device {
        let id = UserDefaults.standard.string(forKey: "device_id") ?? {
            let new = UUID().uuidString
            UserDefaults.standard.set(new, forKey: "device_id")
            return new
        }()
        return Device(
            deviceID: id,
            deviceName: UIDevice.current.name,
            platform: "ios"
        )
    }
}

struct ClipPayload: Codable {
    let version: Int
    let deviceID: String
    let timestamp: Date
    let type: ClipType
    var data: Data?
    var fileName: String?

    enum ClipType: String, Codable {
        case text, fileAnnounce, fileChunk, fileComplete
    }

    func encode() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(from data: Data) -> ClipPayload? {
        try? JSONDecoder().decode(ClipPayload.self, from: data)
    }

    static func text(deviceID: String, content: String) -> ClipPayload {
        ClipPayload(
            version: 1,
            deviceID: deviceID,
            timestamp: Date(),
            type: .text,
            data: content.data(using: .utf8)
        )
    }
}
