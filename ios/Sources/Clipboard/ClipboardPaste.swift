import Foundation
import UIKit

/// iOS 剪贴板写入
final class ClipboardPaste {
    func write(_ payload: ClipPayload) {
        let pb = UIPasteboard.general

        switch payload.type {
        case .text:
            guard let data = payload.data, let text = String(data: data, encoding: .utf8) else { return }
            pb.string = text

        case .image:
            guard let data = payload.data, let img = UIImage(data: data) else { return }
            pb.image = img

        case .video, .file, .document:
            guard let data = payload.data, let fileName = payload.fileName else { return }
            let dest = SyncConfig.syncDirectory.appendingPathComponent(fileName)
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: dest)
            pb.url = dest
        }

        Logger.info("ClipboardPaste: wrote \(payload.type.rawValue) from \(payload.deviceID)")
    }
}
