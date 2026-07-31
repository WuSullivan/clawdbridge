import Foundation

// ── ClawdBridge 入口 ──

let device = Device.localDevice()
Logger.info("ClawdBridge starting: \(device.deviceName) [\(device.deviceID)]")

// 1. 蓝牙桥（Mac ↔ iOS）
let ble = BLEBridge()
ble.start()

// 2. Bonjour 网络发现（Mac ↔ Mac）
let bonjour = BonjourService(localDeviceID: device.deviceID)
bonjour.start(port: SyncConfig.tcpPort)

// 3. UDP 发现（Mac ↔ Android）
let udp = UDPDiscovery(localDeviceID: device.deviceID)
udp.start()

// 4. 中继服务器（iOS ↔ Android via Mac）
let relay = RelayServer()
relay.start()

// 5. 信任 & 配对引擎
let pairing = PairingEngine()

// 6. 同步引擎（剪贴板监听 + 分发）
SyncEngine.shared.setBLEBridge(ble)
SyncEngine.shared.start()

// 7. 保持运行
Logger.info("ClawdBridge: all services started, running...")
RunLoop.main.run()
