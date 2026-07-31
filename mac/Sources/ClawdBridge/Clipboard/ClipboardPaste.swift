import Foundation
import AppKit

/// 剪贴板写入：接收远程 payload 并写入本机剪贴板
final class ClipboardPaste {
    func write(_ payload: ClipPayload) {
        let pb = NSPasteboard.general

        switch payload.type {
        case .text:
            guard let data = payload.data, let text = String(data: data, encoding: .utf8) else { return }
            pb.declareTypes([.string], owner: nil)
            pb.setString(text, forType: .string)
            Logger.info("ClipboardPaste: wrote text (\(text.count) chars)")

        case .image:
            guard let data = payload.data else { return }
            pb.declareTypes([.tiff, .png], owner: nil)
            if let img = NSImage(data: data) {
                pb.writeObjects([img])
            } else {
                pb.setData(data, forType: .png)
            }
            Logger.info("ClipboardPaste: wrote image (\(data.count) bytes)")

        case .video, .file, .document:
            guard let data = payload.data, let fileName = payload.fileName else { return }
            let dest = SyncConfig.syncDirectory.appendingPathComponent(fileName)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: dest)
            // 将文件 URL 写入剪贴板
            pb.declareTypes([.fileURL], owner: nil)
            pb.writeObjects([dest as NSURL])
            Logger.info("ClipboardPaste: wrote file \(fileName) → \(dest.path)")
        }
    }
}
