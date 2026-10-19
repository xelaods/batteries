import SwiftUI
import UIKit

/// SF Symbols は OS によって無いものがあるので、無ければ代わりを使う
enum Symbol {
    static func safe(_ name: String, fallback: String = "battery.75percent") -> String {
        UIImage(systemName: name) != nil ? name : fallback
    }
}

enum BatteryStyle {
    static func color(level: Int, charging: Bool) -> Color {
        if charging { return .green }
        if level <= 10 { return .red }
        if level <= 20 { return .orange }
        return .green
    }

    /// 少し前の値かどうか（色を少し落として「最後の値」だと分かるようにする）
    static func isStale(_ date: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(date) > 15 * 60
    }

    /// 「たった今」「12分前」「3時間前」「昨日 21:04」「10/12 21:04」
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return "たった今" }
        if s < 3600 { return "\(Int(s / 60))分前" }
        if s < 6 * 3600 { return "\(Int(s / 3600))時間前" }
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        if cal.isDateInToday(date) { f.dateFormat = "H:mm"; return f.string(from: date) }
        if cal.isDateInYesterday(date) { f.dateFormat = "昨日 H:mm"; return f.string(from: date) }
        f.dateFormat = "M/d H:mm"
        return f.string(from: date)
    }
}

/// 標準のバッテリーウィジェット風の丸いメーター
struct BatteryRing: View {
    var level: Int
    var charging: Bool
    var symbol: String
    var stale: Bool = false
    var lineWidth: CGFloat = 5

    var body: some View {
        let color = BatteryStyle.color(level: level, charging: charging)
        ZStack {
            Circle()
                .stroke(color.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(level, 2)) / 100)
                .stroke(color.opacity(stale ? 0.55 : 1), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: Symbol.safe(symbol))
                .resizable()
                .scaledToFit()
                .padding(lineWidth * 2.8)
                .foregroundStyle(.primary.opacity(stale ? 0.6 : 1))
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Circle().fill(Color.green))
                    .offset(y: -1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// 横長の電池バー
struct BatteryBar: View {
    var level: Int
    var charging: Bool
    var stale: Bool = false

    var body: some View {
        let color = BatteryStyle.color(level: level, charging: charging)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.2))
                Capsule()
                    .fill(color.opacity(stale ? 0.55 : 1))
                    .frame(width: max(geo.size.height, geo.size.width * CGFloat(level) / 100))
            }
        }
    }
}

/// パーセント表示（充電中は稲妻つき）
struct PercentText: View {
    var level: Int
    var charging: Bool

    var body: some View {
        HStack(spacing: 1) {
            if charging {
                Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(.green)
            }
            Text("\(level)").monospacedDigit()
            + Text("%").font(.caption2)
        }
    }
}

enum DemoData {
    static func snapshot(now: Date = Date()) -> Snapshot {
        var s = Snapshot()
        s.devices = [
            DeviceRecord(id: "iphone", name: "iPhone", kind: .iphone, symbol: "iphone",
                         components: [.init(id: "main", label: "本体", level: 64, charging: false, updatedAt: now)],
                         updatedAt: now, source: "iPhone"),
            DeviceRecord(id: "airpods-1420", name: "AirPods Pro（第2世代）", kind: .airpods, symbol: "airpodspro",
                         components: [
                            .init(id: "left", label: "左", level: 80, charging: false, updatedAt: now.addingTimeInterval(-3 * 3600)),
                            .init(id: "right", label: "右", level: 70, charging: false, updatedAt: now.addingTimeInterval(-3 * 3600)),
                            .init(id: "case", label: "ケース", level: 40, charging: false, updatedAt: now.addingTimeInterval(-5 * 3600)),
                         ],
                         updatedAt: now.addingTimeInterval(-3 * 3600), source: "PC（HARUTO-NOTE）"),
            DeviceRecord(id: "pc-haruto-note", name: "HARUTO-NOTE", kind: .computer, symbol: "laptopcomputer",
                         components: [.init(id: "main", label: "本体", level: 18, charging: true, updatedAt: now.addingTimeInterval(-8 * 60))],
                         updatedAt: now.addingTimeInterval(-8 * 60), source: "PC（HARUTO-NOTE）"),
            DeviceRecord(id: "pc-school-pc", name: "SCHOOL-PC", kind: .computer, symbol: "laptopcomputer",
                         components: [.init(id: "main", label: "本体", level: 92, charging: false, updatedAt: now.addingTimeInterval(-50 * 3600))],
                         updatedAt: now.addingTimeInterval(-50 * 3600), source: "PC（SCHOOL-PC）"),
            DeviceRecord(id: "mouse-vxe", name: "VXE マウス", kind: .mouse, symbol: "computermouse",
                         components: [.init(id: "main", label: "本体", level: 55, charging: false, updatedAt: now.addingTimeInterval(-26 * 3600))],
                         updatedAt: now.addingTimeInterval(-26 * 3600), source: "PC（HARUTO-NOTE）"),
        ]
        s.relayTopic = "bat-7k2m9qx4vd8pn3hr"
        s.computers = ["HARUTO-NOTE": now.addingTimeInterval(-8 * 60), "SCHOOL-PC": now.addingTimeInterval(-50 * 3600)]
        s.savedAt = now
        return s
    }
}
