import WidgetKit
import SwiftUI

struct BatteriesEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

struct BatteriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteriesEntry {
        BatteriesEntry(date: Date(), snapshot: DemoData.snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteriesEntry) -> Void) {
        let saved = SharedStore.loadForWidget()
        let snapshot = (context.isPreview && (saved?.devices.isEmpty ?? true)) ? DemoData.snapshot() : saved
        completion(BatteriesEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteriesEntry>) -> Void) {
        let now = Date()
        var snapshot = SharedStore.loadForWidget()
        // ウィジェット自身でも iOS の電池情報を読み、つながっている機器の値を更新する
        let (_, live) = BatteryCenterReader.read()
        let updates = BatteryCenterReader.updates(from: live, date: now)
        if !updates.isEmpty {
            var s = snapshot ?? Snapshot()
            for u in updates { s.merge(u) }
            s.savedAt = now
            SharedStore.saveFromWidget(s)
            snapshot = s
        }
        // 15分ごとに読み直しを頼む（実際の間隔は iOS が決める）。「◯分前」の表示も進める
        let entries = (0..<4).map { i in
            BatteriesEntry(date: now.addingTimeInterval(Double(i) * 5 * 60), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

struct BatteriesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BatteriesEntry

    private var size: WidgetSize {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemLarge, .systemExtraLarge: .large
        case .accessoryRectangular: .rectangular
        case .accessoryCircular: .circular
        case .accessoryInline: .inline
        @unknown default: .medium
        }
    }

    var body: some View {
        content
            .widgetURL(URL(string: "batteries://scan"))
    }

    @ViewBuilder private var content: some View {
        let view = BatteriesWidgetContent(snapshot: entry.snapshot, size: size, now: entry.date)
        switch family {
        case .accessoryCircular:
            view.containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular, .accessoryInline:
            view.containerBackground(for: .widget) { Color.clear }
        default:
            view.containerBackground(for: .widget) { Color("WidgetBackground") }
        }
    }
}

struct BatteriesWidget: Widget {
    let kind = "BatteriesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteriesProvider()) { entry in
            BatteriesWidgetView(entry: entry)
        }
        .configurationDisplayName("バッテリー")
        .description("接続が切れても、最後に読み取った電池残量を表示し続けます。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct BatteriesWidgetBundle: WidgetBundle {
    var body: some Widget {
        BatteriesWidget()
    }
}
