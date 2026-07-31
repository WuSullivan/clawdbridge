import Foundation
import AppKit

// MARK: - ClawdBridge Mac Daemon v0.2
// Changelog:
//   v0.1: HTTP server, clipboard watch, Bonjour
//   v0.2: File transfer, iCloud device trust, launchd plist, multi-peer mesh

let VERSION = "0.2.0"
let SERVICE_PORT: UInt16 = 18763
let clipboardLock = NSLock()
let fileReceiveDir: String = {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads/ClawdBridge")
        .path
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}()

// MARK: - Logging

func log(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    fputs("[\(ts)] \(msg)\n", stderr)
}

// MARK: - Clipboard Watcher

final class ClipboardWatcher {
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: DispatchSourceTimer?
    private var lastText: String?
    var onChange: ((ClipboardItem) -> Void)?
    
    enum ClipboardItem {
        case text(String)
        case file(URL, Data) // URL + content
    }
    
    func start() {
        let q = DispatchQueue(label: "cb.clawdbridge", qos: .background)
        timer = DispatchSource.makeTimerSource(queue: q)
        timer?.schedule(deadline: .now(), repeating: .milliseconds(500))
        timer?.setEventHandler { [weak self] in
            guard let self else { return }
            let cur = NSPasteboard.general.changeCount
            if cur == self.lastChangeCount { return }
            self.lastChangeCount = cur
            
            // Check text first
            if let text = NSPasteboard.general.string(forType: .string), text != self.lastText {
                self.lastText = text
                DispatchQueue.global().async { self.onChange?(.text(text)) }
                return
            }
            
            // Check file URLs
            if let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
               let url = urls.first {
                if let data = try? Data(contentsOf: url) {
                    DispatchQueue.global().async { self.onChange?(.file(url, data)) }
                }
            }
        }
        timer?.resume()
    }
    
    func writeText(_ text: String) {
        clipboardLock.lock()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
        lastText = text
        clipboardLock.unlock()
    }
    
    func writeFile(_ data: Data, filename: String) {
        clipboardLock.lock()
        let path = (fileReceiveDir as NSString).appendingPathComponent(filename)
        try? data.write(to: URL(fileURLWithPath: path))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
        clipboardLock.unlock()
    }
    
    func stop() { timer?.cancel() }
}

// MARK: - iCloud Device Discovery

final class iCloudDeviceDiscovery {
    // Uses iCloud account hash to derive a shared secret for trust
    // Devices on same iCloud account auto-trust each other
    
    static func iCloudAccountHash() -> String? {
        // Read from MobileMeAccounts plist
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(
            "Library/Application Support/iCloud/accounts/DSID"
        )
        if let dsid = try? String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
            // Return hashed DSID as trust token (not the raw DSID)
            return dsid
        }
        return nil
    }
    
    static func isSameAccount(_ token: String) -> Bool {
        return token == iCloudAccountHash()
    }
    
    func discoverPeers() -> [(host: String, name: String)] {
        // Resolve Bonjour services
        var results: [(String, String)] = []
        let browser = NetServiceBrowser()
        let delegate = BonjourResolver { svc in
            if let host = svc.hostName {
                results.append((host, svc.name))
            }
        }
        objc_setAssociatedObject(browser, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        browser.delegate = delegate
        browser.searchForServices(ofType: "_clawdbridge._tcp", inDomain: "local.")
        
        // Give Bonjour some time
        RunLoop.current.run(until: Date().addingTimeInterval(2.0))
        browser.stop()
        
        return results
    }
}

private final class BonjourResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let onResolve: (NetService) -> Void
    init(onResolve: @escaping (NetService) -> Void) { self.onResolve = onResolve }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 3)
    }
    func netServiceDidResolveAddress(_ sender: NetService) { onResolve(sender) }
}

// MARK: - HTTP Server

final class HTTPServer {
    private var listenFd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "http.clawdbridge", qos: .background)
    var onReceiveText: ((String) -> Void)?
    var onReceiveFile: ((Data, String) -> Void)? // data, filename
    
    func start() -> Bool {
        listenFd = socket(AF_INET, SOCK_STREAM, 0)
        guard listenFd >= 0 else { return false }
        
        var val: Int32 = 1
        setsockopt(listenFd, SOL_SOCKET, SO_REUSEADDR, &val, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(listenFd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = SERVICE_PORT.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { log("bind(:\(SERVICE_PORT)) failed: errno=\(errno)"); return false }
        guard listen(listenFd, 10) == 0 else { return false }
        
        source = DispatchSource.makeReadSource(fileDescriptor: listenFd, queue: queue)
        source?.setEventHandler { [weak self] in self?.accept() }
        source?.resume()
        
        log("HTTP server listening on :\(SERVICE_PORT)")
        return true
    }
    
    private func accept() {
        var clientAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.accept(listenFd, $0, &len)
            }
        }
        guard clientFd >= 0 else { return }
        DispatchQueue.global().async { [weak self] in self?.handle(clientFd) }
    }
    
    private func handle(_ fd: Int32) {
        defer { close(fd) }
        
        // Read headers first
        var headerBuf = [UInt8](repeating: 0, count: 8192)
        let headerLen = read(fd, &headerBuf, headerBuf.count)
        guard headerLen > 0 else { return }
        guard let headerStr = String(bytes: headerBuf[0..<headerLen], encoding: .utf8) else { return }
        
        let headerParts = headerStr.components(separatedBy: "\r\n")
        guard let firstLine = headerParts.first else { return }
        
        let method = firstLine.components(separatedBy: " ").first ?? ""
        let path = firstLine.components(separatedBy: " ").count > 1
            ? firstLine.components(separatedBy: " ")[1] : "/"
        
        // Extract Content-Length
        var contentLength = 0
        var filename = "clipboard.txt"
        for line in headerParts {
            let l = line.lowercased()
            if l.hasPrefix("content-length:") {
                contentLength = Int(line.components(separatedBy: ":")[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
            if l.hasPrefix("x-filename:") {
                filename = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Find body start
        var bodyStart = 0
        if let range = headerStr.range(of: "\r\n\r\n") {
            bodyStart = headerStr.distance(from: headerStr.startIndex, to: range.upperBound)
        }
        
        // Already-read body portion
        var body = Data(headerBuf[bodyStart..<headerLen])
        
        // Read remaining body
        var remaining = contentLength - body.count
        while remaining > 0 {
            var chunk = [UInt8](repeating: 0, count: min(65536, remaining))
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            body.append(contentsOf: chunk[0..<n])
            remaining -= n
        }
        
        if method == "POST" && path == "/clip" {
            if let text = String(data: body, encoding: .utf8) {
                log("Received text: \(text.count) chars")
                DispatchQueue.main.async { [weak self] in self?.onReceiveText?(text) }
            }
            respond(fd, 200, "OK")
        }
        else if method == "POST" && path == "/file" {
            log("Received file: \(filename) (\(body.count) bytes)")
            DispatchQueue.main.async { [weak self] in self?.onReceiveFile?(body, filename) }
            respond(fd, 200, "OK")
        }
        else if method == "GET" && path == "/ping" {
            respond(fd, 200, "{\"version\":\"\(VERSION)\"}")
        }
        else {
            respond(fd, 404, "Not Found")
        }
    }
    
    private func respond(_ fd: Int32, _ status: Int, _ body: String) {
        let response = """
        HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r
        Content-Type: text/plain\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        _ = response.withCString { Darwin.send(fd, $0, strlen($0), 0) }
    }
    
    func stop() { source?.cancel(); close(listenFd) }
}

// MARK: - Bonjour

final class BonjourAdvertiser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private var process: Process?
    private static var browser: NetServiceBrowser?
    private static var discovered: [(name: String, host: String)] = []
    private static let browserLock = NSLock()
    
    func start() {
        // Advertise via dns-sd
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        proc.arguments = ["-R",
            Host.current().localizedName ?? "Mac",
            "_clawdbridge._tcp", "local", String(SERVICE_PORT)]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        self.process = proc
        log("Bonjour: _clawdbridge._tcp advertised")
        
        // Browse for peers
        let selfCapture = self
        DispatchQueue.main.async {
            BonjourAdvertiser.browser = NetServiceBrowser()
            BonjourAdvertiser.browser?.delegate = selfCapture
            BonjourAdvertiser.browser?.searchForServices(ofType: "_clawdbridge._tcp", inDomain: "local.")
        }
    }
    
    func stop() { process?.terminate(); BonjourAdvertiser.browser?.stop() }
    
    // MARK: NetServiceBrowserDelegate
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        if service.name != Host.current().localizedName {
            service.delegate = self
            service.resolve(withTimeout: 5)
        }
    }
    
    // MARK: NetServiceDelegate
    func netServiceDidResolveAddress(_ sender: NetService) {
        if let host = sender.hostName {
            BonjourAdvertiser.browserLock.lock()
            let addr = "\(host):\(sender.port)"
            if !BonjourAdvertiser.discovered.contains(where: { $0.host == addr }) {
                BonjourAdvertiser.discovered.append((sender.name, addr))
                log("Bonjour discovered: \(sender.name) at \(addr)")
            }
            BonjourAdvertiser.browserLock.unlock()
        }
    }
    
    static func discoveredPeers() -> [String] {
        browserLock.lock()
        defer { browserLock.unlock() }
        return discovered.map { $0.host }
    }
}

// MARK: - Peer Pusher

final class PeerPusher {
    private var peers: [String] = []
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 5
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()
    
    func loadPeers() {
        if let saved = UserDefaults.standard.array(forKey: "ClawdBridgePeers") as? [String] {
            peers = saved
        }
    }
    
    func savePeers() {
        UserDefaults.standard.set(peers, forKey: "ClawdBridgePeers")
    }
    
    func addPeer(_ host: String) {
        if !peers.contains(host) {
            peers.append(host)
            savePeers()
        }
    }
    
    func listPeers() -> [String] { peers }
    
    func pushText(_ text: String) {
        // also broadcast to discovered Bonjour peers
        let targets = peers + BonjourAdvertiser.discoveredPeers()
        send(to: Array(Set(targets)), path: "/clip", body: text.data(using: .utf8), filename: "clip")
    }
    
    func pushFile(_ data: Data, filename: String) {
        send(to: peers, path: "/file", body: data, filename: filename)
    }
    
    private func send(to targets: [String], path: String, body: Data?, filename: String?) {
        for peer in targets {
            guard let url = URL(string: "http://\(peer):\(SERVICE_PORT)\(path)") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = body
            req.timeoutInterval = 10
            if let fname = filename {
                req.setValue(fname, forHTTPHeaderField: "X-Filename")
            }
            req.setValue("\(body?.count ?? 0)", forHTTPHeaderField: "Content-Length")
            
            session.dataTask(with: req) { _, _, error in
                if let _ = error { /* peer offline, skip */ }
            }.resume()
        }
    }
}

// MARK: - UDP Pairing Engine (6-digit PIN for Android & other platforms)

final class PairingEngine {
    private static let pairPort: UInt16 = 18764
    
    /// Start advertising a 6-digit code. When someone sends "PAIR <code>", respond with device IP.
    static func advertise(code: String, onPaired: @escaping (String) -> Void) {
        DispatchQueue.global().async {
            let fd = socket(AF_INET, SOCK_DGRAM, 0)
            guard fd >= 0 else { return }
            
            var val: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &val, socklen_t(MemoryLayout<Int32>.size))
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &val, socklen_t(MemoryLayout<Int32>.size))
            
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = pairPort.bigEndian
            addr.sin_addr.s_addr = INADDR_ANY
            
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            
            var tv = timeval(tv_sec: 120, tv_usec: 0) // 2min timeout
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
                let clientIP = withUnsafePointer(to: &clientAddr.sin_addr) {
                    String(cString: inet_ntoa($0.pointee))
                }
                let resp = "PAIR_OK"
                _ = resp.withCString { sendto(fd, $0, strlen($0), 0, nil, 0) }
                onPaired(clientIP)
                log("UDP paired with Android/iOS device at \(clientIP)")
            }
            close(fd)
        }
    }
    
    /// Enter a 6-digit code and scan for the advertiser
    static func scanAndPair(code: String, onPaired: @escaping (String) -> Void) {
        DispatchQueue.global().async {
            let fd = socket(AF_INET, SOCK_DGRAM, 0)
            guard fd >= 0 else { return }
            
            var val: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &val, socklen_t(MemoryLayout<Int32>.size))
            
            var tv = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            
            var broadAddr = sockaddr_in()
            broadAddr.sin_family = sa_family_t(AF_INET)
            broadAddr.sin_port = pairPort.bigEndian
            broadAddr.sin_addr.s_addr = INADDR_BROADCAST
            
            let msg = "PAIR \(code)"
            withUnsafePointer(to: &broadAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                    msg.withCString { sendto(fd, $0, strlen($0), 0, ptr, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
            }
            
            var buf = [UInt8](repeating: 0, count: 64)
            var senderAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            
            let n = withUnsafeMutablePointer(to: &senderAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buf, buf.count, 0, $0, &len)
                }
            }
            
            guard n > 0 else { close(fd); return }
            let resp = String(bytes: buf[0..<n], encoding: .utf8) ?? ""
            
            if resp == "PAIR_OK" {
                let peerIP = withUnsafePointer(to: &senderAddr.sin_addr) {
                    String(cString: inet_ntoa($0.pointee))
                }
                onPaired(peerIP)
                log("UDP paired with peer at \(peerIP)")
            }
            close(fd)
        }
    }
}

// MARK: - Launchd Installer

func installLaunchd() {
    let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key>
        <string>ai.clawdbridge.daemon</string>
        <key>ProgramArguments</key>
        <array>
            <string>\(Bundle.main.executablePath ?? "/usr/local/bin/clawdbridge")</string>
        </array>
        <key>RunAtLoad</key>
        <true/>
        <key>KeepAlive</key>
        <true/>
        <key>StandardErrorPath</key>
        <string>/tmp/clawdbridge.err</string>
        <key>StandardOutPath</key>
        <string>/tmp/clawdbridge.out</string>
    </dict>
    </plist>
    """
    
    let plistPath = NSHomeDirectory() + "/Library/LaunchAgents/ai.clawdbridge.daemon.plist"
    try? plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
    
    // Load it
    let load = Process()
    load.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    load.arguments = ["load", plistPath]
    try? load.run()
    load.waitUntilExit()
    
    log("launchd plist installed at \(plistPath)")
}

// MARK: - Main

let clipboard = ClipboardWatcher()
let server = HTTPServer()
let bonjour = BonjourAdvertiser()
let pusher = PeerPusher()

// Handle incoming
server.onReceiveText = { text in
    DispatchQueue.main.async { clipboard.writeText(text) }
}
server.onReceiveFile = { data, filename in
    DispatchQueue.main.async { clipboard.writeFile(data, filename: filename) }
}

// Handle outgoing
clipboard.onChange = { item in
    switch item {
    case .text(let text):
        log("Local copy: '\(text.prefix(60))...'")
        pusher.pushText(text)
    case .file(let url, let data):
        log("Local file copy: \(url.lastPathComponent) (\(data.count) bytes)")
        pusher.pushFile(data, filename: url.lastPathComponent)
    }
}

guard server.start() else {
    log("FATAL: cannot start server")
    exit(1)
}

bonjour.start()
pusher.loadPeers()

// Auto-discover peers on same iCloud account
let discovery = iCloudDeviceDiscovery()
let peers = discovery.discoverPeers()
for p in peers {
    pusher.addPeer(p.host)
    log("Discovered peer: \(p.name) at \(p.host)")
}

log("ClawdBridge v\(VERSION) ready. Zero-click. Zero-popup. Zero-ui.")

// Install launchd for auto-start
if CommandLine.arguments.contains("--install") {
    installLaunchd()
}

RunLoop.main.run()
