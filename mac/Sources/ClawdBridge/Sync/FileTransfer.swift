import Foundation

/// 文件传输：按需发送 / 接收
///
/// 大文件（>3MB）不自动广播，而是在接收方确认后通过专用通道传输。
/// 小文件直接随 ClipPayload 一起发送。
final class FileTransfer {
    static let shared = FileTransfer()

    /// 正在进行的传输（按 contentHash 索引）
    private var activeTransfers: [String: Transfer] = [:]
    private let lock = NSLock()

    struct Transfer {
        let payload: ClipPayload
        let tempPath: URL
    }

    /// 将大文件 payload 写入临时目录，返回临时路径（供后续按需拉取）
    func stageLargeFile(_ payload: ClipPayload) -> URL? {
        guard let data = payload.data, let fileName = payload.fileName else { return nil }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawdbridge-transfer")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let path = tmp.appendingPathComponent(fileName)
        do {
            try data.write(to: path)
            lock.lock()
            activeTransfers[payload.contentHash] = Transfer(payload: payload, tempPath: path)
            lock.unlock()
            Logger.info("FileTransfer: staged \(fileName) (\(data.count) bytes)")
            return path
        } catch {
            Logger.error("FileTransfer: failed to stage \(fileName): \(error)")
            return nil
        }
    }

    /// 其他设备请求拉取大文件（通过 contentHash）
    func fetchLargeFile(hash: String) -> ClipPayload? {
        lock.lock()
        guard let transfer = activeTransfers[hash] else {
            lock.unlock()
            Logger.warn("FileTransfer: no staged file for hash \(hash.prefix(8))...")
            return nil
        }
        // 重新读取文件数据（确保完整性）
        if let data = try? Data(contentsOf: transfer.tempPath) {
            var payload = transfer.payload
            payload.data = data
            lock.unlock()
            return payload
        }
        lock.unlock()
        return nil
    }

    /// 清理临时文件
    func cleanup(hash: String) {
        lock.lock()
        if let transfer = activeTransfers[hash] {
            try? FileManager.default.removeItem(at: transfer.tempPath)
            activeTransfers.removeValue(forKey: hash)
        }
        lock.unlock()
    }
}
