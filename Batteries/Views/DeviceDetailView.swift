import SwiftUI

struct DeviceDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var deviceID: String

    @State private var name = ""
    @State private var confirmDelete = false

    private var device: DeviceRecord? { model.snapshot.devices.first { $0.id == deviceID } }

    var body: some View {
        Group {
            if let device {
                List {
                    Section {
                        TextField(device.name, text: $name)
                            .submitLabel(.done)
                            .onSubmit { model.rename(deviceID, to: name) }
                    } header: {
                        Text("名前")
                    } footer: {
                        Text("空にすると自動の名前（\(device.name)）に戻ります。")
                    }

                    Section("電池") {
                        ForEach(device.knownComponents) { part in
                            HStack {
                                Text(part.label)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    PercentText(level: part.level ?? 0, charging: part.charging)
                                        .font(.body.weight(.semibold))
                                    Text(part.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section {
                        LabeledContent("読み取り方法", value: device.source)
                        LabeledContent("最後に受け取った時刻", value: device.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }

                    Section {
                        Button("この機器の記録を消す", role: .destructive) {
                            confirmDelete = true
                        }
                    } footer: {
                        Text("次に読み取ったとき、また自動で追加されます。")
                    }
                }
                .navigationTitle(device.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear { name = device.customName ?? "" }
                .onDisappear { model.rename(deviceID, to: name) }
                .confirmationDialog("この機器の記録を消しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("消す", role: .destructive) {
                        dismiss()
                        model.delete(deviceID)
                    }
                }
            } else {
                ContentUnavailableView("記録がありません", systemImage: "battery.0percent")
            }
        }
    }
}
