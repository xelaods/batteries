import SwiftUI

/// ウィジェットの大きさ（WidgetKit の種類をアプリ内でも使えるように置き換えたもの）
enum WidgetSize {
    case small, medium, large, rectangular, circular, inline
}

/// ウィジェットの中身。アプリの「ウィジェットの見本」でも同じものを表示する
struct BatteriesWidgetContent: View {
    var snapshot: Snapshot?
    var size: WidgetSize
    var now: Date

    private var items: [BatteryItem] { snapshot?.items ?? [] }

    var body: some View {
        switch size {
        case .small: small
        case .medium: medium
        case .large: large
        case .rectangular: rectangular
        case .circular: circular
        case .inline: inline
        }
    }

    // MARK: 空のとき

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "battery.0percent")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("アプリを開いて\n読み取ってください")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stale(_ item: BatteryItem) -> Bool { BatteryStyle.isStale(item.updatedAt, now: now) }

    private func isPhone(_ item: BatteryItem) -> Bool {
        snapshot?.devices.first(where: { $0.id == item.deviceID })?.kind == .iphone
    }

    // MARK: 小

    @ViewBuilder private var small: some View {
        if items.isEmpty {
            empty
        } else if items.count == 1, let item = items.first {
            VStack(spacing: 6) {
                BatteryRing(level: item.level, charging: item.charging, symbol: item.symbol, stale: stale(item), lineWidth: 8)
                    .frame(maxWidth: 84)
                PercentText(level: item.level, charging: item.charging)
                    .font(.title3.weight(.semibold))
                Text(stale(item) ? BatteryStyle.ago(item.updatedAt, now: now) : item.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let shown = Array(items.prefix(4))
            Grid(horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    ForEach(shown.prefix(2)) { smallCell($0) }
                }
                if shown.count > 2 {
                    GridRow {
                        ForEach(shown.dropFirst(2)) { smallCell($0) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func smallCell(_ item: BatteryItem) -> some View {
        VStack(spacing: 2) {
            BatteryRing(level: item.level, charging: item.charging, symbol: item.symbol, stale: stale(item), lineWidth: 4.5)
                .frame(width: 46, height: 46)
            Text("\(item.level)%")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(stale(item) ? .secondary : .primary)
        }
    }

    // MARK: 中

    @ViewBuilder private var medium: some View {
        if items.isEmpty {
            empty
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(items.prefix(4)) { item in
                    VStack(spacing: 4) {
                        BatteryRing(level: item.level, charging: item.charging, symbol: item.symbol, stale: stale(item), lineWidth: 6)
                            .frame(width: 58, height: 58)
                        Text("\(item.level)%")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(stale(item) ? BatteryStyle.ago(item.updatedAt, now: now) : item.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: 大

    @ViewBuilder private var large: some View {
        if items.isEmpty {
            empty
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("バッテリー")
                        .font(.headline)
                    Spacer()
                    if let saved = snapshot?.savedAt, saved > .distantPast {
                        Text("記録 \(BatteryStyle.ago(saved, now: now))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(7).enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 40) }
                        largeRow(item)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func largeRow(_ item: BatteryItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Symbol.safe(item.symbol))
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(.primary.opacity(stale(item) ? 0.6 : 1))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    PercentText(level: item.level, charging: item.charging)
                        .font(.subheadline.weight(.semibold))
                }
                BatteryBar(level: item.level, charging: item.charging, stale: stale(item))
                    .frame(height: 5)
                HStack {
                    if let detail = item.detail {
                        Text(detail)
                    }
                    Spacer()
                    Text(stale(item) ? "最後の値・\(BatteryStyle.ago(item.updatedAt, now: now))" : "最新")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: ロック画面

    @ViewBuilder private var rectangular: some View {
        if items.isEmpty {
            Text("バッテリー：未読み取り").font(.caption)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(items.prefix(3)) { item in
                    HStack(spacing: 4) {
                        Image(systemName: Symbol.safe(item.symbol))
                            .frame(width: 16)
                        Text(item.title).lineLimit(1)
                        Spacer(minLength: 2)
                        if item.charging { Image(systemName: "bolt.fill").font(.caption2) }
                        Text("\(item.level)%").monospacedDigit()
                    }
                    .font(.caption)
                    .opacity(stale(item) ? 0.7 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var circular: some View {
        if let item = items.first(where: { !isPhone($0) }) ?? items.first {
            Gauge(value: Double(item.level), in: 0...100) {
                Image(systemName: Symbol.safe(item.symbol))
            } currentValueLabel: {
                Text("\(item.level)")
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Image(systemName: "battery.0percent")
        }
    }

    @ViewBuilder private var inline: some View {
        let others = items.filter { !isPhone($0) }
        if let first = others.first ?? items.first {
            Text("\(first.title) \(first.level)%")
        } else {
            Text("バッテリー：未読み取り")
        }
    }
}

/// アプリ内で見本を表示するときの枠（ホーム画面のウィジェットの大きさ）
struct WidgetPreviewFrame<Content: View>: View {
    var size: WidgetSize
    @ViewBuilder var content: Content

    var body: some View {
        let dims: CGSize = switch size {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        case .rectangular: CGSize(width: 172, height: 76)
        case .circular: CGSize(width: 76, height: 76)
        case .inline: CGSize(width: 250, height: 26)
        }
        content
            .padding(size == .small || size == .medium || size == .large ? 16 : 6)
            .frame(width: dims.width, height: dims.height)
            .background(RoundedRectangle(cornerRadius: size == .circular ? 38 : 22, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}
