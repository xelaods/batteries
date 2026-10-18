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
        let snapshot = SharedStore.loadForWidget()
        let now = Date()
        // 値は同じでも「◯時間前」の表示を進めるため、15分ごとの表示を先に作っておく
        let entries = (0..<12).map { i in
            BatteriesEntry(date: now.addingTimeInterval(Double(i) * 15 * 60), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3 * 3600))))
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
