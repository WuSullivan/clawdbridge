import Foundation
import Network
import UIKit

/// iOS 端轻量日志
enum Logger {
    static func info(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        NSLog("[ClawdBridge] [\(ts)] [INFO] \(msg)")
    }
    static func warn(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        NSLog("[ClawdBridge] [\(ts)] [WARN] \(msg)")
    }
    static func error(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        NSLog("[ClawdBridge] [\(ts)] [ERROR] \(msg)")
    }
}

/// iOS 剪贴板同步会话
final class BridgeSession: ObservableObject {
    static let shared = BridgeSession()

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.clawdbridge.ios.bridge", qos: .utility)
    var monitor = ClipboardMonitor()

    func start() {
        monitor.start()
        discoverMac()
    }

    func stop() {
        monitor.stop()
        connection?.cancel()
    }

    // ── Bonjour 发现 Mac ──

    private func discoverMac() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let browser = NWBrowser(
            for: .bonjour(type: "_clawdbridge._tcp", domain: "local."),
            using: params
        )

        browser.browseResultsChangedHandler = { [weak self] _, changes in
            for change in changes {
                if case .added(let result) = change {
                    self?.connectToMac(endpoint: result.endpoint)
                }
            }
        }

        browser.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                Logger.error("Bonjour browser failed: \(error)")
            }
        }

        browser.start(queue: queue)
        Logger.info("iOS: browsing for Mac...")
    }

    private func connectToMac(endpoint: NWEndpoint) {
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Logger.info("iOS: connected to Mac")
                self?.sendHandshake(over: conn)
                self?.startReceiving(from: conn)
            case .failed(let error):
                Logger.warn("iOS: connection failed: \(error)")
            default:
                break
            }
        }
        conn.start(queue: queue)
        connection = conn
    }

    private func sendHandshake(over conn: NWConnection) {
        let device = Device.localDevice()
        let msg: [String: Any] = [
            "type": "handshake",
            "deviceID": device.deviceID,
            "deviceName": device.deviceName,
            "platform": "ios"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        var length = UInt32(data.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(data)
        conn.send(content: packet, completion: .contentProcessed({ _ in }))
    }

    private func startReceiving(from conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 4 else { return }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            conn.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { data, _, _, error in
                guard let data = data else { return }
                let payload = ClipPayload.decode(from: data)
                if let payload = payload, payload.type == .text,
                   let textData = payload.data,
                   let text = String(data: textData, encoding: .utf8) {
                    self.monitor.writeText(text)
                }
                self.startReceiving(from: conn)
            }
        }
    }

    func sendClipPayload(_ payload: ClipPayload) {
        guard let conn = connection, let data = payload.encode() else { return }
        var length = UInt32(data.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(data)
        conn.send(content: packet, completion: .contentProcessed({ _ in }))
    }
}

// MARK: - Clipboard Monitor (iOS)

final class ClipboardMonitor {
    private var lastChangeCount: Int = UIPasteboard.general.changeCount
    private var timer: Timer?

    var onTextCopied: ((String) -> Void)?

    func start() {
        lastChangeCount = UIPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() { timer?.invalidate() }

    func check() {
        let pb = UIPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        if let text = pb.string {
            onTextCopied?(text)
        }
    }

    func writeText(_ text: String) {
        lastChangeCount = UIPasteboard.general.changeCount
        UIPasteboard.general.string = text
    }

    func performBackgroundCheck() { check() }
}
