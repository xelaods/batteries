import SwiftUI

/// ウィジェットの見本（見た目の確認用）
struct WidgetGalleryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 18) {
                    WidgetPreviewFrame(size: .small) {
                        BatteriesWidgetContent(snapshot: model.snapshot, size: .small, now: Date())
                    }
                    WidgetPreviewFrame(size: .small) {
                        BatteriesWidgetContent(snapshot: single, size: .small, now: Date())
                    }
                }
                WidgetPreviewFrame(size: .medium) {
                    BatteriesWidgetContent(snapshot: model.snapshot, size: .medium, now: Date())
                }
                WidgetPreviewFrame(size: .large) {
                    BatteriesWidgetContent(snapshot: model.snapshot, size: .large, now: Date())
                }
                HStack(spacing: 14) {
                    WidgetPreviewFrame(size: .rectangular) {
                        BatteriesWidgetContent(snapshot: model.snapshot, size: .rectangular, now: Date())
                    }
                    WidgetPreviewFrame(size: .circular) {
                        BatteriesWidgetContent(snapshot: model.snapshot, size: .circular, now: Date())
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("ウィジェット")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 1台だけのときの見本
    private var single: Snapshot {
        var s = model.snapshot
        s.devices = s.devices.filter { $0.kind == .mouse }
        return s
    }
}
