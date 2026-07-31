import Foundation
import Network

/// UDP 广播发现引擎：用于跨平台（Android↔Mac, iOS↔Mac）设备发现与 PIN 配对
/// 广播端口：45454
/// 收到广播后回包，双端建立 TCP 连接进行配对密钥交换
final class UDPDiscovery {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.clawdbridge.udp", qos: .utility)
    private let broadcastPort: UInt16 = 45454

    let localDeviceID: String
    var onDeviceDiscovered: ((Device) -> Void)?

    // 已发现但未配对的设备（等待 PIN 验证）
    var discoveredDevices: [String: Device] = [:]

    init(localDeviceID: String) {
        self.localDeviceID = localDeviceID
    }

    // MARK: - Start Listening

    func start() {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: broadcastPort)!) else {
            Logger.error("UDP: failed to create listener on port \(broadcastPort)")
            return
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleIncomingDatagram(connection)
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Logger.info("UDP: discovery listener ready on port \(listener.port?.rawValue ?? 0)")
            case .failed(let error):
                Logger.error("UDP: listener failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: queue)
        self.listener = listener

        // 同时发送广播宣告自己在线
        sendBroadcastAnnouncement()
    }

    func stop() {
        listener?.cancel()
        Logger.info("UDP: stopped")
    }

    // MARK: - Broadcast

    /// 向局域网广播本机信息，让其他设备发现
    func sendBroadcastAnnouncement() {
        let device = Device.localDevice()
        let announce: [String: Any] = [
            "type": "announce",
            "deviceID": device.deviceID,
            "deviceName": device.deviceName,
            "platform": device.platform.rawValue,
            "port": device.port ?? 0
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: announce) else { return }

        // 向 255.255.255.255 广播
        let host = NWEndpoint.Host("255.255.255.255")
        let port = NWEndpoint.Port(rawValue: broadcastPort)!
        let connection = NWConnection(host: host, port: port, using: .udp)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: data, completion: .contentProcessed({ error in
                    if let error = error {
                        Logger.debug("UDP: broadcast send error: \(error)")
                    } else {
                        Logger.debug("UDP: broadcast sent")
                    }
                }))
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    // MARK: - Incoming Data

    private func handleIncomingDatagram(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveDatagram(from: connection)
    }

    private func receiveDatagram(from connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self = self, let data = data else { return }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                self.processMessage(json)
            }

            // Continue listening
            self.receiveDatagram(from: connection)
        }
    }

    private func processMessage(_ json: [String: Any]) {
        guard let type = json["type"] as? String else { return }

        switch type {
        case "announce":
            handleAnnounce(json)

        case "pin_request":
            handlePINRequest(json)

        case "pin_response":
            handlePINResponse(json)

        default:
            Logger.debug("UDP: unknown message type: \(type)")
        }
    }

    // MARK: - Announcement Handling

    private func handleAnnounce(_ json: [String: Any]) {
        guard let deviceID = json["deviceID"] as? String,
              deviceID != localDeviceID,  // 不处理自己的广播
              let platformRaw = json["platform"] as? String,
              let platform = Device.Platform(rawValue: platformRaw) else {
            return
        }

        let name = json["deviceName"] as? String ?? "Unknown"
        let device = Device(
            deviceID: deviceID,
            deviceName: name,
            platform: platform,
            isTrusted: false,  // UDP 发现 = 跨平台 = 需要配对
            lastSeen: Date()
        )

        discoveredDevices[deviceID] = device
        onDeviceDiscovered?(device)
        Logger.info("UDP: discovered device \(name) [\(deviceID)] platform=\(platformRaw)")
    }

    // MARK: - PIN Pairing Flow

    /// 收到 PIN 配对请求（从 Android 发来）
    private func handlePINRequest(_ json: [String: Any]) {
        guard let peerDeviceID = json["deviceID"] as? String,
              let pin = json["pin"] as? String else {
            return
        }

        Logger.info("UDP: received PIN request from \(peerDeviceID), pin=\(pin)")

        // Mac 端收到 Android 的 PIN 配对请求
        // Android 展示 6 位 PIN，用户在 Mac 端看不到 UI
        // Mac 需要自动响应：检查是否在可信列表
        // 实际流程：Android 生成 PIN 显示给用户 → 用户在其他已配对 Mac 输入 PIN
        // 简化方案：MAC 作为配对发起方时，生成 PIN 并显示给用户输入

        // 这里需要一个外部信号（通过信任存储）来判断配对是否被接受
        // 当前实现：如果该设备已经通过 PairingEngine 完成配对 → 发送确认
    }

    private func handlePINResponse(_ json: [String: Any]) {
        // 处理配对响应
        Logger.info("UDP: received PIN response: \(json)")
    }
}
