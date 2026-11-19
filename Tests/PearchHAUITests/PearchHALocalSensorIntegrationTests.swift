import Foundation
import XCTest
import PearchHACore
import PearchHAAppShell
import PearchHAPersistence
import PearchHASupport
@testable import PearchHAUI

@MainActor
final class PearchHALocalSensorIntegrationTests: XCTestCase {
    func testLocalSelectionSurvivesHomeAssistantFailureAndSignOutWithoutRemoteRequests() async throws {
        let requests = LocalSensorRequests()
        let model = PearchHAPanelModel(
            connector: { _ in .failure(.unreachable(host: "example.invalid")) },
            historyProvider: { _, _, _ in await requests.recordRemote(); return .unavailable("unexpected") },
            localSensorProvider: { keys in await requests.sample(keys) }
        )
        await model.startLocalSensors()
        XCTAssertTrue(model.snapshot.rooms.isEmpty, "Local sensors must be opt-in")
        let cpu = LocalMacSensor.cpuUsage.entityID
        model.setEntity(cpu, isSelected: true)
        model.setMenuBarEntity(cpu, isVisible: true)
        await model.refreshLocalSensors()
        XCTAssertEqual(model.snapshot.rooms.flatMap(\.entities).map(\.id), [cpu])
        XCTAssertTrue(model.snapshot.isLocalOnly)
        XCTAssertFalse(model.applyLiveState(EntityState(id: cpu, name: "Wrong source", state: "99", unit: "%")))
        XCTAssertEqual(model.snapshot.rooms.first?.entities.first?.state, "25")
        model.updateConnectionForm(urlString: "https://example.invalid", token: "test-token")
        await model.connect()
        let entity = try XCTUnwrap(model.snapshot.rooms.first?.entities.first)
        XCTAssertEqual(model.formattedValue(for: entity).status, .available)
        XCTAssertTrue(PearchHAEntityControlField.controls(for: entity).isEmpty)
        XCTAssertNil(model.snapshot.control(for: entity))
        await model.loadHistory(cpu)
        model.signOut()
        XCTAssertEqual(model.snapshot.rooms.flatMap(\.entities).map(\.id), [cpu])
        XCTAssertTrue(model.snapshot.menuBarDisplayConfiguration.isPromoted(cpu))
        let remoteCount = await requests.remoteCount
        XCTAssertEqual(remoteCount, 0)
        let menu = PearchHAMenuBarPresenter().presentations(configuration: .empty, panelSnapshot: model.snapshot)
        XCTAssertEqual(menu.first?.entityID, cpu)
        XCTAssertFalse(menu.first?.title.contains("Stale") ?? true)
        model.stopLocalSensors()
    }

    func testLocalDiscoveryDoesNotReplaceHomeAssistantSelectionOrPromotions() async {
        let remote = DiscoveredEntity(id: "sensor.room", name: "Room", state: "21", unit: "°C", areaID: nil, deviceID: nil)
        let room = Room(id: "room", name: "Room", entities: [remote])
        let model = PearchHAPanelModel(
            connector: { _ in .success(rooms: [room]) },
            localSensorProvider: { _ in ["cpu_usage": "25", "memory_usage": "50", "thermal_state": "nominal"] }
        )
        model.updateConnectionForm(urlString: "https://example.invalid", token: "test-token")
        await model.connect()
        await model.startLocalSensors()
        XCTAssertEqual(model.snapshot.rooms.flatMap(\.entities).map(\.id), [remote.id])
        let cpu = LocalMacSensor.cpuUsage.entityID
        model.setEntity(cpu, isSelected: true)
        model.setMenuBarEntity(cpu, isVisible: true)
        await model.refresh()
        XCTAssertEqual(Set(model.snapshot.rooms.flatMap(\.entities).map(\.id)), [remote.id, cpu])
        XCTAssertTrue(model.snapshot.menuBarDisplayConfiguration.isPromoted(cpu))
        XCTAssertFalse(model.snapshot.availableRooms.flatMap(\.entities).contains { $0.id == LocalMacSensor.batteryLevel.entityID })
        XCTAssertTrue(model.moveRoom(LocalMacSensor.roomID, direction: .up))
        XCTAssertEqual(model.snapshot.rooms.first?.id, LocalMacSensor.roomID)
        await model.refreshLocalSensors()
        XCTAssertEqual(model.snapshot.rooms.first?.id, LocalMacSensor.roomID)
        model.stopLocalSensors()
    }

    func testSamplingRunsWhilePanelIsClosedAndStopsWhenLastConsumerIsRemoved() async {
        let clock = TestPearchClock()
        let requests = LocalSensorRequests()
        let model = PearchHAPanelModel(localSensorProvider: { await requests.sample($0) }, clock: clock)
        await model.startLocalSensors()
        for _ in 0..<100 { await Task.yield() }
        let initial = await requests.requestCount
        _ = await clock.advance(by: .seconds(20))
        for _ in 0..<100 { await Task.yield() }
        let idle = await requests.requestCount
        XCTAssertEqual(idle, initial)

        model.setMenuBarEntity(LocalMacSensor.cpuUsage.entityID, isVisible: true)
        for _ in 0..<1000 {
            if await clock.sleepingTaskCount() > 0 { break }
            await Task.yield()
        }
        let before = await requests.requestCount
        _ = await clock.advance(by: .seconds(5))
        for _ in 0..<1000 {
            if await requests.requestCount > before { break }
            await Task.yield()
        }
        let refreshed = await requests.requestCount
        XCTAssertGreaterThan(refreshed, before)
        XCTAssertFalse(model.isPanelActive)
        let keys = await requests.lastMetrics
        XCTAssertEqual(keys, ["cpu_usage"])

        model.setMenuBarEntity(LocalMacSensor.cpuUsage.entityID, isVisible: false)
        for _ in 0..<100 { await Task.yield() }
        let stopped = await requests.requestCount
        _ = await clock.advance(by: .seconds(20))
        for _ in 0..<100 { await Task.yield() }
        let after = await requests.requestCount
        XCTAssertEqual(after, stopped)
        model.stopLocalSensors()
    }

    func testTranslationsKeepStableIdentifiersAndLocalStateFormatting() {
        let de = Locale(identifier: "de_DE")
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(LocalMacText.thisMac.localized(locale: de), "Dieser Mac")
        XCTAssertEqual(LocalMacText.thisMac.localized(locale: en), "This Mac")
        let sensor = LocalMacSensor.thermalState
        let entity = sensor.entity(state: "nominal")
        XCTAssertEqual(EntityValueFormatter(locale: de).format(entity).text, "Normal")
        XCTAssertEqual(EntityValueFormatter(locale: en).format(entity).text, "Normal")
        XCTAssertEqual(sensor.entityID.source, .thisMac)
        XCTAssertEqual(EntityID("sensor.cpu_usage").source, .homeAssistant)
        XCTAssertEqual(entity.id, sensor.entityID)
        for key in LocalMacText.allCases {
            XCTAssertNotEqual(key.localized(locale: de), key.rawValue)
            XCTAssertNotEqual(key.localized(locale: en), key.rawValue)
        }
        for metric in LocalMacSensor.allCases {
            XCTAssertNotEqual(metric.entity(state: "unknown").name, metric.rawValue)
            XCTAssertFalse(metric.symbol.isEmpty)
            XCTAssertFalse(metric.explanation.isEmpty)
        }
        let charging = LocalMacSensor.batteryCharging.entity(state: "on")
        XCTAssertEqual(EntityValueFormatter(locale: de).format(charging).text, "Wird geladen")
        XCTAssertEqual(EntityValueFormatter(locale: en).format(charging).text, "Charging")
        XCTAssertEqual(EntityValueFormatter(locale: de).format(LocalMacSensor.cpuUsage.entity(state: "unavailable")).text, "Nicht verfügbar")
        XCTAssertEqual(EntityValueFormatter(locale: Locale(identifier: "fr_FR")).format(charging).text, "Charging")
    }

    func testNewerLocalSampleWinsWhenNotificationsOverlapPeriodicSampling() async {
        let source = DelayedLocalSensorSource()
        let model = PearchHAPanelModel(localSensorProvider: { await source.sample($0) })
        await model.startLocalSensors()
        model.setEntity(LocalMacSensor.cpuUsage.entityID, isSelected: true)
        for _ in 0..<1000 {
            if await source.isWaiting(2) { break }
            await Task.yield()
        }
        let latest = Task { await model.refreshLocalSensors() }
        for _ in 0..<1000 {
            if await source.isWaiting(3) { break }
            await Task.yield()
        }
        await source.complete(3, value: "70")
        await latest.value
        await source.complete(2, value: "10")
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(model.snapshot.rooms.first?.entities.first?.state, "70")
        model.stopLocalSensors()
    }
}

private actor LocalSensorRequests {
    var remoteCount = 0
    var requestCount = 0
    var lastMetrics: Set<String> = []
    func recordRemote() { remoteCount += 1 }
    func sample(_ keys: Set<String>) -> [String: String] {
        requestCount += 1
        lastMetrics = keys
        return ["cpu_usage": "25", "memory_usage": "50", "thermal_state": "nominal"].filter { keys.contains($0.key) }
    }
}

private actor DelayedLocalSensorSource {
    var count = 0
    var waiting: [Int: CheckedContinuation<[String: String], Never>] = [:]
    func sample(_ keys: Set<String>) async -> [String: String] {
        guard !keys.isEmpty else { return [:] }
        count += 1
        if count == 1 { return ["cpu_usage": "0", "memory_usage": "50", "thermal_state": "nominal"] }
        return await withCheckedContinuation { waiting[count] = $0 }
    }
    func isWaiting(_ id: Int) -> Bool { waiting[id] != nil }
    func complete(_ id: Int, value: String) { waiting.removeValue(forKey: id)?.resume(returning: ["cpu_usage": value]) }
}
