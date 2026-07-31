import Foundation
import CommonCrypto
import CryptoKit

/// 传输加密会话：基于预共享密钥的对称加密
/// 加密方案：AES-256-GCM via Apple CryptoKit（macOS 10.15+）
///
/// CryptoKit 提供更简洁安全的 API，替代 CommonCrypto 底层调用
final class CryptoSession {
    private let key: SymmetricKey

    // MARK: - Key Management

    /// 使用已建立的对称密钥初始化
    init(sharedKey: Data) {
        precondition(sharedKey.count == 32, "Shared key must be 256 bits")
        self.key = SymmetricKey(data: sharedKey)
    }

    /// 使用原始 SymmetricKey 初始化
    init(symmetricKey: SymmetricKey) {
        self.key = symmetricKey
    }

    /// 从配对 PIN 派生 256-bit 密钥（PBKDF2 with SHA-256）
    /// PIN 是 6 位数字，通过 PBKDF2 增强后派生对称密钥
    static func deriveKey(from pin: String, salt: Data) -> Data {
        let pinData = pin.data(using: .utf8)!
        var derivedKey = Data(count: 32)
        let result = derivedKey.withUnsafeMutableBytes { keyPtr in
            keyPtr.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: 32) { keyBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    (pinData as NSData).bytes.bindMemory(to: Int8.self, capacity: pinData.count),
                    pinData.count,
                    (salt as NSData).bytes.bindMemory(to: UInt8.self, capacity: salt.count),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    100000,  // 10万轮迭代
                    keyBytes,
                    32
                )
            }
        }
        if result == kCCSuccess {
            return derivedKey
        }
        // Fallback: SHA-256 hash (should not hit in practice)
        let hash = SHA256.hash(data: (pin + "clawdbridge-fallback").data(using: .utf8)!)
        return Data(hash)
    }

    /// 生成随机对称密钥（配对完成后交换密钥）
    static func generateRandomKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    // MARK: - Encryption (AES-256-GCM via CryptoKit)

    /// 加密数据，返回 Nonce (12) + Ciphertext + Tag (16)
    func encrypt(plaintext: Data) -> Data? {
        do {
            let sealedBox = try AES.GCM.seal(plaintext, using: key)
            // sealedBox.combined = nonce + ciphertext + tag
            return sealedBox.combined
        } catch {
            Logger.error("Crypto: encrypt failed: \(error)")
            return nil
        }
    }

    /// 解密数据（格式: combined = nonce + ciphertext + tag）
    func decrypt(combined: Data) -> Data? {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            Logger.warn("Crypto: decrypt failed (tag mismatch or tampered): \(error)")
            return nil
        }
    }
}

// MARK: - Convenience Extensions

extension CryptoSession {
    /// 创建来自 PIN 的加密会话
    static func fromPIN(_ pin: String) -> CryptoSession {
        let salt = "clawdbridge-pin-salt-2026".data(using: .utf8)!
        let keyData = CryptoSession.deriveKey(from: pin, salt: salt)
        return CryptoSession(sharedKey: keyData)
    }
}
