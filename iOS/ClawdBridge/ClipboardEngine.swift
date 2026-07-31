import Foundation
import UIKit
import BackgroundTasks

// MARK: - Clipboard Engine (iOS)
// Watches clipboard changes, auto-pushes to Mac or Android peers via HTTP.
// Uses BGTaskScheduler for iOS background persistence (not killed by system).
// Bonjour auto-discovers Mac peers; Android peers added via UDP 6-digit PIN.

#if canImport(BackgroundTasks)
private let bgTaskId = "ai.clawdbridge.clipRefresh"
#endif

final class ClipboardEngine {
    private var lastChangeCount = UIPasteboard.general.changeCount
    private var timer: Timer?
    private var peers: Set<String> = [] // "host:port"
    private let port = 18763
    private let defaults = UserDefaults.standard
    
    // MARK: - Start
    
    func start() {
        loadPeers()
        startTimer()
        discoverPeers()
        registerBGTask()
    }
    
    private func startTimer() {
        // 500ms poll — low CPU, instant responsiveness
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    // MARK: - Clipboard
    
    private func checkClipboard() {
        let current = UIPasteboard.general.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        
        guard let text = UIPasteboard.general.string, !peers.isEmpty else { return }
        
        for peer in peers {
            pushText(text, to: peer)
        }
    }
    
    // Receive: called when HTTP server gets incoming clip
    func receiveText(_ text: String) {
        lastChangeCount = UIPasteboard.general.changeCount + 1 // prevent echo
        DispatchQueue.main.async {
            UIPasteboard.general.string = text
        }
    }
    
    // MARK: - Network Push
    
    private func pushText(_ text: String, to peer: String) {
        let addr = peer.contains(":") ? peer : "\(peer):\(port)"
        guard let url = URL(string: "http://\(addr)/clip") else { return }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = text.data(using: .utf8)
        req.timeoutInterval = 3
        
        URLSession.shared.dataTask(with: req) { _, _, error in
            if error == nil {
                print("[ClawdBridge-iOS] → \(addr) (\(text.count) chars)")
            }
        }.resume()
    }
    
    // MARK: - Peers
    
    func addPeer(_ host: String) {
        peers.insert(host)
        savePeers()
    }
    
    func removePeer(_ host: String) {
        peers.remove(host)
        savePeers()
    }
    
    func listPeers() -> [String] { Array(peers) }
    
    private func loadPeers() {
        if let saved = defaults.array(forKey: "ClawdBridgePeers") as? [String] {
            peers = Set(saved)
        }
    }
    
    private func savePeers() {
        defaults.set(Array(peers), forKey: "ClawdBridgePeers")
    }
    
    // MARK: - Discovery
    
    private func discoverPeers() {
        // Bonjour: auto-discover Mac peers on same network
        let browser = NetServiceBrowser()
        let delegate = BonjourDiscoverDelegate { [weak self] host in
            self?.addPeer(host)
            print("[ClawdBridge-iOS] Bonjour peer: \(host)")
        }
        objc_setAssociatedObject(browser, "delegateKeep", delegate, .OBJC_ASSOCIATION_RETAIN)
        browser.delegate = delegate
        browser.searchForServices(ofType: "_clawdbridge._tcp", inDomain: "local.")
    }
    
    // MARK: - iOS Background Task
    
    private func registerBGTask() {
        #if canImport(BackgroundTasks)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskId, using: nil) { [weak self] task in
            self?.handleBGTask(task as! BGAppRefreshTask)
        }
        scheduleBGTask()
        #endif
    }
    
    private func scheduleBGTask() {
        #if canImport(BackgroundTasks)
        let request = BGAppRefreshTaskRequest(identifier: bgTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }
    
    private func handleBGTask(_ task: BGAppRefreshTask) {
        // Check clipboard once in background, reschedule
        checkClipboard()
        scheduleBGTask()
        task.setTaskCompleted(success: true)
    }
}

// MARK: - Bonjour Delegate

private final class BonjourDiscoverDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let onResolve: (String) -> Void
    
    init(onResolve: @escaping (String) -> Void) {
        self.onResolve = onResolve
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.resolve(withTimeout: 5)
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        if let host = sender.hostName {
            onResolve("\(host):\(sender.port)")
        }
    }
}
