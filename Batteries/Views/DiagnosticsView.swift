import SwiftUI
import CoreBluetooth

/// AirPods の電波が受け取れているかを確かめる画面
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.diagnostics
        List {
            Section {
                Button {
                    if model.scanning { model.stopScan() } else { model.startScan(seconds: 30) }
                } label: {
                    HStack {
                        Label(model.scanning ? "止める" : "30秒間 調べる", systemImage: model.scanning ? "stop.circle" : "play.circle")
                        Spacer()
                        if model.scanning { ProgressView() }
                    }
                }
            } footer: {
                Text("AirPods のケースを開けて iPhone のすぐ横に置いた状態で調べてください。")
            }

            Section("結果") {
                LabeledContent("Bluetooth", value: stateText(model.bluetoothState))
                LabeledContent("受け取った電波", value: "\(d.totalAds)")
                LabeledContent("Apple の電波", value: "\(d.appleAds)")
                LabeledContent("AirPods の信号", value: "\(d.pairingAds)")
                if let last = d.lastPairingAt {
                    LabeledContent("最後に受け取った時刻", value: last.formatted(date: .omitted, time: .standard))
                }
            }

            Section {
                Text(verdict(d))
                    .font(.subheadline)
            } header: {
                Text("判定")
            }

            Section {
                let list = d.candidates.values.sorted { $0.rssi > $1.rssi }
                if list.isEmpty {
                    Text("まだ見つかっていません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(list) { c in
                        CandidateRow(candidate: c)
                    }
                }
            } header: {
                Text("見つかった AirPods・Beats")
            } footer: {
                Text("電波の強さが \(model.rssiThreshold) dBm 以上で、同じ機種の中でいちばん強いものを自分の機器として記録します（設定で変えられます）。")
            }

            if !d.typeCounts.isEmpty {
                Section("Apple の電波の内訳") {
                    ForEach(d.typeCounts.sorted { $0.value > $1.value }, id: \.key) { entry in
                        LabeledContent(String(format: "0x%02X ", entry.key) + ScanDiagnostics.typeName(entry.key), value: "\(entry.value)")
                    }
                }
            }
        }
        .navigationTitle("診断")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stateText(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: return "オン"
        case .poweredOff: return "オフ"
        case .unauthorized: return "許可されていません"
        case .unsupported: return "使えません"
        case .resetting: return "再起動中"
        default: return "確認中"
        }
    }

    private func verdict(_ d: ScanDiagnostics) -> String {
        if d.startedAt == nil { return "「30秒間 調べる」を押してください。" }
        if d.pairingAds > 0 {
            if d.candidates.values.contains(where: \.accepted) {
                return "AirPods の電池を読み取れています。"
            }
            return "AirPods の信号は届いていますが、電波が弱いため自分の機器として記録していません。もっと近づけるか、設定で強さの基準を下げてください。"
        }
        if d.appleAds > 0 {
            return "Apple の電波は届いていますが、AirPods の信号はまだありません。ケースを開けた状態で続けて調べてください。30秒たっても 0 のままなら、iOS がこの信号をアプリに渡していない可能性が高いです。"
        }
        if d.totalAds > 0 {
            return "電波は受け取れていますが、Apple の機器のものはまだありません。"
        }
        return "まだ電波を受け取っていません。Bluetooth がオンか確認してください。"
    }
}

struct CandidateRow: View {
    var candidate: ScanDiagnostics.Candidate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: Symbol.safe(candidate.model.symbol))
                Text(candidate.model.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if candidate.accepted {
                    Text("記録")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.2)))
                        .foregroundStyle(.green)
                }
                Text("\(candidate.rssi) dBm")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(levelsText)
                .font(.caption)
            Text(candidate.reading.rawHex)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("\(candidate.count) 回受信")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var levelsText: String {
        func f(_ v: Int?, _ c: Bool) -> String { v.map { "\($0)%\(c ? "⚡︎" : "")" } ?? "—" }
        let r = candidate.reading
        return "左 \(f(r.left, r.leftCharging))　右 \(f(r.right, r.rightCharging))　ケース \(f(r.caseLevel, r.caseCharging))"
    }
}
