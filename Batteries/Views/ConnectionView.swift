import SwiftUI
import UIKit

/// PC の常駐アプリとつなぐ画面
struct ConnectionView: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""
    @State private var invalid = false
    @State private var confirmUnpair = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            List {
                if let topic = model.relayTopic {
                    Section {
                        LabeledContent("合言葉") {
                            Text(grouped(topic))
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            HStack {
                                Label("今すぐ受け取る", systemImage: "arrow.clockwise")
                                Spacer()
                                if model.refreshing { ProgressView() }
                            }
                        }
                        .disabled(model.refreshing)
                        if let e = model.relayError {
                            Label(e, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if let last = model.lastRefreshAt {
                            Text("\(BatteryStyle.ago(last, now: context.date))に受け取り（直近12時間で \(model.lastReceivedCount) 件）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("連携中")
                    } footer: {
                        Text("ほかの PC にも、同じ合言葉を入れると同じ iPhone に届きます。")
                    }

                    Section("PC") {
                        let pcs = (model.snapshot.computers ?? [:]).sorted { $0.value > $1.value }
                        if pcs.isEmpty {
                            Text("まだ PC から届いていません。PC の常駐アプリが起動しているか確認してください。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(pcs, id: \.key) { pc in
                                HStack {
                                    Image(systemName: "laptopcomputer")
                                        .frame(width: 28)
                                    Text(pc.key)
                                    Spacer()
                                    Text(BatteryStyle.ago(pc.value, now: context.date))
                                        .font(.subheadline)
                                        .foregroundStyle(BatteryStyle.isStale(pc.value, now: context.date) ? .secondary : .primary)
                                }
                            }
                        }
                    }

                    Section {
                        Button("連携をやめる", role: .destructive) { confirmUnpair = true }
                    }
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            step(1, "PC に「バッテリー送信」アプリを入れて起動します。")
                            step(2, "タスクトレイのアイコンから「iPhone とつなぐ」を開きます。")
                            step(3, "表示された QR コードを iPhone のカメラで読み取ります。読み取れないときは、下に合言葉を入力してください。")
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("つなぎ方")
                    }

                    Section {
                        TextField("例：bat-7k2m 9qx4 vd8p n3hr", text: $input)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit(save)
                        Button("つなぐ", action: save)
                            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("コピーした合言葉を貼り付け") {
                            if let text = UIPasteboard.general.string { input = text; save() }
                        }
                    } header: {
                        Text("合言葉を入力")
                    } footer: {
                        if invalid {
                            Text("合言葉の形が違います。英小文字・数字・ハイフンの8文字以上です。")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section {
                } footer: {
                    Text("PC の常駐アプリは、PC 本体・近くの AirPods・マウスの残量を読み取り、無料の中継サービス ntfy.sh に送ります。合言葉を知っている人だけが読めます。届いた値は12時間ほど中継に残り、iPhone ではずっと最後の値を残します。")
                }
            }
        }
        .navigationTitle("PC 連携")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("連携をやめますか？", isPresented: $confirmUnpair, titleVisibility: .visible) {
            Button("やめる", role: .destructive) { model.clearTopic() }
        } message: {
            Text("これまでに受け取った値は残ります。")
        }
    }

    private func save() {
        invalid = !model.setTopic(input)
        if !invalid { input = "" }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.subheadline)
        }
    }

    /// 読みやすいように4文字ずつ区切る（先頭の bat- はそのまま）
    private func grouped(_ topic: String) -> String {
        guard topic.hasPrefix("bat-") else { return topic }
        let body = Array(topic.dropFirst(4))
        let chunks = stride(from: 0, to: body.count, by: 4).map { String(body[$0..<min($0 + 4, body.count)]) }
        return "bat-" + chunks.joined(separator: " ")
    }
}
