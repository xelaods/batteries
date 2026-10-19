import SwiftUI
import CoreBluetooth

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            List {
                Section {
                    ScanStatusRow(now: context.date)
                }

                if model.snapshot.devices.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("まだ記録がありません", systemImage: "battery.0percent")
                        } description: {
                            Text("PC の常駐アプリとつなぐと、AirPods・PC・マウスの残量がここに並びます。")
                        }
                    }
                } else {
                    ForEach(model.snapshot.orderedDevices) { device in
                        Section {
                            NavigationLink(value: device.id) {
                                DeviceCard(device: device, now: context.date)
                            }
                        }
                    }
                }

                Section {
                } footer: {
                    Text("接続が切れても、最後に受け取った値を表示し続けます。ウィジェットも自分で PC の値を受け取りに行きます（間隔は iOS が決めます）。")
                }
            }
            .listSectionSpacing(14)
        }
        .navigationTitle("バッテリー")
        .navigationDestination(for: String.self) { id in
            DeviceDetailView(deviceID: id)
        }
        .refreshable {
            await model.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    ConnectionView()
                } label: {
                    Image(systemName: "laptopcomputer.and.iphone")
                }
                .accessibilityLabel("PC 連携")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("設定")
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .alert("PC とつながりました", isPresented: Binding(get: { model.pairedJustNow }, set: { model.pairedJustNow = $0 })) {
            Button("OK") {}
        } message: {
            Text("PC から届いた残量を受け取ります。")
        }
    }
}

/// PC からの受け取りの状態
struct ScanStatusRow: View {
    @Environment(AppModel.self) private var model
    var now: Date

    var body: some View {
        if model.relayTopic == nil {
            NavigationLink {
                ConnectionView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PC とつなぐ")
                            .font(.subheadline.weight(.medium))
                        Text("AirPods・PC・マウスの残量は PC から受け取ります")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        } else {
            HStack(spacing: 12) {
                Group {
                    if model.refreshing {
                        ProgressView()
                    } else if model.relayError != nil {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
                .font(.title3)
                .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .disabled(model.refreshing)
                .accessibilityLabel("今すぐ受け取る")
            }
            .padding(.vertical, 2)
        }
    }

    private var title: String {
        if model.refreshing { return "PC から受け取り中…" }
        if model.relayError != nil { return "受け取れませんでした" }
        return "PC と連携中"
    }

    private var subtitle: String {
        if let e = model.relayError { return e }
        let pcs = (model.snapshot.computers ?? [:]).count
        let last = model.lastRefreshAt.map { "前回 \(BatteryStyle.ago($0, now: now))" } ?? "下に引っぱると受け取ります"
        return pcs > 0 ? "\(pcs)台の PC・\(last)" : last
    }
}

/// 1台分のカード
struct DeviceCard: View {
    var device: DeviceRecord
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: Symbol.safe(device.symbol))
                    .font(.title3)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 18) {
                ForEach(device.knownComponents) { part in
                    componentView(part)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        if BatteryStyle.isStale(device.updatedAt, now: now) {
            return "最後の値・\(BatteryStyle.ago(device.updatedAt, now: now))"
        }
        return "最新・\(device.source)"
    }

    private func componentView(_ part: BatteryComponent) -> some View {
        let level = part.level ?? 0
        let stale = BatteryStyle.isStale(part.updatedAt, now: now)
        return VStack(spacing: 4) {
            BatteryRing(level: level, charging: part.charging, symbol: symbol(for: part), stale: stale, lineWidth: 5)
                .frame(width: 54, height: 54)
            PercentText(level: level, charging: part.charging)
                .font(.subheadline.weight(.semibold))
            if device.knownComponents.count > 1 {
                Text(part.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func symbol(for part: BatteryComponent) -> String {
        guard device.kind == .airpods else { return device.symbol }
        switch part.id {
        case "left": return Symbol.safe(device.symbol == "airpodspro" ? "airpodpro.left" : "airpod.left", fallback: device.symbol)
        case "right": return Symbol.safe(device.symbol == "airpodspro" ? "airpodpro.right" : "airpod.right", fallback: device.symbol)
        case "case": return AirPodsModel.caseSymbol(for: device.symbol)
        default: return device.symbol
        }
    }
}
