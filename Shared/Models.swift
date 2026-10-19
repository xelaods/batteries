import Foundation

/// 機器の種類（アイコンや並び順に使う）
enum DeviceKind: String, Codable, CaseIterable {
    case iphone
    case airpods
    case bluetooth
    case computer
    case mouse
    case other
}

/// 機器の中の1つの電池（AirPods なら左・右・ケース）
struct BatteryComponent: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    /// 0〜100。一度も取れていなければ nil
    var level: Int?
    var charging: Bool
    /// この電池の値を最後に受け取った時刻
    var updatedAt: Date
}

/// 1台の機器。最後に受け取った値をずっと持ち続ける
struct DeviceRecord: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var kind: DeviceKind
    var symbol: String
    var components: [BatteryComponent]
    /// 最後に何か値を受け取った時刻
    var updatedAt: Date
    /// どこから来た値か（"iPhone"、"AirPods の電波"、"Bluetooth" など）
    var source: String
    /// ユーザーが付けた名前（なければ自動の名前）
    var customName: String?

    var displayName: String {
        if let c = customName?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        return name
    }

    /// 値が入っている電池
    var knownComponents: [BatteryComponent] { components.filter { $0.level != nil } }

    func component(_ id: String) -> BatteryComponent? { components.first { $0.id == id } }
}

/// 保存する中身すべて
struct Snapshot: Codable, Equatable {
    var devices: [DeviceRecord] = []
    var savedAt: Date = .distantPast

    /// 新しく受け取った値を混ぜる。
    /// 値が取れなかった電池（nil）は前の値をそのまま残すので、接続が切れても最後の値が表示され続ける。
    mutating func merge(_ update: DeviceUpdate) {
        if let i = devices.firstIndex(where: { $0.id == update.id }) {
            var device = devices[i]
            device.name = update.name
            device.symbol = update.symbol
            device.source = update.source
            for part in update.components {
                guard let level = part.level else { continue }
                let clamped = max(0, min(100, level))
                if let j = device.components.firstIndex(where: { $0.id == part.id }) {
                    device.components[j].level = clamped
                    device.components[j].charging = part.charging
                    device.components[j].label = part.label
                    device.components[j].updatedAt = update.date
                } else {
                    device.components.append(BatteryComponent(id: part.id, label: part.label, level: clamped, charging: part.charging, updatedAt: update.date))
                }
            }
            if update.components.contains(where: { $0.level != nil }) {
                device.updatedAt = update.date
            }
            devices[i] = device
        } else {
            let parts = update.components.compactMap { part -> BatteryComponent? in
                guard let level = part.level else { return nil }
                return BatteryComponent(id: part.id, label: part.label, level: max(0, min(100, level)), charging: part.charging, updatedAt: update.date)
            }
            guard !parts.isEmpty else { return }
            devices.append(DeviceRecord(id: update.id, name: update.name, kind: update.kind, symbol: update.symbol, components: parts, updatedAt: update.date, source: update.source, customName: nil))
        }
    }
}

extension Snapshot {
    /// 別の保存先の記録を取り込む。電池ごとに新しい方を残す（ウィジェットが自分で読んだ値とアプリの値を合わせるため）
    mutating func absorb(_ other: Snapshot) {
        for od in other.devices {
            guard let i = devices.firstIndex(where: { $0.id == od.id }) else {
                devices.append(od)
                continue
            }
            var d = devices[i]
            for oc in od.components {
                if let j = d.components.firstIndex(where: { $0.id == oc.id }) {
                    if oc.updatedAt > d.components[j].updatedAt { d.components[j] = oc }
                } else {
                    d.components.append(oc)
                }
            }
            if od.updatedAt > d.updatedAt {
                d.updatedAt = od.updatedAt
                d.source = od.source
                d.name = od.name
            }
            if d.customName == nil { d.customName = od.customName }
            devices[i] = d
        }
        savedAt = max(savedAt, other.savedAt)
    }
}

/// 読み取った値（電池ごとに nil があり得る）
struct DeviceUpdate: Equatable {
    struct Part: Equatable {
        var id: String
        var label: String
        var level: Int?
        var charging: Bool
    }

    var id: String
    var name: String
    var kind: DeviceKind
    var symbol: String
    var components: [Part]
    var source: String
    var date: Date
}

/// ウィジェットや一覧で1行（1つの丸）として見せる単位
struct BatteryItem: Identifiable, Hashable {
    var id: String
    var deviceID: String
    var title: String
    var symbol: String
    var level: Int
    var charging: Bool
    var updatedAt: Date
    /// 「左 80%・右 70%」などの補足
    var detail: String?
}

extension Snapshot {
    /// 表示用に並べた機器
    var orderedDevices: [DeviceRecord] {
        let rank: [DeviceKind: Int] = [.iphone: 0, .airpods: 1, .computer: 2, .mouse: 3, .bluetooth: 4, .other: 5]
        return devices.sorted {
            let a = rank[$0.kind] ?? 9, b = rank[$1.kind] ?? 9
            return a != b ? a < b : $0.displayName < $1.displayName
        }
    }

    /// AirPods は「イヤホン（左右）」と「ケース」の2つに分け、それ以外は機器ごとに1つ
    var items: [BatteryItem] {
        var result: [BatteryItem] = []
        for device in orderedDevices {
            if device.kind == .airpods {
                let left = device.component("left"), right = device.component("right")
                let buds = [left, right].compactMap { $0 }.filter { $0.level != nil }
                if !buds.isEmpty {
                    let level = buds.compactMap(\.level).min() ?? 0
                    let date = buds.map(\.updatedAt).max() ?? device.updatedAt
                    var detail: String?
                    if let l = left?.level, let r = right?.level, l != r {
                        detail = "左 \(l)%・右 \(r)%"
                    }
                    result.append(BatteryItem(id: device.id + ".buds", deviceID: device.id, title: device.displayName, symbol: device.symbol, level: level, charging: buds.contains { $0.charging }, updatedAt: date, detail: detail))
                }
                if let single = device.component("main"), let level = single.level {
                    result.append(BatteryItem(id: device.id + ".main", deviceID: device.id, title: device.displayName, symbol: device.symbol, level: level, charging: single.charging, updatedAt: single.updatedAt, detail: nil))
                }
                if let c = device.component("case"), let level = c.level {
                    result.append(BatteryItem(id: device.id + ".case", deviceID: device.id, title: "ケース", symbol: AirPodsModel.caseSymbol(for: device.symbol), level: level, charging: c.charging, updatedAt: c.updatedAt, detail: nil))
                }
                // 左右が見分けられなかった電池はそのまま並べる
                for c in device.knownComponents where !["left", "right", "main", "case"].contains(c.id) {
                    result.append(BatteryItem(id: device.id + "." + c.id, deviceID: device.id, title: "\(device.displayName) \(c.label)", symbol: device.symbol, level: c.level ?? 0, charging: c.charging, updatedAt: c.updatedAt, detail: nil))
                }
            } else {
                for c in device.knownComponents {
                    let title = device.knownComponents.count > 1 ? "\(device.displayName) \(c.label)" : device.displayName
                    result.append(BatteryItem(id: device.id + "." + c.id, deviceID: device.id, title: title, symbol: device.symbol, level: c.level ?? 0, charging: c.charging, updatedAt: c.updatedAt, detail: nil))
                }
            }
        }
        return result
    }
}
