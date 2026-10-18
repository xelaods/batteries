import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeleteAll = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("電波の強さの基準")
                        Spacer()
                        Text("\(model.rssiThreshold) dBm")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(model.rssiThreshold) },
                        set: { model.rssiThreshold = Int($0.rounded()) }
                    ), in: -90...(-40), step: 1) {
                        Text("電波の強さの基準")
                    } minimumValueLabel: {
                        Text("遠く").font(.caption2)
                    } maximumValueLabel: {
                        Text("近く").font(.caption2)
                    }
                }
                Toggle("左右を入れ替える", isOn: $model.swapSides)
            } header: {
                Text("AirPods の読み取り")
            } footer: {
                Text("基準を「近く」に寄せるほど、周りの人の AirPods を拾いにくくなります。自分の AirPods が記録されないときは「遠く」に寄せてください。")
            }

            Section {
                switch model.widgetBridge {
                case .appGroup:
                    Label("App Group で共有中", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .calendar:
                    Label("カレンダー経由で共有中", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .none:
                    Label("ウィジェットに値を渡せていません", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if !SharedStore.isShared {
                    if model.calendarStatus == .notDetermined {
                        Button("カレンダーへのアクセスを許可") {
                            Task { await model.requestCalendarAccess() }
                        }
                    } else if model.calendarStatus != .fullAccess {
                        Button("設定アプリでカレンダーを許可") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                    Toggle("カレンダー経由で渡す", isOn: $model.calendarBridgeEnabled)
                }
            } header: {
                Text("ウィジェット")
            } footer: {
                Text(SharedStore.isShared
                     ? "アプリとウィジェットで同じ保存場所を使っています。"
                     : "署名に App Group が入っていないため、カレンダーの 2001年1月3日にメモを1件だけ保存してウィジェットに渡します（MoneyPlan と同じ方法）。ふだんのカレンダー表示には出てきません。")
            }

            Section {
                Label("ノートPC・マウス（Windows の常駐アプリ）", systemImage: "laptopcomputer")
                    .foregroundStyle(.secondary)
            } header: {
                Text("ほかの機器")
            } footer: {
                Text("次の段階で追加予定です。")
            }

            Section {
                Button("すべての記録を消す", role: .destructive) {
                    confirmDeleteAll = true
                }
            }

            Section {
                LabeledContent("バージョン", value: version)
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完了") { dismiss() }
            }
        }
        .confirmationDialog("すべての記録を消しますか？", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("消す", role: .destructive) { model.deleteAll() }
        }
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v)（\(b)）"
    }
}
