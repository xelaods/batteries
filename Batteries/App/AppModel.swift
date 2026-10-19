import Foundation
import SwiftUI
import UIKit
import CoreBluetooth
import AVFoundation
import EventKit
import WidgetKit

/// 診断用の記録（AirPods の電波が iOS で本当に受け取れるか確かめるため）
struct ScanDiagnostics {
    struct Candidate: Identifiable {
        var id: UUID
        var model: AirPodsModel
        var reading: ProximityPairing.Reading
        var rssi: Int
        var seenAt: Date
        var count: Int
        var accepted: Bool
    }

    var startedAt: Date?
    var totalAds = 0
    var appleAds = 0
    var pairingAds = 0
    var typeCounts: [UInt8: Int] = [:]
    var candidates: [UUID: Candidate] = [:]
    var lastPairingAt: Date?

    static func typeName(_ type: UInt8) -> String {
        switch type {
        case 0x02: return "iBeacon"
        case 0x05: return "AirDrop"
        case 0x07: return "近接ペアリング（AirPods）"
        case 0x09: return "AirPlay 先"
        case 0x0A: return "AirPlay 元"
        case 0x0C: return "Handoff"
        case 0x0D: return "テザリング設定"
        case 0x0E: return "テザリング元"
        case 0x0F: return "近くの操作"
        case 0x10: return "近くの情報"
        case 0x12: return "探す"
        case 0x16: return "近くの操作（新）"
        default: return "不明"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var snapshot: Snapshot
    let isDemo: Bool
    var scanning = false
    var scanEndsAt: Date?
    var lastScanAt: Date?
    var bluetoothState: CBManagerState = .unknown
    var diagnostics = ScanDiagnostics()
    var calendarStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    var connectedAudioName: String?
    /// iOS の電池情報（BatteryCenter）の読み取り結果
    var batteryCenterStatus: BatteryCenterReader.Status?
    var batteryCenterEntries: [BatteryCenterReader.Entry] = []
    var batteryCenterReadAt: Date?

    /// この強さ（dBm）より弱い AirPods の電波は他人のものとして無視する
    var rssiThreshold: Int {
        didSet { UserDefaults.standard.set(rssiThreshold, forKey: "rssiThreshold") }
    }
    /// 左右が逆に表示されるときの切り替え
    var swapSides: Bool {
        didSet { UserDefaults.standard.set(swapSides, forKey: "swapSides") }
    }

    @ObservationIgnored private let scanner = BluetoothScanner()
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// 機種ごとに、今回いちばん強かった電波（他人の AirPods を混ぜないため）
    @ObservationIgnored private var strongest: [UInt16: (id: UUID, rssi: Int)] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init() {
        let args = ProcessInfo.processInfo.arguments
        isDemo = args.contains("-demo")
        snapshot = isDemo ? DemoData.snapshot() : SharedStore.loadForApp()
        rssiThreshold = UserDefaults.standard.object(forKey: "rssiThreshold") as? Int ?? -65
        swapSides = UserDefaults.standard.bool(forKey: "swapSides")
        if isDemo {
            bluetoothState = .poweredOn
            lastScanAt = Date().addingTimeInterval(-90)
            diagnostics = Self.demoDiagnostics()
            batteryCenterStatus = .ok(count: 3)
            batteryCenterReadAt = Date()
            batteryCenterEntries = [
                .init(id: "1", name: "陽翔のAirPods Pro", level: 80, charging: false, isInternal: false, part: "left", summary: "<BCBatteryDevice: name=陽翔のAirPods Pro; percentCharge=80; parts=Left>"),
                .init(id: "2", name: "陽翔のAirPods Pro", level: 70, charging: false, isInternal: false, part: "right", summary: "<BCBatteryDevice: name=陽翔のAirPods Pro; percentCharge=70; parts=Right>"),
                .init(id: "3", name: "iPhone", level: 64, charging: false, isInternal: true, part: nil, summary: "<BCBatteryDevice: name=iPhone; internal=1>"),
            ]
        }

        scanner.onStateChange = { [weak self] state in
            MainActor.assumeIsolated { self?.bluetoothState = state }
        }
        scanner.onAdvertisement = { [weak self] id, data, rssi, name in
            MainActor.assumeIsolated { self?.handleAdvertisement(id: id, data: data, rssi: rssi, name: name) }
        }
        scanner.onBatteryLevel = { [weak self] id, name, level in
            MainActor.assumeIsolated { self?.handleBLEBattery(id: id, name: name, level: level) }
        }

        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePhone() }
        }
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePhone() }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateAudioRoute()
                self?.readBatteryCenter()
            }
        }
    }

    // MARK: 読み取りの開始・終了

    /// アプリを開いたとき
    func becameActive() {
        guard !isDemo else { return }
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        if SharedStore.isShared {
            // ウィジェットが自分で読んだ値を取り込む
            snapshot.absorb(SharedStore.loadForApp())
        }
        updateAudioRoute()
        updatePhone()
        readBatteryCenter()
        startScan(seconds: 12)
    }

    func startScan(seconds: Double) {
        guard !isDemo else { return }
        stopTask?.cancel()
        if !scanning {
            diagnostics = ScanDiagnostics()
            diagnostics.startedAt = Date()
            strongest = [:]
        }
        scanning = true
        scanEndsAt = Date().addingTimeInterval(seconds)
        scanner.start()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.readBatteryCenter()
            }
        }
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.stopScan()
        }
    }

    func stopScan() {
        stopTask?.cancel()
        pollTask?.cancel()
        scanner.stop()
        if scanning { lastScanAt = Date() }
        scanning = false
        scanEndsAt = nil
        persist()
    }

    /// iOS 標準のバッテリーウィジェットと同じ情報源から読む
    func readBatteryCenter() {
        guard !isDemo else { return }
        let (status, entries) = BatteryCenterReader.read()
        batteryCenterStatus = status
        batteryCenterEntries = entries
        batteryCenterReadAt = Date()
        let updates = BatteryCenterReader.updates(from: entries, date: Date())
        guard !updates.isEmpty else { return }
        for u in updates { snapshot.merge(u) }
        schedulePersist()
    }

    func handle(url: URL) {
        guard url.scheme == "batteries" else { return }
        becameActive()
    }

    // MARK: 受け取った値

    private func handleAdvertisement(id: UUID, data: [UInt8]?, rssi: Int, name: String?) {
        diagnostics.totalAds += 1
        guard let data else { return }
        let messages = ProximityPairing.messages(inManufacturerData: data)
        guard !messages.isEmpty else { return }
        diagnostics.appleAds += 1
        for m in messages { diagnostics.typeCounts[m.type, default: 0] += 1 }

        guard let reading = ProximityPairing.parse(manufacturerData: data, swapSides: swapSides) else { return }
        diagnostics.pairingAds += 1
        diagnostics.lastPairingAt = Date()

        // 127 は「強さ不明」
        let validRSSI = rssi != 127 && rssi < 0
        let model = reading.modelInfo
        var accepted = false
        if validRSSI, rssi >= rssiThreshold, reading.hasAnyLevel {
            if let best = strongest[reading.model], best.id != id, best.rssi > rssi + 3 {
                accepted = false
            } else {
                strongest[reading.model] = (id, max(rssi, strongest[reading.model]?.rssi ?? rssi))
                accepted = true
            }
        }

        let previous = diagnostics.candidates[id]
        diagnostics.candidates[id] = .init(id: id, model: model, reading: reading, rssi: rssi, seenAt: Date(), count: (previous?.count ?? 0) + 1, accepted: accepted || (previous?.accepted ?? false))

        guard accepted else { return }
        let deviceID = String(format: "airpods-%04X", reading.model)
        let existingName = snapshot.devices.first { $0.id == deviceID }?.name
        let update = model.update(from: reading, name: connectedAudioName ?? existingName, date: Date())
        snapshot.merge(update)
        schedulePersist()
    }

    private func handleBLEBattery(id: UUID, name: String, level: Int) {
        let update = DeviceUpdate(
            id: "ble-" + id.uuidString,
            name: name,
            kind: guessKind(name),
            symbol: guessSymbol(name),
            components: [.init(id: "main", label: "本体", level: level, charging: false)],
            source: "Bluetooth",
            date: Date()
        )
        snapshot.merge(update)
        schedulePersist()
    }

    private func guessKind(_ name: String) -> DeviceKind {
        let n = name.lowercased()
        if n.contains("mouse") || n.contains("マウス") { return .mouse }
        return .bluetooth
    }

    private func guessSymbol(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("mouse") || n.contains("マウス") { return "computermouse" }
        if n.contains("keyboard") || n.contains("キーボード") { return "keyboard" }
        if n.contains("pencil") { return "applepencil" }
        if n.contains("watch") { return "applewatch" }
        if n.contains("controller") || n.contains("pad") { return "gamecontroller" }
        return "dot.radiowaves.left.and.right"
    }

    func updatePhone() {
        guard !isDemo else { return }
        let device = UIDevice.current
        let level = device.batteryLevel
        guard level >= 0 else { return } // シミュレータなどでは -1
        let charging = device.batteryState == .charging || device.batteryState == .full
        snapshot.merge(DeviceUpdate(
            id: "iphone",
            name: "iPhone",
            kind: .iphone,
            symbol: "iphone",
            components: [.init(id: "main", label: "本体", level: Int((level * 100).rounded()), charging: charging)],
            source: "iPhone",
            date: Date()
        ))
        schedulePersist()
    }

    /// 今つながっているイヤホンの名前（「◯◯のAirPods Pro」など）
    func updateAudioRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let bluetooth = outputs.first { [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType) }
        if let name = bluetooth?.portName, name.localizedCaseInsensitiveContains("airpods") || name.localizedCaseInsensitiveContains("beats") {
            connectedAudioName = name
        } else {
            connectedAudioName = nil
        }
    }

    // MARK: 編集

    func rename(_ id: String, to name: String) {
        guard let i = snapshot.devices.firstIndex(where: { $0.id == id }) else { return }
        snapshot.devices[i].customName = name
        persist()
    }

    func delete(_ id: String) {
        snapshot.devices.removeAll { $0.id == id }
        persist()
    }

    func deleteAll() {
        snapshot.devices.removeAll()
        persist()
    }

    func requestCalendarAccess() async {
        _ = try? await EKEventStore().requestFullAccessToEvents()
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        persist()
    }

    var calendarBridgeEnabled: Bool = CalendarBridge.enabled {
        didSet {
            CalendarBridge.enabled = calendarBridgeEnabled
            persist()
        }
    }

    enum WidgetBridge { case appGroup, calendar, none }

    var widgetBridge: WidgetBridge {
        if SharedStore.isShared { return .appGroup }
        if calendarStatus == .fullAccess && calendarBridgeEnabled { return .calendar }
        return .none
    }

    // MARK: 見本

    private static func demoDiagnostics() -> ScanDiagnostics {
        var d = ScanDiagnostics()
        d.startedAt = Date().addingTimeInterval(-20)
        d.totalAds = 1843
        d.appleAds = 1210
        d.pairingAds = 96
        d.typeCounts = [0x10: 820, 0x0C: 210, 0x07: 96, 0x12: 84]
        d.lastPairingAt = Date()
        let mine: [UInt8] = [0x01, 0x14, 0x20, 0x2B, 0x78, 0x54, 0x01, 0x00, 0x00]
        let other: [UInt8] = [0x01, 0x0F, 0x20, 0x2B, 0x99, 0x0F, 0x03, 0x00, 0x00]
        if let r = ProximityPairing.parse(payload: mine) {
            let id = UUID()
            d.candidates[id] = .init(id: id, model: r.modelInfo, reading: r, rssi: -41, seenAt: Date(), count: 71, accepted: true)
        }
        if let r = ProximityPairing.parse(payload: other) {
            let id = UUID()
            d.candidates[id] = .init(id: id, model: r.modelInfo, reading: r, rssi: -83, seenAt: Date(), count: 25, accepted: false)
        }
        return d
    }

    // MARK: 保存

    private func schedulePersist() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.saveTask = nil
            self?.persist()
        }
    }

    func persist() {
        guard !isDemo else { return }
        snapshot.savedAt = Date()
        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
