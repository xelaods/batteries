import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    /// スクリーンショット用に、最初に開く画面を起動引数で選べる（-screen diag など）
    private var initialScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    var body: some View {
        NavigationStack {
            switch initialScreen {
            case "connect": ConnectionView()
            case "settings": SettingsView()
            case "gallery": WidgetGalleryView()
            case "detail":
                if let first = model.snapshot.orderedDevices.dropFirst().first {
                    DeviceDetailView(deviceID: first.id)
                }
            default: HomeView()
            }
        }
    }
}
