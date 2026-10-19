import SwiftUI
import AppIntents

@main
struct BatteriesApp: App {
    @State private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.handle(url: $0) }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: model.becameActive()
                    case .background: model.becameInactive()
                    default: break
                    }
                }
        }
    }
}

/// ショートカット：アプリを開いて読み取る（オートメーションから使える）
struct RefreshBatteriesIntent: AppIntent {
    static var title: LocalizedStringResource = "バッテリーを更新"
    static var description = IntentDescription("アプリを開いて、PC から届いた電池残量を受け取ります。")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.becameActive()
        return .result()
    }
}

struct BatteriesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RefreshBatteriesIntent(),
            phrases: ["\(.applicationName)を更新"],
            shortTitle: "バッテリーを更新",
            systemImageName: "arrow.clockwise"
        )
    }
}
