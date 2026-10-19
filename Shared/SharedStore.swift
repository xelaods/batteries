import Foundation
import EventKit

/// 保存場所。App Group が使える署名ならアプリとウィジェットで同じ場所を使い、
/// 使えない署名（普段の署名ツール）ならカレンダーのメモ経由でウィジェットに渡す。
enum SharedStore {
    static let appGroupID: String? = {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }()

    static var groupContainer: URL? {
        guard let id = appGroupID else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// App Group が実際に使えるか（署名に App Group が入っているか）
    static var isShared: Bool { groupContainer != nil }

    static var snapshotURL: URL {
        let base = groupContainer
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("batteries.json")
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// アプリ側：自分の保存場所から読む
    static func loadForApp() -> Snapshot {
        if let data = try? Data(contentsOf: snapshotURL),
           let s = try? decoder.decode(Snapshot.self, from: data) {
            return s
        }
        return Snapshot()
    }

    /// アプリ側：保存して、必要ならカレンダーにも写す
    static func save(_ snapshot: Snapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        CalendarBridge.write(data)
    }

    /// ウィジェット側：App Group → カレンダーのメモ の順に読み、ウィジェットが自分で読んだ分も合わせる
    static func loadForWidget() -> Snapshot? {
        var base: Snapshot?
        if isShared,
           let data = try? Data(contentsOf: snapshotURL),
           let s = try? decoder.decode(Snapshot.self, from: data) {
            base = s
        } else if let data = CalendarBridge.read(),
                  let s = try? decoder.decode(Snapshot.self, from: data) {
            base = s
        }
        if !isShared, let local = loadWidgetLocal() {
            if base == nil { base = local } else { base?.absorb(local) }
        }
        return base
    }

    /// ウィジェットが自分で読んだ値を、ウィジェット自身の保存場所（App Group がないとき）に残す
    static var widgetLocalURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("widget-batteries.json")
    }

    static func loadWidgetLocal() -> Snapshot? {
        guard let data = try? Data(contentsOf: widgetLocalURL) else { return nil }
        return try? decoder.decode(Snapshot.self, from: data)
    }

    static func saveFromWidget(_ snapshot: Snapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        if isShared {
            try? data.write(to: snapshotURL, options: .atomic)
        } else {
            try? data.write(to: widgetLocalURL, options: .atomic)
        }
    }
}

/// App Group が使えない署名でもウィジェットに値を渡すための仕組み（MoneyPlan・Shift Note と同じ方法）。
/// 2001年1月3日に終日の予定を1件だけ作り、メモ欄に JSON を入れる（ふだんのカレンダー表示には出てこない日付）。
enum CalendarBridge {
    static let title = "バッテリーの記録"
    static let marker = "[batteries-v1]"

    static var day: Date {
        var c = DateComponents()
        c.year = 2001; c.month = 1; c.day = 3
        return Calendar(identifier: .gregorian).date(from: c) ?? Date(timeIntervalSinceReferenceDate: 2 * 86_400)
    }

    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static var denied: Bool {
        let s = EKEventStore.authorizationStatus(for: .event)
        return s == .denied || s == .restricted || s == .writeOnly
    }

    /// 使うかどうか（設定でオフにできる）
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "calendarBridge") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "calendarBridge") }
    }

    private static func events(in store: EKEventStore) -> [EKEvent] {
        let start = day
        let end = start.addingTimeInterval(86_400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).filter { ($0.notes ?? "").contains(marker) }
    }

    static func read(store: EKEventStore = EKEventStore()) -> Data? {
        guard hasAccess else { return nil }
        for event in events(in: store) {
            guard let notes = event.notes, let range = notes.range(of: marker) else { continue }
            let json = notes[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = json.data(using: .utf8) { return data }
        }
        return nil
    }

    @discardableResult
    static func write(_ data: Data, store: EKEventStore = EKEventStore()) -> Bool {
        guard hasAccess else { return false }
        let existing = events(in: store)
        guard enabled, !SharedStore.isShared else {
            // App Group が使える（またはオフ）ならカレンダーには書かない。前に書いた分は消す
            for e in existing { try? store.remove(e, span: .thisEvent, commit: false) }
            try? store.commit()
            return true
        }
        guard let json = String(data: data, encoding: .utf8) else { return false }
        let notes = "バッテリーアプリのウィジェット用の記録です。消してもアプリのデータは消えません。\n\(marker)\n\(json)"
        let event = existing.first ?? EKEvent(eventStore: store)
        if existing.first == nil {
            guard let calendar = store.defaultCalendarForNewEvents
                    ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications }) else { return false }
            event.calendar = calendar
            event.title = title
            event.isAllDay = true
            event.startDate = day
            event.endDate = day
        }
        guard event.notes != notes else { return true }
        event.notes = notes
        do {
            try store.save(event, span: .thisEvent, commit: true)
            for e in existing.dropFirst() { try? store.remove(e, span: .thisEvent, commit: false) }
            try? store.commit()
            return true
        } catch {
            return false
        }
    }

    static func clear(store: EKEventStore = EKEventStore()) {
        guard hasAccess else { return }
        for e in events(in: store) { try? store.remove(e, span: .thisEvent, commit: false) }
        try? store.commit()
    }
}
