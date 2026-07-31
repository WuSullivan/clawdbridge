import Foundation
import CoreBluetooth

/// Mac 作为 BLE Central（扫描 iOS 外设）或 Peripheral（被 Mac 扫描）
/// ClawdBridge 使用 CoreBluetooth 实现 Mac ↔ iOS 零 Wi-Fi 连接
///
/// 工作模式：Mac 同时作为 Central 和 Peripheral
/// - Central：扫描附近 iOS 设备广播的 Bridge 服务
/// - Peripheral：广播 Bridge 服务，供其他 Mac 发现
///
/// 传输方式：
/// - 小数据（text / small image）：直接通过 GATT characteristic write
/// - 大数据（large image / video / file）：通过 L2CAP channel
///
/// ⚠️ 蓝牙理论范围 10m，实际可靠距离约 2m
/// ⚠️ 不需要用户配对（BLE GATT 无需系统蓝牙配对）
/// ⚠️ 功耗极低：BLE 广播每秒一次，连接后仅在数据传输时活跃
final class BLEBridge: NSObject {
    static let serviceUUID = CBUUID(string: SyncConfig.bluetoothServiceUUID)
    static let charUUID = CBUUID(string: SyncConfig.bluetoothCharUUID)
    static let notifyUUID = CBUUID(string: SyncConfig.bluetoothNotifyUUID)

    // ── Peripheral ──
    private var peripheralManager: CBPeripheralManager?
    private var service: CBMutableService?
    private var dataCharacteristic: CBMutableCharacteristic?
    private var notifyCharacteristic: CBMutableCharacteristic?

    // ── Central ──
    private var centralManager: CBCentralManager?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripherals: Set<UUID> = []

    // ── 待发送队列 ──
    private var pendingPayloads: [ClipPayload] = []
    private let queueLock = NSLock()

    private let bleQueue = DispatchQueue(label: "com.clawdbridge.ble", qos: .background)

    override init() {
        super.init()
    }

    // MARK: - Start

    func start() {
        // Peripheral 模式（被其他设备发现）
        peripheralManager = CBPeripheralManager(delegate: self, queue: bleQueue)

        // Central 模式（扫描附近设备）
        centralManager = CBCentralManager(delegate: self, queue: bleQueue)
    }

    // MARK: - 发送

    func notifyAll(_ payload: ClipPayload) {
        queueLock.lock()
        pendingPayloads.append(payload)
        queueLock.unlock()

        // 通过 peripheral 的 notify characteristic 推送
        notifyConnectedCentrals(payload)
    }

    private func notifyConnectedCentrals(_ payload: ClipPayload) {
        guard let pm = peripheralManager, pm.state == .poweredOn else { return }
        guard let ch = notifyCharacteristic else { return }

        // 广播 metadata（小数据直接推送完整内容）
        if payload.dataSize <= SyncConfig.largeFileThreshold,
           let data = payload.encode() {
            // 小数据：直接推送完整 payload
            let _ = pm.updateValue(data, for: ch, onSubscribedCentrals: nil)
        } else if let meta = payload.metadata.encode() {
            // 大数据：先推送 metadata
            let _ = pm.updateValue(meta, for: ch, onSubscribedCentrals: nil)
        }
    }
}

// MARK: - CBPeripheralManagerDelegate（广播自己的服务）
extension BLEBridge: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            setupService(peripheral)
            peripheral.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
                CBAdvertisementDataLocalNameKey: "ClawdBridge-\(Host.current().name ?? "Mac")"
            ])
            Logger.info("BLE: advertising started")
        }
    }

    private func setupService(_ pm: CBPeripheralManager) {
        // Notify 特征：设备间推送新内容通知
        notifyCharacteristic = CBMutableCharacteristic(
            type: Self.notifyUUID,
            properties: [.notify],
            value: nil,
            permissions: [.readable]
        )

        // Data 特征：用于接收大文件数据
        dataCharacteristic = CBMutableCharacteristic(
            type: Self.charUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        let s = CBMutableService(type: Self.serviceUUID, primary: true)
        s.characteristics = [notifyCharacteristic, dataCharacteristic].compactMap { $0 }
        self.service = s
        pm.add(s)
        Logger.info("BLE: service added")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Logger.info("BLE: central \(central.identifier) subscribed")
        connectedPeripherals.insert(central.identifier)

        // 推送队列中的最新 payload
        queueLock.lock()
        let latest = pendingPayloads.last
        queueLock.unlock()
        if let payload = latest, payload.dataSize <= SyncConfig.largeFileThreshold, let data = payload.encode() {
            let _ = peripheral.updateValue(data, for: characteristic as! CBMutableCharacteristic, onSubscribedCentrals: nil)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            guard let data = req.value else { continue }
            // 从 iOS 收到的新 payload
            if let payload = ClipPayload.decode(from: data) {
                SyncEngine.shared.receiveRemotePayload(payload)
            }
            peripheral.respond(to: req, withResult: .success)
        }
    }
}

// MARK: - CBCentralManagerDelegate（扫描其他设备）
extension BLEBridge: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [Self.serviceUUID], options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ])
            Logger.info("BLE: scanning for ClawdBridge devices...")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        Logger.info("BLE: discovered \(name) (RSSI: \(rssi))")

        // RSSI 约 -50dBm ≈ 2米内，自动连接
        if rssi.intValue > -70 {
            discoveredPeripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Logger.info("BLE: connected to \(peripheral.name ?? "unknown")")
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Logger.info("BLE: disconnected \(peripheral.name ?? "unknown")")
        discoveredPeripherals.removeValue(forKey: peripheral.identifier)
        connectedPeripherals.remove(peripheral.identifier)
    }
}

// MARK: - CBPeripheralDelegate（连接远端外设）
extension BLEBridge: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for svc in services {
            peripheral.discoverCharacteristics([Self.notifyUUID, Self.charUUID], for: svc)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for ch in chars {
            if ch.uuid == Self.notifyUUID {
                peripheral.setNotifyValue(true, for: ch)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        // 从其他 Mac 收到的 payload
        if let payload = ClipPayload.decode(from: data) {
            SyncEngine.shared.receiveRemotePayload(payload)
        }
    }
}
