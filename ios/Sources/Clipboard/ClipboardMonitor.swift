import Foundation

/// iOS 剪贴板监听器
/// 注意：iOS 剪贴板 API 有限制（UIPasteboard 只能在有 active 场景时读取）
/// 所以 iOS 端使用两种策略：
/// 1. 前台：轮询 UIPasteboard.general.changeCount
/// 2. 后台：依赖 Mac/Android 端主动推送
final class ClipboardMonitor {
    private var lastChangeCount: Int = UIPasteboard.general.changeCount
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.clawdbridge.ios.clipboard", qos: .utility)

    var onChange: (([ClipPayload]) -> Void)?

    func start() {
        lastChangeCount = UIPasteboard.general.changeCount
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: SyncConfig.clipboardPollInterval)
        timer?.setEventHandler { [weak self] in
            self?.poll()
        }
        timer?.resume()
    }

    func stop() { timer?.cancel() }

    private func poll() {
        let pb = UIPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        var payloads: [ClipPayload] = []
        let deviceID = Device.localDevice().deviceID

        // ── 文本 ──
        if let text = pb.string, !text.isEmpty {
            payloads.append(.text(deviceID: deviceID, content: text))
        }

        // ── 图片 ──
        if let imgData = pb.image?.pngData() {
            payloads.append(.image(deviceID: deviceID, data: imgData, fileName: "clipboard.png"))
        }

        // ── URL / 文件（iOS 剪贴板文件和文本无明确区分，通过 hasStrings + hasURLs 判断）──
        if let url = pb.url {
            if let data = try? Data(contentsOf: url) {
                let ext = url.pathExtension.lowercased()
                if ["mp4","mov","m4v","avi","mkv","webm","3gp"].contains(ext) {
                    payloads.append(.video(deviceID: deviceID, data: data, fileName: url.lastPathComponent))
                } else if ["png","jpg","jpeg","gif","heic","webp","bmp","tiff"].contains(ext) {
                    payloads.append(.image(deviceID: deviceID, data: data, fileName: url.lastPathComponent))
                } else {
                    payloads.append(.file(deviceID: deviceID, data: data, fileName: url.lastPathComponent))
                }
            }
        }

        if !payloads.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.onChange?(payloads)
            }
        }
    }
}
