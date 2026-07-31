import Foundation
import Network

// MARK: - iOS Pairing Engine
// Uses NWListener/NWBrowser for Bonjour + UDP broadcast for 6-digit PIN pairing.
// On iOS, Bonjour is the primary discovery for iCloud devices.
// UDP PIN pairing is the fallback for Android cross-platform.

final class iOSPairingEngine {
    static func generateCode() -> String {
        String(format: "%06d", Int.random(in: 100000...999999))
    }
    
    static func advertise(code: String, onPaired: @escaping (String) -> Void) {
        // On iOS, we use Bonjour TXT record to publish the code hash
        // + UDP listener for PAIR request as cross-platform fallback
        let queue = DispatchQueue(label: "pair.ios.clawdbridge")
        
        // UDP listener
        queue.async {
            let fd = socket(AF_INET, SOCK_DGRAM, 0)
            guard fd >= 0 else { return }
            
            var val: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &val, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &val, socklen_t(MemoryLayout<Int32>.size))
            
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = UInt16(18764).bigEndian
            addr.sin_addr.s_addr = INADDR_ANY
            
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            
            var tv = timeval(tv_sec: 120, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            
            var buf = [UInt8](repeating: 0, count: 64)
            var clientAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            
            let n = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buf, buf.count, 0, $0, &len)
                }
            }
            
            guard n > 0 else { close(fd); return }
            let msg = String(bytes: buf[0..<n], encoding: .utf8) ?? ""
            
            if msg == "PAIR \(code)" {
                let peerIP = withUnsafePointer(to: &clientAddr.sin_addr) {
                    String(cString: inet_ntoa($0.pointee))
                }
                // Respond
                let resp = "PAIR_OK"
                withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                        resp.withCString {
                            sendto(fd, $0, strlen($0), 0, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
                onPaired(peerIP)
            }
            close(fd)
        }
    }
}
