import Foundation
import CryptoKit

struct ClipMetadata: Codable {
    let version: Int
    let deviceID: String
    let timestamp: Date
    let type: ClipPayload.ClipType
    let contentHash: String
    let dataSize: Int64
    var fileName: String?
    var isLarge: Bool { dataSize > SyncConfig.largeFileThreshold }

    func encode() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(from data: Data) -> ClipMetadata? {
        try? JSONDecoder().decode(ClipMetadata.self, from: data)
    }
}

struct ClipPayload: Codable {
    let version: Int
    let deviceID: String
    let timestamp: Date
    let type: ClipType
    let contentHash: String
    let dataSize: Int64
    var data: Data?
    var fileName: String?

    enum ClipType: String, Codable {
        case text, image, video, file, document
    }

    var metadata: ClipMetadata {
        ClipMetadata(version: version, deviceID: deviceID, timestamp: timestamp,
                      type: type, contentHash: contentHash, dataSize: dataSize, fileName: fileName)
    }

    var isLarge: Bool { dataSize > SyncConfig.largeFileThreshold }

    func encode() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(from data: Data) -> ClipPayload? {
        try? JSONDecoder().decode(ClipPayload.self, from: data)
    }

    // MARK: - Factory

    static func text(deviceID: String, content: String) -> ClipPayload {
        let data = content.data(using: .utf8)!
        return ClipPayload(version: 1, deviceID: deviceID, timestamp: Date(),
            type: .text, contentHash: sha256(data), dataSize: Int64(data.count), data: data)
    }

    static func image(deviceID: String, data: Data, fileName: String?) -> ClipPayload {
        ClipPayload(version: 1, deviceID: deviceID, timestamp: Date(),
            type: .image, contentHash: sha256(data), dataSize: Int64(data.count),
            data: data, fileName: fileName)
    }

    static func video(deviceID: String, data: Data, fileName: String) -> ClipPayload {
        ClipPayload(version: 1, deviceID: deviceID, timestamp: Date(),
            type: .video, contentHash: sha256(data), dataSize: Int64(data.count),
            data: data, fileName: fileName)
    }

    static func file(deviceID: String, data: Data, fileName: String) -> ClipPayload {
        let ext = fileName.lowercased().components(separatedBy: ".").last ?? ""
        let isDocument = ["doc","docx","ppt","pptx","xls","xlsx","pdf",
                          "pages","numbers","key","odt","ods","odp",
                          "rtf","csv","txt","md"].contains(ext)
        return ClipPayload(version: 1, deviceID: deviceID, timestamp: Date(),
            type: isDocument ? .document : .file,
            contentHash: sha256(data), dataSize: Int64(data.count),
            data: data, fileName: fileName)
    }

    mutating func stripData() { data = nil }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}
