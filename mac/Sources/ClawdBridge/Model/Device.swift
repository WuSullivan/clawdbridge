import Foundation

/// 设备模型：表示局域网中的一个同步节点
struct Device: Codable, Equatable, Hashable {
    let deviceID: String
    let deviceName: String
    let platform: Platform
    var ipAddress: String?
    var port: UInt16?
    var isTrusted: Bool
    var lastSeen: Date?

    enum Platform: String, Codable {
        case mac
        case ios
        case android
    }

    static func == (lhs: Device, rhs: Device) -> Bool {
        lhs.deviceID == rhs.deviceID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(deviceID)
    }

    /// 本机设备信息
    static func localDevice() -> Device {
        let id = UserDefaults.standard.string(forKey: "device_id") ?? {
            let new = UUID().uuidString
            UserDefaults.standard.set(new, forKey: "device_id")
            return new
        }()
        return Device(
            deviceID: id,
            deviceName: Host.current().localizedName ?? "Unknown Mac",
            platform: .mac,
            ipAddress: getLocalIPAddress(),
            port: SyncConfig.tcpPort,
            isTrusted: true,
            lastSeen: Date()
        )
    }

    /// 获取本机局域网 IP
    static func getLocalIPAddress() -> String? {
        var addr: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let flags = Int32(ptr.pointee.ifa_flags)
            let name = String(cString: ptr.pointee.ifa_name)
            let isIPv4 = ptr.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if isIPv4 && isUp && !isLoopback && name.hasPrefix("en") {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    ptr.pointee.ifa_addr,
                    socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                    &hostname, socklen_t(hostname.count),
                    nil, 0, NI_NUMERICHOST
                )
                addr = String(cString: hostname)
                break
            }
            ptr = ptr.pointee.ifa_next
        }
        return addr
    }
}
