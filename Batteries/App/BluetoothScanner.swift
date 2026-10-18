import Foundation
import CoreBluetooth

/// 周りの電波を受け取り、つながっている BLE 機器の電池（標準の電池サービス）を読む
final class BluetoothScanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    /// 電波を受け取ったとき（機器ID、製造者データ、電波の強さ、名前）
    var onAdvertisement: ((UUID, [UInt8]?, Int, String?) -> Void)?
    /// BLE 機器の電池を読めたとき（機器ID、名前、0〜100）
    var onBatteryLevel: ((UUID, String, Int) -> Void)?
    var onStateChange: ((CBManagerState) -> Void)?

    private var central: CBCentralManager?
    private var wantsScan = false
    private var peripherals: [UUID: CBPeripheral] = [:]

    var state: CBManagerState { central?.state ?? .unknown }

    func start() {
        wantsScan = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            beginIfReady()
        }
    }

    func stop() {
        wantsScan = false
        guard let central else { return }
        if central.state == .poweredOn { central.stopScan() }
        for p in peripherals.values { central.cancelPeripheralConnection(p) }
        peripherals.removeAll()
    }

    private func beginIfReady() {
        guard wantsScan, let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        // iPhone につながっている機器のうち、標準の電池サービスを持つもの
        for p in central.retrieveConnectedPeripherals(withServices: [Self.batteryService]) where peripherals[p.identifier] == nil {
            peripherals[p.identifier] = p
            p.delegate = self
            central.connect(p)
        }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateChange?(central.state)
        beginIfReady()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let data = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).map { [UInt8]($0) }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        onAdvertisement?(peripheral.identifier, data, RSSI.intValue, name)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        peripherals[peripheral.identifier] = nil
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.batteryService {
            peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] where ch.uuid == Self.batteryLevel {
            peripheral.readValue(for: ch)
            if ch.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: ch)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.batteryLevel, let value = characteristic.value?.first else { return }
        onBatteryLevel?(peripheral.identifier, peripheral.name ?? "Bluetooth 機器", Int(value))
    }
}
