import Foundation

/// AirPods・Beats が周りに発信している「近接ペアリング」信号（Apple の製造者データ、種類 0x07）の読み取り。
///
/// 製造者データの並び： 4C 00 | 種類 | 長さ | 中身 …（種類・長さ・中身がいくつか続く）
/// 種類 0x07 の中身：
///   [0] 前置き  [1-2] 機種  [3] 状態（0x20 で左右の向き）
///   [4] 電池（上位4bit・下位4bit が左右。0〜10 が 0〜100%、15 は不明）
///   [5] 上位4bit が充電中（bit0/1 が左右、bit2 がケース）、下位4bit がケースの電池
///   [6] ふたの開閉回数  [7] 色  以降は暗号化された中身
enum ProximityPairing {
    static let appleCompanyID: UInt16 = 0x004C
    static let messageType: UInt8 = 0x07

    struct Reading: Equatable {
        var model: UInt16
        var left: Int?
        var right: Int?
        var caseLevel: Int?
        var leftCharging: Bool
        var rightCharging: Bool
        var caseCharging: Bool
        var rawHex: String

        var modelInfo: AirPodsModel { AirPodsModel.lookup(model) }

        /// 左右・ケースのどれか1つでも値があるか
        var hasAnyLevel: Bool { left != nil || right != nil || caseLevel != nil }
    }

    /// Apple の製造者データ（先頭が 4C 00）から、中に入っている種類と中身を取り出す
    static func messages(inManufacturerData data: [UInt8]) -> [(type: UInt8, payload: [UInt8])] {
        guard data.count >= 2, UInt16(data[0]) | (UInt16(data[1]) << 8) == appleCompanyID else { return [] }
        var result: [(UInt8, [UInt8])] = []
        var i = 2
        while i + 1 < data.count {
            let type = data[i]
            let length = Int(data[i + 1])
            let start = i + 2
            let end = min(start + length, data.count)
            result.append((type, Array(data[start..<end])))
            if start + length > data.count { break }
            i = start + length
        }
        return result
    }

    /// 製造者データ全体から AirPods の電池を読む
    static func parse(manufacturerData data: [UInt8], swapSides: Bool = false) -> Reading? {
        for message in messages(inManufacturerData: data) where message.type == messageType {
            if let reading = parse(payload: message.payload, swapSides: swapSides) {
                return reading
            }
        }
        return nil
    }

    /// 種類 0x07 の中身を読む
    static func parse(payload p: [UInt8], swapSides: Bool = false) -> Reading? {
        guard p.count >= 6 else { return nil }
        let model = (UInt16(p[1]) << 8) | UInt16(p[2])
        // 種類 0x07 は AirPods 以外の Apple 製品も使う。実在する機種番号のものだけ読む
        guard AirPodsModel.isKnown(model) else { return nil }
        let status = p[3]
        let battery = p[4]
        let chargeAndCase = p[5]

        // 状態の 0x20 が立っていないときは左右が逆に入っている
        var flipped = (status & 0x20) == 0
        if swapSides { flipped.toggle() }

        let high = Int(battery >> 4)
        let low = Int(battery & 0x0F)
        let leftRaw = flipped ? high : low
        let rightRaw = flipped ? low : high
        let charge = Int(chargeAndCase >> 4)
        let caseRaw = Int(chargeAndCase & 0x0F)

        let leftCharging = charge & (flipped ? 0b010 : 0b001) != 0
        let rightCharging = charge & (flipped ? 0b001 : 0b010) != 0
        let caseCharging = charge & 0b100 != 0

        return Reading(
            model: model,
            left: percent(leftRaw),
            right: percent(rightRaw),
            caseLevel: percent(caseRaw),
            leftCharging: leftCharging,
            rightCharging: rightCharging,
            caseCharging: caseCharging,
            rawHex: hex(p)
        )
    }

    /// 0〜10 を 0〜100% に。それ以外（15 など）は不明
    static func percent(_ raw: Int) -> Int? {
        guard (0...10).contains(raw) else { return nil }
        return raw * 10
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

/// 機種番号と名前・アイコン
struct AirPodsModel: Equatable {
    var code: UInt16
    var name: String
    var symbol: String
    /// AirPods Max のように電池が1つだけの機種
    var singleBattery: Bool

    /// 実在する AirPods・Beats の機種番号か（違えば別の Apple 製品の電波）
    static func isKnown(_ code: UInt16) -> Bool { table[code] != nil }

    static func lookup(_ code: UInt16) -> AirPodsModel {
        if let entry = table[code] {
            return AirPodsModel(code: code, name: entry.0, symbol: entry.1, singleBattery: entry.2)
        }
        return AirPodsModel(code: code, name: String(format: "AirPods / Beats（%04X）", code), symbol: "airpods", singleBattery: false)
    }

    private static let table: [UInt16: (String, String, Bool)] = [
            0x0220: ("AirPods", "airpods", false),
            0x0F20: ("AirPods（第2世代）", "airpods", false),
            0x1320: ("AirPods（第3世代）", "airpods.gen3", false),
            0x1920: ("AirPods 4", "airpods.gen3", false),
            0x1B20: ("AirPods 4（ANC）", "airpods.gen3", false),
            0x0E20: ("AirPods Pro", "airpodspro", false),
            0x1420: ("AirPods Pro（第2世代）", "airpodspro", false),
            0x2420: ("AirPods Pro（第2世代・USB-C）", "airpodspro", false),
            0x2720: ("AirPods Pro 3", "airpodspro", false),
            0x0A20: ("AirPods Max", "airpodsmax", true),
            0x1F20: ("AirPods Max（USB-C）", "airpodsmax", true),
            0x0320: ("Powerbeats3", "beats.powerbeats3", true),
            0x0B20: ("Powerbeats Pro", "beats.powerbeatspro", false),
            0x0C20: ("Beats Solo Pro", "headphones", true),
            0x1120: ("Beats Studio Buds", "beats.studiobuds", false),
            0x1020: ("Beats Flex", "beats.earphones", true),
            0x0520: ("BeatsX", "beats.earphones", true),
            0x0620: ("Beats Solo3", "headphones", true),
            0x0920: ("Beats Studio3", "headphones", true),
            0x1720: ("Beats Studio Buds +", "beats.studiobuds", false),
            0x1220: ("Beats Fit Pro", "beats.fitpro", false),
            0x1620: ("Beats Studio Pro", "headphones", true),
    ]

    /// イヤホンのアイコンに合うケースのアイコン
    static func caseSymbol(for symbol: String) -> String {
        switch symbol {
        case "airpodspro": return "airpodspro.chargingcase.wireless"
        case "airpods.gen3": return "airpods.gen3.chargingcase.wireless"
        case "beats.studiobuds": return "beats.studiobuds.chargingcase"
        case "beats.fitpro": return "beats.fitpro.chargingcase"
        case "beats.powerbeatspro": return "beats.powerbeatspro.chargingcase"
        default: return "airpods.chargingcase.wireless"
        }
    }

    /// 読み取り結果を保存用の更新にする
    func update(from reading: ProximityPairing.Reading, name: String?, date: Date) -> DeviceUpdate {
        var parts: [DeviceUpdate.Part]
        if singleBattery {
            let level = [reading.left, reading.right].compactMap { $0 }.max()
            parts = [.init(id: "main", label: "本体", level: level, charging: reading.leftCharging || reading.rightCharging)]
        } else {
            parts = [
                .init(id: "left", label: "左", level: reading.left, charging: reading.leftCharging),
                .init(id: "right", label: "右", level: reading.right, charging: reading.rightCharging),
                .init(id: "case", label: "ケース", level: reading.caseLevel, charging: reading.caseCharging),
            ]
        }
        return DeviceUpdate(
            id: String(format: "airpods-%04X", code),
            name: name ?? self.name,
            kind: .airpods,
            symbol: symbol,
            components: parts,
            source: "AirPods の電波",
            date: date
        )
    }
}
