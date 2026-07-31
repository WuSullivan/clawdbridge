import Foundation
import CryptoKit

/// 新版剪贴板负载：支持懒加载按需传输
struct ClipMetadata: Codable {
    let version: Int
    let deviceID: String
    let timestamp: Date
    let type: ClipPayload.ClipType
    /// 内容 SHA-256（用于去重 & 校验请求）
    let contentHash: String
    /// 原始数据大小（字节）
    let dataSize: Int64
    /// 文件名（仅当 type=.file/.image/.video 时）
    var fileName: String?

    /// 是否为大文件（>3MB）
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
        // document: Word(.doc/.docx), PPT(.ppt/.pptx), PDF, Excel(.xls/.xlsx), Pages, Numbers, Keynote 等
    }

    // ── Metadata ──

    var metadata: ClipMetadata {
        ClipMetadata(
            version: version,
            deviceID: deviceID,
            timestamp: timestamp,
            type: type,
            contentHash: contentHash,
            dataSize: dataSize,
            fileName: fileName
        )
    }

    var isLarge: Bool { dataSize > SyncConfig.largeFileThreshold }

    // ── 编解码 ──

    func encode() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(from data: Data) -> ClipPayload? {
        try? JSONDecoder().decode(ClipPayload.self, from: data)
    }

    // ── 工厂方法 ──

    static func text(deviceID: String, content: String) -> ClipPayload {
        let data = content.data(using: .utf8)!
        return ClipPayload(
            version: 1, deviceID: deviceID, timestamp: Date(),
            type: .text,
            contentHash: sha256(data),
            dataSize: Int64(data.count),
            data: data
        )
    }

    static func image(deviceID: String, data: Data, fileName: String?) -> ClipPayload {
        ClipPayload(
            version: 1, deviceID: deviceID, timestamp: Date(),
            type: .image,
            contentHash: sha256(data),
            dataSize: Int64(data.count),
            data: data,
            fileName: fileName
        )
    }

    static func video(deviceID: String, data: Data, fileName: String) -> ClipPayload {
        ClipPayload(
            version: 1, deviceID: deviceID, timestamp: Date(),
            type: .video,
            contentHash: sha256(data),
            dataSize: Int64(data.count),
            data: data,
            fileName: fileName
        )
    }

    static func file(deviceID: String, data: Data, fileName: String) -> ClipPayload {
        let ext = fileName.lowercased().components(separatedBy: ".").last ?? ""
        let isDocument = ["doc", "docx", "ppt", "pptx", "xls", "xlsx",
                          "pdf", "pages", "numbers", "key", "odt", "ods", "odp",
                          "rtf", "csv", "txt", "md"].contains(ext)
        return ClipPayload(
            version: 1, deviceID: deviceID, timestamp: Date(),
            type: isDocument ? .document : .file,
            contentHash: sha256(data),
            dataSize: Int64(data.count),
            data: data,
            fileName: fileName
        )
    }

    // ── 清理敏感数据（仅保留 metadata 用于广播） ──
    mutating func stripData() {
        data = nil
    }

    fileprivate static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
