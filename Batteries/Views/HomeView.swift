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
                            Text("AirPods のケースを開けて iPhone の近くに置き、「今すぐ読み取る」を押してください。")
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
                    Text("接続が切れても、最後に読み取った値を表示し続けます。AirPods はアプリを開いている間だけ読み取れるので、ウィジェットをタップするとアプリが開いて更新されます。")
                }
            }
            .listSectionSpacing(14)
        }
        .navigationTitle("バッテリー")
        .navigationDestination(for: String.self) { id in
            DeviceDetailView(deviceID: id)
        }
        .refreshable {
            model.startScan(seconds: 10)
            try? await Task.sleep(for: .seconds(1.5))
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Image(systemName: "waveform.path.ecg")
                }
                .accessibilityLabel("診断")
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
    }
}

/// 読み取り中かどうかと、Bluetooth の状態
struct ScanStatusRow: View {
    @Environment(AppModel.self) private var model
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if model.scanning {
                    ProgressView()
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("近くの機器を読み取り中…")
                            .font(.subheadline.weight(.medium))
                        Text("AirPods はケースを開けると見つかりやすくなります")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("止める") { model.stopScan() }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                } else {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今すぐ読み取る")
                            .font(.subheadline.weight(.medium))
                        Text(model.lastScanAt.map { "前回 \(BatteryStyle.ago($0, now: now))" } ?? "アプリを開くと自動で読み取ります")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        model.startScan(seconds: 12)
                    } label: {
                        Text("読み取る")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
            }
            if let warning = bluetoothWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var bluetoothWarning: String? {
        switch model.bluetoothState {
        case .poweredOff: return "Bluetooth がオフです。コントロールセンターでオンにしてください。"
        case .unauthorized: return "Bluetooth の使用が許可されていません。設定アプリ › バッテリー で許可してください。"
        case .unsupported: return "この端末では Bluetooth を使えません。"
        default: return nil
        }
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
