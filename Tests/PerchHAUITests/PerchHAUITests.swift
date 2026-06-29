#if canImport(XCTest)
import AppKit
import Foundation
import FakeHA
import XCTest
import PerchHACore
import PerchHAClient
import PerchHAAppShell
import PerchHAPersistence
import PerchHASupport
@testable import PerchHAUI

@MainActor
final class PerchHAUITests: XCTestCase {
    func testPanelSnapshotExposesConnectionStateSummary() {
        let snapshot = PerchHAPanelSnapshot(connectionState: .reconnecting(attempt: 2))

        XCTAssertEqual(snapshot.connectionSummary, "Reconnecting 2")
        XCTAssertEqual(snapshot.accessibilitySummary, "PerchHA reconnecting 2, 0 visible values")
    }

    func test_t_accessibility_summary_reflects_empty_loading_success_and_error_states() {
        let firstRun = PerchHAPanelSnapshot()
        let connecting = PerchHAPanelSnapshot(connectionState: .connecting, phase: .connecting)
        let empty = PerchHAPanelSnapshot(connectionState: .connected, phase: .connectedEmpty)
        let rooms = selectionRooms()
        let success = PerchHAPanelSnapshot(
            connectionState: .connected,
            phase: .connectedData,
            rooms: rooms,
            availableRooms: rooms
        )
        let failed = PerchHAPanelSnapshot(
            connectionState: .failed(.authentication),
            phase: .failed(.authentication)
        )
        let stale = PerchHAPanelSnapshot(
            connectionState: .failed(.unreachable(host: "ha.local")),
            phase: .failedStale(.unreachable(host: "ha.local")),
            rooms: rooms,
            availableRooms: rooms
        )

        XCTAssertEqual(firstRun.accessibilityPresentation().contentLabel, "Connection form")
        XCTAssertEqual(
            firstRun.accessibilityPresentation().keyboardHint,
            "Use Tab to move through connection fields. Return connects."
        )
        XCTAssertEqual(connecting.accessibilityPresentation().contentLabel, "Connecting to Home Assistant")
        XCTAssertEqual(empty.accessibilityPresentation().contentLabel, "Connected, no selected values")
        XCTAssertEqual(success.accessibilityPresentation().summary, "PerchHA connected, 3 visible values")
        XCTAssertEqual(success.accessibilityPresentation().contentLabel, "3 visible values")
        XCTAssertEqual(failed.accessibilityPresentation().statusLabel, "Connection status: Failed: authentication failed")
        XCTAssertEqual(failed.accessibilityPresentation().contentLabel, "Connection failed: authentication failed")
        XCTAssertEqual(
            stale.accessibilityPresentation().contentLabel,
            "Connection failed: unreachable at ha.local, showing stale values"
        )
    }

    func test_t_accessibility_preferences_map_reduce_motion_and_increase_contrast() {
        let defaults = PerchHAPanelSnapshot().accessibilityPresentation()
        let increased = PerchHAPanelSnapshot().accessibilityPresentation(
            preferences: PerchHAAccessibilityPreferences(reduceMotion: true, increaseContrast: true)
        )

        XCTAssertEqual(defaults.motionPolicy, .system)
        XCTAssertEqual(defaults.contrastPolicy, .standard)
        XCTAssertEqual(increased.motionPolicy, .reduced)
        XCTAssertEqual(increased.contrastPolicy, .increased)
    }

    func test_t_accessibility_view_root_surfaces_state_announcements_and_platform_preferences() {
        let snapshot = PerchHAPanelSnapshot(
            connectionState: .failed(.authentication),
            phase: .failed(.authentication)
        )
        let presentation = PerchHAPanelView.rootAccessibilityPresentation(
            snapshot: snapshot,
            preferences: PerchHAAccessibilityPreferences(reduceMotion: true, increaseContrast: true)
        )

        XCTAssertEqual(presentation.label, "PerchHA failed: authentication failed, 0 visible values")
        XCTAssertEqual(
            presentation.value,
            "Connection status: Failed: authentication failed, Connection failed: authentication failed"
        )
        XCTAssertEqual(presentation.hint, "Use Tab to move through connection fields. Return connects.")
        XCTAssertEqual(presentation.motionPolicy, .reduced)
        XCTAssertEqual(presentation.contrastPolicy, .increased)
    }

    func test_t_accessibility_rows_expose_voiceover_labels_for_values_controls_and_failures() {
        let rooms = controlRooms()
        let entities = rooms.flatMap(\.entities)
        guard let officeLamp = entities.first(where: { $0.id == "switch.office_lamp" }),
              let officeBlinds = entities.first(where: { $0.id == "cover.office_blinds" })
        else {
            XCTFail("expected control fixtures")
            return
        }
        let boost = EntityCustomAction(
            id: "boost-office-lamp",
            entityID: officeLamp.id,
            title: "Boost lamp",
            action: ActionSpec(domain: "script", service: "turn_on", targetEntityID: "script.office_boost"),
            requiresConfirmation: true
        )
        let failed = PerchHAPanelSnapshot(
            connectionState: .connected,
            phase: .connectedData,
            rooms: rooms,
            availableRooms: rooms,
            controlActionState: .failed(entityID: officeLamp.id, message: "script failed")
        )
        let running = PerchHAPanelSnapshot(
            connectionState: .connected,
            phase: .connectedData,
            rooms: rooms,
            availableRooms: rooms,
            controlActionState: .running(entityID: officeBlinds.id)
        )

        let lampRow = failed.accessibilityRow(for: officeLamp, customActions: [boost])
        XCTAssertEqual(lampRow.label, "Office lamp, off")
        XCTAssertEqual(lampRow.value, "off")
        XCTAssertEqual(lampRow.failureLabel, "Office lamp control failed: script failed")
        XCTAssertTrue(
            lampRow.controls.contains(
                PerchHAControlAccessibilityPresentation(
                    label: "Turn on Office lamp",
                    hint: "Turns Office lamp on",
                    isEnabled: true
                )
            )
        )
        XCTAssertTrue(
            lampRow.controls.contains(
                PerchHAControlAccessibilityPresentation(
                    label: "Boost lamp",
                    hint: "Asks before running",
                    isEnabled: true
                )
            )
        )

        let coverRow = failed.accessibilityRow(for: officeBlinds)
        XCTAssertEqual(coverRow.label, "Office blinds, open")
        XCTAssertTrue(
            coverRow.controls.contains(
                PerchHAControlAccessibilityPresentation(
                    label: "Open Office blinds",
                    hint: "Opens Office blinds",
                    isEnabled: true
                )
            )
        )
        XCTAssertTrue(
            coverRow.controls.contains(
                PerchHAControlAccessibilityPresentation(
                    label: "Office blinds position",
                    hint: "Current position 42 percent",
                    isEnabled: true
                )
            )
        )

        let runningCoverRow = running.accessibilityRow(for: officeBlinds)
        XCTAssertTrue(
            runningCoverRow.controls.contains(
                PerchHAControlAccessibilityPresentation(
                    label: "Open Office blinds",
                    hint: "Waiting for Home Assistant",
                    isEnabled: false
                )
            )
        )
    }

    func test_t_accessibility_keyboard_reorder_hints_follow_search_and_boundaries() {
        let unfiltered = PerchHAPanelSnapshot()
        let filtered = PerchHAPanelSnapshot(selectionQuery: "humidity")

        XCTAssertTrue(unfiltered.canReorderSelectionWithKeyboard)
        XCTAssertEqual(
            unfiltered.selectionReorderAccessibilityHint(canMove: true, boundaryReason: "Already first"),
            "Changes display order"
        )
        XCTAssertEqual(
            unfiltered.selectionReorderAccessibilityHint(canMove: false, boundaryReason: "Already first"),
            "Already first"
        )
        XCTAssertEqual(
            unfiltered.menuBarReorderAccessibilityHint(canMove: true, boundaryReason: "Already first in menu bar"),
            "Changes menu bar order"
        )
        XCTAssertEqual(
            unfiltered.menuBarReorderAccessibilityHint(canMove: false, boundaryReason: "Already first in menu bar"),
            "Already first in menu bar"
        )

        XCTAssertFalse(filtered.canReorderSelectionWithKeyboard)
        XCTAssertEqual(
            filtered.selectionReorderAccessibilityHint(canMove: false, boundaryReason: "Already first"),
            "Clear search to reorder"
        )
        XCTAssertEqual(
            filtered.menuBarReorderAccessibilityHint(canMove: false, boundaryReason: "Already first in menu bar"),
            "Clear search to reorder"
        )
    }

    func test_t_first_run_connection_failure_states() async {
        let model = PerchHAPanelModel()

        model.updateConnectionForm(urlString: "homeassistant.local:8123", token: "")
        await model.connect()

        XCTAssertEqual(
            model.snapshot.connectionState,
            .failed(.protocolError("invalid Home Assistant URL"))
        )
        XCTAssertEqual(model.snapshot.failureDescription, "invalid Home Assistant URL")
        XCTAssertEqual(model.snapshot.rooms, [])
        XCTAssertFalse(model.snapshot.canRefresh)
    }

    func testFirstRunAuthenticationFailureIsVisible() async {
        let model = PerchHAPanelModel { _ in
            .failure(.authentication)
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "wrong-token")
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .failed(.authentication))
        XCTAssertEqual(model.snapshot.connectionSummary, "Failed: authentication failed")
        XCTAssertEqual(model.snapshot.failureDescription, "authentication failed")
        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        XCTAssertTrue(model.snapshot.hasTokenInput)
        XCTAssertFalse(model.snapshot.canRefresh)
    }

    func testPublicPanelSnapshotNeverExposesAccessToken() async {
        let model = PerchHAPanelModel { _ in
            .failure(.authentication)
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "secret-token")

        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        XCTAssertTrue(model.snapshot.hasTokenInput)
        XCTAssertEqual(model.snapshot.redactedForDiagnostics().connectionForm.token, "")
        XCTAssertTrue(model.snapshot.redactedForDiagnostics().hasTokenInput)

        await model.connect()

        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        XCTAssertTrue(model.snapshot.hasTokenInput)
        XCTAssertEqual(model.snapshot.redactedForDiagnostics().connectionForm.token, "")
        XCTAssertTrue(model.snapshot.redactedForDiagnostics().hasTokenInput)
    }

    func testConnectionFormSelfSignedCertificateAllowanceIsOffByDefaultAndHostScoped() throws {
        let defaultForm = PerchHAConnectionForm(
            urlString: "https://HOMEASSISTANT.local:8123",
            fallbackURLString: "https://fallback.example"
        )
        let enabledForm = PerchHAConnectionForm(
            urlString: "https://HOMEASSISTANT.local:8123",
            fallbackURLString: "https://fallback.example",
            allowsSelfSignedCertificates: true
        )
        let insecureForm = PerchHAConnectionForm(
            urlString: "http://homeassistant.local:8123",
            fallbackURLString: "http://fallback.example",
            allowsSelfSignedCertificates: true
        )

        XCTAssertEqual(defaultForm.selfSignedCertificateHosts(), Set<String>())
        XCTAssertEqual(enabledForm.selfSignedCertificateHosts(), Set(["homeassistant.local", "fallback.example"]))
        XCTAssertEqual(insecureForm.selfSignedCertificateHosts(), Set<String>())
    }

    func testConnectionFormNormalizesFrontendURLsToUsableBaseURLs() {
        let form = PerchHAConnectionForm(
            urlString: " https://HOME.gomoo.io/lovelace/0?dashboard=1#kitchen ",
            fallbackURLString: "https://fallback.example/ha/history?entity=sensor.temp"
        )

        XCTAssertEqual(
            PerchHAConnectionForm.normalizedHomeAssistantURLString(form.urlString),
            "https://home.gomoo.io"
        )
        XCTAssertEqual(
            PerchHAConnectionForm.normalizedHomeAssistantURLString(form.fallbackURLString),
            "https://fallback.example/ha"
        )
        XCTAssertEqual(form.primaryURL()?.absoluteString, "https://home.gomoo.io")
        XCTAssertEqual(form.fallbackURL()?.absoluteString, "https://fallback.example/ha")
    }

    func testConnectionFormKeepsProxyPrefixWhenNoFrontendRouteIsPresent() {
        let form = PerchHAConnectionForm(urlString: "https://homeassistant.local/ha")

        XCTAssertEqual(form.primaryURL()?.absoluteString, "https://homeassistant.local/ha")
    }

    func testPanelConnectionFormForwardsSelfSignedCertificateAllowanceWithoutLeakingToken() async {
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel { form in
            await recorder.record(form)
            return .success(rooms: [])
        }

        model.updateConnectionForm(
            urlString: "https://homeassistant.local:8123",
            fallbackURLString: "https://fallback.example",
            token: "secret-token",
            allowsSelfSignedCertificates: true
        )
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        XCTAssertTrue(model.snapshot.connectionForm.allowsSelfSignedCertificates)
        XCTAssertEqual(await recorder.tokens(), ["secret-token"])
        XCTAssertEqual(await recorder.selfSignedCertificateAllowances(), [true])
    }

    func testStoredAuthSessionConnectsWithoutVisibleToken() async {
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel { form in
            await recorder.record(form)
            return .success(rooms: [])
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", usesStoredAuthSession: true)
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        XCTAssertTrue(model.snapshot.connectionForm.usesStoredAuthSession)
        XCTAssertTrue(model.snapshot.hasTokenInput)
        XCTAssertEqual(await recorder.tokens(), [""])
        XCTAssertEqual(await recorder.usesStoredAuthSessions(), [true])
    }

    func testStoredAuthSessionAuthenticationFailureRequiresReconnect() async {
        let model = PerchHAPanelModel { _ in
            .failure(.authentication)
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", usesStoredAuthSession: true)
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .failed(.authentication))
        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        XCTAssertFalse(model.snapshot.connectionForm.usesStoredAuthSession)
        XCTAssertFalse(model.snapshot.hasTokenInput)
    }

    func test_t_failed_retry_keeps_token_private_and_reuses_visible_token_presence() async {
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel { form in
            await recorder.record(form)
            return .failure(.authentication)
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "secret-token")
        await model.connect()
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        XCTAssertTrue(model.snapshot.hasTokenInput)
        XCTAssertEqual(await recorder.tokens(), ["secret-token", "secret-token"])
    }

    func test_t_non_token_form_edits_preserve_private_token_for_connection() async {
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel { form in
            await recorder.record(form)
            return .success(rooms: [])
        }

        model.updateConnectionForm(token: "secret-token")
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123")
        model.updateConnectionForm(fallbackURLString: "http://127.0.0.1:8124")
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        XCTAssertTrue(model.snapshot.hasTokenInput)
        XCTAssertEqual(await recorder.tokens(), ["secret-token"])
        XCTAssertEqual(await recorder.fallbackURLString(), "http://127.0.0.1:8124")
    }

    func testClearingTokenRemovesPrivateTokenBeforeConnect() async {
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel { form in
            await recorder.record(form)
            return .success(rooms: [])
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "secret-token")
        model.updateConnectionForm(token: "")
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .failed(.authentication))
        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        XCTAssertFalse(model.snapshot.hasTokenInput)
        XCTAssertEqual(await recorder.callCount(), 0)
    }

    func test_t_cancelling_panel_action_ignores_late_connection_result() async {
        let gate = ConnectionGate()
        let model = PerchHAPanelModel { _ in
            await gate.wait()
            return .success(
                rooms: [
                    Room(
                        id: "office",
                        name: "Office",
                        entities: [
                            DiscoveredEntity(
                                id: "sensor.office_temperature",
                                name: "Office temperature",
                                state: "21.4",
                                unit: "°C",
                                areaID: "office",
                                deviceID: nil
                            )
                        ]
                    )
                ]
            )
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "secret-token")
        model.startConnect()
        await spinUntil { model.snapshot.connectionState == .connecting }

        model.cancelInFlightAction()
        await gate.open()
        await Task.yield()

        XCTAssertEqual(model.snapshot.connectionState, .disconnected)
        XCTAssertEqual(model.snapshot.rooms, [])
        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        XCTAssertTrue(model.snapshot.hasTokenInput)
    }

    func testInvalidFallbackURLFailsBeforeConnectionAttempt() async {
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel { form in
            await recorder.record(form)
            return .success(rooms: [])
        }

        model.updateConnectionForm(
            urlString: "http://127.0.0.1:8123",
            fallbackURLString: "fallback.invalid:8123",
            token: "fake-token"
        )
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .failed(.protocolError("invalid fallback URL")))
        XCTAssertEqual(model.snapshot.failureDescription, "invalid fallback URL")
        XCTAssertEqual(await recorder.callCount(), 0)
    }

    func test_t_fallback_url_is_forwarded_to_connector() async {
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel { form in
            await recorder.record(form)
            return .success(rooms: [])
        }

        model.updateConnectionForm(
            urlString: "http://127.0.0.1:8123",
            fallbackURLString: "http://127.0.0.1:8124",
            token: "fake-token"
        )
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertEqual(await recorder.fallbackURLString(), "http://127.0.0.1:8124")
    }

    func test_t_panel_model_connects_against_fakeha() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
            areaRegistryBody: #"[{"area_id":"office","name":"Office"}]"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryBody: #"[{"entity_id":"sensor.office_temperature","name":"Office temperature","area_id":"office"}]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }

        let model = PerchHAPanelModel(connector: fakeHAConnector)
        model.updateConnectionForm(urlString: server.baseURL.absoluteString, token: "fake-token")
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertEqual(model.snapshot.visibleEntityCount, 1)
        XCTAssertEqual(model.snapshot.rooms.map(\.name), ["Office"])
        XCTAssertEqual(model.snapshot.rooms.first?.entities.first?.name, "Office temperature")
        XCTAssertEqual(model.snapshot.rooms.first?.entities.first?.state, "21.4")
        XCTAssertEqual(model.snapshot.lastUpdateDescription, "Initial load complete")
        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        XCTAssertTrue(model.snapshot.hasTokenInput)
    }

    func test_t_panel_applies_selection_config_to_visible_rooms() async {
        let rooms = selectionRooms()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: rooms) },
            selectionConfiguration: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.office_humidity", "switch.kitchen_light"],
                roomOrder: ["kitchen", "office"],
                entityOrder: ["switch.kitchen_light", "sensor.office_humidity"],
                isExplicit: true
            )
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertEqual(model.snapshot.rooms.map(\.id), ["kitchen", "office"])
        XCTAssertEqual(model.snapshot.rooms.flatMap(\.entities).map(\.id), ["switch.kitchen_light", "sensor.office_humidity"])
        XCTAssertEqual(model.snapshot.availableRooms.flatMap(\.entities).count, 3)
    }

    func test_t_history_hover_debounces_before_provider_call() async {
        let clock = TestPerchClock()
        let recorder = HistoryProviderRecorder(
            results: [
                .success(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4))
            ]
        )
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { form, entityID, range in
                await recorder.provide(form: form, entityID: entityID, range: range)
            },
            clock: clock,
            historyDebounce: .seconds(1)
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        model.startHistoryHover("sensor.office_temperature", range: .hour)

        await spinUntil { await clock.sleepingTaskCount() == 1 }
        XCTAssertEqual(await recorder.callCount(), 0)
        XCTAssertEqual(model.snapshot.historyState, .idle)

        _ = await clock.advance(by: .milliseconds(999))
        await Task.yield()
        XCTAssertEqual(await recorder.callCount(), 0)
        XCTAssertEqual(model.snapshot.historyState, .idle)

        _ = await clock.advance(by: .milliseconds(1))
        await spinUntil {
            if case .loaded = model.snapshot.historyState {
                return true
            }
            return false
        }
        XCTAssertEqual(await recorder.callCount(), 1)
        XCTAssertEqual(await recorder.ranges(), [.hour])
        XCTAssertEqual(model.snapshot.historyState.entityID, "sensor.office_temperature")
    }

    func test_t_history_cancel_hover_resets_loading_state() async {
        let recorder = HistoryProviderRecorder(
            results: [
                .success(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4))
            ],
            waitForRelease: true
        )
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { form, entityID, range in
                await recorder.provide(form: form, entityID: entityID, range: range)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        let task = Task { @MainActor in
            await model.loadHistory("sensor.office_temperature", range: .hour)
        }
        await spinUntil {
            if case .loading = model.snapshot.historyState {
                return true
            }
            return false
        }

        model.cancelHistoryHover()
        await recorder.releaseNext()
        await task.value

        XCTAssertEqual(model.snapshot.historyState, .idle)
    }

    func test_t_history_load_uses_default_history_range_when_nil() async {
        let recorder = HistoryProviderRecorder(
            results: [
                .success(historySeries(entityID: "sensor.office_temperature", range: .day, value: 21.4))
            ]
        )
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { form, entityID, range in
                await recorder.provide(form: form, entityID: entityID, range: range)
            },
            menuBarDisplayConfiguration: MenuBarDisplayConfiguration(
                itemConfigurations: [
                    MenuBarItemConfiguration(
                        entityID: "sensor.office_temperature",
                        defaultHistoryRange: .day
                    )
                ]
            )
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        await model.loadHistory("sensor.office_temperature")

        XCTAssertEqual(await recorder.ranges(), [.day])
        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .day, value: 21.4)))
    }

    func test_t_history_cache_reuses_series_until_ttl_expires() async {
        let clock = TestPerchClock()
        let recorder = HistoryProviderRecorder(
            results: [
                .success(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4)),
                .success(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 22.0))
            ]
        )
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { form, entityID, range in
                await recorder.provide(form: form, entityID: entityID, range: range)
            },
            clock: clock,
            historyDebounce: .milliseconds(0),
            historyCacheConfiguration: PerchHAHistoryCacheConfiguration(capacity: 4, ttl: .seconds(5))
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        await model.loadHistory("sensor.office_temperature", range: .hour)
        XCTAssertEqual(await recorder.callCount(), 1)
        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4)))

        await model.loadHistory("sensor.office_temperature", range: .hour)
        XCTAssertEqual(await recorder.callCount(), 1)
        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4)))

        _ = await clock.advance(by: .seconds(6))
        await model.loadHistory("sensor.office_temperature", range: .hour)
        XCTAssertEqual(await recorder.callCount(), 2)
        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 22.0)))
    }

    func test_t_history_reconnect_clears_cached_series_and_visible_history() async {
        let recorder = HistoryProviderRecorder(
            results: [
                .success(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4)),
                .success(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 22.0))
            ]
        )
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { form, entityID, range in
                await recorder.provide(form: form, entityID: entityID, range: range)
            },
            historyCacheConfiguration: PerchHAHistoryCacheConfiguration(capacity: 4, ttl: .seconds(60))
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "first-token")
        await model.connect()
        await model.loadHistory("sensor.office_temperature", range: .hour)

        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4)))

        model.updateConnectionForm(urlString: "http://127.0.0.1:8124", token: "second-token")
        await model.connect()

        XCTAssertEqual(model.snapshot.historyState, .idle)
        XCTAssertNil(model.snapshot.historyPresentationEntityID)

        await model.loadHistory("sensor.office_temperature", range: .hour)

        XCTAssertEqual(await recorder.callCount(), 2)
        XCTAssertEqual(await recorder.tokens(), ["first-token", "second-token"])
        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 22.0)))
    }

    func testHistoryCacheEvictsLeastRecentlyUsedEntryWhenCapacityIsReached() async {
        let recorder = HistoryProviderRecorder(
            results: [
                .success(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4)),
                .success(historySeries(entityID: "sensor.office_temperature", range: .day, value: 21.8)),
                .success(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 22.0))
            ]
        )
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { form, entityID, range in
                await recorder.provide(form: form, entityID: entityID, range: range)
            },
            historyDebounce: .milliseconds(0),
            historyCacheConfiguration: PerchHAHistoryCacheConfiguration(capacity: 1, ttl: .seconds(60))
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        await model.loadHistory("sensor.office_temperature", range: .hour)
        await model.loadHistory("sensor.office_temperature", range: .day)
        await model.loadHistory("sensor.office_temperature", range: .hour)

        XCTAssertEqual(await recorder.callCount(), 3)
        XCTAssertEqual(await recorder.ranges(), [.hour, .day, .hour])
        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 22.0)))
    }

    func test_t_history_hover_out_closes_loaded_and_unavailable_popovers() async {
        let loadedRecorder = HistoryProviderRecorder(
            results: [
                .success(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4))
            ]
        )
        let loadedModel = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { form, entityID, range in
                await loadedRecorder.provide(form: form, entityID: entityID, range: range)
            },
            historyDebounce: .milliseconds(0)
        )
        loadedModel.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await loadedModel.connect()

        loadedModel.startHistoryHover("sensor.office_temperature", range: .hour)
        await spinUntil {
            if case .loaded = loadedModel.snapshot.historyState {
                return true
            }
            return false
        }

        XCTAssertEqual(loadedModel.snapshot.historyPresentationEntityID, "sensor.office_temperature")
        loadedModel.cancelHistoryHover()
        XCTAssertNil(loadedModel.snapshot.historyPresentationEntityID)
        XCTAssertEqual(loadedModel.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4)))

        let unavailableModel = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { _, _, _ in .unavailable("history unavailable") },
            historyDebounce: .milliseconds(0)
        )
        unavailableModel.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await unavailableModel.connect()

        unavailableModel.startHistoryHover("sensor.office_temperature", range: .hour)
        await spinUntil {
            if case .unavailable = unavailableModel.snapshot.historyState {
                return true
            }
            return false
        }

        XCTAssertEqual(unavailableModel.snapshot.historyPresentationEntityID, "sensor.office_temperature")
        unavailableModel.cancelHistoryHover()
        XCTAssertNil(unavailableModel.snapshot.historyPresentationEntityID)
        XCTAssertEqual(
            unavailableModel.snapshot.historyState,
            .unavailable(entityID: "sensor.office_temperature", range: .hour, message: "history unavailable")
        )
    }

    func testHistoryContentSummaryEmptySeriesIsNoNumericData() {
        XCTAssertEqual(
            PerchHAHistoryContentSummary(
                series: HistorySeries(entityID: "sensor.office_temperature", range: .hour, samples: [])
            ),
            .noNumericData
        )
    }

    func testHistoryContentSummaryNonNumericOnlySeriesIsNoNumericData() {
        XCTAssertEqual(
            PerchHAHistoryContentSummary(
                series: HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .hour,
                    samples: [
                        HistorySample(
                            timestamp: Date(timeIntervalSince1970: 1_789_999_200),
                            state: "unknown",
                            numericValue: nil
                        )
                    ]
                )
            ),
            .noNumericData
        )
    }

    func testHistoryContentSummaryKeepsNumericHistoryWhenTrailingSampleIsNonNumeric() {
        XCTAssertEqual(
            PerchHAHistoryContentSummary(
                series: HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .hour,
                    samples: [
                        HistorySample(
                            timestamp: Date(timeIntervalSince1970: 1_789_999_200),
                            state: "21.4",
                            numericValue: 21.4
                        ),
                        HistorySample(
                            timestamp: Date(timeIntervalSince1970: 1_790_002_800),
                            state: "unknown",
                            numericValue: nil
                        )
                    ]
                )
            ),
            .statistics(PerchHAHistoryStatistics(current: 21.4, minimum: 21.4, average: 21.4, maximum: 21.4))
        )
    }

    func testHistoryContentSummaryMapsSingleNumericSampleToStatistics() {
        XCTAssertEqual(
            PerchHAHistoryContentSummary(
                series: historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4)
            ),
            .statistics(PerchHAHistoryStatistics(current: 21.4, minimum: 21.4, average: 21.4, maximum: 21.4))
        )
    }

    func testHistoryLoadingSkeletonUsesChartAndStatisticsPlaceholders() {
        let skeleton = HistoryLoadingSkeleton()

        XCTAssertEqual(skeleton.layout, .standard)
        XCTAssertEqual(skeleton.layout.cornerRadius, 2)
        XCTAssertEqual(skeleton.layout.chartHeight, 46)
        XCTAssertEqual(skeleton.layout.statisticPlaceholderHeight, 8)
        XCTAssertEqual(
            skeleton.layout.statisticRows,
            [
                HistoryLoadingSkeletonLayout.StatisticRow(id: 0, labelWidth: 42, valueWidth: 54),
                HistoryLoadingSkeletonLayout.StatisticRow(id: 1, labelWidth: 42, valueWidth: 54),
                HistoryLoadingSkeletonLayout.StatisticRow(id: 2, labelWidth: 42, valueWidth: 54),
                HistoryLoadingSkeletonLayout.StatisticRow(id: 3, labelWidth: 42, valueWidth: 54)
            ]
        )
    }

    func testHistoryContentSummaryUsesLatestChronologicalNumericSample() {
        let summary = PerchHAHistoryContentSummary(
            series: HistorySeries(
                entityID: "sensor.office_temperature",
                range: .hour,
                samples: [
                    HistorySample(timestamp: Date(timeIntervalSince1970: 120), state: "30", numericValue: 30),
                    HistorySample(timestamp: Date(timeIntervalSince1970: 100), state: "10", numericValue: 10),
                    HistorySample(timestamp: Date(timeIntervalSince1970: 130), state: "unknown", numericValue: nil),
                    HistorySample(timestamp: Date(timeIntervalSince1970: 110), state: "20", numericValue: 20)
                ]
            )
        )

        XCTAssertEqual(
            summary,
            .statistics(PerchHAHistoryStatistics(current: 30, minimum: 10, average: 20, maximum: 30))
        )
    }

    func testHistoryBodyPresentationUsesSkeletonForLoadingState() {
        XCTAssertEqual(
            PerchHAHistoryBodyPresentation(
                state: .loading(entityID: "sensor.office_temperature", range: .hour),
                entityID: "sensor.office_temperature"
            ),
            .loadingSkeleton
        )
        XCTAssertEqual(
            PerchHAHistoryBodyPresentation(
                state: .loading(entityID: "sensor.other", range: .hour),
                entityID: "sensor.office_temperature"
            ),
            .hidden
        )
    }

    func testHistoryBodyPresentationMapsLoadedAndUnavailableStates() {
        let numericSeries = historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4)
        XCTAssertEqual(
            PerchHAHistoryBodyPresentation(
                state: .loaded(numericSeries),
                entityID: "sensor.office_temperature"
            ),
            .statistics(
                series: numericSeries,
                statistics: PerchHAHistoryStatistics(current: 21.4, minimum: 21.4, average: 21.4, maximum: 21.4)
            )
        )
        XCTAssertEqual(
            PerchHAHistoryBodyPresentation(
                state: .loaded(HistorySeries(entityID: "sensor.office_temperature", range: .hour, samples: [])),
                entityID: "sensor.office_temperature"
            ),
            .noNumericData
        )
        XCTAssertEqual(
            PerchHAHistoryBodyPresentation(
                state: .unavailable(entityID: "sensor.office_temperature", range: .hour, message: "history unavailable"),
                entityID: "sensor.office_temperature"
            ),
            .unavailable("history unavailable")
        )
        XCTAssertEqual(
            PerchHAHistoryBodyPresentation(state: .idle, entityID: "sensor.office_temperature"),
            .hidden
        )
    }

    func testHistorySparklineGeometryMapsTimeAndValueIntoNormalizedPoints() {
        let geometry = PerchHAHistorySparklineGeometry(
            series: HistorySeries(
                entityID: "sensor.office_temperature",
                range: .hour,
                samples: [
                    HistorySample(timestamp: Date(timeIntervalSince1970: 100), state: "10", numericValue: 10),
                    HistorySample(timestamp: Date(timeIntervalSince1970: 110), state: "20", numericValue: 20),
                    HistorySample(timestamp: Date(timeIntervalSince1970: 120), state: "15", numericValue: 15)
                ]
            )
        )

        XCTAssertEqual(
            geometry.points,
            [
                PerchHAHistorySparklinePoint(x: 0, y: 1),
                PerchHAHistorySparklinePoint(x: 0.5, y: 0),
                PerchHAHistorySparklinePoint(x: 1, y: 0.5)
            ]
        )
    }

    func testHistorySparklineGeometrySortsSamplesChronologically() {
        let geometry = PerchHAHistorySparklineGeometry(
            series: HistorySeries(
                entityID: "sensor.office_temperature",
                range: .hour,
                samples: [
                    HistorySample(timestamp: Date(timeIntervalSince1970: 120), state: "15", numericValue: 15),
                    HistorySample(timestamp: Date(timeIntervalSince1970: 100), state: "10", numericValue: 10),
                    HistorySample(timestamp: Date(timeIntervalSince1970: 130), state: "unknown", numericValue: nil),
                    HistorySample(timestamp: Date(timeIntervalSince1970: 110), state: "20", numericValue: 20)
                ]
            )
        )

        XCTAssertEqual(
            geometry.points,
            [
                PerchHAHistorySparklinePoint(x: 0, y: 1),
                PerchHAHistorySparklinePoint(x: 0.5, y: 0),
                PerchHAHistorySparklinePoint(x: 1, y: 0.5)
            ]
        )
    }

    func testHistorySparklineGeometryFallsBackToMidlineWithoutEnoughNumericSamples() {
        let expectedMidline = [
            PerchHAHistorySparklinePoint(x: 0, y: 0.5),
            PerchHAHistorySparklinePoint(x: 1, y: 0.5)
        ]

        XCTAssertEqual(
            PerchHAHistorySparklineGeometry(
                series: HistorySeries(entityID: "sensor.office_temperature", range: .hour, samples: [])
            ).points,
            expectedMidline
        )
        XCTAssertEqual(
            PerchHAHistorySparklineGeometry(
                series: HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .hour,
                    samples: [
                        HistorySample(timestamp: Date(timeIntervalSince1970: 100), state: "unknown", numericValue: nil)
                    ]
                )
            ).points,
            expectedMidline
        )
        XCTAssertEqual(
            PerchHAHistorySparklineGeometry(
                series: HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .hour,
                    samples: [
                        HistorySample(timestamp: Date(timeIntervalSince1970: 100), state: "21.4", numericValue: 21.4)
                    ]
                )
            ).points,
            expectedMidline
        )
    }

    func testHistorySparklineGeometryCentersConstantValuesAndSpreadsEqualTimestamps() {
        let geometry = PerchHAHistorySparklineGeometry(
            series: HistorySeries(
                entityID: "sensor.office_temperature",
                range: .hour,
                samples: [
                    HistorySample(timestamp: Date(timeIntervalSince1970: 100), state: "21.4", numericValue: 21.4),
                    HistorySample(timestamp: Date(timeIntervalSince1970: 100), state: "21.4", numericValue: 21.4),
                    HistorySample(timestamp: Date(timeIntervalSince1970: 100), state: "21.4", numericValue: 21.4)
                ]
            )
        )

        XCTAssertEqual(
            geometry.points,
            [
                PerchHAHistorySparklinePoint(x: 0, y: 0.5),
                PerchHAHistorySparklinePoint(x: 0.5, y: 0.5),
                PerchHAHistorySparklinePoint(x: 1, y: 0.5)
            ]
        )
    }

    func test_t_history_unavailable_state_is_explicit() async {
        let modelWithoutConnection = PerchHAPanelModel()

        await modelWithoutConnection.loadHistory("sensor.office_temperature", range: .hour)

        XCTAssertEqual(
            modelWithoutConnection.snapshot.historyState,
            .unavailable(
                entityID: "sensor.office_temperature",
                range: .hour,
                message: "history requires a connected Home Assistant session"
            )
        )

        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { _, _, _ in .unavailable("history unavailable") }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        await model.loadHistory("sensor.office_temperature", range: .hour)

        XCTAssertEqual(
            model.snapshot.historyState,
            .unavailable(entityID: "sensor.office_temperature", range: .hour, message: "history unavailable")
        )
    }

    func testBuiltInControlDerivesToggleActionsForSupportedDomains() {
        let switchEntity = DiscoveredEntity(
            id: "switch.office_lamp",
            name: "Office lamp",
            state: "off",
            unit: nil,
            areaID: nil,
            deviceID: nil
        )
        let lightEntity = DiscoveredEntity(
            id: "light.kitchen_counter",
            name: "Kitchen counter",
            state: "on",
            unit: nil,
            areaID: nil,
            deviceID: nil
        )
        let inputBoolean = DiscoveredEntity(
            id: "input_boolean.guest_mode",
            name: "Guest mode",
            state: "off",
            unit: nil,
            areaID: nil,
            deviceID: nil
        )
        let sensor = DiscoveredEntity(
            id: "sensor.office_temperature",
            name: "Office temperature",
            state: "21.4",
            unit: "°C",
            areaID: nil,
            deviceID: nil
        )

        XCTAssertEqual(
            PerchHAEntityControl(entity: switchEntity)?.actionSpec(targetIsOn: true),
            ActionSpec(domain: "switch", service: "turn_on", targetEntityID: "switch.office_lamp")
        )
        XCTAssertEqual(
            PerchHAEntityControl(entity: lightEntity)?.actionSpec(targetIsOn: false),
            ActionSpec(domain: "light", service: "turn_off", targetEntityID: "light.kitchen_counter")
        )
        XCTAssertEqual(
            PerchHAEntityControl(entity: inputBoolean)?.actionSpec(targetIsOn: true),
            ActionSpec(domain: "input_boolean", service: "turn_on", targetEntityID: "input_boolean.guest_mode")
        )
        XCTAssertNil(PerchHAEntityControl(entity: sensor))
        XCTAssertNil(
            PerchHAEntityControl(
                entity: DiscoveredEntity(
                    id: "switch.unknown_lamp",
                    name: "Unknown lamp",
                    state: "unknown",
                    unit: nil,
                    areaID: nil,
                    deviceID: nil
                )
            )
        )
    }

    func testBuiltInCoverControlDerivesActionsAndPosition() {
        let cover = DiscoveredEntity(
            id: "cover.office_blinds",
            name: "Office blinds",
            state: "open",
            unit: nil,
            areaID: nil,
            deviceID: nil,
            currentPosition: 42
        )
        let sensor = DiscoveredEntity(
            id: "sensor.office_temperature",
            name: "Office temperature",
            state: "21.4",
            unit: "°C",
            areaID: nil,
            deviceID: nil
        )

        let control = PerchHACoverControl(entity: cover)
        XCTAssertEqual(control?.position, 42)
        XCTAssertEqual(
            control?.actionSpec(command: .open),
            ActionSpec(domain: "cover", service: "open_cover", targetEntityID: "cover.office_blinds")
        )
        XCTAssertEqual(
            control?.actionSpec(command: .close),
            ActionSpec(domain: "cover", service: "close_cover", targetEntityID: "cover.office_blinds")
        )
        XCTAssertEqual(
            control?.actionSpec(command: .stop),
            ActionSpec(domain: "cover", service: "stop_cover", targetEntityID: "cover.office_blinds")
        )
        XCTAssertEqual(
            control?.actionSpec(command: .setPosition(75)),
            ActionSpec(
                domain: "cover",
                service: "set_cover_position",
                targetEntityID: "cover.office_blinds",
                serviceData: ["position": 75]
            )
        )
        XCTAssertEqual(control?.actionSpec(command: .setPosition(150)).serviceData, ["position": 100])
        XCTAssertEqual(control?.actionSpec(command: .setPosition(-10)).serviceData, ["position": 0])
        XCTAssertNil(PerchHACoverControl(entity: sensor))
    }

    func test_t_builtin_controls_toggle_switch_optimistically_and_emit_one_action() async {
        let runner = ActionRunnerRecorder(results: [.success], waitForRelease: true)
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.startEntityControlToggle("switch.office_lamp", isOn: true))
        await spinUntil {
            model.snapshot.controlActionState == .running(entityID: "switch.office_lamp")
        }

        XCTAssertEqual(model.entityState("switch.office_lamp"), "on")
        XCTAssertFalse(model.startEntityControlToggle("switch.office_lamp", isOn: false))
        XCTAssertEqual(await runner.callCount(), 1)
        XCTAssertEqual(
            await runner.actions(),
            [ActionSpec(domain: "switch", service: "turn_on", targetEntityID: "switch.office_lamp")]
        )
        XCTAssertEqual(await runner.tokens(), ["fake-token"])

        await runner.releaseNext()
        await spinUntil {
            model.snapshot.controlActionState == .idle
        }

        XCTAssertEqual(model.entityState("switch.office_lamp"), "on")
        XCTAssertNil(model.snapshot.controlActionState.failureMessage(for: "switch.office_lamp"))
    }

    func test_t_action_rollback_restores_previous_state_and_shows_inline_failure() async {
        let runner = ActionRunnerRecorder(results: [.failed("service failed")], waitForRelease: true)
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.startEntityControlToggle("light.kitchen_counter", isOn: false))
        await spinUntil {
            model.snapshot.controlActionState == .running(entityID: "light.kitchen_counter")
        }
        XCTAssertEqual(model.entityState("light.kitchen_counter"), "off")

        await runner.releaseNext()
        await spinUntil {
            model.snapshot.controlActionState == .failed(entityID: "light.kitchen_counter", message: "service failed")
        }

        XCTAssertEqual(model.entityState("light.kitchen_counter"), "on")
        XCTAssertEqual(model.snapshot.controlActionState.failureMessage(for: "light.kitchen_counter"), "service failed")
        XCTAssertEqual(
            await runner.actions(),
            [ActionSpec(domain: "light", service: "turn_off", targetEntityID: "light.kitchen_counter")]
        )
    }

    func testBuiltInControlCancellationRollsBackOptimisticState() async {
        let runner = ActionRunnerRecorder(results: [.success], waitForRelease: true)
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.startEntityControlToggle("switch.office_lamp", isOn: true))
        await spinUntil {
            model.snapshot.controlActionState == .running(entityID: "switch.office_lamp")
        }
        XCTAssertEqual(model.entityState("switch.office_lamp"), "on")

        model.cancelInFlightAction()
        await runner.releaseNext()

        XCTAssertEqual(model.snapshot.controlActionState, .idle)
        XCTAssertEqual(model.entityState("switch.office_lamp"), "off")
    }

    func testBuiltInControlSuccessReassertsTargetStateAfterStaleRefreshDuringInFlightAction() async {
        let runner = ActionRunnerRecorder(results: [.success], waitForRelease: true)
        let connector = ConnectionResultRecorder(results: [
            .success(rooms: controlRooms()),
            .success(rooms: controlRooms())
        ])
        let model = PerchHAPanelModel(
            connector: { _ in
                await connector.next()
            },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.startEntityControlToggle("switch.office_lamp", isOn: true))
        await spinUntil {
            model.snapshot.controlActionState == .running(entityID: "switch.office_lamp")
        }
        XCTAssertEqual(model.entityState("switch.office_lamp"), "on")

        await model.refresh()
        XCTAssertEqual(model.entityState("switch.office_lamp"), "off")
        await runner.releaseNext()
        await spinUntil {
            model.snapshot.controlActionState == .idle
        }

        XCTAssertEqual(model.entityState("switch.office_lamp"), "on")
        XCTAssertEqual(await connector.callCount(), 2)
    }

    func testBuiltInControlSuccessReassertsTargetStateAfterStaleLiveUpdateDuringInFlightAction() async {
        let runner = ActionRunnerRecorder(results: [.success], waitForRelease: true)
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.startEntityControlToggle("switch.office_lamp", isOn: true))
        await spinUntil {
            model.snapshot.controlActionState == .running(entityID: "switch.office_lamp")
        }
        XCTAssertEqual(model.entityState("switch.office_lamp"), "on")

        XCTAssertTrue(
            model.applyLiveState(
                EntityState(id: "switch.office_lamp", name: "Office lamp", state: "off", unit: nil)
            )
        )
        XCTAssertEqual(model.entityState("switch.office_lamp"), "off")
        await runner.releaseNext()
        await spinUntil {
            model.snapshot.controlActionState == .idle
        }

        XCTAssertEqual(model.entityState("switch.office_lamp"), "on")
    }

    func test_t_builtin_controls_reject_sensor_without_service_call() async {
        let runner = ActionRunnerRecorder(results: [.success])
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertFalse(await model.setEntityControl("sensor.office_temperature", isOn: true))

        XCTAssertEqual(await runner.callCount(), 0)
        XCTAssertEqual(model.entityState("sensor.office_temperature"), "21.4")
        XCTAssertEqual(
            model.snapshot.controlActionState,
            .failed(entityID: "sensor.office_temperature", message: "entity does not support built-in controls")
        )
    }

    func test_t_builtin_cover_open_close_stop_emit_separate_actions() async {
        let runner = ActionRunnerRecorder(results: [.success, .success, .success])
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(await model.setCoverControl("cover.office_blinds", command: .open))
        XCTAssertEqual(model.entityState("cover.office_blinds"), "open")
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 100)

        XCTAssertTrue(await model.setCoverControl("cover.office_blinds", command: .close))
        XCTAssertEqual(model.entityState("cover.office_blinds"), "closed")
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 0)

        XCTAssertTrue(await model.setCoverControl("cover.office_blinds", command: .stop))
        XCTAssertEqual(model.entityState("cover.office_blinds"), "closed")
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 0)

        XCTAssertEqual(
            await runner.actions(),
            [
                ActionSpec(domain: "cover", service: "open_cover", targetEntityID: "cover.office_blinds"),
                ActionSpec(domain: "cover", service: "close_cover", targetEntityID: "cover.office_blinds"),
                ActionSpec(domain: "cover", service: "stop_cover", targetEntityID: "cover.office_blinds")
            ]
        )
    }

    func test_t_builtin_cover_position_updates_optimistically_and_emits_position_payload() async {
        let runner = ActionRunnerRecorder(results: [.success], waitForRelease: true)
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.startCoverPositionChange("cover.office_blinds", position: 75))
        await spinUntil {
            model.snapshot.controlActionState == .running(entityID: "cover.office_blinds")
        }

        XCTAssertEqual(model.entityState("cover.office_blinds"), "open")
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 75)
        XCTAssertFalse(model.startCoverPositionChange("cover.office_blinds", position: 80))
        XCTAssertEqual(
            await runner.actions(),
            [
                ActionSpec(
                    domain: "cover",
                    service: "set_cover_position",
                    targetEntityID: "cover.office_blinds",
                    serviceData: ["position": 75]
                )
            ]
        )
        XCTAssertEqual(await runner.tokens(), ["fake-token"])

        await runner.releaseNext()
        await spinUntil {
            model.snapshot.controlActionState == .idle
        }

        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 75)
    }

    func test_t_builtin_cover_position_rollback_restores_previous_state_and_position() async {
        let runner = ActionRunnerRecorder(results: [.failed("cover service failed")], waitForRelease: true)
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.startCoverPositionChange("cover.office_blinds", position: 25))
        await spinUntil {
            model.snapshot.controlActionState == .running(entityID: "cover.office_blinds")
        }
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 25)

        await runner.releaseNext()
        await spinUntil {
            model.snapshot.controlActionState == .failed(entityID: "cover.office_blinds", message: "cover service failed")
        }

        XCTAssertEqual(model.entityState("cover.office_blinds"), "open")
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 42)
        XCTAssertEqual(model.snapshot.controlActionState.failureMessage(for: "cover.office_blinds"), "cover service failed")
    }

    func testBuiltInCoverPositionCancellationRollsBackOptimisticPosition() async {
        let runner = ActionRunnerRecorder(results: [.success], waitForRelease: true)
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.startCoverPositionChange("cover.office_blinds", position: 75))
        await spinUntil {
            model.snapshot.controlActionState == .running(entityID: "cover.office_blinds")
        }
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 75)

        model.cancelInFlightAction()
        await runner.releaseNext()

        XCTAssertEqual(model.snapshot.controlActionState, .idle)
        XCTAssertEqual(model.entityState("cover.office_blinds"), "open")
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 42)
    }

    func testBuiltInCoverPositionSuccessReassertsTargetAfterStaleRefreshDuringInFlightAction() async {
        let runner = ActionRunnerRecorder(results: [.success], waitForRelease: true)
        let connector = ConnectionResultRecorder(results: [
            .success(rooms: controlRooms()),
            .success(rooms: controlRooms())
        ])
        let model = PerchHAPanelModel(
            connector: { _ in
                await connector.next()
            },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.startCoverPositionChange("cover.office_blinds", position: 75))
        await spinUntil {
            model.snapshot.controlActionState == .running(entityID: "cover.office_blinds")
        }
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 75)

        await model.refresh()
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 42)
        await runner.releaseNext()
        await spinUntil {
            model.snapshot.controlActionState == .idle
        }

        XCTAssertEqual(model.entityState("cover.office_blinds"), "open")
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 75)
        XCTAssertEqual(await connector.callCount(), 2)
    }

    func testBuiltInCoverPositionSuccessReassertsTargetAfterStaleLiveUpdateDuringInFlightAction() async {
        let runner = ActionRunnerRecorder(results: [.success], waitForRelease: true)
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.startCoverPositionChange("cover.office_blinds", position: 75))
        await spinUntil {
            model.snapshot.controlActionState == .running(entityID: "cover.office_blinds")
        }
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 75)

        XCTAssertTrue(
            model.applyLiveState(
                EntityState(
                    id: "cover.office_blinds",
                    name: "Office blinds",
                    state: "open",
                    unit: nil,
                    currentPosition: 10
                )
            )
        )
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 10)
        await runner.releaseNext()
        await spinUntil {
            model.snapshot.controlActionState == .idle
        }

        XCTAssertEqual(model.entityState("cover.office_blinds"), "open")
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 75)
    }

    func test_t_builtin_cover_position_rejects_cover_without_position() async {
        let runner = ActionRunnerRecorder(results: [.success])
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertFalse(await model.setCoverPosition("cover.garage_door", position: 50))

        XCTAssertEqual(await runner.callCount(), 0)
        XCTAssertNil(model.entityPosition("cover.garage_door"))
        XCTAssertEqual(
            model.snapshot.controlActionState,
            .failed(entityID: "cover.garage_door", message: "cover does not report a position")
        )
    }

    func testBuiltInControlUsesFakeHAServiceCallJournal() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                guard let primaryURL = form.primaryURL() else {
                    return .failed("invalid URL")
                }
                let input = HAConnectionInput(
                    endpoint: HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL()),
                    token: form.trimmedToken
                )
                switch await HomeAssistantClient().callService(input, call: action) {
                case .success:
                    return .success
                case let .failure(failure):
                    return .failed(failure.description)
                }
            }
        )
        model.updateConnectionForm(urlString: server.baseURL.absoluteString, token: "fake-token")
        await model.connect()

        XCTAssertTrue(await model.setEntityControl("input_boolean.guest_mode", isOn: true))
        await spinUntil {
            await server.journal.snapshot().contains { $0.path == "/api/websocket/call_service" }
        }

        let serviceEntry = await server.journal.snapshot().last { $0.path == "/api/websocket/call_service" }
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""domain":"input_boolean""#) == true)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""service":"turn_on""#) == true)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""entity_id":"input_boolean.guest_mode""#) == true)
        XCTAssertEqual(model.entityState("input_boolean.guest_mode"), "on")
    }

    func testBuiltInCoverPositionUsesFakeHAServiceCallJournal() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                guard let primaryURL = form.primaryURL() else {
                    return .failed("invalid URL")
                }
                let input = HAConnectionInput(
                    endpoint: HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL()),
                    token: form.trimmedToken
                )
                switch await HomeAssistantClient().callService(input, call: action) {
                case .success:
                    return .success
                case let .failure(failure):
                    return .failed(failure.description)
                }
            }
        )
        model.updateConnectionForm(urlString: server.baseURL.absoluteString, token: "fake-token")
        await model.connect()

        XCTAssertTrue(await model.setCoverPosition("cover.office_blinds", position: 75))
        await spinUntil {
            await server.journal.snapshot().contains { $0.path == "/api/websocket/call_service" }
        }

        let serviceEntry = await server.journal.snapshot().last { $0.path == "/api/websocket/call_service" }
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""domain":"cover""#) == true)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""service":"set_cover_position""#) == true)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""entity_id":"cover.office_blinds""#) == true)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""position":75"#) == true)
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 75)
    }

    func testBuiltInCoverButtonsUseFakeHAServiceCallJournal() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            actionRunner: { form, action in
                guard let primaryURL = form.primaryURL() else {
                    return .failed("invalid URL")
                }
                let input = HAConnectionInput(
                    endpoint: HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL()),
                    token: form.trimmedToken
                )
                switch await HomeAssistantClient().callService(input, call: action) {
                case .success:
                    return .success
                case let .failure(failure):
                    return .failed(failure.description)
                }
            }
        )
        model.updateConnectionForm(urlString: server.baseURL.absoluteString, token: "fake-token")
        await model.connect()

        XCTAssertTrue(await model.setCoverControl("cover.office_blinds", command: .open))
        XCTAssertTrue(await model.setCoverControl("cover.office_blinds", command: .close))
        XCTAssertTrue(await model.setCoverControl("cover.office_blinds", command: .stop))
        await spinUntil {
            await server.journal.snapshot().filter { $0.path == "/api/websocket/call_service" }.count == 3
        }

        let serviceEntries = await server.journal.snapshot().filter { $0.path == "/api/websocket/call_service" }
        XCTAssertEqual(serviceEntries.count, 3)
        XCTAssertTrue(serviceEntries[0].bodyText?.contains(#""service":"open_cover""#) == true)
        XCTAssertTrue(serviceEntries[1].bodyText?.contains(#""service":"close_cover""#) == true)
        XCTAssertTrue(serviceEntries[2].bodyText?.contains(#""service":"stop_cover""#) == true)
        XCTAssertTrue(serviceEntries.allSatisfy { $0.bodyText?.contains(#""domain":"cover""#) == true })
        XCTAssertTrue(serviceEntries.allSatisfy { $0.bodyText?.contains(#""entity_id":"cover.office_blinds""#) == true })
    }

    func testAppShellRunsBuiltInControlThroughInjectedActionRunner() async {
        let runner = ActionRunnerRecorder(results: [.success])
        let application = PerchHAApplication(
            configStore: nil,
            connector: { _ in .success(rooms: controlRooms()) },
            historyProvider: { _, _, _ in .unavailable("history unavailable") },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertTrue(await application.setEntityControl("switch.office_lamp", isOn: true))

        XCTAssertEqual(application.snapshot.controlActionState, .idle)
        XCTAssertEqual(
            await runner.actions(),
            [ActionSpec(domain: "switch", service: "turn_on", targetEntityID: "switch.office_lamp")]
        )
    }

    func testAppShellRunsBuiltInCoverControlThroughInjectedActionRunner() async {
        let runner = ActionRunnerRecorder(results: [.success])
        let application = PerchHAApplication(
            configStore: nil,
            connector: { _ in .success(rooms: controlRooms()) },
            historyProvider: { _, _, _ in .unavailable("history unavailable") },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertTrue(await application.setCoverPosition("cover.office_blinds", position: 75))

        XCTAssertEqual(application.snapshot.controlActionState, .idle)
        XCTAssertEqual(
            await runner.actions(),
            [
                ActionSpec(
                    domain: "cover",
                    service: "set_cover_position",
                    targetEntityID: "cover.office_blinds",
                    serviceData: ["position": 75]
                )
            ]
        )
    }

    func testAppShellRunsBuiltInCoverButtonControlsThroughInjectedActionRunner() async {
        let runner = ActionRunnerRecorder(results: [.success, .success, .success])
        let application = PerchHAApplication(
            configStore: nil,
            connector: { _ in .success(rooms: controlRooms()) },
            historyProvider: { _, _, _ in .unavailable("history unavailable") },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertTrue(await application.setCoverControl("cover.office_blinds", command: .open))
        XCTAssertTrue(await application.setCoverControl("cover.office_blinds", command: .close))
        XCTAssertTrue(await application.setCoverControl("cover.office_blinds", command: .stop))

        XCTAssertEqual(application.snapshot.controlActionState, .idle)
        XCTAssertEqual(
            await runner.actions(),
            [
                ActionSpec(domain: "cover", service: "open_cover", targetEntityID: "cover.office_blinds"),
                ActionSpec(domain: "cover", service: "close_cover", targetEntityID: "cover.office_blinds"),
                ActionSpec(domain: "cover", service: "stop_cover", targetEntityID: "cover.office_blinds")
            ]
        )
    }

    func test_t_sensor_custom_action_attaches_to_sensor_and_emits_exact_payload() async {
        let action = sensorCustomAction()
        let runner = ActionRunnerRecorder(results: [.success])
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.setCustomAction(action))
        XCTAssertEqual(model.customActions(for: selectionRooms()[0].entities[0]), [action])
        XCTAssertTrue(await model.runCustomAction(action.id))

        XCTAssertEqual(model.entityState("sensor.office_temperature"), "21.4")
        XCTAssertEqual(await runner.tokens(), ["fake-token"])
        XCTAssertEqual(await runner.actions(), [action.action])
    }

    func testCustomActionConfirmationBlocksUnconfirmedRun() async {
        let action = sensorCustomAction(requiresConfirmation: true)
        let runner = ActionRunnerRecorder(results: [.success])
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.setCustomAction(action))
        XCTAssertFalse(await model.runCustomAction(action.id))
        XCTAssertEqual(await runner.callCount(), 0)
        XCTAssertTrue(await model.runCustomAction(action.id, confirmed: true))

        XCTAssertEqual(await runner.actions(), [action.action])
    }

    func test_t_custom_action_failure_shows_inline_error_without_changing_sensor_state() async {
        let action = sensorCustomAction()
        let runner = ActionRunnerRecorder(results: [.failed("script failed")])
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.setCustomAction(action))
        XCTAssertFalse(await model.runCustomAction(action.id))

        XCTAssertEqual(model.entityState("sensor.office_temperature"), "21.4")
        XCTAssertEqual(
            model.snapshot.controlActionState,
            .failed(entityID: "sensor.office_temperature", message: "script failed")
        )
    }

    func testCustomActionRejectsIncompleteOrUnknownEntityConfiguration() async {
        let model = PerchHAPanelModel(connector: { _ in .success(rooms: selectionRooms()) })
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertFalse(
            model.setCustomAction(
                EntityCustomAction(
                    id: "bad-action",
                    entityID: "sensor.office_temperature",
                    title: " ",
                    action: ActionSpec(domain: "script", service: "turn_on", targetEntityID: "script.boost")
                )
            )
        )
        XCTAssertFalse(
            model.setCustomAction(
                EntityCustomAction(
                    id: "missing-entity-action",
                    entityID: "sensor.missing",
                    title: "Boost",
                    action: ActionSpec(domain: "script", service: "turn_on", targetEntityID: "script.boost")
                )
            )
        )
        XCTAssertEqual(model.customActionPersistenceFailureDescription, "custom action is incomplete")
    }

    func testCustomActionStoresProtectedServiceDataKeysInProtectedStore() async throws {
        let protectedStore = InMemoryProtectedActionValueStore()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            protectedActionValueStore: protectedStore
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(
            model.setCustomAction(
                EntityCustomAction(
                    id: "arm-alarm",
                    entityID: "sensor.office_temperature",
                    title: "Arm alarm",
                    action: ActionSpec(
                        domain: "alarm_control_panel",
                        service: "alarm_arm_home",
                        targetEntityID: "alarm_control_panel.home",
                        serviceData: [
                            "alarm": .object([
                                "pin": "1234"
                            ])
                        ]
                    ),
                    requiresConfirmation: true
                )
            )
        )
        let action = try XCTUnwrap(model.customAction(id: "arm-alarm"))
        guard case let .object(alarm) = action.action.serviceData["alarm"],
              case let .protectedString(reference) = alarm["pin"] else {
            return XCTFail("expected protected pin reference")
        }
        XCTAssertEqual(try protectedStore.load(reference), "1234")
        let encoded = try JSONEncoder().encode(model.customActionConfiguration)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains("1234"))
        XCTAssertNil(model.customActionPersistenceFailureDescription)
    }

    func testCustomActionServiceDataEditorUpdatesScalarsAndStoresProtectedKeys() async throws {
        let action = EntityCustomAction(
            id: "boost-air",
            entityID: "sensor.office_temperature",
            title: "Boost air",
            action: ActionSpec(domain: "script", service: "turn_on", targetEntityID: "script.air_cleaner_boost")
        )
        let protectedStore = InMemoryProtectedActionValueStore()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            protectedActionValueStore: protectedStore
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.setCustomAction(action))
        XCTAssertTrue(model.setCustomActionServiceDataValue(action.id, key: "mode", value: "boost"))
        XCTAssertTrue(model.setCustomActionServiceDataValue(action.id, key: "duration", value: 15))
        XCTAssertTrue(model.setCustomActionServiceDataValue(action.id, key: "enabled", value: true))
        XCTAssertEqual(
            model.customAction(id: action.id)?.action.serviceData,
            ["mode": "boost", "duration": 15, "enabled": true]
        )

        XCTAssertTrue(model.renameCustomActionServiceDataKey(action.id, from: "mode", to: "profile"))
        XCTAssertEqual(
            model.customAction(id: action.id)?.action.serviceData,
            ["profile": "boost", "duration": 15, "enabled": true]
        )
        XCTAssertFalse(
            model.setCustomActionServiceDataText(
                action.id,
                key: "duration",
                text: "not-a-number",
                kind: .number
            )
        )
        XCTAssertEqual(model.customActionPersistenceFailureDescription, "custom action service data value is invalid")
        XCTAssertEqual(model.customAction(id: action.id)?.action.serviceData["duration"], 15)
        XCTAssertFalse(
            model.setCustomActionServiceDataText(
                action.id,
                key: "enabled",
                text: "maybe",
                kind: .bool
            )
        )
        XCTAssertEqual(model.customAction(id: action.id)?.action.serviceData["enabled"], true)
        XCTAssertFalse(model.renameCustomActionServiceDataKey(action.id, from: "profile", to: "duration"))
        XCTAssertEqual(model.customActionPersistenceFailureDescription, "custom action service data key is duplicated")
        XCTAssertTrue(model.setCustomActionServiceDataValue(action.id, key: "pin", value: "1234"))
        guard case let .protectedString(reference) = model.customAction(id: action.id)?.action.serviceData["pin"] else {
            return XCTFail("expected protected pin reference")
        }
        XCTAssertEqual(try protectedStore.load(reference), "1234")

        XCTAssertTrue(model.removeCustomActionServiceDataKey(action.id, key: "enabled"))
        XCTAssertEqual(
            model.customAction(id: action.id)?.action.serviceData,
            ["profile": "boost", "duration": 15, "pin": .protectedString(reference)]
        )
    }

    func testCustomActionServiceDataEditorUpdatesObjectsAndArrays() async throws {
        let action = EntityCustomAction(
            id: "boost-air",
            entityID: "sensor.office_temperature",
            title: "Boost air",
            action: ActionSpec(domain: "script", service: "turn_on", targetEntityID: "script.air_cleaner_boost")
        )
        let protectedStore = InMemoryProtectedActionValueStore()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            protectedActionValueStore: protectedStore
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.setCustomAction(action))
        XCTAssertTrue(model.setCustomActionServiceDataValue(action.id, path: [.key("payload")], value: .object([:])))
        XCTAssertTrue(model.setCustomActionServiceDataValue(action.id, path: [.key("payload"), .key("mode")], value: "boost"))
        XCTAssertTrue(
            model.setCustomActionServiceDataText(
                action.id,
                path: [.key("payload"), .key("duration")],
                text: "15",
                kind: .number
            )
        )
        XCTAssertTrue(model.setCustomActionServiceDataValue(action.id, path: [.key("payload"), .key("steps")], value: .array([])))
        XCTAssertTrue(
            model.appendCustomActionServiceDataArrayValue(
                action.id,
                path: [.key("payload"), .key("steps")],
                value: .object(["service": "fan.turn_on"])
            )
        )
        XCTAssertTrue(
            model.appendCustomActionServiceDataArrayValue(
                action.id,
                path: [.key("payload"), .key("steps")],
                value: .object(["service": "fan.set_preset_mode"])
            )
        )
        XCTAssertTrue(
            model.setCustomActionServiceDataValue(
                action.id,
                path: [.key("payload"), .key("steps"), .index(1), .key("data")],
                value: .object(["preset_mode": "boost"])
            )
        )
        XCTAssertTrue(
            model.renameCustomActionServiceDataKey(
                action.id,
                parentPath: [.key("payload")],
                from: "mode",
                to: "profile"
            )
        )
        XCTAssertTrue(
            model.moveCustomActionServiceDataArrayValue(
                action.id,
                path: [.key("payload"), .key("steps"), .index(1)],
                direction: .up
            )
        )
        XCTAssertTrue(
            model.setCustomActionServiceDataValue(
                action.id,
                path: [.key("payload"), .key("steps"), .index(0), .key("pin")],
                value: "1234"
            )
        )
        let nestedPayload = try XCTUnwrap(model.customAction(id: action.id)?.action.serviceData["payload"])
        guard case let .object(payload) = nestedPayload,
              case let .array(steps) = payload["steps"],
              case let .object(firstStep) = steps.first,
              case let .protectedString(reference) = firstStep["pin"] else {
            return XCTFail("expected nested protected pin reference")
        }
        XCTAssertEqual(try protectedStore.load(reference), "1234")
        XCTAssertFalse(
            model.setCustomActionServiceDataValue(
                action.id,
                path: [.key("payload"), .key("missing"), .key("value")],
                value: "ignored"
            )
        )
        XCTAssertEqual(model.customActionPersistenceFailureDescription, "custom action service data path is invalid")
        XCTAssertTrue(
            model.removeCustomActionServiceDataValue(
                action.id,
                path: [.key("payload"), .key("steps"), .index(1)]
            )
        )

        XCTAssertEqual(
            model.customAction(id: action.id)?.action.serviceData,
            [
                "payload": .object([
                    "profile": "boost",
                    "duration": 15,
                    "steps": .array([
                        .object([
                            "service": "fan.set_preset_mode",
                            "data": .object(["preset_mode": "boost"]),
                            "pin": .protectedString(reference)
                        ])
                    ])
                ])
            ]
        )
    }

    func testCustomActionServiceDataTypeChangesReplaceObjectsAndArraysWithScalarDefaults() async {
        let action = EntityCustomAction(
            id: "boost-air",
            entityID: "sensor.office_temperature",
            title: "Boost air",
            action: ActionSpec(domain: "script", service: "turn_on", targetEntityID: "script.air_cleaner_boost")
        )
        let model = PerchHAPanelModel(connector: { _ in .success(rooms: selectionRooms()) })
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.setCustomAction(action))
        XCTAssertTrue(model.setCustomActionServiceDataValue(action.id, path: [.key("payload")], value: .object(["mode": "boost"])))
        XCTAssertTrue(
            model.setCustomActionServiceDataType(
                action.id,
                path: [.key("payload")],
                kind: .string
            )
        )
        XCTAssertEqual(model.customAction(id: action.id)?.action.serviceData["payload"], "")

        XCTAssertTrue(model.setCustomActionServiceDataValue(action.id, path: [.key("steps")], value: .array(["fan"])))
        XCTAssertTrue(
            model.setCustomActionServiceDataType(
                action.id,
                path: [.key("steps")],
                kind: .number
            )
        )
        XCTAssertEqual(model.customAction(id: action.id)?.action.serviceData["steps"], 0)

        XCTAssertTrue(model.setCustomActionServiceDataValue(action.id, path: [.key("enabled")], value: .object(["previous": true])))
        XCTAssertTrue(
            model.setCustomActionServiceDataType(
                action.id,
                path: [.key("enabled")],
                kind: .bool
            )
        )
        XCTAssertEqual(model.customAction(id: action.id)?.action.serviceData["enabled"], false)
    }

    func testCustomActionOrphanedLoadedActionsRemainVisibleForDeletion() async {
        let orphanedAction = EntityCustomAction(
            id: "orphaned-action",
            entityID: "sensor.removed",
            title: "Removed sensor action",
            action: ActionSpec(domain: "script", service: "turn_on", targetEntityID: "script.cleanup")
        )
        let sink = CustomActionSinkRecorder()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            customActionConfiguration: CustomActionConfiguration(actions: [orphanedAction]),
            customActionSink: { configuration in
                sink.record(configuration)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertEqual(model.customActionConfiguration.actions, [orphanedAction])
        XCTAssertEqual(model.orphanedCustomActions, [orphanedAction])
        XCTAssertTrue(model.removeCustomAction(orphanedAction.id))
        XCTAssertEqual(model.customActionConfiguration.actions, [])
        XCTAssertEqual(model.orphanedCustomActions, [])
        XCTAssertEqual(sink.configurations(), [CustomActionConfiguration()])
    }

    func testCustomActionServiceMetadataLoadsAfterConnectAndScaffoldsDefaults() async {
        let metadata = [
            HAServiceMetadata(
                domain: "script",
                service: "turn_on",
                name: "Turn on",
                description: "Runs a script.",
                fields: [
                    HAServiceFieldMetadata(
                        key: "duration",
                        name: "Duration",
                        description: nil,
                        required: false,
                        example: 15,
                        selector: .object(["number": .object(["min": 1])])
                    ),
                    HAServiceFieldMetadata(
                        key: "entity_id",
                        name: "Entity",
                        description: nil,
                        required: true,
                        example: "script.air_cleaner_boost",
                        selector: .object(["entity": .object(["domain": "script"])])
                    ),
                    HAServiceFieldMetadata(
                        key: "variables",
                        name: "Variables",
                        description: nil,
                        required: false,
                        example: .object([
                            "mode": "boost",
                            "steps": .array(["fan", "purifier"])
                        ]),
                        selector: .object(["object": .object([:])])
                    )
                ]
            )
        ]
        let action = EntityCustomAction(
            id: "boost-air",
            entityID: "sensor.office_temperature",
            title: "Boost air",
            action: ActionSpec(
                domain: "homeassistant",
                service: "update_entity",
                targetEntityID: "sensor.office_temperature",
                serviceData: ["mode": "boost"]
            )
        )
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            serviceMetadataProvider: { form in
                form.trimmedToken == "fake-token" ? .success(metadata) : .unavailable("metadata unavailable")
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertEqual(model.snapshot.serviceMetadata, metadata)
        XCTAssertNil(model.snapshot.serviceMetadataFailureDescription)
        XCTAssertTrue(model.setCustomAction(action))
        XCTAssertTrue(model.setCustomActionService(action.id, domain: "script", service: "turn_on"))

        XCTAssertEqual(model.customAction(id: action.id)?.action.domain, "script")
        XCTAssertEqual(model.customAction(id: action.id)?.action.service, "turn_on")
        XCTAssertEqual(
            model.customAction(id: action.id)?.action.serviceData,
            [
                "mode": "boost",
                "duration": 15,
                "variables": .object([
                    "mode": "boost",
                    "steps": .array(["fan", "purifier"])
                ])
            ]
        )
    }

    func testCustomActionServiceMetadataUsesProtectedReferenceForSensitiveDefaults() async throws {
        let metadata = [
            HAServiceMetadata(
                domain: "alarm_control_panel",
                service: "alarm_arm_home",
                name: "Arm home",
                description: "Arms the home profile",
                fields: [
                    HAServiceFieldMetadata(
                        key: "code",
                        name: "Code",
                        description: "Alarm code",
                        required: true,
                        example: "1234",
                        selector: nil
                    ),
                    HAServiceFieldMetadata(
                        key: "mode",
                        name: "Mode",
                        description: "Alarm mode",
                        required: false,
                        example: "home",
                        selector: nil
                    )
                ]
            )
        ]
        let action = EntityCustomAction(
            id: "arm-home",
            entityID: "sensor.office_temperature",
            title: "Arm home",
            action: ActionSpec(
                domain: "homeassistant",
                service: "update_entity",
                targetEntityID: "sensor.office_temperature"
            )
        )
        let protectedStore = InMemoryProtectedActionValueStore()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            serviceMetadataProvider: { _ in .success(metadata) },
            protectedActionValueStore: protectedStore
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.setCustomAction(action))
        XCTAssertTrue(model.setCustomActionService(action.id, domain: "alarm_control_panel", service: "alarm_arm_home"))
        let storedAction = try XCTUnwrap(model.customAction(id: action.id))
        guard case let .protectedString(reference) = storedAction.action.serviceData["code"] else {
            return XCTFail("expected protected code reference")
        }
        XCTAssertThrowsError(try protectedStore.load(reference)) { error in
            XCTAssertEqual(error as? ProtectedActionValueStoreError, .missingValue(reference))
        }
        XCTAssertEqual(storedAction.action.serviceData["mode"], "home")
    }

    func testCustomActionServiceMetadataFailureDoesNotFailConnection() async {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            serviceMetadataProvider: { _ in .unavailable("metadata unavailable") }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertEqual(model.snapshot.serviceMetadata, [])
        XCTAssertEqual(model.snapshot.serviceMetadataFailureDescription, "metadata unavailable")
    }

    func testCustomActionUsesFakeHAServiceCallJournal() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let action = sensorCustomAction()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            actionRunner: { form, action in
                guard let primaryURL = form.primaryURL() else {
                    return .failed("invalid URL")
                }
                let input = HAConnectionInput(
                    endpoint: HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL()),
                    token: form.trimmedToken
                )
                switch await HomeAssistantClient().callService(input, call: action) {
                case .success:
                    return .success
                case let .failure(failure):
                    return .failed(failure.description)
                }
            }
        )
        model.updateConnectionForm(urlString: server.baseURL.absoluteString, token: "fake-token")
        await model.connect()
        XCTAssertTrue(model.setCustomAction(action))

        XCTAssertTrue(await model.runCustomAction(action.id))
        await spinUntil {
            await server.journal.snapshot().contains { $0.path == "/api/websocket/call_service" }
        }

        let serviceEntry = await server.journal.snapshot().last { $0.path == "/api/websocket/call_service" }
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""domain":"script""#) == true)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""service":"turn_on""#) == true)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""entity_id":"script.air_cleaner_boost""#) == true)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""mode":"boost""#) == true)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""duration":15"#) == true)
    }

    func testCustomActionRunFailsExplicitlyWhenProtectedValueIsMissing() async {
        let reference: ProtectedActionValueReference = "protected-pin"
        let action = EntityCustomAction(
            id: "arm-home",
            entityID: "sensor.office_temperature",
            title: "Arm home",
            action: ActionSpec(
                domain: "alarm_control_panel",
                service: "alarm_arm_home",
                targetEntityID: "alarm_control_panel.home",
                serviceData: ["pin": .protectedString(reference)]
            ),
            requiresConfirmation: true
        )
        let runner = ActionRunnerRecorder(results: [.success])
        let protectedStore = InMemoryProtectedActionValueStore()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            },
            protectedActionValueStore: protectedStore
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        XCTAssertTrue(model.setCustomAction(action))

        XCTAssertFalse(await model.runCustomAction(action.id, confirmed: true))
        XCTAssertEqual(await runner.actions(), [])
        XCTAssertTrue(
            model.snapshot.controlActionState.failureMessage(for: action.entityID)?
                .contains("protected custom action value protected-pin is missing") == true
        )
    }

    func testAppShellPersistsCustomActionsAndRunsInjectedActionRunner() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        let action = sensorCustomAction()
        let runner = ActionRunnerRecorder(results: [.success])
        let protectedStore = InMemoryProtectedActionValueStore()
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { _, _, _ in .unavailable("history unavailable") },
            actionRunner: { form, action in
                await runner.run(form: form, action: action)
            },
            protectedActionValueStore: protectedStore
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertTrue(application.setCustomAction(action))
        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [action])
        XCTAssertTrue(application.setCustomActionServiceDataValue(action.id, key: "speed", value: "high"))
        XCTAssertTrue(application.renameCustomActionServiceDataKey(action.id, from: "speed", to: "fan_speed"))
        XCTAssertTrue(application.removeCustomActionServiceDataKey(action.id, key: "fan_speed"))
        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [action])
        XCTAssertTrue(application.setCustomActionServiceDataValue(action.id, key: "pin", value: "1234"))
        XCTAssertTrue(application.setCustomActionServiceDataValue(action.id, path: [.key("payload")], value: .object([:])))
        XCTAssertTrue(application.setCustomActionServiceDataValue(action.id, path: [.key("payload"), .key("steps")], value: .array([])))
        XCTAssertTrue(
            application.appendCustomActionServiceDataArrayValue(
                action.id,
                path: [.key("payload"), .key("steps")],
                value: .object(["service": "script.turn_on"])
            )
        )
        XCTAssertTrue(
            application.appendCustomActionServiceDataArrayValue(
                action.id,
                path: [.key("payload"), .key("steps")],
                value: .object(["service": "script.turn_off"])
            )
        )
        XCTAssertTrue(
            application.setCustomActionServiceDataText(
                action.id,
                path: [.key("payload"), .key("steps"), .index(1), .key("delay")],
                text: "2.5",
                kind: .number
            )
        )
        XCTAssertTrue(
            application.renameCustomActionServiceDataKey(
                action.id,
                parentPath: [.key("payload"), .key("steps"), .index(1)],
                from: "delay",
                to: "seconds"
            )
        )
        XCTAssertTrue(
            application.moveCustomActionServiceDataArrayValue(
                action.id,
                path: [.key("payload"), .key("steps"), .index(1)],
                direction: .up
            )
        )
        XCTAssertFalse(
            application.moveCustomActionServiceDataArrayValue(
                action.id,
                path: [.key("payload"), .key("steps"), .index(1)],
                direction: .down
            )
        )
        XCTAssertTrue(
            application.removeCustomActionServiceDataValue(
                action.id,
                path: [.key("payload"), .key("steps"), .index(0), .key("seconds")]
            )
        )
        XCTAssertTrue(application.removeCustomActionServiceDataValue(action.id, path: [.key("payload")]))
        guard case let .protectedString(configuredReference) = application.snapshot.customActionConfiguration.action(id: action.id)?.action.serviceData["pin"] else {
            return XCTFail("expected protected pin reference")
        }
        let protectedAction = EntityCustomAction(
            id: action.id,
            entityID: action.entityID,
            title: action.title,
            action: ActionSpec(
                domain: action.action.domain,
                service: action.action.service,
                targetEntityID: action.action.targetEntityID,
                serviceData: [
                    "mode": "boost",
                    "duration": 15,
                    "pin": .protectedString(configuredReference)
                ]
            ),
            requiresConfirmation: action.requiresConfirmation
        )
        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [protectedAction])
        let secondAction = EntityCustomAction(
            id: "boost-air-later",
            entityID: "sensor.office_temperature",
            title: "Boost air later",
            action: ActionSpec(
                domain: "script",
                service: "turn_on",
                targetEntityID: "script.air_cleaner_boost",
                serviceData: ["mode": "boost"]
            )
        )
        XCTAssertTrue(application.setCustomAction(secondAction))
        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [protectedAction, secondAction])
        let renamedAction = EntityCustomAction(
            id: action.id,
            entityID: action.entityID,
            title: "Boost air now",
            action: protectedAction.action,
            requiresConfirmation: action.requiresConfirmation
        )
        XCTAssertTrue(application.setCustomAction(renamedAction))
        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [renamedAction, secondAction])
        XCTAssertTrue(application.moveCustomAction(action.id, direction: .down))
        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [secondAction, renamedAction])
        XCTAssertTrue(await application.runCustomAction(action.id))
        let storedProtectedAction = try XCTUnwrap(application.snapshot.customActionConfiguration.action(id: action.id))
        guard case let .protectedString(reference) = storedProtectedAction.action.serviceData["pin"] else {
            return XCTFail("expected protected pin reference")
        }
        XCTAssertEqual(reference, configuredReference)
        XCTAssertEqual(try protectedStore.load(reference), "1234")
        let persistedConfiguration = try store.load()
        let persistedText = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(persistedText.contains("1234"))

        XCTAssertEqual(
            await runner.actions(),
            [
                ActionSpec(
                    domain: action.action.domain,
                    service: action.action.service,
                    targetEntityID: action.action.targetEntityID,
                    serviceData: [
                        "mode": "boost",
                        "duration": 15,
                        "pin": "1234"
                    ]
                )
            ]
        )
        XCTAssertEqual(persistedConfiguration.customActions, [secondAction, renamedAction])

        XCTAssertTrue(application.removeCustomAction(action.id))
        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [secondAction])
        XCTAssertEqual(try? store.load().customActions, [secondAction])
        XCTAssertThrowsError(try protectedStore.load(reference)) { error in
            XCTAssertEqual(error as? ProtectedActionValueStoreError, .missingValue(reference))
        }
        XCTAssertTrue(application.removeCustomAction(secondAction.id))
        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [])
        XCTAssertEqual(try? store.load().customActions, [])
    }

    func test_t_app_shell_custom_action_save_failure_rejects_live_configuration_change() async {
        let store = FailingConfigStore(
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let action = sensorCustomAction()
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: selectionRooms()) }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertFalse(application.setCustomAction(action))
        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [])
        XCTAssertTrue(application.snapshot.customActionPersistenceFailureDescription?.contains("disk full") == true)
        XCTAssertEqual(store.saveCallCount, 1)
        guard case let .saveFailed(message) = application.snapshot.configurationPersistenceState else {
            XCTFail("expected app shell save failure")
            return
        }
        XCTAssertTrue(message.contains("disk full"))
    }

    func testAppShellRollsBackProtectedCustomActionValueWhenSaveFails() async throws {
        let action = sensorCustomAction()
        let store = FailingConfigStore(
            loadedConfiguration: PerchHAConfiguration(customActions: [action]),
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let protectedStore = InMemoryProtectedActionValueStore()
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: selectionRooms()) },
            protectedActionValueStore: protectedStore
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertFalse(application.setCustomActionServiceDataValue(action.id, key: "pin", value: "1234"))
        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [action])
        XCTAssertEqual(try protectedStore.snapshot(), [:])
        XCTAssertTrue(application.snapshot.customActionPersistenceFailureDescription?.contains("disk full") == true)
    }

    func test_t_app_shell_custom_action_remove_failure_rejects_live_configuration_change() {
        let action = sensorCustomAction()
        let store = FailingConfigStore(
            loadedConfiguration: PerchHAConfiguration(customActions: [action]),
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let application = PerchHAApplication(configStore: store)
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [action])
        XCTAssertFalse(application.removeCustomAction(action.id))
        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [action])
        XCTAssertTrue(application.snapshot.customActionPersistenceFailureDescription?.contains("disk full") == true)
        XCTAssertEqual(store.saveCallCount, 1)
        guard case let .saveFailed(message) = application.snapshot.configurationPersistenceState else {
            XCTFail("expected app shell save failure")
            return
        }
        XCTAssertTrue(message.contains("disk full"))
    }

    func test_t_app_shell_rejects_invalid_loaded_custom_action_configuration() {
        let action = EntityCustomAction(
            id: "bad-action",
            entityID: "sensor.office_temperature",
            title: " ",
            action: ActionSpec(domain: "script", service: "turn_on", targetEntityID: "script.air_cleaner_boost")
        )
        let store = FailingConfigStore(
            loadedConfiguration: PerchHAConfiguration(customActions: [action])
        )
        let application = PerchHAApplication(configStore: store)
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        XCTAssertEqual(application.snapshot.customActionConfiguration.actions, [])
        guard case let .loadFailed(message) = application.snapshot.configurationPersistenceState else {
            XCTFail("expected app shell load failure")
            return
        }
        XCTAssertTrue(message.contains("custom action bad-action is incomplete"))
    }

    func test_t_settings_toggle_updates_selection_and_persists() async {
        let sink = SelectionSinkRecorder()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            selectionSink: { selection in
                sink.record(selection)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        model.toggleSettings()
        model.updateSelectionQuery("office")
        model.setEntity("sensor.office_temperature", isSelected: false)

        XCTAssertTrue(model.snapshot.isSettingsPresented)
        XCTAssertEqual(model.snapshot.selectionTree.map(\.id), ["office"])
        XCTAssertTrue(model.snapshot.selectionConfiguration.isExplicit)
        XCTAssertFalse(model.snapshot.selectionConfiguration.selectedEntityIDs.contains("sensor.office_temperature"))
        XCTAssertEqual(sink.lastSelection?.isExplicit, true)
    }

    func test_t_settings_reorders_rooms_and_entities_and_persists() async {
        let sink = SelectionSinkRecorder()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            selectionConfiguration: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
                isExplicit: true
            ),
            selectionSink: { selection in
                sink.record(selection)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.moveRoom("kitchen", direction: .up))
        XCTAssertEqual(model.snapshot.rooms.map(\.id), ["kitchen", "office"])
        XCTAssertEqual(model.snapshot.rooms.flatMap(\.entities).map(\.id), [
            "switch.kitchen_light",
            "sensor.office_temperature",
            "sensor.office_humidity"
        ])
        XCTAssertEqual(sink.lastSelection?.roomOrder, ["kitchen", "office"])

        XCTAssertTrue(model.moveEntity("sensor.office_humidity", direction: .up))
        XCTAssertEqual(model.snapshot.rooms.flatMap(\.entities).map(\.id), [
            "switch.kitchen_light",
            "sensor.office_humidity",
            "sensor.office_temperature"
        ])
        XCTAssertEqual(sink.lastSelection?.entityOrder, [
            "switch.kitchen_light",
            "sensor.office_humidity",
            "sensor.office_temperature"
        ])
        XCTAssertEqual(sink.lastSelection?.selectedEntityIDs, [
            "switch.kitchen_light",
            "sensor.office_humidity",
            "sensor.office_temperature"
        ])
    }

    func test_t_settings_drag_reorder_places_rooms_and_entities_and_persists() async {
        let sink = SelectionSinkRecorder()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            selectionConfiguration: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
                isExplicit: true
            ),
            selectionSink: { selection in
                sink.record(selection)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.moveRoom("office", relativeTo: "kitchen", placement: .after))
        XCTAssertEqual(model.snapshot.rooms.map(\.id), ["kitchen", "office"])
        XCTAssertEqual(sink.lastSelection?.roomOrder, ["kitchen", "office"])

        XCTAssertTrue(model.moveEntity("sensor.office_temperature", relativeTo: "sensor.office_humidity", placement: .after))
        XCTAssertEqual(model.snapshot.rooms.flatMap(\.entities).map(\.id), [
            "switch.kitchen_light",
            "sensor.office_humidity",
            "sensor.office_temperature"
        ])
        XCTAssertEqual(sink.lastSelection?.entityOrder, [
            "switch.kitchen_light",
            "sensor.office_humidity",
            "sensor.office_temperature"
        ])
    }

    func test_t_settings_reorders_promoted_menu_bar_entities_and_persists() async {
        let sink = MenuBarDisplaySinkRecorder()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            menuBarDisplayConfiguration: MenuBarDisplayConfiguration(
                promotedEntityIDs: ["sensor.office_humidity", "sensor.office_temperature"]
            ),
            menuBarDisplaySink: { displayConfiguration in
                sink.record(displayConfiguration)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.moveMenuBarEntity("sensor.office_humidity", direction: .down))
        XCTAssertEqual(model.snapshot.menuBarDisplayConfiguration.promotedEntityIDs, [
            "sensor.office_temperature",
            "sensor.office_humidity"
        ])
        XCTAssertEqual(sink.lastDisplayConfiguration?.promotedEntityIDs, [
            "sensor.office_temperature",
            "sensor.office_humidity"
        ])

        XCTAssertTrue(
            model.moveMenuBarEntity(
                "sensor.office_humidity",
                relativeTo: "sensor.office_temperature",
                placement: .before
            )
        )
        XCTAssertEqual(model.snapshot.menuBarDisplayConfiguration.promotedEntityIDs, [
            "sensor.office_humidity",
            "sensor.office_temperature"
        ])
        XCTAssertFalse(model.moveMenuBarEntity("sensor.office_humidity", direction: .up))
    }

    func test_t_settings_search_blocks_promoted_menu_bar_reorder() async {
        let sink = MenuBarDisplaySinkRecorder()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            menuBarDisplayConfiguration: MenuBarDisplayConfiguration(
                promotedEntityIDs: ["sensor.office_humidity", "sensor.office_temperature"]
            ),
            menuBarDisplaySink: { displayConfiguration in
                sink.record(displayConfiguration)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        model.toggleSettings()
        model.updateSelectionQuery("humidity")

        XCTAssertEqual(model.snapshot.selectionTree.flatMap(\.entities).map(\.entity.id), ["sensor.office_humidity"])
        XCTAssertFalse(model.moveMenuBarEntity("sensor.office_humidity", direction: .down))
        XCTAssertFalse(
            model.moveMenuBarEntity(
                "sensor.office_humidity",
                relativeTo: "sensor.office_temperature",
                placement: .after
            )
        )
        XCTAssertEqual(model.snapshot.menuBarDisplayConfiguration.promotedEntityIDs, [
            "sensor.office_humidity",
            "sensor.office_temperature"
        ])
        XCTAssertNil(sink.lastDisplayConfiguration)
    }

    func test_t_settings_rejects_promoted_menu_bar_reorder_when_save_fails() async {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            menuBarDisplayConfiguration: MenuBarDisplayConfiguration(
                promotedEntityIDs: ["sensor.office_humidity", "sensor.office_temperature"]
            ),
            menuBarDisplaySink: { _ in
                .failed("disk full")
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertFalse(model.moveMenuBarEntity("sensor.office_humidity", direction: .down))
        XCTAssertEqual(model.snapshot.menuBarDisplayConfiguration.promotedEntityIDs, [
            "sensor.office_humidity",
            "sensor.office_temperature"
        ])
        XCTAssertTrue(model.snapshot.displayPersistenceFailureDescription?.contains("disk full") == true)
    }

    func test_t_settings_updates_default_history_range_and_persists() async {
        let sink = MenuBarDisplaySinkRecorder()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            menuBarDisplayConfiguration: MenuBarDisplayConfiguration(
                promotedEntityIDs: ["sensor.office_humidity"],
                itemConfigurations: [
                    MenuBarItemConfiguration(entityID: "sensor.office_humidity")
                ]
            ),
            menuBarDisplaySink: { displayConfiguration in
                sink.record(displayConfiguration)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.setMenuBarDefaultHistoryRange("sensor.office_humidity", defaultHistoryRange: .week))
        XCTAssertEqual(
            model.snapshot.menuBarDisplayConfiguration
                .itemConfiguration(for: "sensor.office_humidity")
                .defaultHistoryRange,
            .week
        )
        XCTAssertEqual(
            sink.lastDisplayConfiguration?
                .itemConfiguration(for: "sensor.office_humidity")
                .defaultHistoryRange,
            .week
        )
    }

    func test_t_settings_rejects_default_history_range_when_save_fails() async {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            menuBarDisplayConfiguration: MenuBarDisplayConfiguration(
                promotedEntityIDs: ["sensor.office_humidity"],
                itemConfigurations: [
                    MenuBarItemConfiguration(entityID: "sensor.office_humidity", defaultHistoryRange: .day)
                ]
            ),
            menuBarDisplaySink: { _ in
                .failed("disk full")
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertFalse(model.setMenuBarDefaultHistoryRange("sensor.office_humidity", defaultHistoryRange: .month))
        XCTAssertEqual(
            model.snapshot.menuBarDisplayConfiguration
                .itemConfiguration(for: "sensor.office_humidity")
                .defaultHistoryRange,
            .day
        )
        XCTAssertTrue(model.snapshot.displayPersistenceFailureDescription?.contains("disk full") == true)
    }

    func testSelectionDropTranslatorUsesTargetRelativePlacement() {
        let tree = EntitySelectionProjector().selectionTree(
            rooms: selectionRooms(),
            configuration: EntitySelectionConfiguration()
        )
        let translator = SelectionDropTranslator()

        XCTAssertEqual(
            translator.translate(source: .room("office"), target: .room("kitchen"), tree: tree),
            .room(source: "office", target: "kitchen", placement: .after)
        )
        XCTAssertEqual(
            translator.translate(source: .room("kitchen"), target: .room("office"), tree: tree),
            .room(source: "kitchen", target: "office", placement: .before)
        )
        XCTAssertEqual(
            translator.translate(
                source: .entity("sensor.office_temperature"),
                target: .entity("sensor.office_humidity"),
                tree: tree
            ),
            .entity(source: "sensor.office_temperature", target: "sensor.office_humidity", placement: .after)
        )
        XCTAssertEqual(
            translator.translate(
                source: .entity("switch.kitchen_light"),
                target: .entity("sensor.office_temperature"),
                tree: tree
            ),
            .unsupported
        )
    }

    func test_t_settings_reorder_boundary_move_does_not_persist() async {
        let sink = SelectionSinkRecorder()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            selectionSink: { selection in
                sink.record(selection)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertFalse(model.moveRoom("office", direction: .up))
        XCTAssertNil(sink.lastSelection)
    }

    func test_t_reordering_after_refresh_failure_keeps_rows_stale() async {
        let sink = SelectionSinkRecorder()
        var calls = 0
        let model = PerchHAPanelModel(
            connector: { _ in
                calls += 1
                if calls == 1 {
                    return .success(rooms: selectionRooms())
                }
                return .failure(.unreachable(host: "homeassistant.local"))
            },
            selectionSink: { selection in
                sink.record(selection)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        await model.refresh()

        XCTAssertTrue(model.moveEntity("sensor.office_humidity", direction: .up))

        XCTAssertEqual(model.snapshot.phase, .failedStale(.unreachable(host: "homeassistant.local")))
        XCTAssertEqual(model.snapshot.rooms.first?.entities.map(\.id), [
            "sensor.office_humidity",
            "sensor.office_temperature"
        ])
        XCTAssertEqual(
            model.snapshot.rooms.first?.entities.first.map { model.snapshot.formattedValue(for: $0, locale: Locale(identifier: "en_US")) },
            FormattedEntityValue(text: "Stale: 44 %", status: .stale)
        )
        XCTAssertEqual(sink.lastSelection?.entityOrder, [
            "sensor.office_humidity",
            "sensor.office_temperature",
            "switch.kitchen_light"
        ])
    }

    func test_t_reconnect_request_volume_uses_single_discovery_and_service_metadata_fetch() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
            areaRegistryBody: #"[{"area_id":"office","name":"Office"}]"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryDisplayBody: #"{"entities":[{"ei":"sensor.office_temperature","en":"Office temperature","ai":"office"}]}"#,
            entityRegistryBody: #"[{"entity_id":"sensor.office_temperature","name":"Office temperature","area_id":"office"}]"#,
            servicesBody: #"{}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }

        let client = HomeAssistantClient()
        let model = PerchHAPanelModel(
            connector: { form in
                guard let primaryURL = form.primaryURL() else {
                    return .failure(.protocolError("invalid Home Assistant URL"))
                }
                let input = HAConnectionInput(
                    endpoint: HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL()),
                    token: form.trimmedToken
                )
                switch await client.discovery(input) {
                case let .success(snapshot):
                    return .success(rooms: RoomResolver().resolve(snapshot: snapshot))
                case let .failure(failure):
                    return .failure(failure.connectionFailure)
                }
            },
            serviceMetadataProvider: { form in
                guard let primaryURL = form.primaryURL() else {
                    return .unavailable("invalid Home Assistant URL")
                }
                let input = HAConnectionInput(
                    endpoint: HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL()),
                    token: form.trimmedToken
                )
                switch await client.services(input) {
                case let .success(metadata):
                    return .success(metadata)
                case let .failure(failure):
                    return .unavailable(failure.description)
                }
            }
        )
        let expectedPathCounts = [
            "/api/websocket": 2,
            "/api/websocket/config/area_registry/list": 1,
            "/api/websocket/config/device_registry/list": 1,
            "/api/websocket/config/entity_registry/list_for_display": 1,
            "/api/websocket/get_services": 1
        ]
        let expectedPathCount = expectedPathCounts.values.reduce(0, +)

        func pathCounts(_ paths: [String]) -> [String: Int] {
            Dictionary(grouping: paths, by: { $0 }).mapValues(\.count)
        }

        func requestPaths(after index: Int) async -> [String] {
            let paths = await server.journal.snapshot().map(\.path)
            return Array(paths.dropFirst(index))
        }

        model.updateConnectionForm(urlString: server.baseURL.absoluteString, token: "fake-token")
        await model.connect()

        await spinUntil {
            await requestPaths(after: 0).count >= expectedPathCount
        }
        let initialPaths = await requestPaths(after: 0)
        XCTAssertEqual(pathCounts(initialPaths), expectedPathCounts)
        XCTAssertFalse(initialPaths.contains("/api/websocket/config/entity_registry/list"))

        let beforeRefreshCount = initialPaths.count
        await model.refresh()

        await spinUntil {
            await requestPaths(after: beforeRefreshCount).count >= expectedPathCount
        }
        let reconnectPaths = await requestPaths(after: beforeRefreshCount)
        XCTAssertEqual(model.snapshot.refreshCount, 1)
        XCTAssertEqual(pathCounts(reconnectPaths), expectedPathCounts)
        XCTAssertFalse(reconnectPaths.contains("/api/websocket/config/entity_registry/list"))
        XCTAssertNil(model.snapshot.serviceMetadataFailureDescription)
    }

    func test_t_reconnecting_rows_render_as_stale_values() async {
        let refreshGate = ConnectionGate()
        let model = PerchHAPanelModel { _ in
            await refreshGate.wait()
            return .success(rooms: selectionRooms())
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await refreshGate.open()
        await model.connect()

        let secondGate = ConnectionGate()
        let refreshing = PerchHAPanelModel(
            connector: { _ in
                await secondGate.wait()
                return .success(rooms: selectionRooms())
            }
        )
        refreshing.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await secondGate.open()
        await refreshing.connect()

        let thirdGate = ConnectionGate()
        let staleModel = PerchHAPanelModel(
            connector: { _ in
                await thirdGate.wait()
                return .success(rooms: selectionRooms())
            }
        )
        staleModel.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await thirdGate.open()
        await staleModel.connect()
        staleModel.startRefresh()
        await spinUntil { staleModel.snapshot.connectionState == .reconnecting(attempt: 1) }

        let entity = staleModel.snapshot.rooms.first?.entities.first
        XCTAssertEqual(
            entity.map { staleModel.snapshot.formattedValue(for: $0, locale: Locale(identifier: "en_US")) },
            FormattedEntityValue(text: "Stale: 21.4 °C", status: .stale)
        )
    }

    func test_t_live_update_during_reconnect_preserves_stale_phase() async {
        let refreshGate = ConnectionGate()
        var calls = 0
        let model = PerchHAPanelModel { _ in
            calls += 1
            if calls == 1 {
                return .success(rooms: selectionRooms())
            }
            await refreshGate.wait()
            return .success(rooms: selectionRooms())
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        model.startRefresh()
        await spinUntil { model.snapshot.connectionState == .reconnecting(attempt: 1) }

        XCTAssertTrue(
            model.applyLiveState(
                EntityState(
                    id: "sensor.office_humidity",
                    name: "Office humidity",
                    state: "47",
                    unit: "%"
                )
            )
        )
        XCTAssertEqual(model.snapshot.connectionState, .reconnecting(attempt: 1))
        XCTAssertEqual(model.snapshot.phase, .reconnecting(attempt: 1))
        XCTAssertEqual(
            model.snapshot.rooms.first?.entities.last.map { model.snapshot.formattedValue(for: $0, locale: Locale(identifier: "en_US")) },
            FormattedEntityValue(text: "Stale: 47 %", status: .stale)
        )

        model.cancelInFlightAction()
        await refreshGate.open()
    }

    func test_t_refresh_failure_keeps_last_rows_visible_as_stale() async {
        var calls = 0
        let model = PerchHAPanelModel { _ in
            calls += 1
            if calls == 1 {
                return .success(rooms: selectionRooms())
            }
            return .failure(.unreachable(host: "homeassistant.local"))
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        await model.refresh()

        XCTAssertEqual(model.snapshot.connectionState, .failed(.unreachable(host: "homeassistant.local")))
        XCTAssertEqual(model.snapshot.phase, .failedStale(.unreachable(host: "homeassistant.local")))
        XCTAssertEqual(model.snapshot.visibleEntityCount, 3)
        XCTAssertEqual(
            model.snapshot.rooms.first?.entities.first.map { model.snapshot.formattedValue(for: $0, locale: Locale(identifier: "en_US")) },
            FormattedEntityValue(text: "Stale: 21.4 °C", status: .stale)
        )
    }

    func test_t_live_update_after_refresh_failure_preserves_failed_stale_phase() async {
        let failure = ConnectionFailure.unreachable(host: "homeassistant.local")
        var calls = 0
        let model = PerchHAPanelModel { _ in
            calls += 1
            if calls == 1 {
                return .success(rooms: selectionRooms())
            }
            return .failure(failure)
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        await model.refresh()

        XCTAssertTrue(
            model.applyLiveState(
                EntityState(
                    id: "sensor.office_humidity",
                    name: "Office humidity",
                    state: "47",
                    unit: "%"
                )
            )
        )
        XCTAssertEqual(model.snapshot.connectionState, .failed(failure))
        XCTAssertEqual(model.snapshot.phase, .failedStale(failure))
        XCTAssertEqual(
            model.snapshot.rooms.first?.entities.last.map { model.snapshot.formattedValue(for: $0, locale: Locale(identifier: "en_US")) },
            FormattedEntityValue(text: "Stale: 47 %", status: .stale)
        )
    }

    func test_t_cancelling_reconnect_does_not_mark_state_connected() async {
        let gate = ConnectionGate()
        let model = PerchHAPanelModel { _ in
            await gate.wait()
            return .success(rooms: selectionRooms())
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await gate.open()
        await model.connect()

        let refreshGate = ConnectionGate()
        let refreshing = PerchHAPanelModel { _ in
            await refreshGate.wait()
            return .success(rooms: selectionRooms())
        }
        refreshing.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await refreshGate.open()
        await refreshing.connect()

        let blockedGate = ConnectionGate()
        let blocked = PerchHAPanelModel { _ in
            await blockedGate.wait()
            return .success(rooms: selectionRooms())
        }
        blocked.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await blockedGate.open()
        await blocked.connect()
        blocked.startRefresh()
        await spinUntil { blocked.snapshot.connectionState == .reconnecting(attempt: 1) }
        blocked.cancelInFlightAction()

        XCTAssertEqual(blocked.snapshot.connectionState, .reconnecting(attempt: 1))
        XCTAssertEqual(blocked.snapshot.phase, .reconnecting(attempt: 1))
        XCTAssertTrue(blocked.snapshot.valuesAreStale)
    }

    func test_t_vanished_selected_ids_are_removed_when_selection_changes() async {
        let sink = SelectionSinkRecorder()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            selectionConfiguration: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.missing", "sensor.office_temperature"],
                isExplicit: true
            ),
            selectionSink: { selection in
                sink.record(selection)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        model.setEntity("sensor.office_humidity", isSelected: true)

        XCTAssertEqual(Set(model.snapshot.selectionConfiguration.selectedEntityIDs), Set<EntityID>(["sensor.office_temperature", "sensor.office_humidity"]))
        XCTAssertEqual(Set(sink.lastSelection?.selectedEntityIDs ?? []), Set<EntityID>(["sensor.office_temperature", "sensor.office_humidity"]))
    }

    func test_t_manual_refresh_updates_panel_values() async {
        var calls = 0
        let model = PerchHAPanelModel { _ in
            calls += 1
            return .success(
                rooms: [
                    Room(
                        id: "office",
                        name: "Office",
                        entities: [
                            DiscoveredEntity(
                                id: "sensor.office_temperature",
                                name: "Office temperature",
                                state: "\(20 + calls)",
                                unit: "°C",
                                areaID: "office",
                                deviceID: nil
                            )
                        ]
                    )
                ]
            )
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        await model.refresh()

        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertEqual(model.snapshot.rooms.first?.entities.first?.state, "22")
        XCTAssertEqual(model.snapshot.refreshCount, 1)
        XCTAssertEqual(model.snapshot.lastUpdateDescription, "Refresh 1 complete")
    }

    func testConnectedEmptyStateDoesNotShowFirstRunPhase() async {
        let model = PerchHAPanelModel { _ in
            .success(rooms: [])
        }

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertEqual(model.snapshot.phase, .connectedEmpty)
        XCTAssertEqual(model.snapshot.visibleEntityCount, 0)
        XCTAssertTrue(model.snapshot.canRefresh)
    }

    func testPanelSnapshotRedactsTokenForDiagnostics() {
        let snapshot = PerchHAPanelSnapshot(
            connectionForm: PerchHAConnectionForm(
                urlString: "http://127.0.0.1:8123",
                fallbackURLString: "",
                token: "secret-token"
            )
        )

        XCTAssertEqual(snapshot.redactedForDiagnostics().connectionForm.token, "")
        XCTAssertTrue(snapshot.redactedForDiagnostics().hasTokenInput)
        XCTAssertEqual(snapshot.connectionForm.token, "")
        XCTAssertTrue(snapshot.hasTokenInput)
        XCTAssertFalse(snapshot.redactedForDiagnostics().accessibilitySummary.contains("secret-token"))
    }

    func testAppShellPanelCanBecomeKeyForFirstRunTextEntry() {
        let panel = PerchHAApplication.makePanel(model: PerchHAPanelModel())
        defer {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }
        let frameSize = panel.frame.size

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(panel.titleVisibility, .hidden)
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertTrue(panel.hidesOnDeactivate)
        XCTAssertNotNil(panel.contentViewController)
        XCTAssertEqual(Int(frameSize.width.rounded()), 360)
        XCTAssertGreaterThanOrEqual(Int(frameSize.height.rounded()), 420)
    }

    func testAppShellSettingsCustomActionEditorExposesOrderedNativeTextFieldFocusPath() {
        let action = EntityCustomAction(
            id: "boost-air",
            entityID: "sensor.office_temperature",
            title: "Boost air",
            action: ActionSpec(
                domain: "script",
                service: "turn_on",
                targetEntityID: "script.air_cleaner_boost",
                serviceData: [
                    "variables": .object([
                        "steps": .array(["fan", "purifier"])
                    ])
                ]
            ),
            requiresConfirmation: true
        )
        let rooms = selectionRooms()
        let snapshot = PerchHAPanelSnapshot(
            connectionState: .connected,
            phase: .connectedData,
            rooms: rooms,
            availableRooms: rooms,
            selectionQuery: "temperature",
            isSettingsPresented: true,
            lastUpdateDescription: "Snapshot ready",
            canRetry: true
        )
        let model = PerchHAPanelModel(
            snapshot: snapshot,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            customActionConfiguration: CustomActionConfiguration(actions: [action])
        )
        let panel = PerchHAApplication.makePanel(model: model)
        defer {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }

        panel.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()

        let textFields = editableTextFields(in: panel.contentView)
        let popUpButtons = nativePopUpButtons(in: panel.contentView)
        let debugSummary = nativeControlDebugSummary(in: panel.contentView)
        let titleField = textFields.first { $0.placeholderString == "Title" }
        let targetField = textFields.first { $0.placeholderString == "Target entity" }
        let keyField = textFields.first { $0.placeholderString == "Key" }
        let valueField = textFields.first { $0.placeholderString == "Value" }

        XCTAssertNotNil(titleField, debugSummary)
        XCTAssertNotNil(targetField, debugSummary)
        XCTAssertNotNil(keyField, debugSummary)
        XCTAssertNotNil(valueField, debugSummary)
        let selectedPopupTitles = Set(popUpButtons.compactMap(\.titleOfSelectedItem))
        XCTAssertTrue(selectedPopupTitles.contains("script"), debugSummary)
        XCTAssertTrue(selectedPopupTitles.contains("turn_on"), debugSummary)
        XCTAssertTrue(selectedPopupTitles.contains("Object"), debugSummary)
        XCTAssertTrue(selectedPopupTitles.contains("List"), debugSummary)

        guard let titleField else {
            return
        }
        XCTAssertTrue(panel.makeFirstResponder(titleField))
        let firstResponder = panel.firstResponder as AnyObject?
        XCTAssertTrue(firstResponder === titleField.currentEditor() || firstResponder === titleField)

        let keyViewLabels = nativeKeyViewLoopLabels(startingAt: titleField)
        let keyViewSummary = keyViewLabels.joined(separator: " -> ")
        let targetIndex = keyViewLabels.firstIndex { $0.contains("placeholder:Target entity") }
        let keyIndex = keyViewLabels.firstIndex { $0.contains("placeholder:Key") }
        let valueIndex = keyViewLabels.firstIndex { $0.contains("placeholder:Value") }

        XCTAssertNotNil(targetIndex, keyViewSummary)
        XCTAssertNotNil(keyIndex, keyViewSummary)
        XCTAssertNotNil(valueIndex, keyViewSummary)
        if let targetIndex, let keyIndex, let valueIndex {
            XCTAssertGreaterThan(targetIndex, 0, keyViewSummary)
            XCTAssertGreaterThan(keyIndex, targetIndex, keyViewSummary)
            XCTAssertGreaterThan(valueIndex, keyIndex, keyViewSummary)
        }
    }

    func testAppShellConnectionFormNormalizesFrontendURLsThroughNativeTextFields() throws {
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel { form in
            await recorder.record(form)
            return .success(rooms: [])
        }
        let panel = PerchHAApplication.makePanel(model: model)
        defer {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }

        panel.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()

        let textFields = editableTextFields(in: panel.contentView)
        let debugSummary = nativeControlDebugSummary(in: panel.contentView)
        guard let urlField = textFields.first(where: { $0.placeholderString == "Home Assistant URL" }) else {
            XCTFail(debugSummary)
            return
        }
        guard let fallbackField = textFields.first(where: { $0.placeholderString == "Fallback URL" }) else {
            XCTFail(debugSummary)
            return
        }

        try setNativeTextFieldValue("https://home.gomoo.io/lovelace/0", for: urlField, in: panel)
        try setNativeTextFieldValue("https://fallback.example/ha/history?entity=sensor.temp", for: fallbackField, in: panel)

        XCTAssertEqual(model.snapshot.connectionForm.urlString, "https://home.gomoo.io")
        XCTAssertEqual(model.snapshot.connectionForm.fallbackURLString, "https://fallback.example/ha")
    }

    func testAppShellConnectionFormUsesNativeSecurePasswordFieldForTokenEntry() {
        let model = PerchHAPanelModel()
        let panel = PerchHAApplication.makePanel(model: model)
        defer {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }

        panel.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()

        let secureFields = secureTextFields(in: panel.contentView)
        let debugSummary = nativeControlDebugSummary(in: panel.contentView)
        guard let tokenField = secureFields.first(where: { $0.placeholderString == "Access token" }) else {
            XCTFail(debugSummary)
            return
        }

        if #available(macOS 11.0, *) {
            XCTAssertEqual(tokenField.contentType, .password)
        }
    }

    func testAppShellConnectionFormSupportsCommandVPasteInStatusPanel() throws {
        let model = PerchHAPanelModel()
        let panel = PerchHAApplication.makePanel(model: model)
        defer {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }

        panel.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()

        let textFields = editableTextFields(in: panel.contentView)
        let debugSummary = nativeControlDebugSummary(in: panel.contentView)
        guard let urlField = textFields.first(where: { $0.placeholderString == "Home Assistant URL" }) else {
            XCTFail(debugSummary)
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("https://home.gomoo.io/lovelace/0", forType: .string))

        XCTAssertTrue(panel.makeFirstResponder(urlField))
        drainPanelRunLoop()
        let firstResponder = panel.firstResponder as AnyObject?
        let responder = urlField.currentEditor() ?? urlField
        XCTAssertTrue(firstResponder === responder || firstResponder === urlField)

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "v",
                charactersIgnoringModifiers: "v",
                isARepeat: false,
                keyCode: 9
            )
        )

        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        drainPanelRunLoop()
        panel.endEditing(for: nil)
        drainPanelRunLoop()

        XCTAssertEqual(model.snapshot.connectionForm.urlString, "https://home.gomoo.io")
    }

    func testAppShellSettingsCustomActionEditorMutatesNestedServiceDataThroughNativeTextFields() throws {
        let action = EntityCustomAction(
            id: "boost-air",
            entityID: "sensor.office_temperature",
            title: "Boost air",
            action: ActionSpec(
                domain: "script",
                service: "turn_on",
                targetEntityID: "script.air_cleaner_boost",
                serviceData: [
                    "variables": .object([
                        "steps": .array(["fan", "purifier"])
                    ])
                ]
            ),
            requiresConfirmation: true
        )
        let rooms = selectionRooms()
        let snapshot = PerchHAPanelSnapshot(
            connectionState: .connected,
            phase: .connectedData,
            rooms: rooms,
            availableRooms: rooms,
            selectionQuery: "temperature",
            isSettingsPresented: true,
            lastUpdateDescription: "Snapshot ready",
            canRetry: true,
            serviceMetadata: [
                HAServiceMetadata(
                    domain: "script",
                    service: "turn_on",
                    name: "Turn on",
                    description: nil,
                    fields: [
                        HAServiceFieldMetadata(
                            key: "variables",
                            name: "Variables",
                            description: nil,
                            required: false,
                            example: .object([
                                "steps": .array(["fan", "purifier"])
                            ]),
                            selector: .object(["object": .object([:])])
                        )
                    ]
                )
            ]
        )
        let model = PerchHAPanelModel(
            snapshot: snapshot,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            customActionConfiguration: CustomActionConfiguration(actions: [action])
        )
        let panel = PerchHAApplication.makePanel(model: model)
        defer {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }

        panel.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()

        let textFields = editableTextFields(in: panel.contentView)
        let debugSummary = nativeControlDebugSummary(in: panel.contentView)
        guard let titleField = textFields.first(where: { $0.placeholderString == "Title" && $0.stringValue == "Boost air" }) else {
            XCTFail(debugSummary)
            return
        }
        guard let targetField = textFields.first(where: { $0.placeholderString == "Target entity" && $0.stringValue == "script.air_cleaner_boost" }) else {
            XCTFail(debugSummary)
            return
        }
        let valueFields = textFields.filter { $0.placeholderString == "Value" }
        guard let nestedValueField = valueFields.last else {
            XCTFail(debugSummary)
            return
        }

        try setNativeTextFieldValue("Boost harder", for: titleField, in: panel)
        try setNativeTextFieldValue("script.air_cleaner_quiet", for: targetField, in: panel)
        try setNativeTextFieldValue("boost", for: nestedValueField, in: panel)

        let updatedAction = try XCTUnwrap(model.customActionConfiguration.action(id: "boost-air"))
        XCTAssertEqual(updatedAction.title, "Boost harder")
        XCTAssertEqual(updatedAction.action.targetEntityID, "script.air_cleaner_quiet")
        XCTAssertEqual(
            updatedAction.action.serviceData,
            [
                "variables": .object([
                    "steps": .array(["fan", "boost"])
                ])
            ]
        )
    }

    func testAppShellSettingsCustomActionEditorMutatesServiceAndNestedTypeThroughNativePopups() throws {
        let action = EntityCustomAction(
            id: "boost-air",
            entityID: "sensor.office_temperature",
            title: "Boost air",
            action: ActionSpec(
                domain: "script",
                service: "turn_on",
                targetEntityID: "script.air_cleaner_boost",
                serviceData: [
                    "variables": .object([
                        "steps": .array(["fan", "purifier"])
                    ])
                ]
            ),
            requiresConfirmation: true
        )
        let rooms = selectionRooms()
        let snapshot = PerchHAPanelSnapshot(
            connectionState: .connected,
            phase: .connectedData,
            rooms: rooms,
            availableRooms: rooms,
            selectionQuery: "temperature",
            isSettingsPresented: true,
            lastUpdateDescription: "Snapshot ready",
            canRetry: true,
            serviceMetadata: [
                HAServiceMetadata(
                    domain: "script",
                    service: "turn_on",
                    name: "Turn on",
                    description: nil,
                    fields: [
                        HAServiceFieldMetadata(
                            key: "variables",
                            name: "Variables",
                            description: nil,
                            required: false,
                            example: .object([
                                "steps": .array(["fan", "purifier"])
                            ]),
                            selector: .object(["object": .object([:])])
                        )
                    ]
                ),
                HAServiceMetadata(
                    domain: "script",
                    service: "turn_off",
                    name: "Turn off",
                    description: nil,
                    fields: [
                        HAServiceFieldMetadata(
                            key: "transition",
                            name: "Transition",
                            description: nil,
                            required: false,
                            example: 3,
                            selector: .object(["number": .object(["min": 0])])
                        )
                    ]
                )
            ]
        )
        let model = PerchHAPanelModel(
            snapshot: snapshot,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            customActionConfiguration: CustomActionConfiguration(actions: [action])
        )
        let panel = PerchHAApplication.makePanel(model: model)
        defer {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }

        panel.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()

        let popUpButtons = nativePopUpButtons(in: panel.contentView)
        let debugSummary = nativeControlDebugSummary(in: panel.contentView)
        guard let servicePopUp = popUpButtons.first(where: { $0.titleOfSelectedItem == "turn_on" }) else {
            XCTFail(debugSummary)
            return
        }
        guard let typePopUp = popUpButtons.first(where: { $0.titleOfSelectedItem == "List" }) else {
            XCTFail(debugSummary)
            return
        }

        try setNativePopUpSelection("turn_off", for: servicePopUp)
        try setNativePopUpSelection("Text", for: typePopUp)

        let updatedAction = try XCTUnwrap(model.customActionConfiguration.action(id: "boost-air"))
        XCTAssertEqual(updatedAction.action.service, "turn_off")
        XCTAssertEqual(
            updatedAction.action.serviceData,
            [
                "variables": .object([
                    "steps": ""
                ]),
                "transition": 3
            ]
        )
    }

    func testAppShellBuiltInControlsExposeNativeSwitchAndSlider() {
        let rooms = controlRooms()
        let snapshot = PerchHAPanelSnapshot(
            connectionState: .connected,
            phase: .connectedData,
            rooms: rooms,
            availableRooms: rooms,
            lastUpdateDescription: "Snapshot ready",
            canRetry: true,
            controlActionState: .failed(entityID: "switch.office_lamp", message: "planned service failure")
        )
        let model = PerchHAPanelModel(snapshot: snapshot)
        let panel = PerchHAApplication.makePanel(model: model)
        defer {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }

        panel.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()

        let switches = nativeSwitches(in: panel.contentView)
        let sliders = nativeSliders(in: panel.contentView)
        let buttons = nativeButtons(in: panel.contentView)
        let debugSummary = nativeControlDebugSummary(in: panel.contentView)

        let controlSwitch = switches.first
        let coverSlider = sliders.first
        let coverButtons = buttons.filter { String(describing: type(of: $0)).contains("SwiftUIAppKitButton") }

        XCTAssertEqual(switches.count, 1, debugSummary)
        XCTAssertEqual(sliders.count, 1, debugSummary)
        XCTAssertGreaterThanOrEqual(coverButtons.count, 3, debugSummary)
        XCTAssertTrue(controlSwitch.map { String(describing: type(of: $0)).contains("PlatformSwitch") } == true, debugSummary)
        XCTAssertTrue(coverSlider.map { String(describing: type(of: $0)).contains("CustomMarkedSlider") } == true, debugSummary)

        if let controlSwitch {
            XCTAssertTrue(controlSwitch.acceptsFirstResponder, debugSummary)
            XCTAssertTrue(panel.makeFirstResponder(controlSwitch))
            let firstResponder = panel.firstResponder as AnyObject?
            XCTAssertTrue(firstResponder === controlSwitch || firstResponder === controlSwitch.currentEditor())
        }
        if let slider = coverSlider {
            XCTAssertTrue(slider.acceptsFirstResponder, debugSummary)
            XCTAssertTrue(panel.makeFirstResponder(slider))
            let firstResponder = panel.firstResponder as AnyObject?
            XCTAssertTrue(firstResponder === slider || firstResponder === slider.currentEditor())
        }
    }

    func test_t_app_shell_launch_wires_status_item_panel_and_cleanup() {
        let application = PerchHAApplication()
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        let snapshot = application.snapshot
        XCTAssertEqual(snapshot.statusItemTitle, "PerchHA")
        XCTAssertFalse(snapshot.statusItemHasImage)
        XCTAssertNil(snapshot.statusItemImageWidth)
        XCTAssertNil(snapshot.statusItemImageHeight)
        XCTAssertTrue(snapshot.statusItemTargetIsApplication)
        XCTAssertTrue(snapshot.statusItemHasAction)
        XCTAssertTrue(snapshot.hasPanel)
        XCTAssertTrue(snapshot.hasPanelModel)
        XCTAssertTrue(snapshot.panelCanBecomeKey)
        XCTAssertTrue(snapshot.panelCanBecomeMain)
        XCTAssertTrue(snapshot.panelIsFloating)
        XCTAssertTrue(snapshot.panelHidesOnDeactivate)
        XCTAssertEqual(snapshot.panelContentWidth, 360)
        XCTAssertEqual(snapshot.panelContentHeight, 420)
        XCTAssertEqual(snapshot.selectedEntityIDs, [])
        XCTAssertEqual(snapshot.menuBarEntityIDs, [])
        XCTAssertEqual(snapshot.roomOrder, [])
        XCTAssertEqual(snapshot.entityOrder, [])
        XCTAssertFalse(snapshot.isEntitySelectionExplicit)
        XCTAssertEqual(snapshot.configurationPersistenceState, .unavailable)

        application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        XCTAssertNil(application.snapshot.statusItemTitle)
        XCTAssertFalse(application.snapshot.statusItemHasImage)
        XCTAssertFalse(application.snapshot.hasPanel)
        XCTAssertFalse(application.snapshot.hasPanelModel)
    }

    func test_t_app_shell_launch_loads_selection_config() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity"],
                menuBarEntityIDs: ["sensor.office_humidity"],
                roomOrder: ["office"],
                entityOrder: ["sensor.office_humidity"],
                isEntitySelectionExplicit: true
            )
        )

        let application = PerchHAApplication(configStore: store)
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        XCTAssertEqual(application.snapshot.selectedEntityIDs, ["sensor.office_humidity"])
        XCTAssertEqual(application.snapshot.menuBarEntityIDs, ["sensor.office_humidity"])
        XCTAssertEqual(application.snapshot.roomOrder, ["office"])
        XCTAssertEqual(application.snapshot.entityOrder, ["sensor.office_humidity"])
        XCTAssertTrue(application.snapshot.isEntitySelectionExplicit)
        XCTAssertEqual(application.snapshot.configurationPersistenceState, .ready)
    }

    func test_t_app_shell_promoted_menu_bar_item_updates_from_panel_and_live_state() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity"],
                menuBarEntityIDs: ["sensor.office_humidity"],
                isEntitySelectionExplicit: true
            )
        )
        let gaugeRenderer = CountingStatusItemGaugeImageRenderer()
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: selectionRooms()) },
            gaugeImageRenderer: gaugeRenderer
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        XCTAssertEqual(application.snapshot.statusItemTitle, "PerchHA")
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "PerchHA")
        XCTAssertFalse(application.snapshot.statusItemHasImage)

        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertEqual(application.snapshot.statusItemTitle, "44 %")
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Office humidity, 44 %")
        XCTAssertFalse(application.snapshot.statusItemHasImage)

        XCTAssertTrue(
            application.applyLiveState(
                EntityState(
                    id: "sensor.office_humidity",
                    name: "Office humidity",
                    state: "47",
                    unit: "%"
                )
            )
        )
        XCTAssertEqual(application.snapshot.statusItemTitle, "47 %")
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Office humidity, 47 %")
        XCTAssertFalse(application.snapshot.statusItemHasImage)
    }

    func test_t_app_shell_load_history_uses_injected_provider() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_temperature"],
                isEntitySelectionExplicit: true
            )
        )
        let recorder = HistoryProviderRecorder(
            results: [
                .success(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4))
            ]
        )
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { form, entityID, range in
                await recorder.provide(form: form, entityID: entityID, range: range)
            }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()
        await application.loadHistory("sensor.office_temperature", range: .hour)

        XCTAssertEqual(await recorder.callCount(), 1)
        XCTAssertEqual(await recorder.tokens(), ["fake-token"])
        XCTAssertEqual(await recorder.ranges(), [.hour])
        XCTAssertEqual(
            application.snapshot.historyState,
            .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4))
        )
    }

    func testAppShellRefreshesStoredOAuthSessionAndRetriesConnectionOnce() async throws {
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            _ = try? sessionStore.clear()
        }
        try sessionStore.save(
            PerchHAAuthSession(
                accessToken: "expired-access",
                refreshToken: "refresh-token",
                clientID: "https://perchha.dev/app"
            )
        )
        let client = RefreshingHAClientRecorder(
            discoveryResults: [
                .failure(.authentication),
                .success(oauthDiscoverySnapshot())
            ],
            refreshResults: [
                .success(
                    HAOAuthToken(
                        accessToken: "fresh-access",
                        refreshToken: nil,
                        expiresInSeconds: 1800,
                        tokenType: "Bearer"
                    )
                )
            ]
        )
        let application = PerchHAApplication(
            configStore: nil,
            authSessionStore: sessionStore,
            client: client
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(
            urlString: "http://homeassistant.local:8123",
            usesStoredAuthSession: true
        )
        await application.connect()

        XCTAssertEqual(application.snapshot.connectionState, .connected)
        XCTAssertEqual(application.snapshot.connectionForm.token, "")
        XCTAssertTrue(application.snapshot.connectionForm.usesStoredAuthSession)
        XCTAssertTrue(application.snapshot.hasTokenInput)
        XCTAssertEqual(await client.discoveryTokens(), ["expired-access", "fresh-access"])
        XCTAssertEqual(
            await client.refreshRequests(),
            [
                OAuthRefreshRequest(
                    baseURL: try XCTUnwrap(URL(string: "http://homeassistant.local:8123")),
                    refreshToken: "refresh-token",
                    clientID: "https://perchha.dev/app",
                    serverTrustPolicy: .default
                )
            ]
        )
        XCTAssertEqual(try sessionStore.load().accessToken, "fresh-access")
        XCTAssertEqual(try sessionStore.load().refreshToken, "refresh-token")
        XCTAssertEqual(try sessionStore.load().clientID, "https://perchha.dev/app")
    }

    func testAppShellForwardsSelfSignedCertificatePolicyToConnectionAndRefresh() async throws {
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            _ = try? sessionStore.clear()
        }
        try sessionStore.save(
            PerchHAAuthSession(
                accessToken: "expired-access",
                refreshToken: "refresh-token",
                clientID: "https://perchha.dev/app"
            )
        )
        let client = RefreshingHAClientRecorder(
            discoveryResults: [
                .failure(.authentication),
                .success(oauthDiscoverySnapshot())
            ],
            refreshResults: [
                .success(
                    HAOAuthToken(
                        accessToken: "fresh-access",
                        refreshToken: nil,
                        expiresInSeconds: 1800,
                        tokenType: "Bearer"
                    )
                )
            ]
        )
        let application = PerchHAApplication(
            configStore: nil,
            authSessionStore: sessionStore,
            client: client
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(
            urlString: "https://HOMEASSISTANT.local:8123",
            fallbackURLString: "https://fallback.example",
            usesStoredAuthSession: true,
            allowsSelfSignedCertificates: true
        )
        await application.connect()

        let expectedPolicy = HAServerTrustPolicy(
            allowedSelfSignedCertificateHosts: ["homeassistant.local", "fallback.example"]
        )
        XCTAssertEqual(application.snapshot.connectionState, .connected)
        XCTAssertEqual(application.snapshot.connectionForm.token, "")
        XCTAssertTrue(application.snapshot.connectionForm.allowsSelfSignedCertificates)
        XCTAssertEqual(await client.discoveryTrustPolicies(), [expectedPolicy, expectedPolicy])
        XCTAssertEqual(
            await client.refreshRequests(),
            [
                OAuthRefreshRequest(
                    baseURL: try XCTUnwrap(URL(string: "https://HOMEASSISTANT.local:8123")),
                    refreshToken: "refresh-token",
                    clientID: "https://perchha.dev/app",
                    serverTrustPolicy: expectedPolicy
                )
            ]
        )
    }

    func testStoredOAuthRefreshUsesFallbackBaseURLAfterPrimaryTransportFailureAndFallbackAuthentication() async throws {
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            _ = try? sessionStore.clear()
        }
        try sessionStore.save(
            PerchHAAuthSession(
                accessToken: "expired-access",
                refreshToken: "refresh-token",
                clientID: "https://perchha.dev/app"
            )
        )
        let client = RefreshingHAClientRecorder(
            discoveryResults: [
                .failure(.unreachable(host: "primary.local")),
                .failure(.authentication),
                .success(oauthDiscoverySnapshot())
            ],
            refreshResults: [
                .success(
                    HAOAuthToken(
                        accessToken: "fresh-access",
                        refreshToken: nil,
                        expiresInSeconds: 1800,
                        tokenType: "Bearer"
                    )
                )
            ]
        )
        let application = PerchHAApplication(
            configStore: nil,
            authSessionStore: sessionStore,
            client: client
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        let primaryURL = try XCTUnwrap(URL(string: "https://primary.local:8123"))
        let fallbackURL = try XCTUnwrap(URL(string: "https://fallback.example"))
        let expectedPolicy = HAServerTrustPolicy(
            allowedSelfSignedCertificateHosts: ["primary.local", "fallback.example"]
        )

        application.updateConnectionForm(
            urlString: primaryURL.absoluteString,
            fallbackURLString: fallbackURL.absoluteString,
            usesStoredAuthSession: true,
            allowsSelfSignedCertificates: true
        )
        await application.connect()

        XCTAssertEqual(application.snapshot.connectionState, .connected)
        XCTAssertEqual(await client.discoveryURLs(), [primaryURL, fallbackURL, fallbackURL])
        XCTAssertEqual(await client.discoveryTokens(), ["expired-access", "expired-access", "fresh-access"])
        XCTAssertEqual(await client.discoveryTrustPolicies(), [expectedPolicy, expectedPolicy, expectedPolicy])
        XCTAssertEqual(
            await client.refreshRequests(),
            [
                OAuthRefreshRequest(
                    baseURL: fallbackURL,
                    refreshToken: "refresh-token",
                    clientID: "https://perchha.dev/app",
                    serverTrustPolicy: expectedPolicy
                )
            ]
        )
        XCTAssertEqual(try sessionStore.load().accessToken, "fresh-access")
    }

    func testAuthorizedGatewayFallsBackAfterPrimaryTransportFailure() async throws {
        let client = RefreshingHAClientRecorder(
            discoveryResults: [
                .failure(.transport("socket closed before response")),
                .success(oauthDiscoverySnapshot())
            ]
        )
        let gateway = PerchHAAuthorizedHomeAssistantGateway(client: client)
        let primaryURL = try XCTUnwrap(URL(string: "https://primary.local:8123"))
        let fallbackURL = try XCTUnwrap(URL(string: "https://fallback.example"))
        let form = PerchHAConnectionForm(
            urlString: primaryURL.absoluteString,
            fallbackURLString: fallbackURL.absoluteString,
            token: "long-lived-token"
        )

        let result = await gateway.connect(form: form)

        XCTAssertEqual(result, .success(rooms: RoomResolver().resolve(snapshot: oauthDiscoverySnapshot())))
        XCTAssertEqual(await client.discoveryURLs(), [primaryURL, fallbackURL])
        XCTAssertEqual(await client.discoveryTokens(), ["long-lived-token", "long-lived-token"])
    }

    func testAppShellClearsStoredOAuthSessionWhenRefreshFails() async throws {
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            _ = try? sessionStore.clear()
        }
        try sessionStore.save(
            PerchHAAuthSession(
                accessToken: "expired-access",
                refreshToken: "refresh-token",
                clientID: "https://perchha.dev/app"
            )
        )
        let client = RefreshingHAClientRecorder(
            discoveryResults: [
                .failure(.authentication)
            ],
            refreshResults: [
                .failure(.authentication)
            ]
        )
        let application = PerchHAApplication(
            configStore: nil,
            authSessionStore: sessionStore,
            client: client
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(
            urlString: "http://homeassistant.local:8123",
            usesStoredAuthSession: true
        )
        await application.connect()

        XCTAssertEqual(application.snapshot.connectionState, .failed(.authentication))
        XCTAssertEqual(application.snapshot.connectionForm.token, "")
        XCTAssertFalse(application.snapshot.connectionForm.usesStoredAuthSession)
        XCTAssertFalse(application.snapshot.hasTokenInput)
        XCTAssertEqual(await client.discoveryTokens(), ["expired-access"])
        XCTAssertEqual(await client.refreshRequests().map(\.refreshToken), ["refresh-token"])
        XCTAssertThrowsError(try sessionStore.load()) { error in
            XCTAssertEqual(error as? SecretStoreError, .notFound(.accessToken))
        }
    }

    func testAppShellDoesNotLoopWhenRetryAfterRefreshStillAuthenticates() async throws {
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            _ = try? sessionStore.clear()
        }
        try sessionStore.save(
            PerchHAAuthSession(
                accessToken: "expired-access",
                refreshToken: "refresh-token",
                clientID: "https://perchha.dev/app"
            )
        )
        let client = RefreshingHAClientRecorder(
            discoveryResults: [
                .failure(.authentication),
                .failure(.authentication)
            ],
            refreshResults: [
                .success(
                    HAOAuthToken(
                        accessToken: "fresh-access",
                        refreshToken: nil,
                        expiresInSeconds: 1800,
                        tokenType: "Bearer"
                    )
                )
            ]
        )
        let application = PerchHAApplication(
            configStore: nil,
            authSessionStore: sessionStore,
            client: client
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(
            urlString: "http://homeassistant.local:8123",
            usesStoredAuthSession: true
        )
        await application.connect()

        XCTAssertEqual(application.snapshot.connectionState, .failed(.authentication))
        XCTAssertEqual(application.snapshot.connectionForm.token, "")
        XCTAssertFalse(application.snapshot.connectionForm.usesStoredAuthSession)
        XCTAssertFalse(application.snapshot.hasTokenInput)
        XCTAssertEqual(await client.discoveryTokens(), ["expired-access", "fresh-access"])
        XCTAssertEqual(await client.refreshRequests().count, 1)
        XCTAssertEqual(try sessionStore.load().accessToken, "fresh-access")
        XCTAssertEqual(try sessionStore.load().refreshToken, "refresh-token")
        XCTAssertEqual(try sessionStore.load().clientID, "https://perchha.dev/app")
    }

    func testOAuthApplicationConfigurationLoadsFromExplicitEnvironmentFile() throws {
        let fileURL = try temporaryEnvironmentFileURL()
        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        try """
        url=http://homeassistant.local:8123
        token='ignored-token'
        PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
        PERCHHA_OAUTH_REDIRECT_URI=perchha://auth
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try XCTUnwrap(
            try PerchHAOAuthApplicationConfiguration.fromEnvironment([
                PerchHAOAuthApplicationConfiguration.environmentFileEnvironmentKey: fileURL.path
            ])
        )

        XCTAssertEqual(configuration.clientID, "https://perchha.dev/app")
        XCTAssertEqual(configuration.redirectURI, "perchha://auth")
        XCTAssertEqual(configuration.callbackURLScheme, "perchha")
    }

    func testOAuthApplicationConfigurationEnvironmentOverridesEnvironmentFile() throws {
        let fileURL = try temporaryEnvironmentFileURL()
        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        try """
        PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/file
        PERCHHA_OAUTH_REDIRECT_URI=perchha-file://auth
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try XCTUnwrap(
            try PerchHAOAuthApplicationConfiguration.fromEnvironment([
                PerchHAOAuthApplicationConfiguration.environmentFileEnvironmentKey: fileURL.path,
                PerchHAOAuthApplicationConfiguration.clientIDEnvironmentKey: "https://perchha.dev/env",
                PerchHAOAuthApplicationConfiguration.redirectURIEnvironmentKey: "perchha-env://auth"
            ])
        )

        XCTAssertEqual(configuration.clientID, "https://perchha.dev/env")
        XCTAssertEqual(configuration.redirectURI, "perchha-env://auth")
        XCTAssertEqual(configuration.callbackURLScheme, "perchha-env")
    }

    func testOAuthApplicationConfigurationEnvironmentOverridesMalformedEnvironmentFile() throws {
        let fileURL = try temporaryEnvironmentFileURL()
        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        try """
        PERCHHA_OAUTH_CLIENT_ID
        PERCHHA_OAUTH_REDIRECT_URI=perchha-file://auth
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try XCTUnwrap(
            try PerchHAOAuthApplicationConfiguration.fromEnvironment([
                PerchHAOAuthApplicationConfiguration.environmentFileEnvironmentKey: fileURL.path,
                PerchHAOAuthApplicationConfiguration.clientIDEnvironmentKey: "https://perchha.dev/env",
                PerchHAOAuthApplicationConfiguration.redirectURIEnvironmentKey: "perchha-env://auth"
            ])
        )

        XCTAssertEqual(configuration.clientID, "https://perchha.dev/env")
        XCTAssertEqual(configuration.redirectURI, "perchha-env://auth")
    }

    func testOAuthApplicationConfigurationEnvironmentOverridesMissingEnvironmentFile() throws {
        let missingFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-missing-env-\(UUID().uuidString)", isDirectory: false)

        let configuration = try XCTUnwrap(
            try PerchHAOAuthApplicationConfiguration.fromEnvironment([
                PerchHAOAuthApplicationConfiguration.environmentFileEnvironmentKey: missingFileURL.path,
                PerchHAOAuthApplicationConfiguration.clientIDEnvironmentKey: "https://perchha.dev/env",
                PerchHAOAuthApplicationConfiguration.redirectURIEnvironmentKey: "perchha-env://auth"
            ])
        )

        XCTAssertEqual(configuration.clientID, "https://perchha.dev/env")
        XCTAssertEqual(configuration.redirectURI, "perchha-env://auth")
    }

    func testOAuthApplicationConfigurationBlankEnvironmentValueOverridesEnvironmentFile() throws {
        let fileURL = try temporaryEnvironmentFileURL()
        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        try """
        PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/file
        PERCHHA_OAUTH_REDIRECT_URI=perchha-file://auth
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try PerchHAOAuthApplicationConfiguration.fromEnvironment([
                PerchHAOAuthApplicationConfiguration.environmentFileEnvironmentKey: fileURL.path,
                PerchHAOAuthApplicationConfiguration.clientIDEnvironmentKey: " ",
                PerchHAOAuthApplicationConfiguration.redirectURIEnvironmentKey: "perchha-env://auth"
            ])
        ) { error in
            XCTAssertEqual(
                error as? PerchHAOAuthSignInFailure,
                .configuration("OAuth client ID is not configured")
            )
        }
    }

    func testOAuthApplicationConfigurationRejectsMalformedEnvironmentFileLine() {
        XCTAssertThrowsError(
            try PerchHAOAuthApplicationConfiguration.parseEnvironmentFile(
                """
                PERCHHA_OAUTH_CLIENT_ID
                PERCHHA_OAUTH_REDIRECT_URI=perchha://auth
                """
            )
        ) { error in
            XCTAssertEqual(error as? PerchHAOAuthEnvironmentFileError, .invalidLine(1))
        }
    }

    func testOAuthApplicationConfigurationFromEnvironmentRejectsMalformedEnvironmentFileLine() throws {
        let fileURL = try temporaryEnvironmentFileURL()
        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }
        try """
        PERCHHA_OAUTH_CLIENT_ID
        PERCHHA_OAUTH_REDIRECT_URI=perchha://auth
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try PerchHAOAuthApplicationConfiguration.fromEnvironment([
                PerchHAOAuthApplicationConfiguration.environmentFileEnvironmentKey: fileURL.path
            ])
        ) { error in
            XCTAssertEqual(error as? PerchHAOAuthEnvironmentFileError, .invalidLine(1))
        }
    }

    func testAppShellApplicationOpenAcceptsConfiguredOAuthCallbackWithoutRetainingSecrets() throws {
        let application = PerchHAApplication(
            configStore: nil,
            connector: { _ in .success(rooms: []) },
            oauthApplicationConfiguration: try PerchHAOAuthApplicationConfiguration(
                clientID: "https://perchha.dev/app",
                redirectURI: "perchha://auth"
            )
        )
        let callbackURL = try XCTUnwrap(URL(string: "perchha://auth?code=secret-code&state=secret-state"))

        application.application(NSApplication.shared, open: [callbackURL])

        let event = try XCTUnwrap(application.snapshot.lastExternalURLEvent)
        XCTAssertEqual(event.scheme, "perchha")
        XCTAssertEqual(event.host, "auth")
        XCTAssertEqual(event.path, "")
        XCTAssertTrue(event.hasQuery)
        XCTAssertFalse(event.hasFragment)
        XCTAssertEqual(event.disposition, .acceptedOAuthCallback)
        XCTAssertFalse(String(describing: event).contains("secret-code"))
        XCTAssertFalse(String(describing: event).contains("secret-state"))
    }

    func testAppShellExternalOAuthCallbackSurvivesColdLaunchCleanup() throws {
        let application = PerchHAApplication(
            configStore: nil,
            connector: { _ in .success(rooms: []) },
            oauthApplicationConfiguration: try PerchHAOAuthApplicationConfiguration(
                clientID: "https://perchha.dev/app",
                redirectURI: "perchha://auth"
            )
        )
        let callbackURL = try XCTUnwrap(URL(string: "perchha://auth?code=secret-code&state=secret-state"))

        application.application(NSApplication.shared, open: [callbackURL])
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        let event = try XCTUnwrap(application.snapshot.lastExternalURLEvent)
        XCTAssertEqual(event.disposition, .acceptedOAuthCallback)
        XCTAssertFalse(String(describing: event).contains("secret-code"))
        XCTAssertFalse(String(describing: event).contains("secret-state"))
    }

    func testAppShellExternalOAuthCallbackRejectsWrongScheme() throws {
        let application = PerchHAApplication(
            configStore: nil,
            connector: { _ in .success(rooms: []) },
            oauthApplicationConfiguration: try PerchHAOAuthApplicationConfiguration(
                clientID: "https://perchha.dev/app",
                redirectURI: "perchha://auth"
            )
        )
        let callbackURL = try XCTUnwrap(URL(string: "wrong://auth?code=secret-code&state=secret-state"))

        let events = application.handleExternalURLs([callbackURL])

        XCTAssertEqual(events.first?.disposition, .rejectedUnsupportedScheme)
        XCTAssertEqual(application.snapshot.lastExternalURLEvent?.disposition, .rejectedUnsupportedScheme)
        XCTAssertFalse(String(describing: events).contains("secret-code"))
        XCTAssertFalse(String(describing: events).contains("secret-state"))
    }

    func testAppShellExternalOAuthCallbackRejectsMismatchedRedirectBase() throws {
        let application = PerchHAApplication(
            configStore: nil,
            connector: { _ in .success(rooms: []) },
            oauthApplicationConfiguration: try PerchHAOAuthApplicationConfiguration(
                clientID: "https://perchha.dev/app",
                redirectURI: "perchha://auth"
            )
        )
        let callbackURL = try XCTUnwrap(URL(string: "perchha://other?code=secret-code&state=secret-state"))

        let events = application.handleExternalURLs([callbackURL])

        XCTAssertEqual(events.first?.scheme, "perchha")
        XCTAssertEqual(events.first?.host, "other")
        XCTAssertEqual(events.first?.disposition, .rejectedRedirectMismatch)
        XCTAssertEqual(application.snapshot.lastExternalURLEvent?.disposition, .rejectedRedirectMismatch)
        XCTAssertFalse(String(describing: events).contains("secret-code"))
        XCTAssertFalse(String(describing: events).contains("secret-state"))
    }

    func testAppShellExternalOAuthCallbackRejectsWhenOAuthIsNotConfigured() throws {
        let application = PerchHAApplication(
            configStore: nil,
            connector: { _ in .success(rooms: []) }
        )
        let callbackURL = try XCTUnwrap(URL(string: "perchha://auth?code=secret-code&state=secret-state"))

        let events = application.handleExternalURLs([callbackURL])

        XCTAssertEqual(events.first?.disposition, .rejectedOAuthNotConfigured)
        XCTAssertEqual(application.snapshot.lastExternalURLEvent?.disposition, .rejectedOAuthNotConfigured)
        XCTAssertFalse(String(describing: events).contains("secret-code"))
        XCTAssertFalse(String(describing: events).contains("secret-state"))
    }

    func testOAuthSignInCoordinatorStoresSessionFromCallback() async throws {
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            _ = try? sessionStore.clear()
        }
        let transport = OAuthHARESTTransportRecorder(
            responses: [
                HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"access-token","refresh_token":"refresh-token","expires_in":1800,"token_type":"Bearer"}"#.utf8)
                )
            ]
        )
        let presenter = OAuthPresenterRecorder(
            result: .callback(try XCTUnwrap(URL(string: "perchha://auth?code=auth-code&state=state-value")))
        )
        let coordinator = PerchHAOAuthSignInCoordinator(
            configuration: try PerchHAOAuthApplicationConfiguration(
                clientID: "https://perchha.dev/app",
                redirectURI: "perchha://auth"
            ),
            client: HomeAssistantClient(transport: transport),
            authSessionStore: sessionStore,
            presenter: presenter,
            stateGenerator: { "state-value" }
        )

        let result = await coordinator.signIn(
            form: PerchHAConnectionForm(
                urlString: "https://homeassistant.local:8123",
                fallbackURLString: "https://fallback.example",
                allowsSelfSignedCertificates: true
            )
        )

        XCTAssertEqual(result, .success)
        XCTAssertEqual(
            await presenter.authorizationURLs().first,
            try XCTUnwrap(URL(string: "https://homeassistant.local:8123/auth/authorize?client_id=https%3A%2F%2Fperchha.dev%2Fapp&redirect_uri=perchha%3A%2F%2Fauth&state=state-value"))
        )
        let request = try await XCTUnwrap(transport.requests().first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/auth/token")
        XCTAssertEqual(
            request.serverTrustPolicy,
            HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["homeassistant.local", "fallback.example"])
        )
        XCTAssertEqual(
            String(data: try XCTUnwrap(request.body), encoding: .utf8),
            "grant_type=authorization_code&code=auth-code&client_id=https%3A%2F%2Fperchha.dev%2Fapp"
        )
        XCTAssertEqual(try sessionStore.load().accessToken, "access-token")
        XCTAssertEqual(try sessionStore.load().refreshToken, "refresh-token")
        XCTAssertEqual(try sessionStore.load().clientID, "https://perchha.dev/app")
    }

    func testOAuthSignInCoordinatorRejectsMismatchedStateWithoutStoringSession() async throws {
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            _ = try? sessionStore.clear()
        }
        let transport = OAuthHARESTTransportRecorder(responses: [])
        let presenter = OAuthPresenterRecorder(
            result: .callback(try XCTUnwrap(URL(string: "perchha://auth?code=auth-code&state=wrong-state")))
        )
        let coordinator = PerchHAOAuthSignInCoordinator(
            configuration: try PerchHAOAuthApplicationConfiguration(
                clientID: "https://perchha.dev/app",
                redirectURI: "perchha://auth"
            ),
            client: HomeAssistantClient(transport: transport),
            authSessionStore: sessionStore,
            presenter: presenter,
            stateGenerator: { "state-value" }
        )

        let result = await coordinator.signIn(
            form: PerchHAConnectionForm(urlString: "http://homeassistant.local:8123")
        )

        XCTAssertEqual(result, .failed("OAuth state did not match"))
        XCTAssertEqual(await transport.requests(), [])
        XCTAssertThrowsError(try sessionStore.load()) { error in
            XCTAssertEqual(error as? SecretStoreError, .notFound(.accessToken))
        }
    }

    func testOAuthSignInCoordinatorRejectsMismatchedCallbackSchemeWithoutStoringSession() async throws {
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            _ = try? sessionStore.clear()
        }
        let transport = OAuthHARESTTransportRecorder(responses: [])
        let presenter = OAuthPresenterRecorder(
            result: .callback(try XCTUnwrap(URL(string: "wrong://auth?code=auth-code&state=state-value")))
        )
        let coordinator = PerchHAOAuthSignInCoordinator(
            configuration: try PerchHAOAuthApplicationConfiguration(
                clientID: "https://perchha.dev/app",
                redirectURI: "perchha://auth"
            ),
            client: HomeAssistantClient(transport: transport),
            authSessionStore: sessionStore,
            presenter: presenter,
            stateGenerator: { "state-value" }
        )

        let result = await coordinator.signIn(
            form: PerchHAConnectionForm(urlString: "http://homeassistant.local:8123")
        )

        XCTAssertEqual(result, .failed("OAuth callback scheme did not match"))
        XCTAssertEqual(await transport.requests(), [])
        XCTAssertThrowsError(try sessionStore.load()) { error in
            XCTAssertEqual(error as? SecretStoreError, .notFound(.accessToken))
        }
    }

    func testOAuthSignInCoordinatorRejectsMismatchedRedirectURIWithoutStoringSession() async throws {
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            _ = try? sessionStore.clear()
        }
        let transport = OAuthHARESTTransportRecorder(responses: [])
        let presenter = OAuthPresenterRecorder(
            result: .callback(try XCTUnwrap(URL(string: "perchha://other?code=auth-code&state=state-value")))
        )
        let coordinator = PerchHAOAuthSignInCoordinator(
            configuration: try PerchHAOAuthApplicationConfiguration(
                clientID: "https://perchha.dev/app",
                redirectURI: "perchha://auth"
            ),
            client: HomeAssistantClient(transport: transport),
            authSessionStore: sessionStore,
            presenter: presenter,
            stateGenerator: { "state-value" }
        )

        let result = await coordinator.signIn(
            form: PerchHAConnectionForm(urlString: "http://homeassistant.local:8123")
        )

        XCTAssertEqual(result, .failed("OAuth callback redirect URI did not match"))
        XCTAssertEqual(await transport.requests(), [])
        XCTAssertThrowsError(try sessionStore.load()) { error in
            XCTAssertEqual(error as? SecretStoreError, .notFound(.accessToken))
        }
    }

    func testPanelOAuthSignInSwitchesToStoredSessionAndConnects() async {
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel(
            connector: { form in
                await recorder.record(form)
                return .success(rooms: [])
            },
            oauthSignInRunner: { _ in .success }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123")
        await model.signInWithOAuth()

        XCTAssertEqual(model.oauthSignInState, .idle)
        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertTrue(model.snapshot.connectionForm.usesStoredAuthSession)
        XCTAssertTrue(model.snapshot.hasTokenInput)
        XCTAssertEqual(await recorder.tokens(), [""])
        XCTAssertEqual(await recorder.usesStoredAuthSessions(), [true])
    }

    func testPanelOAuthSignInConnectsWithAuthorizedFormWhenFieldsChangeDuringSignIn() async {
        let recorder = ConnectionFormRecorder()
        var model: PerchHAPanelModel!
        model = PerchHAPanelModel(
            connector: { form in
                await recorder.record(form)
                return .success(rooms: [])
            },
            oauthSignInRunner: { _ in
                model.updateConnectionForm(urlString: "http://other-homeassistant.local:8123")
                return .success
            }
        )

        model.updateConnectionForm(urlString: "http://homeassistant.local:8123")
        await model.signInWithOAuth()

        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertEqual(model.snapshot.connectionForm.urlString, "http://homeassistant.local:8123")
        XCTAssertEqual(await recorder.urlStrings(), ["http://homeassistant.local:8123"])
        XCTAssertEqual(await recorder.usesStoredAuthSessions(), [true])
    }

    func testPanelOAuthSignInFailureDoesNotStoreSessionFlag() async {
        let model = PerchHAPanelModel(
            oauthSignInRunner: { _ in .failed("OAuth sign-in is not configured") }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123")
        await model.signInWithOAuth()

        XCTAssertEqual(model.oauthSignInState, .failed("OAuth sign-in is not configured"))
        XCTAssertFalse(model.snapshot.connectionForm.usesStoredAuthSession)
        XCTAssertFalse(model.snapshot.hasTokenInput)
    }

    func test_t_display_settings_apply_live() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity"],
                menuBarEntityIDs: ["sensor.office_humidity"],
                isEntitySelectionExplicit: true
            )
        )
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: selectionRooms()) }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()
        XCTAssertEqual(gaugeRenderer.renderCount, 0)

        XCTAssertTrue(application.setMenuBarDisplayStyle("sensor.office_humidity", style: .battery))
        XCTAssertEqual(application.snapshot.statusItemTitle, "44 %")
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Office humidity, 44 %, 44 percent, battery")
        XCTAssertTrue(application.snapshot.statusItemHasImage)
        XCTAssertEqual(application.snapshot.statusItemImageWidth, 24)
        XCTAssertEqual(application.snapshot.statusItemImageHeight, 18)
        XCTAssertEqual(application.snapshot.statusItemImageIsTemplate, false)
        XCTAssertEqual(gaugeRenderer.renderCount, 1)

        XCTAssertTrue(
            application.applyLiveState(
                EntityState(
                    id: "sensor.office_humidity",
                    name: "Office humidity",
                    state: "44",
                    unit: "%"
                )
            )
        )
        XCTAssertEqual(gaugeRenderer.renderCount, 1)

        XCTAssertTrue(application.setMenuBarShowsLabel("sensor.office_humidity", showsLabel: true))
        XCTAssertEqual(application.snapshot.statusItemTitle, "Office humidity 44 %")
        XCTAssertEqual(gaugeRenderer.renderCount, 1)

        XCTAssertTrue(application.setMenuBarShowsUnit("sensor.office_humidity", showsUnit: false))
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Office humidity, 44, 44 percent, battery")
        XCTAssertEqual(gaugeRenderer.renderCount, 1)

        XCTAssertTrue(
            application.applyLiveState(
                EntityState(
                    id: "sensor.office_humidity",
                    name: "Office humidity",
                    state: "44.49",
                    unit: "%"
                )
            )
        )
        XCTAssertEqual(gaugeRenderer.renderCount, 2)
        XCTAssertTrue(application.setMenuBarMaximumFractionDigits("sensor.office_humidity", maximumFractionDigits: 1))
        XCTAssertEqual(gaugeRenderer.renderCount, 2)
        let expectedDecimalValue = EntityValueFormatter(
            locale: .current,
            maximumFractionDigits: 1
        ).format(
            DiscoveredEntity(
                id: "sensor.office_humidity",
                name: "Office humidity",
                state: "44.49",
                unit: nil,
                areaID: nil,
                deviceID: nil
            )
        ).text
        XCTAssertEqual(
            application.snapshot.statusItemAccessibilityLabel,
            "Office humidity, \(expectedDecimalValue), 44 percent, battery"
        )
        XCTAssertEqual(application.snapshot.statusItemTitle, "Office humidity \(expectedDecimalValue)")

        XCTAssertTrue(application.setMenuBarDefaultHistoryRange("sensor.office_humidity", defaultHistoryRange: .day))
        XCTAssertEqual(gaugeRenderer.renderCount, 2)
        XCTAssertEqual(application.snapshot.statusItemTitle, "Office humidity \(expectedDecimalValue)")
        XCTAssertEqual(
            application.snapshot.menuBarDisplayConfiguration
                .itemConfiguration(for: "sensor.office_humidity")
                .defaultHistoryRange,
            .day
        )

        let saved = try store.load()
        XCTAssertEqual(saved.menuBarEntityIDs, ["sensor.office_humidity"])
        XCTAssertEqual(saved.menuBarItemConfigurations.count, 1)
        XCTAssertEqual(saved.menuBarItemConfigurations.first?.style, .battery)
        XCTAssertEqual(saved.menuBarItemConfigurations.first?.showsLabel, true)
        XCTAssertEqual(saved.menuBarItemConfigurations.first?.showsUnit, false)
        XCTAssertEqual(saved.menuBarItemConfigurations.first?.maximumFractionDigits, 1)
        XCTAssertEqual(saved.menuBarItemConfigurations.first?.defaultHistoryRange, .day)
    }

    func test_t_status_item_gauge_image_renderer_draws_severity_colors() {
        let palette = PerchHAStatusItemGaugePalette(
            normal: NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1),
            warning: NSColor(calibratedRed: 1, green: 0.5, blue: 0, alpha: 1),
            critical: NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1),
            track: NSColor(calibratedWhite: 0.25, alpha: 1)
        )
        let renderer = PerchHAStatusItemGaugeImageRenderer(
            size: NSSize(width: 24, height: 18),
            palette: palette
        )
        let warning = MenuBarItemRenderer().render(
            entity: DiscoveredEntity(
                id: "sensor.office_humidity",
                name: "Office humidity",
                state: "44",
                unit: "%",
                areaID: nil,
                deviceID: nil
            ),
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.office_humidity",
                style: .bar,
                thresholds: ValueThresholds(warning: ValueThreshold(value: 40, direction: .aboveOrEqual))
            ),
            locale: Locale(identifier: "en_US")
        )
        let critical = MenuBarItemRenderer().render(
            entity: DiscoveredEntity(
                id: "sensor.office_humidity",
                name: "Office humidity",
                state: "44",
                unit: "%",
                areaID: nil,
                deviceID: nil
            ),
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.office_humidity",
                style: .battery,
                thresholds: ValueThresholds(critical: ValueThreshold(value: 40, direction: .aboveOrEqual))
            ),
            locale: Locale(identifier: "en_US")
        )
        let ring = MenuBarItemRenderer().render(
            entity: DiscoveredEntity(
                id: "sensor.energy_today",
                name: "Energy today",
                state: "30",
                unit: "kWh",
                areaID: nil,
                deviceID: nil
            ),
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.energy_today",
                style: .ring,
                absoluteTotal: 120,
                thresholds: ValueThresholds(critical: ValueThreshold(value: 20, direction: .aboveOrEqual))
            ),
            locale: Locale(identifier: "en_US")
        )
        let text = MenuBarItemRenderer().render(
            entity: DiscoveredEntity(
                id: "sensor.office_humidity",
                name: "Office humidity",
                state: "44",
                unit: "%",
                areaID: nil,
                deviceID: nil
            ),
            configuration: MenuBarItemConfiguration(entityID: "sensor.office_humidity", style: .text),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertNil(renderer.image(for: text))
        guard let warningImage = renderer.image(for: warning),
              let criticalImage = renderer.image(for: critical),
              let ringImage = renderer.image(for: ring)
        else {
            XCTFail("expected gauge images")
            return
        }
        XCTAssertFalse(warningImage.isTemplate)
        XCTAssertEqual(Int(warningImage.size.width.rounded()), 24)
        XCTAssertEqual(Int(warningImage.size.height.rounded()), 18)
        XCTAssertTrue(warningImage.containsPixel(closeTo: palette.warning))
        XCTAssertTrue(criticalImage.containsPixel(closeTo: palette.critical))
        XCTAssertTrue(ringImage.containsPixel(closeTo: palette.critical))
    }

    func test_t_display_total_threshold_settings_apply_live() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.energy_today"],
                menuBarEntityIDs: ["sensor.energy_today"],
                isEntitySelectionExplicit: true
            )
        )
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: energyRooms()) }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertEqual(application.snapshot.statusItemTitle, "30 kWh")
        XCTAssertTrue(application.setMenuBarDisplayStyle("sensor.energy_today", style: .ring))
        XCTAssertEqual(application.snapshot.statusItemTitle, "30 kWh")
        XCTAssertFalse(application.snapshot.statusItemHasImage)

        XCTAssertTrue(application.setMenuBarAbsoluteTotal("sensor.energy_today", total: 120))
        XCTAssertEqual(application.snapshot.statusItemTitle, "30 kWh")
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Energy today, 30 kWh, 25 percent, ring")
        XCTAssertTrue(application.snapshot.statusItemHasImage)
        XCTAssertEqual(application.snapshot.statusItemImageWidth, 24)
        XCTAssertEqual(application.snapshot.statusItemImageHeight, 18)
        XCTAssertEqual(application.snapshot.statusItemImageIsTemplate, false)

        XCTAssertTrue(
            application.setMenuBarWarningThreshold(
                "sensor.energy_today",
                threshold: ValueThreshold(value: 20, direction: .aboveOrEqual)
            )
        )
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Energy today, 30 kWh, 25 percent, warning, ring")

        XCTAssertTrue(
            application.setMenuBarCriticalThreshold(
                "sensor.energy_today",
                threshold: ValueThreshold(value: 25, direction: .aboveOrEqual)
            )
        )
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Energy today, 30 kWh, 25 percent, critical, ring")

        XCTAssertTrue(application.setMenuBarTotalEntityID("sensor.energy_today", totalEntityID: "sensor.energy_budget"))
        XCTAssertEqual(application.snapshot.statusItemTitle, "30 kWh")

        XCTAssertTrue(application.setMenuBarWarningThreshold("sensor.energy_today", threshold: nil))
        XCTAssertTrue(application.setMenuBarCriticalThreshold("sensor.energy_today", threshold: nil))
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Energy today, 30 kWh, 50 percent, ring")

        let savedConfiguration = try store.load()
            .menuBarDisplayConfiguration
            .itemConfiguration(for: "sensor.energy_today")
        XCTAssertEqual(savedConfiguration.style, .ring)
        XCTAssertNil(savedConfiguration.absoluteTotal)
        XCTAssertEqual(savedConfiguration.totalEntityID, EntityID("sensor.energy_budget"))
        XCTAssertNil(savedConfiguration.thresholds.warning)
        XCTAssertNil(savedConfiguration.thresholds.critical)
    }

    func test_t_display_total_threshold_settings_reject_invalid_inputs() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.energy_today"],
                menuBarEntityIDs: ["sensor.energy_today"],
                menuBarItemConfigurations: [
                    MenuBarItemConfiguration(
                        entityID: "sensor.energy_today",
                        style: .ring,
                        absoluteTotal: 120,
                        thresholds: ValueThresholds(
                            warning: ValueThreshold(value: 20, direction: .aboveOrEqual)
                        )
                    )
                ],
                isEntitySelectionExplicit: true
            )
        )
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: energyRooms()) }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertEqual(application.snapshot.statusItemTitle, "30 kWh")
        XCTAssertTrue(application.snapshot.statusItemHasImage)
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Energy today, 30 kWh, 25 percent, warning, ring")
        XCTAssertFalse(application.setMenuBarAbsoluteTotal("sensor.energy_today", total: 0))
        XCTAssertFalse(application.setMenuBarAbsoluteTotal("sensor.energy_today", total: Double.nan))
        XCTAssertFalse(application.setMenuBarTotalEntityID("sensor.energy_today", totalEntityID: "sensor.utility_humidity"))
        XCTAssertFalse(application.setMenuBarTotalEntityID("sensor.energy_today", totalEntityID: ""))
        XCTAssertFalse(
            application.setMenuBarWarningThreshold(
                "sensor.energy_today",
                threshold: ValueThreshold(value: Double.nan, direction: .aboveOrEqual)
            )
        )
        XCTAssertFalse(application.setMenuBarAbsoluteTotal("sensor.utility_humidity", total: 100))

        XCTAssertEqual(application.snapshot.statusItemTitle, "30 kWh")
        XCTAssertTrue(application.snapshot.statusItemHasImage)
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Energy today, 30 kWh, 25 percent, warning, ring")
        let savedConfiguration = try store.load()
            .menuBarDisplayConfiguration
            .itemConfiguration(for: "sensor.energy_today")
        XCTAssertEqual(savedConfiguration.absoluteTotal, 120)
        XCTAssertNil(savedConfiguration.totalEntityID)
        XCTAssertEqual(savedConfiguration.thresholds.warning, ValueThreshold(value: 20, direction: .aboveOrEqual))
    }

    func test_t_display_settings_save_failure_rejects_live_status_item_change() async {
        let store = FailingConfigStore(
            loadedConfiguration: PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity"],
                menuBarEntityIDs: ["sensor.office_humidity"],
                isEntitySelectionExplicit: true
            ),
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: selectionRooms()) }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertEqual(application.snapshot.statusItemTitle, "44 %")
        XCTAssertFalse(application.setMenuBarDisplayStyle("sensor.office_humidity", style: .battery))
        XCTAssertEqual(application.snapshot.statusItemTitle, "44 %")
        XCTAssertEqual(application.snapshot.menuBarItemConfigurations, [])
        XCTAssertTrue(application.snapshot.displayPersistenceFailureDescription?.contains("disk full") == true)
        XCTAssertFalse(application.setMenuBarDefaultHistoryRange("sensor.office_humidity", defaultHistoryRange: .month))
        XCTAssertEqual(application.snapshot.statusItemTitle, "44 %")
        XCTAssertEqual(application.snapshot.menuBarItemConfigurations, [])
    }

    func test_t_display_total_threshold_save_failure_rejects_live_status_item_change() async {
        let store = FailingConfigStore(
            loadedConfiguration: PerchHAConfiguration(
                selectedEntityIDs: ["sensor.energy_today"],
                menuBarEntityIDs: ["sensor.energy_today"],
                menuBarItemConfigurations: [
                    MenuBarItemConfiguration(entityID: "sensor.energy_today", style: .ring)
                ],
                isEntitySelectionExplicit: true
            ),
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: energyRooms()) }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertEqual(application.snapshot.statusItemTitle, "30 kWh")
        XCTAssertFalse(application.setMenuBarAbsoluteTotal("sensor.energy_today", total: 120))
        XCTAssertEqual(application.snapshot.statusItemTitle, "30 kWh")
        XCTAssertEqual(application.snapshot.menuBarItemConfigurations.first?.absoluteTotal, nil)
        XCTAssertTrue(application.snapshot.displayPersistenceFailureDescription?.contains("disk full") == true)
    }

    func test_t_menu_bar_reorder_settings_apply_live_and_persist() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity", "sensor.office_temperature"],
                menuBarEntityIDs: ["sensor.office_humidity", "sensor.office_temperature"],
                isEntitySelectionExplicit: true
            )
        )
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: selectionRooms()) }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertEqual(application.snapshot.statusItemTitle, "44 %")
        XCTAssertTrue(application.moveMenuBarEntity("sensor.office_humidity", direction: .down))
        let expectedTemperature = EntityValueFormatter(locale: .current, maximumFractionDigits: 0).format(
            DiscoveredEntity(
                id: "sensor.office_temperature",
                name: "Office temperature",
                state: "21.4",
                unit: "°C",
                areaID: nil,
                deviceID: nil
            )
        ).text
        XCTAssertEqual(application.snapshot.statusItemTitle, expectedTemperature)
        XCTAssertEqual(application.snapshot.menuBarEntityIDs, ["sensor.office_temperature", "sensor.office_humidity"])
        XCTAssertEqual(try store.load().menuBarEntityIDs, ["sensor.office_temperature", "sensor.office_humidity"])

        XCTAssertTrue(
            application.moveMenuBarEntity(
                "sensor.office_humidity",
                relativeTo: "sensor.office_temperature",
                placement: .before
            )
        )
        XCTAssertEqual(application.snapshot.statusItemTitle, "44 %")
        XCTAssertEqual(application.snapshot.menuBarEntityIDs, ["sensor.office_humidity", "sensor.office_temperature"])
        XCTAssertFalse(application.moveMenuBarEntity("sensor.office_humidity", direction: .up))
        XCTAssertEqual(try store.load().menuBarEntityIDs, ["sensor.office_humidity", "sensor.office_temperature"])
    }

    func test_t_menu_bar_reorder_save_failure_rejects_live_status_item_change() async {
        let store = FailingConfigStore(
            loadedConfiguration: PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity", "sensor.office_temperature"],
                menuBarEntityIDs: ["sensor.office_humidity", "sensor.office_temperature"],
                isEntitySelectionExplicit: true
            ),
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: selectionRooms()) }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertEqual(application.snapshot.statusItemTitle, "44 %")
        XCTAssertFalse(application.moveMenuBarEntity("sensor.office_humidity", direction: .down))
        XCTAssertEqual(application.snapshot.statusItemTitle, "44 %")
        XCTAssertEqual(application.snapshot.menuBarEntityIDs, ["sensor.office_humidity", "sensor.office_temperature"])
        XCTAssertTrue(application.snapshot.displayPersistenceFailureDescription?.contains("disk full") == true)
    }

    func test_t_app_shell_reorder_save_survives_relaunch() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                menuBarEntityIDs: ["sensor.office_humidity"]
            )
        )
        let firstApplication = PerchHAApplication(configStore: store)
        firstApplication.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        var firstApplicationIsRunning = true
        defer {
            if firstApplicationIsRunning {
                firstApplication.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            }
        }

        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            selectionConfiguration: firstApplication.snapshotSelectionConfiguration,
            selectionSink: { selection in
                firstApplication.persist(selection: selection)
            }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        XCTAssertTrue(model.moveRoom("kitchen", direction: .up))
        XCTAssertTrue(model.moveEntity("sensor.office_humidity", direction: .up))

        firstApplication.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        firstApplicationIsRunning = false

        let secondApplication = PerchHAApplication(configStore: store)
        secondApplication.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            secondApplication.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        XCTAssertEqual(secondApplication.snapshot.roomOrder, ["kitchen", "office"])
        XCTAssertEqual(secondApplication.snapshot.entityOrder, [
            "switch.kitchen_light",
            "sensor.office_humidity",
            "sensor.office_temperature"
        ])
        XCTAssertEqual(secondApplication.snapshot.selectedEntityIDs, [])
        XCTAssertEqual(secondApplication.snapshot.menuBarEntityIDs, ["sensor.office_humidity"])
        XCTAssertFalse(secondApplication.snapshot.isEntitySelectionExplicit)
        XCTAssertEqual(secondApplication.snapshot.configurationPersistenceState, .ready)
    }

    func testAppShellRemembersConnectionProfileAndStoredAccessTokenAcrossRelaunch() async throws {
        let url = temporaryConfigURL()
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            _ = try? sessionStore.clear()
        }

        let firstApplication = PerchHAApplication(
            configStore: JSONConfigStore(fileURL: url),
            authSessionStore: sessionStore,
            client: RefreshingHAClientRecorder(
                discoveryResults: [.success(oauthDiscoverySnapshot())]
            )
        )
        firstApplication.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        var firstApplicationIsRunning = true
        defer {
            if firstApplicationIsRunning {
                firstApplication.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            }
        }

        firstApplication.updateConnectionForm(
            urlString: "https://homeassistant.local:8123/lovelace/0",
            fallbackURLString: "https://fallback.example/ha/history",
            token: "long-lived-token",
            allowsSelfSignedCertificates: true
        )
        await firstApplication.connect()

        XCTAssertEqual(try sessionStore.loadAccessToken(), "long-lived-token")
        XCTAssertThrowsError(try sessionStore.load()) { error in
            XCTAssertEqual(error as? SecretStoreError, .notFound(.refreshToken))
        }

        firstApplication.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        firstApplicationIsRunning = false

        let secondApplication = PerchHAApplication(
            configStore: JSONConfigStore(fileURL: url),
            authSessionStore: sessionStore,
            client: RefreshingHAClientRecorder()
        )
        secondApplication.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            secondApplication.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        XCTAssertEqual(secondApplication.snapshot.connectionForm.urlString, "https://homeassistant.local:8123")
        XCTAssertEqual(secondApplication.snapshot.connectionForm.fallbackURLString, "https://fallback.example/ha")
        XCTAssertEqual(secondApplication.snapshot.connectionForm.token, "")
        XCTAssertTrue(secondApplication.snapshot.connectionForm.usesStoredAuthSession)
        XCTAssertTrue(secondApplication.snapshot.connectionForm.allowsSelfSignedCertificates)
        XCTAssertTrue(secondApplication.snapshot.hasTokenInput)
    }

    func test_t_app_shell_reports_config_load_failure_and_blocks_save() {
        let store = FailingConfigStore(
            loadError: .malformedConfig(URL(fileURLWithPath: "/tmp/perchha-bad-config.json"), message: "bad json")
        )
        let application = PerchHAApplication(configStore: store)
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        guard case let .loadFailed(message) = application.snapshot.configurationPersistenceState else {
            XCTFail("expected config load failure")
            return
        }
        XCTAssertTrue(message.contains("bad json"))
        let result = application.persist(
            selection: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.office_temperature"],
                isExplicit: true
            )
        )
        guard case let .failed(saveMessage) = result else {
            XCTFail("expected blocked save failure")
            return
        }
        XCTAssertTrue(saveMessage.contains("save blocked"))
        XCTAssertEqual(store.saveCallCount, 0)
        guard case .loadFailed = application.snapshot.configurationPersistenceState else {
            XCTFail("expected load failure to remain visible")
            return
        }
    }

    func test_t_app_shell_reports_config_save_failure_without_mutating_loaded_config() {
        let store = FailingConfigStore(
            loadedConfiguration: PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_temperature"],
                isEntitySelectionExplicit: true
            ),
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let application = PerchHAApplication(configStore: store)
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        XCTAssertEqual(application.snapshot.selectedEntityIDs, ["sensor.office_temperature"])
        let result = application.persist(
            selection: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.office_humidity"],
                entityOrder: ["sensor.office_humidity"],
                isExplicit: true
            )
        )
        guard case let .failed(saveMessage) = result else {
            XCTFail("expected config save failure")
            return
        }
        XCTAssertTrue(saveMessage.contains("disk full"))

        guard case let .saveFailed(message) = application.snapshot.configurationPersistenceState else {
            XCTFail("expected config save failure")
            return
        }
        XCTAssertTrue(message.contains("disk full"))
        XCTAssertEqual(store.saveCallCount, 1)
        XCTAssertEqual(application.snapshot.selectedEntityIDs, ["sensor.office_temperature"])
    }

    func test_t_panel_rejects_reorder_when_app_shell_save_fails() async {
        let store = FailingConfigStore(
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let application = PerchHAApplication(configStore: store)
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            selectionConfiguration: application.snapshotSelectionConfiguration,
            selectionSink: { selection in
                application.persist(selection: selection)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertFalse(model.moveRoom("kitchen", direction: .up))
        XCTAssertEqual(model.snapshot.rooms.map(\.id), ["office", "kitchen"])
        XCTAssertEqual(model.snapshot.selectionConfiguration.roomOrder, [])
        XCTAssertTrue(model.snapshot.selectionPersistenceFailureDescription?.contains("disk full") == true)
        XCTAssertEqual(store.saveCallCount, 1)
        guard case let .saveFailed(message) = application.snapshot.configurationPersistenceState else {
            XCTFail("expected app shell save failure")
            return
        }
        XCTAssertTrue(message.contains("disk full"))
    }

    func test_t_panel_rejects_drop_reorder_when_app_shell_save_fails() async {
        let store = FailingConfigStore(
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let application = PerchHAApplication(configStore: store)
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            selectionConfiguration: application.snapshotSelectionConfiguration,
            selectionSink: { selection in
                application.persist(selection: selection)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertFalse(model.moveRoom("office", relativeTo: "kitchen", placement: .after))
        XCTAssertEqual(model.snapshot.rooms.map(\.id), ["office", "kitchen"])
        XCTAssertEqual(model.snapshot.selectionConfiguration.roomOrder, [])
        XCTAssertTrue(model.snapshot.selectionPersistenceFailureDescription?.contains("disk full") == true)
        XCTAssertEqual(store.saveCallCount, 1)
    }

    func test_t_panel_rejects_entity_drop_reorder_when_app_shell_save_fails() async {
        let store = FailingConfigStore(
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let application = PerchHAApplication(configStore: store)
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            selectionConfiguration: application.snapshotSelectionConfiguration,
            selectionSink: { selection in
                application.persist(selection: selection)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertFalse(model.moveEntity("sensor.office_temperature", relativeTo: "sensor.office_humidity", placement: .after))
        XCTAssertEqual(model.snapshot.rooms.first?.entities.map(\.id), [
            "sensor.office_temperature",
            "sensor.office_humidity"
        ])
        XCTAssertEqual(model.snapshot.selectionConfiguration.entityOrder, [])
        XCTAssertTrue(model.snapshot.selectionPersistenceFailureDescription?.contains("disk full") == true)
        XCTAssertEqual(store.saveCallCount, 1)
    }

    func test_t_panel_rejects_entity_move_when_app_shell_save_fails() async {
        let store = FailingConfigStore(
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let application = PerchHAApplication(configStore: store)
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            selectionConfiguration: application.snapshotSelectionConfiguration,
            selectionSink: { selection in
                application.persist(selection: selection)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertFalse(model.moveEntity("sensor.office_humidity", direction: .up))
        XCTAssertEqual(model.snapshot.rooms.first?.entities.map(\.id), [
            "sensor.office_temperature",
            "sensor.office_humidity"
        ])
        XCTAssertEqual(model.snapshot.selectionConfiguration.entityOrder, [])
        XCTAssertTrue(model.snapshot.selectionPersistenceFailureDescription?.contains("disk full") == true)
        XCTAssertEqual(store.saveCallCount, 1)
    }

    func test_t_panel_rejects_selection_toggle_when_app_shell_save_fails() async {
        let store = FailingConfigStore(
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let application = PerchHAApplication(configStore: store)
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            selectionConfiguration: application.snapshotSelectionConfiguration,
            selectionSink: { selection in
                application.persist(selection: selection)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        model.setEntity("sensor.office_temperature", isSelected: false)

        XCTAssertFalse(model.snapshot.selectionConfiguration.isExplicit)
        XCTAssertEqual(model.snapshot.visibleEntityCount, 3)
        XCTAssertTrue(model.snapshot.selectionPersistenceFailureDescription?.contains("disk full") == true)
        XCTAssertEqual(store.saveCallCount, 1)
    }

    private func fakeHAConnector(form: PerchHAConnectionForm) async -> PerchHAConnectionAttemptResult {
        guard let primaryURL = form.primaryURL() else {
            return .failure(.protocolError("invalid Home Assistant URL"))
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL()),
            token: form.trimmedToken
        )

        switch await HomeAssistantClient().discovery(input) {
        case let .success(snapshot):
            return .success(rooms: RoomResolver().resolve(snapshot: snapshot))
        case let .failure(failure):
            return .failure(failure.connectionFailure)
        }
    }

    private func spinUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    private func spinUntil(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<100 {
            if await condition() {
                return
            }
            await Task.yield()
        }
    }

    private func historySeries(entityID: EntityID, range: HistoryRange, value: Double) -> HistorySeries {
        HistorySeries(
            entityID: entityID,
            range: range,
            samples: [
                HistorySample(
                    timestamp: Date(timeIntervalSince1970: 1_789_999_200),
                    state: "\(value)",
                    numericValue: value
                )
            ]
        )
    }

    private func oauthDiscoverySnapshot() -> DiscoverySnapshot {
        DiscoverySnapshot(
            areas: [],
            devices: [],
            entities: [],
            states: [
                EntityState(
                    id: "sensor.office_temperature",
                    name: "Office temperature",
                    state: "21.4",
                    unit: "°C"
                )
            ]
        )
    }

    private func selectionRooms() -> [Room] {
        [
            Room(
                id: "office",
                name: "Office",
                entities: [
                    DiscoveredEntity(
                        id: "sensor.office_temperature",
                        name: "Office temperature",
                        state: "21.4",
                        unit: "°C",
                        areaID: nil,
                        deviceID: nil
                    ),
                    DiscoveredEntity(
                        id: "sensor.office_humidity",
                        name: "Office humidity",
                        state: "44",
                        unit: "%",
                        areaID: nil,
                        deviceID: nil
                    )
                ]
            ),
            Room(
                id: "kitchen",
                name: "Kitchen",
                entities: [
                    DiscoveredEntity(
                        id: "switch.kitchen_light",
                        name: "Kitchen light",
                        state: "off",
                        unit: nil,
                        areaID: nil,
                        deviceID: nil
                    )
                ]
            )
        ]
    }

    private func drainPanelRunLoop() {
        for _ in 0..<3 {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        }
    }

    private func editableTextFields(in root: NSView?) -> [NSTextField] {
        guard let root else {
            return []
        }
        var result: [NSTextField] = []
        func collect(_ view: NSView) {
            if let textField = view as? NSTextField, !textField.isHiddenOrHasHiddenAncestor, textField.isEditable {
                result.append(textField)
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result
    }

    private func secureTextFields(in root: NSView?) -> [NSSecureTextField] {
        guard let root else {
            return []
        }
        var result: [NSSecureTextField] = []
        func collect(_ view: NSView) {
            if let textField = view as? NSSecureTextField, !textField.isHiddenOrHasHiddenAncestor, textField.isEditable {
                result.append(textField)
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result
    }

    private func setNativeTextFieldValue(_ value: String, for textField: NSTextField, in panel: NSPanel) throws {
        XCTAssertTrue(panel.makeFirstResponder(textField))
        drainPanelRunLoop()
        if let editor = textField.currentEditor() {
            editor.string = value
            textField.stringValue = value
            NotificationCenter.default.post(
                name: NSControl.textDidChangeNotification,
                object: textField,
                userInfo: ["NSFieldEditor": editor]
            )
            NotificationCenter.default.post(
                name: NSControl.textDidEndEditingNotification,
                object: textField,
                userInfo: ["NSFieldEditor": editor]
            )
        }
        textField.stringValue = value
        textField.validateEditing()
        textField.sendAction(textField.action, to: textField.target)
        panel.endEditing(for: nil)
        _ = panel.makeFirstResponder(nil)
        drainPanelRunLoop()
    }

    private func setNativePopUpSelection(_ title: String, for popUpButton: NSPopUpButton) throws {
        XCTAssertTrue(popUpButton.itemTitles.contains(title))
        popUpButton.selectItem(withTitle: title)
        popUpButton.synchronizeTitleAndSelectedItem()
        let index = popUpButton.indexOfSelectedItem
        if index >= 0 {
            popUpButton.menu?.performActionForItem(at: index)
        }
        popUpButton.sendAction(popUpButton.action, to: popUpButton.target)
        drainPanelRunLoop()
    }

    @MainActor
    private func nativeSwitches(in root: NSView?) -> [NSSwitch] {
        guard let root else {
            return []
        }
        var result: [NSSwitch] = []
        func collect(_ view: NSView) {
            if let controlSwitch = view as? NSSwitch, !controlSwitch.isHiddenOrHasHiddenAncestor {
                result.append(controlSwitch)
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result
    }

    @MainActor
    private func nativeSliders(in root: NSView?) -> [NSSlider] {
        guard let root else {
            return []
        }
        var result: [NSSlider] = []
        func collect(_ view: NSView) {
            if let slider = view as? NSSlider, !slider.isHiddenOrHasHiddenAncestor {
                result.append(slider)
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result
    }

    @MainActor
    private func nativeButtons(in root: NSView?) -> [NSButton] {
        guard let root else {
            return []
        }
        var result: [NSButton] = []
        func collect(_ view: NSView) {
            if let button = view as? NSButton, !button.isHiddenOrHasHiddenAncestor {
                result.append(button)
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result
    }

    private func nativePopUpButtons(in root: NSView?) -> [NSPopUpButton] {
        guard let root else {
            return []
        }
        var result: [NSPopUpButton] = []
        func collect(_ view: NSView) {
            if let popUpButton = view as? NSPopUpButton, !popUpButton.isHiddenOrHasHiddenAncestor {
                result.append(popUpButton)
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result
    }

    private func nativeKeyViewLoopLabels(startingAt start: NSView) -> [String] {
        var labels: [String] = []
        var visited: Set<ObjectIdentifier> = []
        var current: NSView? = start

        while let view = current, labels.count < 64 {
            let identifier = ObjectIdentifier(view)
            if !visited.insert(identifier).inserted {
                break
            }
            labels.append(nativeControlLabel(for: view))
            current = view.nextValidKeyView
        }

        return labels
    }

    private func nativeControlLabel(for view: NSView) -> String {
        if let textField = view as? NSTextField {
            return "\(type(of: view))(placeholder:\(textField.placeholderString ?? ""))"
        }
        if let button = view as? NSButton {
            return "\(type(of: view))(title:\(button.title),label:\(button.accessibilityLabel() ?? ""))"
        }
        return String(describing: type(of: view))
    }

    private func nativeControlDebugSummary(in root: NSView?) -> String {
        guard let root else {
            return "no-root-view"
        }
        var result: [String] = []
        func collect(_ view: NSView) {
            if let control = view as? NSControl {
                let placeholder = (control as? NSTextField)?.placeholderString ?? ""
                let title = control is NSButton ? (control as? NSButton)?.title ?? "" : ""
                let label = control.accessibilityLabel() ?? ""
                result.append("\(type(of: control))(placeholder:\(placeholder),title:\(title),label:\(label),enabled:\(control.isEnabled),hidden:\(control.isHiddenOrHasHiddenAncestor))")
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result.prefix(16).joined(separator: " | ")
    }

    private func controlRooms() -> [Room] {
        [
            Room(
                id: "controls",
                name: "Controls",
                entities: [
                    DiscoveredEntity(
                        id: "switch.office_lamp",
                        name: "Office lamp",
                        state: "off",
                        unit: nil,
                        areaID: nil,
                        deviceID: nil
                    ),
                    DiscoveredEntity(
                        id: "light.kitchen_counter",
                        name: "Kitchen counter",
                        state: "on",
                        unit: nil,
                        areaID: nil,
                        deviceID: nil
                    ),
                    DiscoveredEntity(
                        id: "input_boolean.guest_mode",
                        name: "Guest mode",
                        state: "off",
                        unit: nil,
                        areaID: nil,
                        deviceID: nil
                    ),
                    DiscoveredEntity(
                        id: "cover.office_blinds",
                        name: "Office blinds",
                        state: "open",
                        unit: nil,
                        areaID: nil,
                        deviceID: nil,
                        currentPosition: 42
                    ),
                    DiscoveredEntity(
                        id: "cover.garage_door",
                        name: "Garage door",
                        state: "closed",
                        unit: nil,
                        areaID: nil,
                        deviceID: nil
                    )
                ]
            )
        ]
    }

    private func sensorCustomAction(requiresConfirmation: Bool = false) -> EntityCustomAction {
        EntityCustomAction(
            id: "boost-air",
            entityID: "sensor.office_temperature",
            title: "Boost air",
            action: ActionSpec(
                domain: "script",
                service: "turn_on",
                targetEntityID: "script.air_cleaner_boost",
                serviceData: [
                    "mode": "boost",
                    "duration": 15
                ]
            ),
            requiresConfirmation: requiresConfirmation
        )
    }

    private func energyRooms() -> [Room] {
        [
            Room(
                id: "utility",
                name: "Utility",
                entities: [
                    DiscoveredEntity(
                        id: "sensor.energy_today",
                        name: "Energy today",
                        state: "30",
                        unit: "kWh",
                        areaID: nil,
                        deviceID: nil
                    ),
                    DiscoveredEntity(
                        id: "sensor.energy_budget",
                        name: "Energy budget",
                        state: "60",
                        unit: "kWh",
                        areaID: nil,
                        deviceID: nil
                    ),
                    DiscoveredEntity(
                        id: "sensor.utility_humidity",
                        name: "Utility humidity",
                        state: "44",
                        unit: "%",
                        areaID: nil,
                        deviceID: nil
                    )
                ]
            )
        ]
    }

    private func temporaryConfigURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-ui-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    private func temporaryEnvironmentFileURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-env-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(".env.local", isDirectory: false)
    }
}

private struct OAuthRefreshRequest: Equatable, Sendable {
    let baseURL: URL
    let refreshToken: String
    let clientID: String
    let serverTrustPolicy: HAServerTrustPolicy
}

@MainActor
private final class OAuthPresenterRecorder: PerchHAOAuthAuthorizationPresenter, @unchecked Sendable {
    private let result: PerchHAOAuthPresentationResult
    private var recordedAuthorizationURLs: [URL] = []

    init(result: PerchHAOAuthPresentationResult) {
        self.result = result
    }

    func callbackURL(
        authorizationURL: URL,
        callbackURLScheme: String
    ) async -> PerchHAOAuthPresentationResult {
        recordedAuthorizationURLs.append(authorizationURL)
        return result
    }

    func authorizationURLs() -> [URL] {
        recordedAuthorizationURLs
    }
}

private actor OAuthHARESTTransportRecorder: HARESTTransport {
    private var responses: [HARESTResponse]
    private var recordedRequests: [HARESTRequest] = []

    init(responses: [HARESTResponse]) {
        self.responses = responses
    }

    func send(_ request: HARESTRequest) async throws -> HARESTResponse {
        recordedRequests.append(request)
        guard !responses.isEmpty else {
            throw URLError(.cannotConnectToHost)
        }
        return responses.removeFirst()
    }

    func requests() -> [HARESTRequest] {
        recordedRequests
    }
}

private actor RefreshingHAClientRecorder: PerchHAServerTrustRefreshingHomeAssistantClient {
    private var discoveryResults: [HAClientResult<DiscoverySnapshot>]
    private var refreshResults: [HAClientResult<HAOAuthToken>]
    private var recordedDiscoveryURLs: [URL] = []
    private var recordedDiscoveryTokens: [String] = []
    private var recordedDiscoveryTrustPolicies: [HAServerTrustPolicy] = []
    private var recordedRefreshRequests: [OAuthRefreshRequest] = []

    init(
        discoveryResults: [HAClientResult<DiscoverySnapshot>] = [],
        refreshResults: [HAClientResult<HAOAuthToken>] = []
    ) {
        self.discoveryResults = discoveryResults
        self.refreshResults = refreshResults
    }

    func discovery(_ input: HAConnectionInput) async -> HAClientResult<DiscoverySnapshot> {
        recordedDiscoveryURLs.append(input.endpoint.primaryURL)
        recordedDiscoveryTokens.append(input.token)
        recordedDiscoveryTrustPolicies.append(input.serverTrustPolicy)
        guard !discoveryResults.isEmpty else {
            return .failure(.transport("unexpected discovery request"))
        }
        return discoveryResults.removeFirst()
    }

    func history(_ input: HAConnectionInput, entityID: EntityID, range: HistoryRange, end: Date) async -> HAClientResult<HistorySeries> {
        .failure(.transport("unexpected history request"))
    }

    func services(_ input: HAConnectionInput) async -> HAClientResult<[HAServiceMetadata]> {
        .success([])
    }

    func callService(_ input: HAConnectionInput, call: HAServiceCall) async -> HAClientResult<HAServiceCallResult> {
        .failure(.transport("unexpected service call"))
    }

    func refreshAccessToken(baseURL: URL, refreshToken: String, clientID: String) async -> HAClientResult<HAOAuthToken> {
        await refreshAccessToken(
            baseURL: baseURL,
            refreshToken: refreshToken,
            clientID: clientID,
            serverTrustPolicy: .default
        )
    }

    func refreshAccessToken(
        baseURL: URL,
        refreshToken: String,
        clientID: String,
        serverTrustPolicy: HAServerTrustPolicy
    ) async -> HAClientResult<HAOAuthToken> {
        recordedRefreshRequests.append(
            OAuthRefreshRequest(
                baseURL: baseURL,
                refreshToken: refreshToken,
                clientID: clientID,
                serverTrustPolicy: serverTrustPolicy
            )
        )
        guard !refreshResults.isEmpty else {
            return .failure(.transport("unexpected refresh request"))
        }
        return refreshResults.removeFirst()
    }

    func discoveryURLs() -> [URL] {
        recordedDiscoveryURLs
    }

    func discoveryTokens() -> [String] {
        recordedDiscoveryTokens
    }

    func discoveryTrustPolicies() -> [HAServerTrustPolicy] {
        recordedDiscoveryTrustPolicies
    }

    func refreshRequests() -> [OAuthRefreshRequest] {
        recordedRefreshRequests
    }
}

private actor ConnectionFormRecorder {
    private var recordedCallCount = 0
    private var recordedURLStrings: [String] = []
    private var recordedFallbackURLString: String?
    private var recordedTokens: [String] = []
    private var recordedUsesStoredAuthSessions: [Bool] = []
    private var recordedSelfSignedCertificateAllowances: [Bool] = []

    func record(_ form: PerchHAConnectionForm) {
        recordedCallCount += 1
        recordedURLStrings.append(form.primaryURL()?.absoluteString ?? form.urlString)
        recordedFallbackURLString = form.fallbackURL()?.absoluteString
        recordedTokens.append(form.token)
        recordedUsesStoredAuthSessions.append(form.usesStoredAuthSession)
        recordedSelfSignedCertificateAllowances.append(form.allowsSelfSignedCertificates)
    }

    func callCount() -> Int {
        recordedCallCount
    }

    func fallbackURLString() -> String? {
        recordedFallbackURLString
    }

    func urlStrings() -> [String] {
        recordedURLStrings
    }

    func tokens() -> [String] {
        recordedTokens
    }

    func usesStoredAuthSessions() -> [Bool] {
        recordedUsesStoredAuthSessions
    }

    func selfSignedCertificateAllowances() -> [Bool] {
        recordedSelfSignedCertificateAllowances
    }
}

private actor ConnectionResultRecorder {
    private var results: [PerchHAConnectionAttemptResult]
    private var recordedCallCount = 0

    init(results: [PerchHAConnectionAttemptResult]) {
        self.results = results
    }

    func next() -> PerchHAConnectionAttemptResult {
        recordedCallCount += 1
        if results.isEmpty {
            return .failure(.protocolError("connection result sequence is empty"))
        }
        return results.removeFirst()
    }

    func callCount() -> Int {
        recordedCallCount
    }
}

private actor HistoryProviderRecorder {
    private var results: [PerchHAHistoryProviderResult]
    private let waitForRelease: Bool
    private var recordedForms: [PerchHAConnectionForm] = []
    private var recordedEntityIDs: [EntityID] = []
    private var recordedRanges: [HistoryRange] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(results: [PerchHAHistoryProviderResult], waitForRelease: Bool = false) {
        self.results = results
        self.waitForRelease = waitForRelease
    }

    func provide(
        form: PerchHAConnectionForm,
        entityID: EntityID,
        range: HistoryRange
    ) async -> PerchHAHistoryProviderResult {
        recordedForms.append(form)
        recordedEntityIDs.append(entityID)
        recordedRanges.append(range)
        if waitForRelease {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        if results.isEmpty {
            return .unavailable("history result sequence is empty")
        }
        return results.removeFirst()
    }

    func releaseNext() {
        guard !waiters.isEmpty else {
            return
        }
        let continuation = waiters.removeFirst()
        continuation.resume()
    }

    func callCount() -> Int {
        recordedRanges.count
    }

    func ranges() -> [HistoryRange] {
        recordedRanges
    }

    func entityIDs() -> [EntityID] {
        recordedEntityIDs
    }

    func tokens() -> [String] {
        recordedForms.map(\.token)
    }
}

private actor ActionRunnerRecorder {
    private var results: [PerchHAActionResult]
    private let waitForRelease: Bool
    private var recordedForms: [PerchHAConnectionForm] = []
    private var recordedActions: [ActionSpec] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(results: [PerchHAActionResult], waitForRelease: Bool = false) {
        self.results = results
        self.waitForRelease = waitForRelease
    }

    func run(form: PerchHAConnectionForm, action: ActionSpec) async -> PerchHAActionResult {
        recordedForms.append(form)
        recordedActions.append(action)
        if waitForRelease {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
        if results.isEmpty {
            return .failed("action result sequence is empty")
        }
        return results.removeFirst()
    }

    func releaseNext() {
        guard !waiters.isEmpty else {
            return
        }
        waiters.removeFirst().resume()
    }

    func callCount() -> Int {
        recordedActions.count
    }

    func actions() -> [ActionSpec] {
        recordedActions
    }

    func tokens() -> [String] {
        recordedForms.map(\.token)
    }
}

private actor ConnectionGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

@MainActor
private final class SelectionSinkRecorder {
    private(set) var lastSelection: EntitySelectionConfiguration?

    func record(_ selection: EntitySelectionConfiguration) -> SelectionPersistenceResult {
        lastSelection = selection
        return .saved
    }
}

@MainActor
private final class MenuBarDisplaySinkRecorder {
    private(set) var lastDisplayConfiguration: MenuBarDisplayConfiguration?

    func record(_ displayConfiguration: MenuBarDisplayConfiguration) -> SelectionPersistenceResult {
        lastDisplayConfiguration = displayConfiguration
        return .saved
    }
}

@MainActor
private final class CountingStatusItemGaugeImageRenderer: PerchHAStatusItemGaugeImageRendering {
    private let renderer = PerchHAStatusItemGaugeImageRenderer()
    private(set) var renderedItems: [RenderedMenuBarItem] = []

    var renderCount: Int {
        renderedItems.count
    }

    func image(for item: RenderedMenuBarItem) -> NSImage? {
        renderedItems.append(item)
        return renderer.image(for: item)
    }
}

@MainActor
private final class CustomActionSinkRecorder {
    private var recordedConfigurations: [CustomActionConfiguration] = []

    func record(_ configuration: CustomActionConfiguration) -> SelectionPersistenceResult {
        recordedConfigurations.append(configuration)
        return .saved
    }

    func configurations() -> [CustomActionConfiguration] {
        recordedConfigurations
    }
}

private final class InMemoryProtectedActionValueStore: ProtectedActionValueStore, @unchecked Sendable {
    private var values: [ProtectedActionValueReference: String] = [:]

    func save(_ value: String, for reference: ProtectedActionValueReference) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw SecretStoreError.emptySecret(.customActionProtectedValues)
        }
        values[reference] = normalized
    }

    func load(_ reference: ProtectedActionValueReference) throws -> String {
        guard let value = values[reference] else {
            throw ProtectedActionValueStoreError.missingValue(reference)
        }
        return value
    }

    func delete(_ reference: ProtectedActionValueReference) throws {
        values.removeValue(forKey: reference)
    }

    func snapshot() throws -> [ProtectedActionValueReference: String] {
        values
    }
}

private extension PerchHAPanelModel {
    func entityState(_ id: EntityID) -> String? {
        snapshot.availableRooms
            .flatMap(\.entities)
            .first { $0.id == id }?
            .state
    }

    func entityPosition(_ id: EntityID) -> Int? {
        snapshot.availableRooms
            .flatMap(\.entities)
            .first { $0.id == id }?
            .currentPosition
    }
}

private extension PerchHAApplication {
    var snapshotSelectionConfiguration: EntitySelectionConfiguration {
        EntitySelectionConfiguration(
            selectedEntityIDs: snapshot.selectedEntityIDs,
            roomOrder: snapshot.roomOrder,
            entityOrder: snapshot.entityOrder,
            isExplicit: snapshot.isEntitySelectionExplicit
        )
    }
}

private extension NSImage {
    func containsPixel(closeTo expectedColor: NSColor) -> Bool {
        var proposedRect = NSRect(origin: .zero, size: size)
        guard let cgImage = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
              let expected = expectedColor.usingColorSpace(.sRGB)
        else {
            return false
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let actual = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      actual.alphaComponent > 0.75
                else {
                    continue
                }
                if abs(actual.redComponent - expected.redComponent) < 0.08,
                   abs(actual.greenComponent - expected.greenComponent) < 0.08,
                   abs(actual.blueComponent - expected.blueComponent) < 0.08 {
                    return true
                }
            }
        }
        return false
    }
}

private final class FailingConfigStore: ConfigStore, @unchecked Sendable {
    private let loadedConfiguration: PerchHAConfiguration
    private let loadError: ConfigStoreError?
    private let saveError: ConfigStoreError?
    private(set) var saveCallCount = 0

    init(
        loadedConfiguration: PerchHAConfiguration = .empty,
        loadError: ConfigStoreError? = nil,
        saveError: ConfigStoreError? = nil
    ) {
        self.loadedConfiguration = loadedConfiguration
        self.loadError = loadError
        self.saveError = saveError
    }

    func describe() -> PerchHAModule {
        PerchHAPersistence.module
    }

    func load() throws -> PerchHAConfiguration {
        if let loadError {
            throw loadError
        }
        return loadedConfiguration
    }

    @discardableResult
    func save(_ configuration: PerchHAConfiguration) throws -> PerchHAConfiguration {
        saveCallCount += 1
        if let saveError {
            throw saveError
        }
        return configuration
    }
}
#endif
