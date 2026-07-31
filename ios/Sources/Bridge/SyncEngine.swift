import Foundation

/// iOS 端同步引擎：监听本地剪贴板 → BLE 广播 → 接收远端
final class SyncEngine {
    static let shared = SyncEngine()

    private var clipboardMonitor: ClipboardMonitor
    private var pastein: ClipboardPaste
    private var bleBridge: BLEBridge?

    /// 去重
    private var recentHashes: Set<String> = []
    private var recentHashesOrder: [String] = []
    private let dedupLock = NSLock()
    private let maxDedup = 100

    /// 避免回写循环
    private var lastPasteSourceDeviceID: String?

    private var selfDeviceID: String { Device.localDevice().deviceID }

    private init() {
        clipboardMonitor = ClipboardMonitor()
        pastein = ClipboardPaste()
        clipboardMonitor.onChange = { [weak self] payloads in
            self?.handleLocalClipboardChange(payloads)
        }
    }

    func setBLEBridge(_ bridge: BLEBridge) {
        bleBridge = bridge
        bridge.onPayloadReceived = { [weak self] payload in
            self?.receiveRemotePayload(payload)
        }
    }

    func start() {
        clipboardMonitor.start()
        Logger.info("SyncEngine(iOS): started")
    }

    // MARK: - 本机剪贴板变化

    private func handleLocalClipboardChange(_ payloads: [ClipPayload]) {
        for payload in payloads {
            guard !isDuplicate(payload.contentHash) else { continue }
            markSeen(payload.contentHash)

            if payload.deviceID == lastPasteSourceDeviceID {
                lastPasteSourceDeviceID = nil
                continue
            }

            bleBridge?.notifyAll(payload)
        }
    }

    // MARK: - 接收远程

    func receiveRemotePayload(_ payload: ClipPayload) {
        guard !isDuplicate(payload.contentHash) else { return }
        markSeen(payload.contentHash)
        lastPasteSourceDeviceID = payload.deviceID
        pastein.write(payload)
    }

    // MARK: - 去重

    private func isDuplicate(_ hash: String) -> Bool {
        dedupLock.lock(); defer { dedupLock.unlock() }
        return recentHashes.contains(hash)
    }

    private func markSeen(_ hash: String) {
        dedupLock.lock()
        recentHashes.insert(hash)
        recentHashesOrder.append(hash)
        while recentHashesOrder.count > maxDedup {
            recentHashes.remove(recentHashesOrder.removeFirst())
        }
        dedupLock.unlock()
    }
}
