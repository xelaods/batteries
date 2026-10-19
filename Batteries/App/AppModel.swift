import Foundation
import SwiftUI
import UIKit
import CoreBluetooth
import EventKit
import WidgetKit

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var snapshot: Snapshot
    let isDemo: Bool
    var refreshing = false
    var lastRefreshAt: Date?
    /// 最後の受け取りで失敗したときの理由
    var relayError: String?
    /// 最後の受け取りで届いた件数
    var lastReceivedCount = 0
    var bluetoothState: CBManagerState = .unknown
    var calendarStatus: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    /// ペアリング用の URL で合言葉が設定されたとき（画面で知らせる）
    var pairedJustNow = false

    @ObservationIgnored private let scanner = BluetoothScanner()
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let args = ProcessInfo.processInfo.arguments
        isDemo = args.contains("-demo")
        snapshot = isDemo ? DemoData.snapshot() : SharedStore.loadForApp()
        if isDemo {
            bluetoothState = .poweredOn
            lastRefreshAt = Date().addingTimeInterval(-90)
            lastReceivedCount = 6
        }

        scanner.onStateChange = { [weak self] state in
            MainActor.assumeIsolated { self?.bluetoothState = state }
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
    }

    // MARK: 更新

    var relayTopic: String? { snapshot.relayTopic }

    /// アプリを開いたとき
    func becameActive() {
        guard !isDemo else { return }
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        if SharedStore.isShared {
            // ウィジェットが自分で受け取った値を取り込む
            snapshot.absorb(SharedStore.loadForApp())
        }
        updatePhone()
        scanner.start()
        Task { await refresh() }
    }

    func becameInactive() {
        scanner.stop()
        persist()
    }

    /// PC から届いている値を受け取る
    func refresh() async {
        guard !isDemo else { return }
        updatePhone()
        guard let topic = snapshot.relayTopic else { return }
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let received = try await RelayClient.fetch(topic: topic)
            RelayClient.apply(received, to: &snapshot)
            lastReceivedCount = received.count
            relayError = nil
            lastRefreshAt = Date()
            persist()
        } catch {
            relayError = error.localizedDescription
        }
    }

    func handle(url: URL) {
        guard url.scheme == "batteries" else { return }
        if url.host == "pair", let topic = RelayClient.normalizeTopic(url.absoluteString) {
            setTopic(topic)
            pairedJustNow = true
        }
        becameActive()
    }

    @discardableResult
    func setTopic(_ input: String) -> Bool {
        guard let topic = RelayClient.normalizeTopic(input) else { return false }
        snapshot.relayTopic = topic
        persist()
        Task { await refresh() }
        return true
    }

    func clearTopic() {
        snapshot.relayTopic = nil
        snapshot.computers = nil
        relayError = nil
        persist()
    }

    // MARK: 受け取った値

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

    // MARK: 編集

    func rename(_ id: String, to name: String) {
        guard let i = snapshot.devices.firstIndex(where: { $0.id == id }) else { return }
        guard snapshot.devices[i].customName ?? "" != name else { return }
        snapshot.devices[i].customName = name
        persist()
    }

    func delete(_ id: String) {
        snapshot.devices.removeAll { $0.id == id }
        persist()
    }

    func deleteAll() {
        snapshot.devices.removeAll()
        snapshot.computers = nil
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
