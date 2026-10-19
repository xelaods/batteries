import Foundation

/// PC の常駐アプリが ntfy.sh に送ってくる中身（JSON）。
/// 時刻はすべて Unix 時間（秒）。電池ごとに「実際に読み取った時刻」を持つので、
/// 複数の PC から届いても新しい値だけが残る。
struct RelayMessage: Codable, Equatable {
    struct Part: Codable, Equatable {
        var id: String
        var label: String?
        var level: Int
        var charging: Bool?
        var at: Double
    }

    struct Device: Codable, Equatable {
        var id: String
        var name: String?
        var kind: String
        var symbol: String?
        /// AirPods の機種番号（例：0x1420 = 5152）
        var model: Int?
        var parts: [Part]
    }

    var v: Int
    /// 送ってきた PC の名前
    var pc: String
    var at: Double?
    var devices: [Device]
    /// PC を見分ける変わらない ID（古い版の PC アプリにはない）
    var pcId: String? = nil
    /// 前に使っていた機器 ID
    var formerIds: [String]? = nil
    /// 前に使っていた PC の名前
    var formerNames: [String]? = nil

    /// PC 一覧で使うキー
    var computerKey: String { pcId ?? pc }

    static func label(for partID: String) -> String {
        switch partID {
        case "left": return "左"
        case "right": return "右"
        case "case": return "ケース"
        default: return "本体"
        }
    }

    /// 保存用の更新にする
    func updates() -> [DeviceUpdate] {
        let source = "PC（\(pc)）"
        let sent = Date(timeIntervalSince1970: at ?? Date().timeIntervalSince1970)
        return devices.compactMap { d in
            let kind = DeviceKind(rawValue: d.kind) ?? .other
            var name = d.name ?? "機器"
            var symbol = d.symbol ?? "dot.radiowaves.left.and.right"
            var parts = d.parts.map {
                DeviceUpdate.Part(id: $0.id, label: $0.label ?? Self.label(for: $0.id), level: $0.level, charging: $0.charging ?? false, date: Date(timeIntervalSince1970: $0.at))
            }
            if kind == .airpods, let model = d.model {
                let info = AirPodsModel.lookup(UInt16(truncatingIfNeeded: model))
                name = d.name ?? info.name
                symbol = info.symbol
                if info.singleBattery {
                    // AirPods Max など電池が1つの機種は、左右のどちらかに入ってくる値を「本体」にまとめる
                    let buds = parts.filter { $0.id == "left" || $0.id == "right" }
                    if let best = buds.max(by: { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }) {
                        parts = [.init(id: "main", label: "本体", level: buds.compactMap(\.level).max(), charging: buds.contains { $0.charging }, date: best.date)]
                    } else {
                        parts = []
                    }
                }
            }
            guard !parts.isEmpty else { return nil }
            return DeviceUpdate(id: d.id, name: name, kind: kind, symbol: symbol, components: parts, source: source, date: sent)
        }
    }
}

/// ntfy.sh から PC の値を受け取る
enum RelayClient {
    static let server = "https://ntfy.sh"

    struct Received: Equatable {
        var time: Date
        var message: RelayMessage
    }

    enum RelayError: LocalizedError {
        case badTopic
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .badTopic: return "合言葉の形がおかしいです"
            case .http(let code): return "中継サーバーがエラーを返しました（\(code)）"
            }
        }
    }

    /// 合言葉として使える形か（英小文字・数字・ハイフン、8〜64文字）
    static func isValidTopic(_ topic: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        return (8...64).contains(topic.count) && topic.allSatisfy { allowed.contains($0) }
    }

    /// 入力された文字やペアリング用の URL から合言葉を取り出す
    static func normalizeTopic(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = comps.queryItems?.first(where: { $0.name == "code" })?.value {
            text = code
        }
        text = text.lowercased().replacingOccurrences(of: " ", with: "")
        return isValidTopic(text) ? text : nil
    }

    /// ntfy の JSON（1行に1件）を読む
    static func parse(_ data: Data) -> [Received] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var result: [Received] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  obj["event"] as? String == "message",
                  let body = obj["message"] as? String,
                  let bodyData = body.data(using: .utf8),
                  let message = try? JSONDecoder().decode(RelayMessage.self, from: bodyData) else { continue }
            let time = (obj["time"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970
            result.append(Received(time: Date(timeIntervalSince1970: time), message: message))
        }
        return result
    }

    static func fetch(topic: String, since: String = "12h", timeout: TimeInterval = 10) async throws -> [Received] {
        guard isValidTopic(topic),
              let url = URL(string: "\(server)/\(topic)/json?poll=1&since=\(since)") else { throw RelayError.badTopic }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("batteries-ios", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RelayError.http(http.statusCode)
        }
        return parse(data)
    }

    /// 受け取った値を記録に混ぜる
    static func apply(_ received: [Received], to snapshot: inout Snapshot) {
        for r in received {
            let m = r.message
            if let pcId = m.pcId {
                // 名前を変えた PC：前の ID の記録を今の ID にまとめ、前の名前を PC 一覧から消す
                let current = "pc-" + pcId
                for old in m.formerIds ?? [] { snapshot.retire(old, into: current) }
                // 古い版は PC の名前をキーにしていたので、今の名前のキーも消す
                for name in (m.formerNames ?? []) + [m.pc] where name != pcId {
                    snapshot.computers?[name] = nil
                    snapshot.computerNames?[name] = nil
                }
            }
            for u in m.updates() { snapshot.merge(snapshot.redirected(u)) }
            var key = m.computerKey
            var updatesName = true
            if m.pcId == nil, let pcDevice = m.devices.first(where: { $0.kind == DeviceKind.computer.rawValue }) {
                // 古い版の PC アプリのメッセージ：今の ID を持つ PC のものなら、そちらにまとめる
                let target = snapshot.redirectedID(pcDevice.id)
                if target.hasPrefix("pc-") {
                    let pid = String(target.dropFirst(3))
                    if pid != m.pc, snapshot.computers?[pid] != nil {
                        key = pid
                        updatesName = false
                    }
                }
            }
            var computers = snapshot.computers ?? [:]
            if r.time > (computers[key] ?? .distantPast) {
                computers[key] = r.time
                if updatesName {
                    var names = snapshot.computerNames ?? [:]
                    names[key] = m.pc
                    snapshot.computerNames = names
                }
            }
            snapshot.computers = computers
        }
    }
}
