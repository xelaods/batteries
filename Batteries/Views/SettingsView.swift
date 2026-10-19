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
                NavigationLink {
                    ConnectionView()
                } label: {
                    LabeledContent("PC 連携", value: model.relayTopic == nil ? "未設定" : "\((model.snapshot.computers ?? [:]).count)台")
                }
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
