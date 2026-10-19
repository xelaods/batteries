import Foundation
import ObjectiveC

/// iOS 標準のバッテリーウィジェットが使っている内部の仕組み（BatteryCenter）から、
/// iPhone につながっている機器の電池を読む。公開されていない仕組みなので、取れない場合は空を返す。
enum BatteryCenterReader {
    struct Entry: Identifiable, Equatable {
        var id: String
        var name: String
        var level: Int
        var charging: Bool
        var isInternal: Bool
        var part: String?
        var summary: String
    }

    enum Status: Equatable {
        case unavailable(String)
        case ok(count: Int)
    }

    private static let path = "/System/Library/PrivateFrameworks/BatteryCenter.framework/BatteryCenter"

    private static var controller: NSObject? = {
        guard dlopen(path, RTLD_NOW) != nil else { return nil }
        guard let cls = NSClassFromString("BCBatteryDeviceController") as? NSObject.Type else { return nil }
        let shared = NSSelectorFromString("sharedInstance")
        guard cls.responds(to: shared),
              let obj = cls.perform(shared)?.takeUnretainedValue() as? NSObject else { return nil }
        return obj
    }()

    static func read() -> (Status, [Entry]) {
        guard let controller else {
            return (.unavailable("BatteryCenter を読み込めませんでした"), [])
        }
        let sel = NSSelectorFromString("connectedDevices")
        guard controller.responds(to: sel) else {
            return (.unavailable("connectedDevices がありません"), [])
        }
        guard let devices = controller.perform(sel)?.takeUnretainedValue() as? [NSObject] else {
            return (.ok(count: 0), [])
        }
        let entries = devices.enumerated().compactMap { index, d in entry(from: d, index: index) }
        return (.ok(count: entries.count), entries)
    }

    private static func value(_ obj: NSObject, _ key: String) -> Any? {
        guard obj.responds(to: NSSelectorFromString(key)) else { return nil }
        return obj.value(forKey: key)
    }

    private static func entry(from d: NSObject, index: Int) -> Entry? {
        let name = (value(d, "name") as? String) ?? "不明な機器"
        guard let level = (value(d, "percentCharge") as? NSNumber)?.intValue else { return nil }
        let charging = (value(d, "isCharging") as? NSNumber)?.boolValue ?? false
        let isInternal = (value(d, "isInternal") as? NSNumber)?.boolValue ?? false
        let identifier = (value(d, "identifier") as? String) ?? "\(name)#\(index)"
        let description = d.description
        return Entry(
            id: identifier,
            name: name,
            level: level,
            charging: charging,
            isInternal: isInternal,
            part: partID(of: d, description: description),
            summary: description
        )
    }

    /// AirPods の左・右・ケースを見分ける
    private static func partID(of d: NSObject, description: String) -> String? {
        let text = description.lowercased()
        if text.contains("case") { return "case" }
        if text.contains("left") { return "left" }
        if text.contains("right") { return "right" }
        return nil
    }

    /// 読み取った値を、保存用の更新にまとめる（同じ名前のものを1台として扱う）
    static func updates(from entries: [Entry], date: Date) -> [DeviceUpdate] {
        let external = entries.filter { !$0.isInternal }
        let groups = Dictionary(grouping: external, by: \.name)
        return groups.keys.sorted().compactMap { name in
            guard let list = groups[name], !list.isEmpty else { return nil }
            let lower = name.lowercased()
            let isAudio = lower.contains("airpods") || lower.contains("beats")
            let symbol: String
            if lower.contains("max") { symbol = "airpodsmax" }
            else if lower.contains("airpods pro") { symbol = "airpodspro" }
            else if lower.contains("airpods") { symbol = "airpods.gen3" }
            else if lower.contains("beats") { symbol = "beats.earphones" }
            else if lower.contains("watch") { symbol = "applewatch" }
            else if lower.contains("pencil") { symbol = "applepencil" }
            else if lower.contains("keyboard") || lower.contains("キーボード") { symbol = "keyboard" }
            else if lower.contains("mouse") || lower.contains("マウス") { symbol = "computermouse" }
            else { symbol = "dot.radiowaves.left.and.right" }

            var parts: [DeviceUpdate.Part] = []
            if list.count == 1, list[0].part == nil {
                parts = [.init(id: "main", label: "本体", level: list[0].level, charging: list[0].charging)]
            } else {
                let labels = ["left": "左", "right": "右", "case": "ケース"]
                var used = Set<String>()
                for (i, e) in list.enumerated() {
                    var id = e.part ?? "p\(i + 1)"
                    if used.contains(id) { id += "-\(i + 1)" }
                    used.insert(id)
                    parts.append(.init(id: id, label: labels[id] ?? "\(i + 1)", level: e.level, charging: e.charging))
                }
            }
            return DeviceUpdate(
                id: "bc-" + name,
                name: name,
                kind: isAudio ? .airpods : (symbol == "computermouse" ? .mouse : .bluetooth),
                symbol: symbol,
                components: parts,
                source: "iOS の電池情報",
                date: date
            )
        }
    }
}
