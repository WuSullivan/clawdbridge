import Foundation
import Network

/// TCP 连接管理器：管理对等设备的 TCP 连接
/// 用于跨平台设备间的数据传输（非 Apple 设备通过 UDP 发现后建立 TCP 通道）
final class PeerConnection {
    private let queue = DispatchQueue(label: "com.clawdbridge.peer", qos: .utility)
    private var connection: NWConnection?
    private var isConnected = false

    let remoteDeviceID: String
    let address: String
    let port: UInt16
    var onDisconnected: (() -> Void)?
    var onPayloadReceived: ((ClipPayload) -> Void)?

    init(deviceID: String, address: String, port: UInt16) {
        self.remoteDeviceID = deviceID
        self.address = address
        self.port = port
    }

    func connect() {
        let host = NWEndpoint.Host(address)
        let port = NWEndpoint.Port(rawValue: self.port)!
        let connection = NWConnection(host: host, port: port, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Logger.info("PeerConnection: connected to \(self?.remoteDeviceID ?? "unknown")")
                self?.isConnected = true
                self?.startReceiving()

            case .failed(let error):
                Logger.warn("PeerConnection: connection to \(self?.remoteDeviceID ?? "") failed: \(error)")
                self?.isConnected = false
                self?.onDisconnected?()
                connection.cancel()

            case .cancelled:
                self?.isConnected = false
                self?.onDisconnected?()

            default:
                break
            }
        }

        connection.start(queue: queue)
        self.connection = connection
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    // MARK: - Send

    /// 发送未加密载荷（用于 BLE / Mac-Mac 等无需加密的场景）
    func send(_ payload: ClipPayload) {
        send(payload: payload, with: nil)
    }

    /// 发送加密后的载荷（调用方先加密再传入）
    func send(data: Data) {
        guard let conn = connection, isConnected else {
            Logger.warn("PeerConnection: cannot send, not connected")
            return
        }

        // 4 字节长度前缀
        var length = UInt32(data.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(data)

        conn.send(content: packet, completion: .contentProcessed({ error in
            if let error = error {
                Logger.warn("PeerConnection: send error: \(error)")
            }
        }))
    }

    /// 发送剪贴板载荷（自动加密）
    func send(payload: ClipPayload, with crypto: CryptoSession?) {
        guard let encoded = payload.encode() else { return }
        let finalData: Data
        if let crypto = crypto {
            guard let encrypted = crypto.encrypt(plaintext: encoded) else {
                Logger.error("PeerConnection: encryption failed")
                return
            }
            finalData = encrypted
        } else {
            finalData = encoded
        }
        send(data: finalData)
    }

    // MARK: - Receive

    private func startReceiving() {
        receiveNext()
    }

    private func receiveNext() {
        guard let conn = connection else { return }

        // Read 4-byte length header
        conn.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 4 else {
                if let error = error {
                    Logger.debug("PeerConnection: header read error: \(error)")
                }
                return
            }

            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            guard length > 0, length < 100_000_000 else {  // 100MB max per message
                Logger.warn("PeerConnection: invalid message length: \(length)")
                return
            }

            // Read the actual payload
            conn.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { data, _, _, error in
                guard let data = data else { return }

                if let payload = ClipPayload.decode(from: data) {
                    self.onPayloadReceived?(payload)
                }

                // Continue receiving
                self.receiveNext()
            }
        }
    }
}
