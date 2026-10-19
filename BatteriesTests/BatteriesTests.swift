import XCTest
@testable import Batteries

final class ProximityPairingTests: XCTestCase {
    /// 4C 00 | 07 19 | 中身25バイト
    private func ad(_ payload: [UInt8]) -> [UInt8] {
        var p = payload
        while p.count < 25 { p.append(0) }
        return [0x4C, 0x00, 0x07, UInt8(p.count)] + p
    }

    func testParsesLevelsNotFlipped() throws {
        // 状態 0x2B（0x20 が立っている）→ 下位4bit が左、上位4bit が右
        let r = try XCTUnwrap(ProximityPairing.parse(manufacturerData: ad([0x01, 0x14, 0x20, 0x2B, 0x78, 0x54])))
        XCTAssertEqual(r.model, 0x1420)
        XCTAssertEqual(r.left, 80)
        XCTAssertEqual(r.right, 70)
        XCTAssertEqual(r.caseLevel, 40)
        XCTAssertTrue(r.leftCharging)   // 上位4bit 0x5 = 0b101 → bit0 とケース
        XCTAssertFalse(r.rightCharging)
        XCTAssertTrue(r.caseCharging)
        XCTAssertEqual(r.modelInfo.name, "AirPods Pro（第2世代）")
    }

    func testParsesLevelsFlipped() throws {
        // 状態 0x0B（0x20 が立っていない）→ 上位4bit が左
        let r = try XCTUnwrap(ProximityPairing.parse(manufacturerData: ad([0x01, 0x0E, 0x20, 0x0B, 0x78, 0x1A])))
        XCTAssertEqual(r.left, 70)
        XCTAssertEqual(r.right, 80)
        XCTAssertEqual(r.caseLevel, 100)
        XCTAssertFalse(r.leftCharging)  // 上位4bit 0x1：反転時は bit1 が左
        XCTAssertTrue(r.rightCharging)
    }

    func testUnknownValuesAreNil() throws {
        let r = try XCTUnwrap(ProximityPairing.parse(manufacturerData: ad([0x01, 0x0F, 0x20, 0x2B, 0xF9, 0x0F])))
        XCTAssertEqual(r.left, 90)
        XCTAssertNil(r.right)
        XCTAssertNil(r.caseLevel)
    }

    func testSwapSides() throws {
        let r = try XCTUnwrap(ProximityPairing.parse(manufacturerData: ad([0x01, 0x14, 0x20, 0x2B, 0x78, 0x00]), swapSides: true))
        XCTAssertEqual(r.left, 70)
        XCTAssertEqual(r.right, 80)
    }

    func testIgnoresOtherAppleMessages() {
        // 近くの情報（0x10）だけ
        let data: [UInt8] = [0x4C, 0x00, 0x10, 0x05, 0x01, 0x18, 0x1C, 0x5E, 0x2A]
        XCTAssertNil(ProximityPairing.parse(manufacturerData: data))
        XCTAssertEqual(ProximityPairing.messages(inManufacturerData: data).map(\.type), [0x10])
    }

    func testIgnoresOtherCompanies() {
        XCTAssertTrue(ProximityPairing.messages(inManufacturerData: [0x06, 0x00, 0x07, 0x01, 0x00]).isEmpty)
    }

    func testFindsPairingAfterAnotherMessage() throws {
        var data: [UInt8] = [0x4C, 0x00, 0x10, 0x02, 0xAA, 0xBB]
        data += ad([0x01, 0x14, 0x20, 0x2B, 0x55, 0x05]).dropFirst(2)
        let r = try XCTUnwrap(ProximityPairing.parse(manufacturerData: data))
        XCTAssertEqual(r.left, 50)
        XCTAssertEqual(r.caseLevel, 50)
    }

    func testShortPayloadIsIgnored() {
        XCTAssertNil(ProximityPairing.parse(manufacturerData: [0x4C, 0x00, 0x07, 0x03, 0x01, 0x14, 0x20]))
    }
}

final class SnapshotMergeTests: XCTestCase {
    private func airpods(left: Int?, right: Int?, case caseLevel: Int?, at date: Date) -> DeviceUpdate {
        DeviceUpdate(
            id: "airpods-1420", name: "AirPods Pro", kind: .airpods, symbol: "airpodspro",
            components: [
                .init(id: "left", label: "左", level: left, charging: false),
                .init(id: "right", label: "右", level: right, charging: false),
                .init(id: "case", label: "ケース", level: caseLevel, charging: false),
            ],
            source: "test", date: date
        )
    }

    func testKeepsLastValueWhenMissing() {
        var s = Snapshot()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        s.merge(airpods(left: 80, right: 70, case: 40, at: t0))
        // ケースを閉じて耳に付けている：ケースの値が来なくなる
        s.merge(airpods(left: 60, right: 50, case: nil, at: t1))
        let d = s.devices[0]
        XCTAssertEqual(d.component("left")?.level, 60)
        XCTAssertEqual(d.component("case")?.level, 40)
        XCTAssertEqual(d.component("case")?.updatedAt, t0)
        XCTAssertEqual(d.component("left")?.updatedAt, t1)
        XCTAssertEqual(d.updatedAt, t1)
    }

    func testAllMissingDoesNotChangeTime() {
        var s = Snapshot()
        let t0 = Date(timeIntervalSince1970: 1_000)
        s.merge(airpods(left: 80, right: 70, case: 40, at: t0))
        s.merge(airpods(left: nil, right: nil, case: nil, at: Date(timeIntervalSince1970: 5_000)))
        XCTAssertEqual(s.devices[0].updatedAt, t0)
        XCTAssertEqual(s.devices[0].component("right")?.level, 70)
    }

    func testEmptyUpdateDoesNotCreateDevice() {
        var s = Snapshot()
        s.merge(airpods(left: nil, right: nil, case: nil, at: Date()))
        XCTAssertTrue(s.devices.isEmpty)
    }

    func testCustomNameSurvivesUpdates() {
        var s = Snapshot()
        s.merge(airpods(left: 80, right: 70, case: 40, at: Date()))
        s.devices[0].customName = "通学用"
        s.merge(airpods(left: 70, right: 70, case: 40, at: Date()))
        XCTAssertEqual(s.devices[0].displayName, "通学用")
    }

    func testItemsSplitBudsAndCase() {
        var s = Snapshot()
        s.merge(airpods(left: 80, right: 70, case: 40, at: Date()))
        let items = s.items
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].level, 70)
        XCTAssertEqual(items[0].detail, "左 80%・右 70%")
        XCTAssertEqual(items[1].title, "ケース")
        XCTAssertEqual(items[1].level, 40)
    }

    func testSnapshotRoundTrip() throws {
        var s = DemoData.snapshot(now: Date(timeIntervalSince1970: 1_700_000_000))
        s.devices[0].customName = "メイン"
        let data = try SharedStore.encoder.encode(s)
        let back = try SharedStore.decoder.decode(Snapshot.self, from: data)
        XCTAssertEqual(back, s)
    }

    func testAgoText() {
        let now = Date()
        XCTAssertEqual(BatteryStyle.ago(now.addingTimeInterval(-10), now: now), "たった今")
        XCTAssertEqual(BatteryStyle.ago(now.addingTimeInterval(-12 * 60), now: now), "12分前")
        XCTAssertEqual(BatteryStyle.ago(now.addingTimeInterval(-3 * 3600 - 5), now: now), "3時間前")
    }

    func testAbsorbKeepsNewerPerComponent() {
        let t0 = Date(timeIntervalSince1970: 1_000), t1 = Date(timeIntervalSince1970: 2_000)
        var app = Snapshot()
        app.merge(airpods(left: 80, right: 70, case: 40, at: t1))
        var widget = Snapshot()
        widget.merge(airpods(left: 10, right: 10, case: 90, at: t0))
        widget.devices[0].components[2].updatedAt = Date(timeIntervalSince1970: 3_000)
        app.absorb(widget)
        XCTAssertEqual(app.devices[0].component("left")?.level, 80)
        XCTAssertEqual(app.devices[0].component("case")?.level, 90)
    }
}

final class RelayTests: XCTestCase {
    private func line(time: Double, _ body: String) -> String {
        let escaped = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "{\"id\":\"x\",\"time\":\(Int(time)),\"event\":\"message\",\"topic\":\"bat-test1234\",\"message\":\"\(escaped)\"}"
    }

    func testParseAndApply() {
        let a = #"{"v":1,"pc":"NOTE","at":2000,"devices":[{"id":"pc-note","name":"NOTE","kind":"computer","symbol":"laptopcomputer","parts":[{"id":"main","level":81,"charging":true,"at":2000}]},{"id":"airpods-1420","kind":"airpods","model":5152,"parts":[{"id":"left","level":80,"at":1900},{"id":"right","level":70,"at":1900},{"id":"case","level":40,"at":1500}]}]}"#
        // 別の PC が、もっと前に読んだ AirPods の値を後から送ってきた
        let b = #"{"v":1,"pc":"DESK","at":2100,"devices":[{"id":"airpods-1420","kind":"airpods","model":5152,"parts":[{"id":"left","level":10,"at":1000},{"id":"case","level":90,"at":1800}]}]}"#
        let text = [line(time: 2000, a), #"{"id":"k","time":2050,"event":"keepalive","topic":"t"}"#, line(time: 2100, b)].joined(separator: "\n")
        let received = RelayClient.parse(Data(text.utf8))
        XCTAssertEqual(received.count, 2)

        var s = Snapshot()
        RelayClient.apply(received, to: &s)
        let pc = s.devices.first { $0.id == "pc-note" }
        XCTAssertEqual(pc?.component("main")?.level, 81)
        XCTAssertEqual(pc?.component("main")?.charging, true)
        let pods = s.devices.first { $0.id == "airpods-1420" }
        XCTAssertEqual(pods?.name, "AirPods Pro（第2世代）")
        XCTAssertEqual(pods?.component("left")?.level, 80)   // 古い値（at 1000）は無視
        XCTAssertEqual(pods?.component("case")?.level, 90)   // 新しい値（at 1800）は採用
        XCTAssertEqual(s.computers?.count, 2)
    }

    func testSingleBatteryModel() {
        let msg = RelayMessage(v: 1, pc: "NOTE", at: 100, devices: [
            .init(id: "airpods-0A20", name: nil, kind: "airpods", symbol: nil, model: 0x0A20, parts: [
                .init(id: "left", label: nil, level: 60, charging: false, at: 100),
            ]),
        ])
        let u = msg.updates()
        XCTAssertEqual(u.first?.components.map(\.id), ["main"])
        XCTAssertEqual(u.first?.components.first?.level, 60)
    }

    func testNormalizeTopic() {
        XCTAssertEqual(RelayClient.normalizeTopic("batteries://pair?code=bat-7k2m9qx4vd8pn3hr"), "bat-7k2m9qx4vd8pn3hr")
        XCTAssertEqual(RelayClient.normalizeTopic(" BAT-7K2M 9QX4 VD8P N3HR "), "bat-7k2m9qx4vd8pn3hr")
        XCTAssertNil(RelayClient.normalizeTopic("abc"))
        XCTAssertNil(RelayClient.normalizeTopic("bat-日本語のコード"))
    }

    func testOldSnapshotStillDecodes() throws {
        let json = #"{"devices":[],"savedAt":"2026-10-19T00:00:00Z"}"#
        let s = try SharedStore.decoder.decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertNil(s.relayTopic)
    }

    func testRenamedPcIsMerged() {
        // 古い版：名前から ID を作っていた（最初は MACHINE、名前を変えて NOTE）
        let old1 = #"{"v":1,"pc":"MACHINE","at":1000,"devices":[{"id":"pc-machine","name":"MACHINE","kind":"computer","parts":[{"id":"main","level":50,"at":1000}]}]}"#
        let old2 = #"{"v":1,"pc":"NOTE","at":2000,"devices":[{"id":"pc-note","name":"NOTE","kind":"computer","parts":[{"id":"main","level":60,"at":2000}]}]}"#
        // 新しい版：変わらない ID と、前の ID・名前を一緒に送る
        let new = #"{"v":1,"pc":"NOTE","pcId":"machine","formerIds":["pc-note"],"formerNames":["MACHINE"],"at":3000,"devices":[{"id":"pc-machine","name":"NOTE","kind":"computer","parts":[{"id":"main","level":70,"at":3000}]}]}"#
        let text = [line(time: 1000, old1), line(time: 2000, old2), line(time: 3000, new)].joined(separator: "\n")
        var s = Snapshot()
        RelayClient.apply(RelayClient.parse(Data(text.utf8)), to: &s)
        let pcs = s.devices.filter { $0.kind == .computer }
        XCTAssertEqual(pcs.count, 1)
        XCTAssertEqual(pcs.first?.id, "pc-machine")
        XCTAssertEqual(pcs.first?.name, "NOTE")
        XCTAssertEqual(pcs.first?.component("main")?.level, 70)
        XCTAssertEqual(s.computers?.keys.sorted(), ["machine"])
        XCTAssertEqual(s.computerNames?["machine"], "NOTE")

        // 中継に残っていた古いメッセージをもう一度受け取っても、2台に戻らない
        let replay = [line(time: 1000, old1), line(time: 2000, old2), line(time: 3000, new)].joined(separator: "\n")
        RelayClient.apply(RelayClient.parse(Data(replay.utf8)), to: &s)
        XCTAssertEqual(s.devices.filter { $0.kind == .computer }.count, 1)
        XCTAssertEqual(s.computers?.keys.sorted(), ["machine"])
        XCTAssertEqual(s.computerNames?["machine"], "NOTE")
        XCTAssertEqual(s.devices.first { $0.kind == .computer }?.component("main")?.level, 70)
    }
}
