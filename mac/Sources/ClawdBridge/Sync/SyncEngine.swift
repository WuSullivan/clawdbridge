import Foundation
import AppKit

/// 同步引擎：按需传输核心逻辑
///
/// 流程：
/// 1. 本机复制 → 打包 ClipPayload → 如果 ≤3MB 直接 broadcast 给所有设备
/// 2. 如果 >3MB → 本地弹窗确认，用户同意后才 broadcast
/// 3. 接收方收到 payload → 写入剪贴板（覆盖旧内容）
/// 4. 如果接收方收到的是 metadata-only（大文件已剥离），弹窗询问要不要拉取
///
/// 广播方式：
/// - Mac → iOS：CoreBluetooth peripheral notify
/// - Mac → Android：TCP push
/// - Mac → Mac：Bonjour TCP
final class SyncEngine {
    static let shared = SyncEngine()

    private var clipboardMonitor: ClipboardMonitor
    private var pastein: ClipboardPaste
    private var connections: [String: PeerConnection] = [:]
    private let connLock = NSLock()

    /// 最近 100 条 payload hash，用于去重
    private var recentHashes: Set<String> = []
    private var recentHashesOrder: [String] = []
    private let dedupLock = NSLock()
    private let maxDedup = 100

    /// 蓝牙广播
    private var bleBridge: BLEBridge?

    /// 最后一次剪贴板写入的来源 deviceID（避免自循环）
    private var lastPasteSourceDeviceID: String?

    private var selfDeviceID: String {
        Device.localDevice().deviceID
    }

    private init() {
        clipboardMonitor = ClipboardMonitor()
        pastein = ClipboardPaste()
        clipboardMonitor.onChange = { [weak self] payloads in
            self?.handleLocalClipboardChange(payloads)
        }
    }

    // MARK: - 启动

    func start() {
        clipboardMonitor.start()
        // BLE 由外部注入（BonjourService 启动时创建）
        Logger.info("SyncEngine: started (polling clipboard every \(SyncConfig.clipboardPollInterval)s)")
    }

    func setBLEBridge(_ bridge: BLEBridge) {
        bleBridge = bridge
    }

    // MARK: - 连接管理

    func addConnection(_ deviceID: String, _ conn: PeerConnection) {
        connLock.lock()
        connections[deviceID] = conn
        connLock.unlock()
    }

    func removeConnection(_ deviceID: String) {
        connLock.lock()
        connections.removeValue(forKey: deviceID)
        connLock.unlock()
    }

    // MARK: - 本机剪贴板变化

    private func handleLocalClipboardChange(_ payloads: [ClipPayload]) {
        for payload in payloads {
            guard !isDuplicate(payload.contentHash) else { continue }
            markSeen(payload.contentHash)

            // 大文件弹窗确认
            if payload.isLarge, let fileName = payload.fileName {
                let ok = requestUserApproval(fileName: fileName, size: payload.dataSize)
                if !ok {
                    Logger.info("SyncEngine: user rejected large file \(fileName)")
                    continue
                }
            }

            // ⭐ 如果本机刚收到远程写入，不再回传
            if payload.deviceID == lastPasteSourceDeviceID {
                Logger.info("SyncEngine: suppressing loopback for \(payload.deviceID)")
                lastPasteSourceDeviceID = nil
                continue
            }

            broadcast(payload)
        }
    }

    // MARK: - 接收远程 payload

    func receiveRemotePayload(_ payload: ClipPayload) {
        guard !isDuplicate(payload.contentHash) else { return }
        markSeen(payload.contentHash)

        // 记录来源，避免回写触发循环
        lastPasteSourceDeviceID = payload.deviceID

        // 写入本机剪贴板（覆盖之前的内容）
        pastein.write(payload)
        Logger.info("SyncEngine: received \(payload.type.rawValue) from \(payload.deviceID)")
    }

    // MARK: - 广播

    private func broadcast(_ payload: ClipPayload) {
        Logger.info("SyncEngine: broadcasting \(payload.type.rawValue) (hash: \(payload.contentHash.prefix(8))...)")

        // 1. 通过 BLE 广播 metadata 给 iOS 设备
        if let ble = bleBridge {
            ble.notifyAll(payload)
        }

        // 2. 通过 TCP 广播给已知连接（Android + 其他 Mac）
        connLock.lock()
        let peers = Array(connections.values)
        connLock.unlock()

        for conn in peers {
            conn.send(payload: payload, with: nil)
        }
    }

    // MARK: - 大文件确认（GUI 弹窗）

    private func requestUserApproval(fileName: String, size: Int64) -> Bool {
        let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        let semaphore = DispatchSemaphore(value: 0)
        var approved = false

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "发送大文件？"
            alert.informativeText = "剪贴板中有大文件「\(fileName)」（\(sizeStr)），\n是否发送到其他设备？"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "发送")
            alert.addButton(withTitle: "跳过")
            approved = (alert.runModal() == .alertFirstButtonReturn)
            semaphore.signal()
        }

        semaphore.wait()
        return approved
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
            let old = recentHashesOrder.removeFirst()
            recentHashes.remove(old)
        }
        dedupLock.unlock()
    }
}
