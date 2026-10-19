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

final class BatteryCenterTests: XCTestCase {
    func testGroupsAirPodsParts() {
        let entries: [BatteryCenterReader.Entry] = [
            .init(id: "a", name: "AirPods Pro", level: 80, charging: false, isInternal: false, part: "left", summary: ""),
            .init(id: "b", name: "AirPods Pro", level: 70, charging: true, isInternal: false, part: "right", summary: ""),
            .init(id: "c", name: "AirPods Pro", level: 40, charging: false, isInternal: false, part: "case", summary: ""),
            .init(id: "d", name: "iPhone", level: 50, charging: false, isInternal: true, part: nil, summary: ""),
            .init(id: "e", name: "Magic Keyboard", level: 33, charging: false, isInternal: false, part: nil, summary: ""),
        ]
        let updates = BatteryCenterReader.updates(from: entries, date: Date())
        XCTAssertEqual(updates.count, 2)
        let pods = updates.first { $0.name == "AirPods Pro" }!
        XCTAssertEqual(pods.kind, .airpods)
        XCTAssertEqual(Set(pods.components.map(\.id)), ["left", "right", "case"])
        var s = Snapshot()
        for u in updates { s.merge(u) }
        XCTAssertEqual(s.items.count, 3) // イヤホン・ケース・キーボード
    }

    func testUnknownPartsStillShown() {
        let entries: [BatteryCenterReader.Entry] = [
            .init(id: "a", name: "AirPods", level: 80, charging: false, isInternal: false, part: nil, summary: ""),
            .init(id: "b", name: "AirPods", level: 60, charging: false, isInternal: false, part: nil, summary: ""),
        ]
        var s = Snapshot()
        for u in BatteryCenterReader.updates(from: entries, date: Date()) { s.merge(u) }
        XCTAssertEqual(s.items.count, 2)
    }
}
