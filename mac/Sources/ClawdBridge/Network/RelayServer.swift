import Foundation
import Network

/// iOS ↔ Android 中继服务器
/// 当 iOS 和 Android 处于同一局域网但无法直连时，Mac 作为中继节点
/// iOS 通过蓝牙连接到 Mac → Mac 通过 TCP 桥接 Android 连接
final class RelayServer {
    private var relayRoutes: [String: RelayRoute] = [:]
    private let lock = NSLock()

    func start() {
        Logger.info("RelayServer: started (passive, routes added on-demand)")
    }

    struct RelayRoute {
        let sourceDeviceID: String
        let targetDeviceID: String
        let targetAddress: String
        let targetPort: UInt16
        var targetConnection: PeerConnection?
    }

    func addRoute(from sourceDeviceID: String, to targetDeviceID: String,
                  address: String, port: UInt16) {
        let route = RelayRoute(
            sourceDeviceID: sourceDeviceID,
            targetDeviceID: targetDeviceID,
            targetAddress: address,
            targetPort: port,
            targetConnection: nil
        )
        lock.lock()
        relayRoutes["\(sourceDeviceID)→\(targetDeviceID)"] = route
        lock.unlock()
        Logger.info("RelayServer: route added \(sourceDeviceID) → \(targetDeviceID)")
    }

    func relay(payload: ClipPayload, from sourceID: String, to targetID: String) -> Bool {
        let key = "\(sourceID)→\(targetID)"
        lock.lock()
        guard let route = relayRoutes[key] else {
            lock.unlock()
            Logger.warn("RelayServer: no route for \(key)")
            return false
        }
        let conn = route.targetConnection
        lock.unlock()

        conn?.send(payload)
        return true
    }

    func removeRoutes(for deviceID: String) {
        lock.lock()
        relayRoutes = relayRoutes.filter {
            $0.value.sourceDeviceID != deviceID && $0.value.targetDeviceID != deviceID
        }
        lock.unlock()
        Logger.info("RelayServer: removed routes for \(deviceID)")
    }
}
