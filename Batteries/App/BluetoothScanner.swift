import Foundation
import CoreBluetooth

/// iPhone につながっている BLE 機器（キーボードなど）のうち、標準の電池サービスを持つものの電池を読む。
/// （AirPods は iOS がアプリに値を渡さないので、PC 経由で受け取る）
final class BluetoothScanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    /// 電池を読めたとき（機器ID、名前、0〜100）
    var onBatteryLevel: ((UUID, String, Int) -> Void)?
    var onStateChange: ((CBManagerState) -> Void)?

    private var central: CBCentralManager?
    private var wantsRead = false
    private var peripherals: [UUID: CBPeripheral] = [:]

    func start() {
        wantsRead = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            readIfReady()
        }
    }

    func stop() {
        wantsRead = false
        guard let central else { return }
        for p in peripherals.values { central.cancelPeripheralConnection(p) }
        peripherals.removeAll()
    }

    private func readIfReady() {
        guard wantsRead, let central, central.state == .poweredOn else { return }
        for p in central.retrieveConnectedPeripherals(withServices: [Self.batteryService]) where peripherals[p.identifier] == nil {
            peripherals[p.identifier] = p
            p.delegate = self
            central.connect(p)
        }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateChange?(central.state)
        readIfReady()
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
