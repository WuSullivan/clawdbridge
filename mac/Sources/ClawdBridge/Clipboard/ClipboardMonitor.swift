import Foundation
import AppKit

/// 剪贴板监听器：轮询 changeCount，检测变化后打包 payload
final class ClipboardMonitor {
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.clawdbridge.clipboard", qos: .utility)

    var onChange: (([ClipPayload]) -> Void)?

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: SyncConfig.clipboardPollInterval)
        timer?.setEventHandler { [weak self] in
            self?.check()
        }
        timer?.resume()
    }

    func stop() { timer?.cancel() }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        var payloads: [ClipPayload] = []
        let deviceID = Device.localDevice().deviceID

        // ── 纯文本 ──
        if let text = pb.string(forType: .string), !text.isEmpty {
            payloads.append(.text(deviceID: deviceID, content: text))
        }

        // ── 图片 ──
        if let imgData = pb.data(forType: .tiff) {
            if let rep = NSBitmapImageRep(data: imgData),
               let pngData = rep.representation(using: .png, properties: [:]) {
                payloads.append(.image(deviceID: deviceID, data: pngData, fileName: "clipboard.png"))
            }
        }

        // ── 文件 URL（含图片/视频/文档自动分类）──
        if let fileURLs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in fileURLs {
                guard let data = try? Data(contentsOf: url) else { continue }
                let ext = url.pathExtension.lowercased()
                if ["mp4", "mov", "m4v", "avi", "mkv", "webm", "3gp"].contains(ext) {
                    payloads.append(.video(deviceID: deviceID, data: data, fileName: url.lastPathComponent))
                } else if ["png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff"].contains(ext) {
                    payloads.append(.image(deviceID: deviceID, data: data, fileName: url.lastPathComponent))
                } else {
                    payloads.append(.file(deviceID: deviceID, data: data, fileName: url.lastPathComponent))
                }
            }
        }

        if !payloads.isEmpty {
            onChange?(payloads)
        }
    }
}
