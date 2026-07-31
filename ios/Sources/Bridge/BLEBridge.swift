import Foundation

/// iOS 蓝牙桥：作为 BLE Peripheral，广播 + 接收
/// iOS 只做 Peripheral（被 Mac/其他 iOS 扫描），不做 Central 扫描（省电）
final class BLEBridge: NSObject {
    static let serviceUUID = CBUUID(string: SyncConfig.bluetoothServiceUUID)
    static let charUUID = CBUUID(string: SyncConfig.bluetoothCharUUID)
    static let notifyUUID = CBUUID(string: SyncConfig.bluetoothNotifyUUID)

    private var peripheralManager: CBPeripheralManager?
    private var notifyCharacteristic: CBMutableCharacteristic?
    private var dataCharacteristic: CBMutableCharacteristic?
    private var pendingPayloads: [ClipPayload] = []
    private let lock = NSLock()
    private let bleQueue = DispatchQueue(label: "com.clawdbridge.ios.ble", qos: .background)

    var onPayloadReceived: ((ClipPayload) -> Void)?
    var isAdvertising: Bool { peripheralManager?.isAdvertising ?? false }

    func start() {
        peripheralManager = CBPeripheralManager(delegate: self, queue: bleQueue)
    }

    func stop() {
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
    }

    func notifyAll(_ payload: ClipPayload) {
        lock.lock()
        pendingPayloads.append(payload)
        lock.unlock()
        pushLatestToSubscribers()
    }

    private func pushLatestToSubscribers() {
        guard let pm = peripheralManager, pm.state == .poweredOn,
              let ch = notifyCharacteristic else { return }

        lock.lock()
        let latest = pendingPayloads.last
        lock.unlock()

        guard let payload = latest else { return }

        // 小数据直接推送 payload；大数据仅推送 metadata
        if payload.dataSize <= SyncConfig.largeFileThreshold,
           let data = payload.encode() {
            _ = pm.updateValue(data, for: ch, onSubscribedCentrals: nil)
        } else if let meta = payload.metadata.encode() {
            _ = pm.updateValue(meta, for: ch, onSubscribedCentrals: nil)
        }
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BLEBridge: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { return }

        notifyCharacteristic = CBMutableCharacteristic(
            type: Self.notifyUUID, properties: [.notify], value: nil, permissions: [.readable])
        dataCharacteristic = CBMutableCharacteristic(
            type: Self.charUUID, properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeable])

        let svc = CBMutableService(type: Self.serviceUUID, primary: true)
        svc.characteristics = [notifyCharacteristic, dataCharacteristic].compactMap { $0 }
        peripheral.add(svc)

        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: "ClawdBridge-\(UIDevice.current.name)"
        ])
        Logger.info("BLE: iOS advertising started")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        Logger.info("BLE: central \(central.identifier) subscribed")
        pushLatestToSubscribers()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            guard let data = req.value else { continue }
            if let payload = ClipPayload.decode(from: data) {
                DispatchQueue.main.async { [weak self] in
                    self?.onPayloadReceived?(payload)
                }
            }
            peripheral.respond(to: req, withResult: .success)
        }
    }
}
