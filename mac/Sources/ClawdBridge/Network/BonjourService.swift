import Foundation
import Network

/// Bonjour 服务广播 & 发现：Apple 设备间零配置自动发现
/// 同一局域网下，同一 Apple ID 设备自动信任，无需配对码
final class BonjourService {
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [String: NWConnection] = [:]
    private let queue = DispatchQueue(label: "com.clawdbridge.bonjour", qos: .utility)

    let serviceType = "_clawdbridge._tcp"
    let serviceName: String
    let localDeviceID: String
    var onDeviceDiscovered: ((Device) -> Void)?
    var onDeviceRemoved: ((String) -> Void)?
    var onIncomingClipPayload: ((ClipPayload) -> Void)?

    init(localDeviceID: String) {
        self.localDeviceID = localDeviceID
        self.serviceName = "ClawdBridge-\(Host.current().localizedName ?? "Mac")"
    }

    // MARK: - Start Broadcasting + Browsing

    func start(port: UInt16) {
        startListener(port: port)
        startBrowser()
        Logger.info("Bonjour: broadcasting as '\(serviceName)' on port \(port)")
    }

    func stop() {
        listener?.cancel()
        browser?.cancel()
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        Logger.info("Bonjour: stopped")
    }

    // MARK: - Listener (advertise ourselves)

    private func startListener(port: UInt16) {
        let params = NWParameters.tcp
        // 使用 Bonjour 发布服务
        params.includePeerToPeer = true

        guard let listener = try? NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!) else {
            Logger.error("Bonjour: failed to create listener on port \(port)")
            return
        }

        listener.service = NWListener.Service(name: serviceName, type: serviceType)
        listener.serviceRegistrationUpdateHandler = { change in
            switch change {
            case .add(let endpoint):
                Logger.debug("Bonjour: service registered: \(endpoint)")
            case .remove(let endpoint):
                Logger.debug("Bonjour: service removed: \(endpoint)")
            @unknown default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleIncomingConnection(connection)
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Logger.info("Bonjour: listener ready on port \(listener.port?.rawValue ?? 0)")
            case .failed(let error):
                Logger.error("Bonjour: listener failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: queue)
        self.listener = listener
    }

    // MARK: - Browser (discover other devices)

    private func startBrowser() {
        let params = NWParameters.tcp
        params.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: "local."), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            for change in changes {
                switch change {
                case .added(let result):
                    self?.handleDiscoveredEndpoint(result)
                case .removed(let result):
                    let name = result.endpoint.debugDescription
                    self?.onDeviceRemoved?(name)
                case .identical, .changed:
                    break
                @unknown default:
                    break
                }
            }
        }

        browser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Logger.info("Bonjour: browser ready, scanning for devices...")
            case .failed(let error):
                Logger.error("Bonjour: browser failed: \(error)")
            default:
                break
            }
        }

        browser.start(queue: queue)
        self.browser = browser
    }

    // MARK: - Connection Handling

    private func handleDiscoveredEndpoint(_ result: NWBrowser.Result) {
        // Extract metadata from Bonjour TXT record
        // NWBrowser.Result gives us the endpoint; we connect to exchange device info
        let connection = NWConnection(to: result.endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Logger.debug("Bonjour: connected to discovered device")
                self?.sendDeviceInfo(over: connection)
                self?.receivePayload(from: connection)

            case .failed(let error):
                Logger.warn("Bonjour: connection failed: \(error)")
                connection.cancel()

            default:
                break
            }
        }

        connection.start(queue: queue)

        let key = result.endpoint.debugDescription
        connections[key] = connection
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Logger.debug("Bonjour: incoming connection established")
                self?.sendDeviceInfo(over: connection)
                self?.receivePayload(from: connection)
            case .failed(let error):
                Logger.warn("Bonjour: incoming connection failed: \(error)")
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)

        let key = UUID().uuidString
        connections[key] = connection
    }

    // MARK: - Data Exchange

    /// 首次连接时交换设备信息
    private func sendDeviceInfo(over connection: NWConnection) {
        let device = Device.localDevice()
        // 构造 JSON 握手消息
        let handshake: [String: Any] = [
            "type": "handshake",
            "deviceID": device.deviceID,
            "deviceName": device.deviceName,
            "platform": device.platform.rawValue
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: handshake) else { return }
        // 消息格式：4 字节大端长度前缀 + JSON
        var length = UInt32(data.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(data)

        connection.send(content: packet, completion: .contentProcessed({ error in
            if let error = error {
                Logger.warn("Bonjour: failed to send device info: \(error)")
            }
        }))
    }

    /// 接收来自远端设备的载荷（剪贴板内容 or 文件块）
    private func receivePayload(from connection: NWConnection) {
        // 先读取 4 字节长度头
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self = self, let data = data, data.count == 4 else { return }
            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            // 再读取实际内容
            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { data, _, _, error in
                guard let data = data else { return }

                // 尝试解析为 ClipPayload
                if let payload = ClipPayload.decode(from: data) {
                    self.onIncomingClipPayload?(payload)
                } else {
                    // 检查是否为握手消息
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let type = json["type"] as? String, type == "handshake" {
                        let device = Device(
                            deviceID: json["deviceID"] as? String ?? "",
                            deviceName: json["deviceName"] as? String ?? "Unknown",
                            platform: Device.Platform(rawValue: json["platform"] as? String ?? "mac") ?? .mac,
                            isTrusted: true,  // Bonjour discovered = Apple-to-Apple = auto-trust
                            lastSeen: Date()
                        )
                        self.onDeviceDiscovered?(device)
                        Logger.info("Bonjour: discovered device \(device.deviceName) [\(device.deviceID)]")
                    }
                }

                // 继续监听后续消息
                self.receivePayload(from: connection)
            }
        }
    }

    /// 发送剪贴板载荷到所有已连接设备
    func broadcast(payload: ClipPayload) {
        guard let data = payload.encode() else { return }
        var length = UInt32(data.count).bigEndian
        var packet = Data(bytes: &length, count: 4)
        packet.append(data)

        for (_, conn) in connections {
            conn.send(content: packet, completion: .contentProcessed({ error in
                if let error = error {
                    Logger.debug("Bonjour: send error: \(error)")
                }
            }))
        }
    }
}
