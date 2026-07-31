import Foundation
import Network

/// 配对引擎：管理跨平台 PIN 配对流程
/// 流程：
/// 1. 用户在某设备上选择"配对 Android"
/// 2. 显示 6 位 PIN
/// 3. 对方设备扫描发现 → 收到 PIN → 用户在对方设备输入 PIN
/// 4. UDP 回传 PIN 验证 → 验证通过则交换密钥 → 完成配对
final class PairingEngine {
    private let trustStore = TrustStore()
    private var pendingPairings: [String: PendingPairing] = [:]
    private let queue = DispatchQueue(label: "com.clawdbridge.pairing", qos: .utility)

    struct PendingPairing {
        let deviceID: String
        let deviceName: String
        let pin: String
        let createdAt: Date
    }

    // Event hooks — for forwarding to SyncEngine
    var onPairingCompleted: ((String, Data) -> Void)?  // deviceID, sharedKey

    // MARK: - Generate PIN for new pairing

    /// 为指定设备生成 6 位配对 PIN（Android 端调用）
    func generatePIN(for deviceID: String, deviceName: String) -> String {
        let pin = String(format: "%06d", Int.random(in: 0...999999))
        pendingPairings[deviceID] = PendingPairing(
            deviceID: deviceID,
            deviceName: deviceName,
            pin: pin,
            createdAt: Date()
        )

        // PIN 有效期 5 分钟
        queue.asyncAfter(deadline: .now() + 300) { [weak self] in
            self?.pendingPairings.removeValue(forKey: deviceID)
        }

        Logger.info("PairingEngine: generated PIN \(pin) for \(deviceName)")
        return pin
    }

    // MARK: - Verify PIN

    /// 验证对方设备发送的 PIN
    /// 返回验证结果
    func verifyPIN(for deviceID: String, pin input: String) -> PairingResult {
        guard let pending = pendingPairings[deviceID] else {
            return .noPendingPairing
        }

        guard Date().timeIntervalSince(pending.createdAt) < 300 else {
            pendingPairings.removeValue(forKey: deviceID)
            return .expired
        }

        guard input == pending.pin else {
            return .mismatch
        }

        // PIN 匹配 → 生成对称密钥并交换
        pendingPairings.removeValue(forKey: deviceID)

        let sharedKey = CryptoSession.generateRandomKey()
        trustStore.add(
            deviceID: deviceID,
            name: pending.deviceName,
            platform: "android",
            key: sharedKey
        )

        onPairingCompleted?(deviceID, sharedKey)
        Logger.info("PairingEngine: pairing completed for \(pending.deviceName)")
        return .success(sharedKey: sharedKey)
    }

    // MARK: - Check trust

    func isTrusted(_ deviceID: String) -> Bool {
        trustStore.isTrusted(deviceID)
    }

    func getKey(for deviceID: String) -> Data? {
        trustStore.getKey(for: deviceID)
    }
}

// MARK: - Pairing Result

enum PairingResult {
    case success(sharedKey: Data)
    case mismatch
    case expired
    case noPendingPairing
}
