#if canImport(XCTest)
import AppKit
import Combine
import Foundation
import FakeHA
import SwiftUI
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
        XCTAssertEqual(snapshot.accessibilitySummary, "PearchHA reconnecting 2, 0 visible values")
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
        XCTAssertEqual(success.accessibilityPresentation().summary, "PearchHA connected, 3 visible values")
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

    func test_t_design_tokens_expose_the_documented_spacing_and_radius_scale() {
        XCTAssertEqual(PerchHASpacing.xs, 4)
        XCTAssertEqual(PerchHASpacing.sm, 8)
        XCTAssertEqual(PerchHASpacing.md, 12)
        XCTAssertEqual(PerchHASpacing.lg, 16)
        XCTAssertEqual(PerchHASpacing.xl, 24)
        XCTAssertEqual(PerchHACornerRadius.control, 8)
        XCTAssertEqual(PerchHACornerRadius.card, 12)
        XCTAssertEqual(PerchHACornerRadius.panel, 16)
    }

    func test_t_motion_token_duration_sits_in_the_documented_range() {
        XCTAssertEqual(PerchHAMotion.standardDuration, 0.18, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(PerchHAMotion.standardDuration, 0.12)
        XCTAssertLessThanOrEqual(PerchHAMotion.standardDuration, 0.20)
    }

    func test_t_motion_animation_helper_is_nil_only_when_reduce_motion_is_on() {
        XCTAssertNil(PerchHAMotion.animation(reduceMotion: true))
        XCTAssertNotNil(PerchHAMotion.animation(reduceMotion: false))
    }

    func test_t_state_view_kind_maps_loading_phase() {
        XCTAssertEqual(PerchHAStateViewKind.forContent(phase: .connecting), .loading)
    }

    func test_t_state_view_kind_maps_empty_phase() {
        XCTAssertEqual(PerchHAStateViewKind.forContent(phase: .connectedEmpty), .empty)
    }

    func test_t_state_view_kind_maps_connection_form_phases() {
        XCTAssertEqual(PerchHAStateViewKind.forContent(phase: .firstRun), .connectionForm)
        XCTAssertEqual(
            PerchHAStateViewKind.forContent(phase: .failed(.authentication)),
            .connectionForm
        )
    }

    func test_t_state_view_kind_maps_data_phases() {
        XCTAssertEqual(PerchHAStateViewKind.forContent(phase: .connectedData), .data)
        XCTAssertEqual(PerchHAStateViewKind.forContent(phase: .reconnecting(attempt: 1)), .data)
        XCTAssertEqual(
            PerchHAStateViewKind.forContent(phase: .failedStale(.unreachable(host: "ha.local"))),
            .data
        )
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

        XCTAssertEqual(presentation.label, "PearchHA failed: authentication failed, 0 visible values")
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

    func testConnectionFormNormalizesFrontendURLsToUsableBaseURLs() {
        let form = PerchHAConnectionForm(
            urlString: " https://HA-PRIMARY.example/lovelace/0?dashboard=1#kitchen ",
            fallbackURLString: "https://fallback.example/ha/history?entity=sensor.temp"
        )

        XCTAssertEqual(
            PerchHAConnectionForm.normalizedHomeAssistantURLString(form.urlString),
            "https://ha-primary.example"
        )
        XCTAssertEqual(
            PerchHAConnectionForm.normalizedHomeAssistantURLString(form.fallbackURLString),
            "https://fallback.example/ha"
        )
        XCTAssertEqual(form.primaryURL()?.absoluteString, "https://ha-primary.example")
        XCTAssertEqual(form.fallbackURL()?.absoluteString, "https://fallback.example/ha")
    }

    func testConnectionFormKeepsProxyPrefixWhenNoFrontendRouteIsPresent() {
        let form = PerchHAConnectionForm(urlString: "https://homeassistant.local/ha")

        XCTAssertEqual(form.primaryURL()?.absoluteString, "https://homeassistant.local/ha")
    }

    func testPanelConnectionFormForwardsCredentialsWithoutLeakingToken() async {
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel { form in
            await recorder.record(form)
            return .success(rooms: [])
        }

        model.updateConnectionForm(
            urlString: "https://homeassistant.local:8123",
            fallbackURLString: "https://fallback.example",
            token: "secret-token"
        )
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        let recordedTokens = await recorder.tokens()
        XCTAssertEqual(recordedTokens, ["secret-token"])
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
        let _hoisted1 = await recorder.tokens()
        XCTAssertEqual(_hoisted1, [""])
        let _hoisted2 = await recorder.usesStoredAuthSessions()
        XCTAssertEqual(_hoisted2, [true])
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

    func testConnectionTokenPresentationExplainsSavedKeychainToken() {
        let presentation = PerchHAConnectionTokenAccessPresentation(
            usesStoredToken: true,
            tokenDraft: ""
        )

        XCTAssertEqual(presentation.fieldPlaceholder, "Paste new token to replace the saved one")
        XCTAssertEqual(presentation.editableButtonTitle, "Connect with saved token")
        XCTAssertEqual(presentation.connectedButtonTitle, "Reconnect with saved token")
        XCTAssertNotNil(presentation.savedTokenGuidance)
    }

    func testConnectionTokenPresentationTreatsTypedDraftAsReplacementToken() {
        let presentation = PerchHAConnectionTokenAccessPresentation(
            usesStoredToken: true,
            tokenDraft: "replacement-token"
        )

        XCTAssertEqual(presentation.fieldPlaceholder, "Access token")
        XCTAssertEqual(presentation.editableButtonTitle, "Connect with token")
        XCTAssertEqual(presentation.connectedButtonTitle, "Update token and reconnect")
        XCTAssertNil(presentation.savedTokenGuidance)
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
        let _hoisted3 = await recorder.tokens()
        XCTAssertEqual(_hoisted3, ["secret-token", "secret-token"])
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
        let _hoisted4 = await recorder.tokens()
        XCTAssertEqual(_hoisted4, ["secret-token"])
        let _hoisted5 = await recorder.fallbackURLString()
        XCTAssertEqual(_hoisted5, "http://127.0.0.1:8124")
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
        let _hoisted6 = await recorder.callCount()
        XCTAssertEqual(_hoisted6, 0)
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

        XCTAssertEqual(model.snapshot.connectionState, .failed(.protocolError("invalid alternative address")))
        XCTAssertEqual(model.snapshot.failureDescription, "invalid alternative address")
        let _hoisted7 = await recorder.callCount()
        XCTAssertEqual(_hoisted7, 0)
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
        let _hoisted8 = await recorder.fallbackURLString()
        XCTAssertEqual(_hoisted8, "http://127.0.0.1:8124")
    }

    func testConnectBuildsEndpointWithAllAddressesInOrder() async throws {
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel { form in
            await recorder.record(form)
            return .success(rooms: [])
        }

        model.updateConnectionForm(
            urlString: "https://home.local:8123",
            addresses: [
                PerchHAConnectionAddressField(label: "VPN", urlString: "https://vpn.example/ha"),
                PerchHAConnectionAddressField(label: "Remote", urlString: "https://remote.example")
            ],
            token: "fake-token"
        )
        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .connected)
        let urlLists = await recorder.urlLists()
        XCTAssertEqual(
            urlLists.last,
            ["https://home.local:8123", "https://vpn.example/ha", "https://remote.example"]
        )
    }

    func testAddRemoveAndReorderConnectionAddressesMutateFormList() {
        let model = PerchHAPanelModel()
        model.updateConnectionForm(urlString: "https://home.local:8123")

        model.addConnectionAddress()
        model.addConnectionAddress()
        XCTAssertEqual(model.snapshot.connectionForm.addresses.count, 2)

        let first = model.snapshot.connectionForm.addresses[0].id
        let second = model.snapshot.connectionForm.addresses[1].id
        model.updateConnectionAddress(id: first, label: "VPN", urlString: "https://vpn.example")
        model.updateConnectionAddress(id: second, label: "Remote", urlString: "https://remote.example")

        XCTAssertTrue(model.moveConnectionAddress(id: second, direction: .up))
        XCTAssertEqual(
            model.snapshot.connectionForm.addresses.map(\.label),
            ["Remote", "VPN"]
        )
        XCTAssertFalse(model.moveConnectionAddress(id: second, direction: .up))

        model.removeConnectionAddress(id: first)
        XCTAssertEqual(model.snapshot.connectionForm.addresses.map(\.label), ["Remote"])
    }

    func testEditingAddressesWhileConnectedReconnectsWithStoredTokenWithoutLosingIt() async throws {
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel { form in
            await recorder.record(form)
            return .success(rooms: [])
        }

        model.updateConnectionForm(urlString: "https://home.local:8123", usesStoredAuthSession: true)
        await model.connect()
        XCTAssertEqual(model.snapshot.connectionState, .connected)

        model.addConnectionAddress()
        let alternative = try XCTUnwrap(model.snapshot.connectionForm.addresses.first)
        model.updateConnectionAddress(id: alternative.id, urlString: "https://vpn.example")
        XCTAssertTrue(model.canApplyConnectionEdits)

        await model.connect()

        XCTAssertEqual(model.snapshot.connectionState, .connected)
        let sessions = await recorder.usesStoredAuthSessions()
        XCTAssertEqual(sessions.last, true)
        let urlLists = await recorder.urlLists()
        XCTAssertEqual(urlLists.last, ["https://home.local:8123", "https://vpn.example"])
        XCTAssertTrue(model.snapshot.connectionForm.usesStoredAuthSession)
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
        XCTAssertTrue(model.snapshot.lastUpdateDescription.hasPrefix("Updated at "), model.snapshot.lastUpdateDescription)
        XCTAssertNil(model.snapshot.problemDescription)
        XCTAssertEqual(model.snapshot.connectionForm.token, "")
        XCTAssertTrue(model.snapshot.hasTokenInput)
    }

    func test_t_sign_out_resets_state_and_invokes_handler() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
            areaRegistryBody: #"[{"area_id":"office","name":"Office"}]"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryBody: #"[{"entity_id":"sensor.office_temperature","name":"Office temperature","area_id":"office"}]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer { server.stop() }

        var signOutCount = 0
        let model = PerchHAPanelModel(
            connector: fakeHAConnector,
            signOutHandler: { signOutCount += 1 }
        )
        model.updateConnectionForm(urlString: server.baseURL.absoluteString, token: "fake-token")
        await model.connect()
        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertFalse(model.snapshot.rooms.isEmpty)

        model.signOut()

        XCTAssertEqual(signOutCount, 1)
        XCTAssertEqual(model.snapshot.connectionState, .disconnected)
        XCTAssertEqual(model.snapshot.phase, .firstRun)
        XCTAssertTrue(model.snapshot.rooms.isEmpty)
        XCTAssertFalse(model.snapshot.hasTokenInput)
        XCTAssertFalse(model.snapshot.connectionForm.usesStoredAuthSession)
        // The saved URL is kept so the user can reconnect easily.
        XCTAssertEqual(model.snapshot.connectionForm.urlString, server.baseURL.absoluteString)

        // Reconnecting after sign-out works.
        model.updateConnectionForm(token: "fake-token")
        await model.connect()
        XCTAssertEqual(model.snapshot.connectionState, .connected)
        XCTAssertFalse(model.snapshot.rooms.isEmpty)
    }

    func test_t_footer_problem_description_is_silent_when_healthy_and_reports_failures() {
        let connected = PerchHAPanelSnapshot(
            connectionState: .connected,
            phase: .connectedData
        )
        XCTAssertNil(connected.problemDescription)

        let connecting = PerchHAPanelSnapshot(
            connectionState: .connecting,
            phase: .connecting
        )
        XCTAssertNil(connecting.problemDescription)

        let disconnected = PerchHAPanelSnapshot(
            connectionState: .disconnected,
            phase: .firstRun
        )
        XCTAssertEqual(disconnected.problemDescription, "Disconnected")

        let reconnecting = PerchHAPanelSnapshot(
            connectionState: .reconnecting(attempt: 2),
            phase: .reconnecting(attempt: 2)
        )
        XCTAssertEqual(reconnecting.problemDescription, "Reconnecting (attempt 2)")

        let failed = PerchHAPanelSnapshot(
            connectionState: .failed(.authentication),
            phase: .failed(.authentication)
        )
        XCTAssertEqual(failed.problemDescription, "authentication failed")
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

    func test_t_panel_select_all_and_clear_all_entities() async {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        let availableCount = model.snapshot.availableRooms.flatMap(\.entities).count

        model.setAllEntities(isSelected: true)
        XCTAssertEqual(model.snapshot.selectionConfiguration.selectedEntityIDs.count, availableCount)
        XCTAssertEqual(model.snapshot.rooms.flatMap(\.entities).count, availableCount)

        model.setAllEntities(isSelected: false)
        XCTAssertEqual(model.snapshot.selectionConfiguration.selectedEntityIDs, [])
        XCTAssertEqual(model.snapshot.rooms.flatMap(\.entities).count, 0)
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
        let _hoisted9 = await recorder.callCount()
        XCTAssertEqual(_hoisted9, 0)
        XCTAssertEqual(model.snapshot.historyState, .idle)

        _ = await clock.advance(by: .milliseconds(999))
        await Task.yield()
        let _hoisted10 = await recorder.callCount()
        XCTAssertEqual(_hoisted10, 0)
        XCTAssertEqual(model.snapshot.historyState, .idle)

        _ = await clock.advance(by: .milliseconds(1))
        await spinUntil {
            if case .loaded = model.snapshot.historyState {
                return true
            }
            return false
        }
        let _hoisted11 = await recorder.callCount()
        XCTAssertEqual(_hoisted11, 1)
        let _hoisted12 = await recorder.ranges()
        XCTAssertEqual(_hoisted12, [.hour])
        XCTAssertEqual(model.snapshot.historyState.entityID, "sensor.office_temperature")
    }

    func test_t_history_cancel_hover_resets_loading_state() async {
        let clock = TestPerchClock()
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
            },
            clock: clock,
            historyHoverGrace: .milliseconds(300)
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
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        _ = await clock.advance(by: .milliseconds(300))
        await spinUntil { model.snapshot.historyState == .idle }

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

        let _hoisted13 = await recorder.ranges()
        XCTAssertEqual(_hoisted13, [.day])
        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .day, value: 21.4)))
    }

    func test_t_history_load_uses_dashboard_default_history_range_when_entity_inherits() async {
        let recorder = HistoryProviderRecorder(
            results: [
                .success(historySeries(entityID: "sensor.office_temperature", range: .week, value: 21.4))
            ]
        )
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { form, entityID, range in
                await recorder.provide(form: form, entityID: entityID, range: range)
            }
        )
        model.applyDisplayPreferences(.defaults.with(defaultHistoryRange: .week))

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        await model.loadHistory("sensor.office_temperature")

        let _hoisted13b = await recorder.ranges()
        XCTAssertEqual(_hoisted13b, [.week])
        XCTAssertEqual(
            model.snapshot.historyState,
            .loaded(historySeries(entityID: "sensor.office_temperature", range: .week, value: 21.4))
        )
    }

    func test_t_history_load_uses_updated_entity_default_history_range_after_settings_change() async {
        let recorder = HistoryProviderRecorder(
            results: [
                .success(historySeries(entityID: "sensor.office_temperature", range: .week, value: 21.4))
            ]
        )
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { form, entityID, range in
                await recorder.provide(form: form, entityID: entityID, range: range)
            },
            menuBarDisplayConfiguration: MenuBarDisplayConfiguration(
                itemConfigurations: [
                    MenuBarItemConfiguration(entityID: "sensor.office_temperature")
                ]
            )
        )
        model.applyDisplayPreferences(.defaults.with(defaultHistoryRange: .day))

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        XCTAssertTrue(model.setMenuBarDefaultHistoryRange("sensor.office_temperature", defaultHistoryRange: .week))

        await model.loadHistory("sensor.office_temperature")

        let _hoisted13c = await recorder.ranges()
        XCTAssertEqual(_hoisted13c, [.week])
        XCTAssertEqual(
            model.snapshot.historyState,
            .loaded(historySeries(entityID: "sensor.office_temperature", range: .week, value: 21.4))
        )
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
        let _hoisted14 = await recorder.callCount()
        XCTAssertEqual(_hoisted14, 1)
        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4)))

        await model.loadHistory("sensor.office_temperature", range: .hour)
        let _hoisted15 = await recorder.callCount()
        XCTAssertEqual(_hoisted15, 1)
        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4)))

        _ = await clock.advance(by: .seconds(6))
        await model.loadHistory("sensor.office_temperature", range: .hour)
        let _hoisted16 = await recorder.callCount()
        XCTAssertEqual(_hoisted16, 2)
        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 22.0)))
    }

    func test_t_expired_entry_survives_failed_refetch_for_stale_display() async {
        let clock = TestPerchClock()
        let recorder = HistoryProviderRecorder(
            results: [
                .success(historySeries(entityID: "sensor.office_temperature", range: .day, value: 21.4)),
                .unavailable("server hiccup")
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
        await model.loadHistory("sensor.office_temperature", range: .day)
        XCTAssertNotNil(model.cachedHistorySeries(for: "sensor.office_temperature"))

        // The entry crosses its TTL, the refetch fails: the hover popover reports
        // unavailable, but the inline preview must keep its last-known series —
        // an expired read that races a server hiccup used to delete the entry and
        // blank the sparkline until the next successful sync.
        _ = await clock.advance(by: .seconds(6))
        await model.loadHistory("sensor.office_temperature", range: .day)

        XCTAssertEqual(
            model.snapshot.historyState,
            .unavailable(entityID: "sensor.office_temperature", range: .day, message: "server hiccup")
        )
        XCTAssertEqual(
            model.cachedHistorySeries(for: "sensor.office_temperature"),
            historySeries(entityID: "sensor.office_temperature", range: .day, value: 21.4),
            "a failed refetch must not evict the stale-but-displayable series"
        )
    }

    func test_t_clicking_a_row_pins_the_history_popover_until_unpinned() async {
        let clock = TestPerchClock()
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
            clock: clock,
            historyDebounce: .milliseconds(0),
            historyHoverGrace: .milliseconds(300)
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        // Click pins the popover open.
        model.toggleHistoryPin("sensor.office_temperature")
        await spinUntil { model.snapshot.historyPresentationEntityID == "sensor.office_temperature" }
        XCTAssertEqual(model.pinnedHistoryEntityID, "sensor.office_temperature")

        // Hover-out is ignored while pinned: no grace close is even scheduled.
        model.cancelHistoryHover()
        _ = await clock.advance(by: .seconds(2))
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(model.snapshot.historyPresentationEntityID, "sensor.office_temperature")

        // Hovering another row must not steal a pinned popover.
        model.startHistoryHover("sensor.office_humidity")
        XCTAssertEqual(model.snapshot.historyPresentationEntityID, "sensor.office_temperature")

        // Clicking again unpins and closes immediately.
        model.toggleHistoryPin("sensor.office_temperature")
        XCTAssertNil(model.pinnedHistoryEntityID)
        XCTAssertNil(model.snapshot.historyPresentationEntityID)
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

        let _hoisted17 = await recorder.callCount()
        XCTAssertEqual(_hoisted17, 2)
        let _hoisted18 = await recorder.tokens()
        XCTAssertEqual(_hoisted18, ["first-token", "second-token"])
        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 22.0)))
    }

    func testHistoryCacheEvictsLeastRecentlyUsedEntryWhenCapacityIsReached() async {
        let recorder = HistoryProviderRecorder(
            results: [
                .success(historySeries(entityID: "sensor.office_temperature", range: .day, value: 21.4)),
                .success(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.8)),
                .success(historySeries(entityID: "sensor.office_temperature", range: .week, value: 21.9)),
                .success(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 22.0))
            ]
        )
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { form, entityID, range in
                await recorder.provide(form: form, entityID: entityID, range: range)
            },
            historyDebounce: .milliseconds(0),
            historyCacheConfiguration: PerchHAHistoryCacheConfiguration(capacity: 2, ttl: .seconds(60))
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        // .day is the displayed default range — its key backs the inline
        // preview and is exempt from eviction. The hover ranges compete for the
        // remaining capacity: loading .week over a full cache evicts .hour (the
        // least recently used evictable entry), never the .day preview key.
        await model.loadHistory("sensor.office_temperature", range: .day)
        await model.loadHistory("sensor.office_temperature", range: .hour)
        await model.loadHistory("sensor.office_temperature", range: .week)

        // .hour was evicted, so it refetches; .day is still cached.
        await model.loadHistory("sensor.office_temperature", range: .hour)
        await model.loadHistory("sensor.office_temperature", range: .day)

        let _hoisted19 = await recorder.callCount()
        XCTAssertEqual(_hoisted19, 4)
        let _hoisted20 = await recorder.ranges()
        XCTAssertEqual(_hoisted20, [.day, .hour, .week, .hour])
        XCTAssertEqual(model.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .day, value: 21.4)))
        XCTAssertEqual(
            model.cachedHistorySeries(for: "sensor.office_temperature"),
            historySeries(entityID: "sensor.office_temperature", range: .day, value: 21.4),
            "the displayed preview key must survive capacity pressure"
        )
    }
    func test_t_history_hover_out_closes_loaded_and_unavailable_popovers() async {
        let loadedClock = TestPerchClock()
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
            clock: loadedClock,
            historyDebounce: .milliseconds(0),
            historyHoverGrace: .milliseconds(300)
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
        await spinUntil { await loadedClock.sleepingTaskCount() == 1 }
        _ = await loadedClock.advance(by: .milliseconds(300))
        await spinUntil { loadedModel.snapshot.historyPresentationEntityID == nil }
        XCTAssertNil(loadedModel.snapshot.historyPresentationEntityID)
        XCTAssertEqual(loadedModel.snapshot.historyState, .loaded(historySeries(entityID: "sensor.office_temperature", range: .hour, value: 21.4)))

        let unavailableClock = TestPerchClock()
        let unavailableModel = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { _, _, _ in .unavailable("history unavailable") },
            clock: unavailableClock,
            historyDebounce: .milliseconds(0),
            historyHoverGrace: .milliseconds(300)
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
        await spinUntil { await unavailableClock.sleepingTaskCount() == 1 }
        _ = await unavailableClock.advance(by: .milliseconds(300))
        await spinUntil { unavailableModel.snapshot.historyPresentationEntityID == nil }
        XCTAssertNil(unavailableModel.snapshot.historyPresentationEntityID)
        XCTAssertEqual(
            unavailableModel.snapshot.historyState,
            .unavailable(entityID: "sensor.office_temperature", range: .hour, message: "history unavailable")
        )
    }

    func test_t_history_hover_out_keeps_presentation_until_grace_elapses() async {
        let clock = TestPerchClock()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { _, entityID, range in
                .success(historySeriesFixture(entityID: entityID, range: range, value: 21.4))
            },
            clock: clock,
            historyDebounce: .milliseconds(0),
            historyHoverGrace: .milliseconds(300)
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        model.startHistoryHover("sensor.office_temperature", range: .hour)
        await spinUntil {
            if case .loaded = model.snapshot.historyState {
                return true
            }
            return false
        }

        model.cancelHistoryHover()
        await spinUntil { await clock.sleepingTaskCount() == 1 }

        _ = await clock.advance(by: .milliseconds(299))
        await Task.yield()
        XCTAssertEqual(model.snapshot.historyPresentationEntityID, "sensor.office_temperature")

        _ = await clock.advance(by: .milliseconds(1))
        await spinUntil { model.snapshot.historyPresentationEntityID == nil }
        XCTAssertNil(model.snapshot.historyPresentationEntityID)
    }

    func test_t_history_keep_alive_cancels_pending_grace_close() async {
        let clock = TestPerchClock()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { _, entityID, range in
                .success(historySeriesFixture(entityID: entityID, range: range, value: 21.4))
            },
            clock: clock,
            historyDebounce: .milliseconds(0),
            historyHoverGrace: .milliseconds(300)
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        model.startHistoryHover("sensor.office_temperature", range: .hour)
        await spinUntil {
            if case .loaded = model.snapshot.historyState {
                return true
            }
            return false
        }

        model.cancelHistoryHover()
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        model.keepHistoryHoverAlive()
        await spinUntil { await clock.sleepingTaskCount() == 0 }

        _ = await clock.advance(by: .seconds(5))
        await Task.yield()
        XCTAssertEqual(model.snapshot.historyPresentationEntityID, "sensor.office_temperature")
    }

    func test_t_history_re_entering_row_cancels_pending_grace_close() async {
        let clock = TestPerchClock()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { _, entityID, range in
                .success(historySeriesFixture(entityID: entityID, range: range, value: 21.4))
            },
            clock: clock,
            historyDebounce: .milliseconds(0),
            historyHoverGrace: .milliseconds(300)
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        model.startHistoryHover("sensor.office_temperature", range: .hour)
        await spinUntil {
            if case .loaded = model.snapshot.historyState {
                return true
            }
            return false
        }

        model.cancelHistoryHover()
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        model.startHistoryHover("sensor.office_temperature", range: .hour)
        await spinUntil {
            if case .loaded = model.snapshot.historyState {
                return true
            }
            return false
        }

        _ = await clock.advance(by: .seconds(5))
        await Task.yield()
        XCTAssertEqual(model.snapshot.historyPresentationEntityID, "sensor.office_temperature")
    }

    func test_t_history_empty_loaded_series_produces_empty_state() async {
        let emptySeries = HistorySeries(entityID: "sensor.office_temperature", range: .hour, samples: [])
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { _, _, _ in .success(emptySeries) },
            historyDebounce: .milliseconds(0)
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        await model.loadHistory("sensor.office_temperature", range: .hour)

        XCTAssertEqual(model.snapshot.historyState, .loaded(emptySeries))
        XCTAssertEqual(
            PerchHAHistoryBodyPresentation(state: model.snapshot.historyState, entityID: "sensor.office_temperature"),
            .empty
        )
    }

    func test_t_history_provider_failure_produces_unavailable_state() async {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { _, _, _ in .unavailable("lost connection to Home Assistant") },
            historyDebounce: .milliseconds(0)
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        await model.loadHistory("sensor.office_temperature", range: .hour)

        XCTAssertEqual(
            model.snapshot.historyState,
            .unavailable(
                entityID: "sensor.office_temperature",
                range: .hour,
                message: "lost connection to Home Assistant"
            )
        )
        XCTAssertEqual(
            PerchHAHistoryBodyPresentation(state: model.snapshot.historyState, entityID: "sensor.office_temperature"),
            .unavailable("lost connection to Home Assistant")
        )
    }

    /// The reserved-grid promise: swapping a row's history-preview placeholder for
    /// a real micro chart must not change the row's height, so cache-fill lands in
    /// place without shifting neighbors. Rendered through the public ``TelemetryRow``
    /// entrypoint into a hosting view at a fixed width.
    func testHistoryContentSummaryEmptySeriesIsEmpty() {
        XCTAssertEqual(
            PerchHAHistoryContentSummary(
                series: HistorySeries(entityID: "sensor.office_temperature", range: .hour, samples: [])
            ),
            .empty
        )
    }

    func testHistoryContentSummaryNonNumericSeriesBecomesStateTimeline() {
        let series = HistorySeries(
            entityID: "cover.office_blinds",
            range: .day,
            samples: [
                HistorySample(timestamp: Date(timeIntervalSince1970: 0), state: "open", numericValue: nil),
                HistorySample(timestamp: Date(timeIntervalSince1970: 600), state: "open", numericValue: nil),
                HistorySample(timestamp: Date(timeIntervalSince1970: 1_200), state: "closed", numericValue: nil)
            ]
        )
        XCTAssertEqual(
            PerchHAHistoryContentSummary(series: series),
            .stateTimeline(
                [
                    HistoryStateSegment(
                        state: "open",
                        start: Date(timeIntervalSince1970: 0),
                        end: Date(timeIntervalSince1970: 1_200)
                    ),
                    HistoryStateSegment(
                        state: "closed",
                        start: Date(timeIntervalSince1970: 1_200),
                        end: Date(timeIntervalSince1970: 1_200)
                    )
                ]
            )
        )
    }

    func testHistoryBodyPresentationMapsNonNumericSeriesToStateTimeline() {
        let series = HistorySeries(
            entityID: "switch.office_lamp",
            range: .day,
            samples: [
                HistorySample(timestamp: Date(timeIntervalSince1970: 0), state: "on", numericValue: nil),
                HistorySample(timestamp: Date(timeIntervalSince1970: 300), state: "off", numericValue: nil)
            ]
        )
        let segments = HistoryStateSegments.segments(of: series)
        XCTAssertEqual(
            PerchHAHistoryBodyPresentation(state: .loaded(series), entityID: "switch.office_lamp"),
            .stateTimeline(series: series, segments: segments)
        )
    }

    func testHistoryChartPeaksFormatMinAndMaxForCornerLabels() {
        let series = HistorySeries(
            entityID: "sensor.office_temperature",
            range: .day,
            samples: [
                HistorySample(timestamp: Date(timeIntervalSince1970: 0), state: "18.2", numericValue: 18.2),
                HistorySample(timestamp: Date(timeIntervalSince1970: 300), state: "24", numericValue: 24),
                HistorySample(timestamp: Date(timeIntervalSince1970: 600), state: "unknown", numericValue: nil)
            ]
        )
        let peaks = PerchHAHistoryPopoverContent.chartPeaks(series: series)
        XCTAssertEqual(peaks?.minimum, "18.2")
        XCTAssertEqual(peaks?.maximum, "24")
    }

    func testHistoryChartPeaksHideForFlatOrNonNumericSeries() {
        let flat = HistorySeries(
            entityID: "sensor.office_temperature",
            range: .day,
            samples: [
                HistorySample(timestamp: Date(timeIntervalSince1970: 0), state: "21", numericValue: 21),
                HistorySample(timestamp: Date(timeIntervalSince1970: 300), state: "21", numericValue: 21)
            ]
        )
        XCTAssertNil(
            PerchHAHistoryPopoverContent.chartPeaks(series: flat),
            "a flat series has no spread worth labelling"
        )
        let nonNumeric = HistorySeries(
            entityID: "switch.office_lamp",
            range: .day,
            samples: [
                HistorySample(timestamp: Date(timeIntervalSince1970: 0), state: "on", numericValue: nil)
            ]
        )
        XCTAssertNil(PerchHAHistoryPopoverContent.chartPeaks(series: nonNumeric))
    }

    func testHistoryCursorReadoutIncludesDateAndTimeForDayRange() {
        let readout = PerchHAHistoryPopoverContent.cursorReadout(
            value: 53.2,
            unit: "%",
            timestamp: Date(timeIntervalSince1970: 0),
            range: .day,
            locale: Locale(identifier: "de_DE"),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt
        )

        XCTAssertEqual(readout, "53.2 % · 01.01.70, 00:00")
    }

    func testHistoryCursorReadoutShowsOnlyDateForWeekRange() {
        let readout = PerchHAHistoryPopoverContent.cursorReadout(
            value: 53.2,
            unit: "%",
            timestamp: Date(timeIntervalSince1970: 0),
            range: .week,
            locale: Locale(identifier: "de_DE"),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt
        )

        XCTAssertEqual(readout, "53.2 % · 01.01.70")
    }

    func testHistoryStateTimelineReadoutIncludesTimeForDayRange() {
        let readout = PerchHAHistoryStateTimelinePopoverBody.readout(
            state: "bad",
            start: Date(timeIntervalSince1970: 1_200),
            duration: 7 * 60 * 60,
            range: .day,
            locale: Locale(identifier: "de_DE"),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt
        )

        XCTAssertEqual(readout, "Bad · 01.01.70, 00:20 · 7h")
    }

    func testHistoryStateTimelineReadoutShowsOnlyDateForWeekRange() {
        let readout = PerchHAHistoryStateTimelinePopoverBody.readout(
            state: "bad",
            start: Date(timeIntervalSince1970: 1_200),
            duration: 7 * 60 * 60,
            range: .week,
            locale: Locale(identifier: "de_DE"),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt
        )

        XCTAssertEqual(readout, "Bad · 01.01.70 · 7h")
    }

    func testSliderValueFormattingUsesCompactPercentLabel() {
        XCTAssertEqual(PerchHASliderValueFormatting.label(for: 42, unit: "%"), "42%")
        XCTAssertEqual(PerchHASliderValueFormatting.accessibilityValue(for: 42, unit: "%"), "42 percent")
    }

    func testSliderValueFormattingUsesNumericValueAndUnitWhenPresent() {
        XCTAssertEqual(PerchHASliderValueFormatting.label(for: 21.4, unit: "°C"), "21.4 °C")
        XCTAssertEqual(PerchHASliderValueFormatting.accessibilityValue(for: 21.4, unit: "°C"), "21.4 °C")
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
            .empty
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
        let _hoisted21 = await runner.callCount()
        XCTAssertEqual(_hoisted21, 1)
        let _mlHoisted1001 = await runner.actions()
        XCTAssertEqual(
            _mlHoisted1001,
            [ActionSpec(domain: "switch", service: "turn_on", targetEntityID: "switch.office_lamp")]
        )
        let _hoisted22 = await runner.tokens()
        XCTAssertEqual(_hoisted22, ["fake-token"])

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
        let _mlHoisted1002 = await runner.actions()
        XCTAssertEqual(
            _mlHoisted1002,
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
        let _hoisted23 = await connector.callCount()
        XCTAssertEqual(_hoisted23, 2)
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

        let _hoisted24 = await model.setEntityControl("sensor.office_temperature", isOn: true)
        XCTAssertFalse(_hoisted24)

        let _hoisted25 = await runner.callCount()
        XCTAssertEqual(_hoisted25, 0)
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

        let _hoisted26 = await model.setCoverControl("cover.office_blinds", command: .open)
        XCTAssertTrue(_hoisted26)
        XCTAssertEqual(model.entityState("cover.office_blinds"), "open")
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 100)

        let _hoisted27 = await model.setCoverControl("cover.office_blinds", command: .close)
        XCTAssertTrue(_hoisted27)
        XCTAssertEqual(model.entityState("cover.office_blinds"), "closed")
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 0)

        let _hoisted28 = await model.setCoverControl("cover.office_blinds", command: .stop)
        XCTAssertTrue(_hoisted28)
        XCTAssertEqual(model.entityState("cover.office_blinds"), "closed")
        XCTAssertEqual(model.entityPosition("cover.office_blinds"), 0)

        let _mlHoisted1003 = await runner.actions()
        XCTAssertEqual(
            _mlHoisted1003,
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
        let _mlHoisted1004 = await runner.actions()
        XCTAssertEqual(
            _mlHoisted1004,
            [
                ActionSpec(
                    domain: "cover",
                    service: "set_cover_position",
                    targetEntityID: "cover.office_blinds",
                    serviceData: ["position": 75]
                )
            ]
        )
        let _hoisted29 = await runner.tokens()
        XCTAssertEqual(_hoisted29, ["fake-token"])

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
        let _hoisted30 = await connector.callCount()
        XCTAssertEqual(_hoisted30, 2)
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

        let _hoisted31 = await model.setCoverPosition("cover.garage_door", position: 50)
        XCTAssertFalse(_hoisted31)

        let _hoisted32 = await runner.callCount()
        XCTAssertEqual(_hoisted32, 0)
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

        let _hoisted33 = await model.setEntityControl("input_boolean.guest_mode", isOn: true)
        XCTAssertTrue(_hoisted33)
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

        let _hoisted34 = await model.setCoverPosition("cover.office_blinds", position: 75)
        XCTAssertTrue(_hoisted34)
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

        let _hoisted35 = await model.setCoverControl("cover.office_blinds", command: .open)
        XCTAssertTrue(_hoisted35)
        let _hoisted36 = await model.setCoverControl("cover.office_blinds", command: .close)
        XCTAssertTrue(_hoisted36)
        let _hoisted37 = await model.setCoverControl("cover.office_blinds", command: .stop)
        XCTAssertTrue(_hoisted37)
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

        let _hoisted38 = await application.setEntityControl("switch.office_lamp", isOn: true)
        XCTAssertTrue(_hoisted38)

        XCTAssertEqual(application.snapshot.controlActionState, .idle)
        let _mlHoisted1005 = await runner.actions()
        XCTAssertEqual(
            _mlHoisted1005,
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

        let _hoisted39 = await application.setCoverPosition("cover.office_blinds", position: 75)
        XCTAssertTrue(_hoisted39)

        XCTAssertEqual(application.snapshot.controlActionState, .idle)
        let _mlHoisted1006 = await runner.actions()
        XCTAssertEqual(
            _mlHoisted1006,
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

        let _hoisted40 = await application.setCoverControl("cover.office_blinds", command: .open)
        XCTAssertTrue(_hoisted40)
        let _hoisted41 = await application.setCoverControl("cover.office_blinds", command: .close)
        XCTAssertTrue(_hoisted41)
        let _hoisted42 = await application.setCoverControl("cover.office_blinds", command: .stop)
        XCTAssertTrue(_hoisted42)

        XCTAssertEqual(application.snapshot.controlActionState, .idle)
        let _mlHoisted1007 = await runner.actions()
        XCTAssertEqual(
            _mlHoisted1007,
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
        let _hoisted43 = await model.runCustomAction(action.id)
        XCTAssertTrue(_hoisted43)

        XCTAssertEqual(model.entityState("sensor.office_temperature"), "21.4")
        let _hoisted44 = await runner.tokens()
        XCTAssertEqual(_hoisted44, ["fake-token"])
        let _hoisted45 = await runner.actions()
        XCTAssertEqual(_hoisted45, [action.action])
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
        let _hoisted46 = await model.runCustomAction(action.id)
        XCTAssertFalse(_hoisted46)
        let _hoisted47 = await runner.callCount()
        XCTAssertEqual(_hoisted47, 0)
        let _hoisted48 = await model.runCustomAction(action.id, confirmed: true)
        XCTAssertTrue(_hoisted48)

        let _hoisted49 = await runner.actions()
        XCTAssertEqual(_hoisted49, [action.action])
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
        let _hoisted50 = await model.runCustomAction(action.id)
        XCTAssertFalse(_hoisted50)

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

        let _hoisted51 = await model.runCustomAction(action.id)
        XCTAssertTrue(_hoisted51)
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

        let _hoisted52 = await model.runCustomAction(action.id, confirmed: true)
        XCTAssertFalse(_hoisted52)
        let _hoisted53 = await runner.actions()
        XCTAssertEqual(_hoisted53, [])
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
        let _hoisted54 = await application.runCustomAction(action.id)
        XCTAssertTrue(_hoisted54)
        let storedProtectedAction = try XCTUnwrap(application.snapshot.customActionConfiguration.action(id: action.id))
        guard case let .protectedString(reference) = storedProtectedAction.action.serviceData["pin"] else {
            return XCTFail("expected protected pin reference")
        }
        XCTAssertEqual(reference, configuredReference)
        XCTAssertEqual(try protectedStore.load(reference), "1234")
        let persistedConfiguration = try store.load()
        let persistedText = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(persistedText.contains("1234"))

        let _mlHoisted1008 = await runner.actions()
        XCTAssertEqual(
            _mlHoisted1008,
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
        XCTAssertEqual(store.saveCallCount, 2)
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

    /// A room not in the expanded set is collapsed by default, so the Entities
    /// tab opens as a compact list of room headers.
    func testSelectionRoomCollapsedByDefault() {
        XCTAssertFalse(
            SelectionRoomCollapse.isExpanded(
                roomID: "office",
                expandedRoomIDs: [],
                isSearching: false,
                roomContainsInspectedEntity: false
            )
        )
    }

    /// A room whose id is in the expanded set shows its rows.
    func testSelectionRoomExpandedShowsRows() {
        XCTAssertTrue(
            SelectionRoomCollapse.isExpanded(
                roomID: "office",
                expandedRoomIDs: ["office"],
                isSearching: false,
                roomContainsInspectedEntity: false
            )
        )
    }

    /// An active search forces a collapsed room expanded so matches stay visible,
    /// without touching the stored expanded state.
    func testSelectionSearchForcesCollapsedRoomVisible() {
        XCTAssertTrue(
            SelectionRoomCollapse.isExpanded(
                roomID: "office",
                expandedRoomIDs: [],
                isSearching: true,
                roomContainsInspectedEntity: false
            )
        )
    }

    /// The room holding the open inspector is forced expanded so the inspected
    /// entity stays reachable even if the room is otherwise collapsed.
    func testSelectionInspectedRoomForcedVisible() {
        XCTAssertTrue(
            SelectionRoomCollapse.isExpanded(
                roomID: "office",
                expandedRoomIDs: [],
                isSearching: false,
                roomContainsInspectedEntity: true
            )
        )
    }

    /// Collapse-all reports true only when every shown room is collapsed.
    func testSelectionAllCollapsedWhenEveryRoomCollapsed() {
        XCTAssertTrue(
            SelectionRoomCollapse.allCollapsed(
                roomIDs: ["kitchen", "office"],
                expandedRoomIDs: [],
                isSearching: false
            )
        )
    }

    /// Collapse-all reports false while any shown room is still expanded.
    func testSelectionAllCollapsedFalseWhenAnyRoomExpanded() {
        XCTAssertFalse(
            SelectionRoomCollapse.allCollapsed(
                roomIDs: ["kitchen", "office"],
                expandedRoomIDs: ["office"],
                isSearching: false
            )
        )
    }

    /// During a search no room counts as collapsed, since search forces rooms
    /// open; the affordance must then read as "Collapse all", not "Expand all".
    func testSelectionAllCollapsedFalseWhileSearching() {
        XCTAssertFalse(
            SelectionRoomCollapse.allCollapsed(
                roomIDs: ["kitchen", "office"],
                expandedRoomIDs: [],
                isSearching: true
            )
        )
    }

    /// With no rooms shown the affordance is inert, so collapse-all reports false.
    func testSelectionAllCollapsedFalseWhenNoRooms() {
        XCTAssertFalse(
            SelectionRoomCollapse.allCollapsed(
                roomIDs: [],
                expandedRoomIDs: [],
                isSearching: false
            )
        )
    }

    func test_t_requests_per_minute_counts_outbound_requests() async {
        let dates = MutableDateBox(Date(timeIntervalSince1970: 1_000_000))
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            wallClock: { dates.now }
        )
        XCTAssertEqual(model.requestsPerMinute(), 0)

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertGreaterThanOrEqual(
            model.requestsPerMinute(),
            1,
            "connecting sends at least one request that the traffic diagnostic must count"
        )
    }

    func test_t_requests_per_minute_prunes_requests_older_than_a_minute() async {
        let dates = MutableDateBox(Date(timeIntervalSince1970: 1_000_000))
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            wallClock: { dates.now }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        XCTAssertGreaterThanOrEqual(model.requestsPerMinute(), 1)

        dates.advance(by: 61)

        XCTAssertEqual(
            model.requestsPerMinute(),
            0,
            "requests older than the one-minute window must not count"
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
        let calls = CallCounter()
        let model = PerchHAPanelModel(
            connector: { _ in
                if await calls.next() == 1 {
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
            FormattedEntityValue(text: "Stale: 44%", status: .stale)
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
        let calls = CallCounter()
        let model = PerchHAPanelModel { _ in
            if await calls.next() == 1 {
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
            FormattedEntityValue(text: "Stale: 47%", status: .stale)
        )

        model.cancelInFlightAction()
        await refreshGate.open()
    }

    func test_t_refresh_failure_keeps_last_rows_visible_as_stale() async {
        let calls = CallCounter()
        let model = PerchHAPanelModel { _ in
            if await calls.next() == 1 {
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

    func test_t_live_update_stream_starts_on_connect_applies_events_and_reconnects_with_backoff() async {
        let clock = TestPerchClock()
        let script = LiveStreamSessionScript(sessions: [
            // Session 1 pushes one live value, then drops after events flowed.
            LiveStreamSessionScript.Session(
                events: [EntityState(id: "sensor.office_humidity", name: "Office humidity", state: "47", unit: "%")],
                failure: .unreachable(host: "homeassistant.local"),
                holdsOpen: false
            ),
            // Session 2 dies before producing anything — backoff must double.
            LiveStreamSessionScript.Session(
                events: [],
                failure: .unreachable(host: "homeassistant.local"),
                holdsOpen: false
            ),
            // Session 3 pushes another value and stays open.
            LiveStreamSessionScript.Session(
                events: [EntityState(id: "sensor.office_humidity", name: "Office humidity", state: "51", unit: "%")],
                failure: .unreachable(host: "homeassistant.local"),
                holdsOpen: true
            )
        ])
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            liveUpdateStreamer: { form, onEvent in
                await script.run(form: form, onEvent: onEvent)
            },
            clock: clock,
            bulkSyncConfiguration: .disabled,
            periodicRefreshConfiguration: .disabled,
            liveUpdateConfiguration: PerchHALiveUpdateConfiguration(reconnectDelay: .seconds(1), maximumBackoff: .seconds(8))
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        // The stream starts with the successful connect (no panel visibility
        // required) and its pushed value lands in the snapshot immediately.
        await spinUntil {
            model.snapshot.rooms.first?.entities.contains { $0.id == "sensor.office_humidity" && $0.state == "47" } == true
        }
        let formTokens = await script.formTokens()
        XCTAssertEqual(formTokens.first, "fake-token", "the stream authenticates with the connected form")

        // Session 1 dropped after delivering events: reconnect at the base delay.
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        _ = await clock.advance(by: .seconds(1))
        await spinUntil { await script.startedSessions() == 2 }

        // Session 2 failed before any event: the next delay doubles, so one
        // base interval is not enough to start session 3.
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        _ = await clock.advance(by: .seconds(1))
        for _ in 0..<20 {
            await Task.yield()
        }
        let afterBaseDelay = await script.startedSessions()
        XCTAssertEqual(afterBaseDelay, 2, "a stream that died without events reconnects with doubled backoff")

        _ = await clock.advance(by: .seconds(1))
        await spinUntil { await script.startedSessions() == 3 }
        await spinUntil {
            model.snapshot.rooms.first?.entities.contains { $0.id == "sensor.office_humidity" && $0.state == "51" } == true
        }
        XCTAssertTrue(
            model.diagnosticEvents.contains { $0.kind == .liveUpdatesInterrupted },
            "stream drops surface in diagnostics"
        )

        // Signing out ends the loop for good.
        model.signOut()
        await script.release()
        _ = await clock.advance(by: .seconds(30))
        for _ in 0..<20 {
            await Task.yield()
        }
        let afterSignOut = await script.startedSessions()
        XCTAssertEqual(afterSignOut, 3, "sign-out cancels the live update loop")
    }

    func test_t_live_update_after_refresh_failure_preserves_failed_stale_phase() async {
        let failure = ConnectionFailure.unreachable(host: "homeassistant.local")
        let calls = CallCounter()
        let model = PerchHAPanelModel { _ in
            if await calls.next() == 1 {
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
            FormattedEntityValue(text: "Stale: 47%", status: .stale)
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
        let calls = CallCounter()
        let model = PerchHAPanelModel { _ in
            let callCount = await calls.next()
            return .success(
                rooms: [
                    Room(
                        id: "office",
                        name: "Office",
                        entities: [
                            DiscoveredEntity(
                                id: "sensor.office_temperature",
                                name: "Office temperature",
                                state: "\(20 + callCount)",
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
        XCTAssertTrue(model.snapshot.lastUpdateDescription.hasPrefix("Updated at "), model.snapshot.lastUpdateDescription)
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
        // The panel is borderless so the SwiftUI root paints the rounded
        // dashboard surface itself: no titlebar, no window frame/background.
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertFalse(panel.styleMask.contains(.titled))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.hasShadow)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertTrue(panel.hidesOnDeactivate)
        XCTAssertNotNil(panel.contentViewController)
        XCTAssertEqual(Int(frameSize.width.rounded()), 384)
        XCTAssertGreaterThanOrEqual(Int(frameSize.height.rounded()), 468)
    }

    func testAppShellConnectionFormNormalizesFrontendURLsThroughNativeTextFields() throws {
        // The connection form lives only in the Settings window; the menu-bar
        // panel just points there.
        let recorder = ConnectionFormRecorder()
        let model = PerchHAPanelModel { form in
            await recorder.record(form)
            return .success(rooms: [])
        }
        let window = PerchHAApplication.makeSettingsWindow(model: model, initialTab: .connection)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        window.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        window.contentView?.layoutSubtreeIfNeeded()

        model.addConnectionAddress()
        drainPanelRunLoop()
        window.contentView?.layoutSubtreeIfNeeded()

        let textFields = editableTextFields(in: window.contentView)
        let debugSummary = nativeControlDebugSummary(in: window.contentView)
        guard let urlField = textFields.first(where: { $0.placeholderString == "Home Assistant URL" }) else {
            XCTFail(debugSummary)
            return
        }
        guard let fallbackField = textFields.first(where: { $0.placeholderString == "Alternative URL" }) else {
            XCTFail(debugSummary)
            return
        }

        try setNativeTextFieldValue("https://ha-primary.example/lovelace/0", for: urlField, in: window)
        try setNativeTextFieldValue("https://fallback.example/ha/history?entity=sensor.temp", for: fallbackField, in: window)

        XCTAssertEqual(model.snapshot.connectionForm.urlString, "https://ha-primary.example")
        XCTAssertEqual(model.snapshot.connectionForm.fallbackURLString, "https://fallback.example/ha")
    }

    func testAppShellConnectionFormUsesNativeSecurePasswordFieldForTokenEntry() {
        let model = PerchHAPanelModel()
        let window = PerchHAApplication.makeSettingsWindow(model: model, initialTab: .connection)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        window.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        window.contentView?.layoutSubtreeIfNeeded()

        let secureFields = secureTextFields(in: window.contentView)
        let debugSummary = nativeControlDebugSummary(in: window.contentView)
        guard let tokenField = secureFields.first(where: { $0.placeholderString == "Access token" }) else {
            XCTFail(debugSummary)
            return
        }

        if #available(macOS 11.0, *) {
            XCTAssertEqual(tokenField.contentType, .password)
        }
    }

    func testAppShellConnectionFormSupportsCommandVPasteInSettingsWindow() throws {
        let model = PerchHAPanelModel()
        let window = PerchHAApplication.makeSettingsWindow(model: model, initialTab: .connection)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        window.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        window.contentView?.layoutSubtreeIfNeeded()

        let textFields = editableTextFields(in: window.contentView)
        let debugSummary = nativeControlDebugSummary(in: window.contentView)
        guard let urlField = textFields.first(where: { $0.placeholderString == "Home Assistant URL" }) else {
            XCTFail(debugSummary)
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("https://ha-primary.example/lovelace/0", forType: .string))

        XCTAssertTrue(window.makeFirstResponder(urlField))
        drainPanelRunLoop()
        let firstResponder = window.firstResponder as AnyObject?
        let responder = urlField.currentEditor() ?? urlField
        XCTAssertTrue(firstResponder === responder || firstResponder === urlField)

        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "v",
                charactersIgnoringModifiers: "v",
                isARepeat: false,
                keyCode: 9
            )
        )

        // A titled window resolves Cmd+V through the application main menu —
        // the same Edit menu `PerchHAApplication.main()` installs. Menu-claimed
        // actions dispatch through the key window, which headless tests do not
        // reliably have, so the paste itself drives the field editor directly.
        let mainMenu = PerchHAApplication.standardMainMenu()
        XCTAssertTrue(mainMenu.performKeyEquivalent(with: event), "the standard Edit menu claims Cmd+V")
        let editor = try XCTUnwrap(urlField.currentEditor(), "the focused URL field has a field editor")
        editor.paste(urlField)
        drainPanelRunLoop()
        window.endEditing(for: nil)
        drainPanelRunLoop()

        XCTAssertEqual(model.snapshot.connectionForm.urlString, "https://ha-primary.example")
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

        XCTAssertEqual(switches.count, 3, debugSummary)
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

    func testSettingsEntitiesTabExposesNativeSearchPopupsAndKeyViewLoop() async throws {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        let window = PerchHAApplication.makeSettingsWindow(
            model: model,
            initialTab: .entities,
            initiallyExpandedEntityIDs: ["sensor.office_humidity"]
        )
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        window.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        window.contentView?.layoutSubtreeIfNeeded()
        window.recalculateKeyViewLoop()

        let textFields = editableTextFields(in: window.contentView)
        let popUpButtons = nativePopUpButtons(in: window.contentView)
        let buttons = nativeButtons(in: window.contentView)
        let debugSummary = nativeControlDebugSummary(in: window.contentView)
        let searchField = textFields.first { $0.placeholderString == "Search" }
        let minField = textFields.first { $0.placeholderString == "0" }
        let maxField = textFields.first { $0.placeholderString == "100" }
        let firstPopup = popUpButtons.first

        XCTAssertNotNil(searchField, debugSummary)
        XCTAssertNotNil(minField, debugSummary)
        XCTAssertNotNil(maxField, debugSummary)
        XCTAssertGreaterThanOrEqual(popUpButtons.count, 4, debugSummary)
        XCTAssertGreaterThanOrEqual(buttons.count, 4, debugSummary)

        if let searchField {
            XCTAssertTrue(window.makeFirstResponder(searchField), debugSummary)
            let labels = nativeKeyViewLoopLabels(startingAt: searchField)
            XCTAssertGreaterThanOrEqual(labels.count, 3, "\(labels)")
            XCTAssertTrue(labels.contains(where: { $0.contains("placeholder:Search") }), "\(labels)")
        }
        if let firstPopup {
            XCTAssertTrue(firstPopup.acceptsFirstResponder, debugSummary)
            XCTAssertTrue(window.makeFirstResponder(firstPopup), debugSummary)
        }
    }

    func testHistoryPopoverExposesNativeRangeControlAndFocus() {
        let hostingView = NSHostingView(
            rootView: PerchHAHistoryPopoverContent(
                entityID: "sensor.office_humidity",
                entityName: "Office humidity",
                valueText: "44%",
                unit: "%",
                state: .loaded(
                    HistorySeries(
                        entityID: "sensor.office_humidity",
                        range: .day,
                        samples: [
                            HistorySample(
                                timestamp: Date(timeIntervalSince1970: 1_788_998_400),
                                state: "44",
                                numericValue: 44
                            ),
                            HistorySample(
                                timestamp: Date(timeIntervalSince1970: 1_789_002_000),
                                state: "46",
                                numericValue: 46
                            )
                        ]
                    )
                ),
                onOpenSettings: {},
                selectedRange: .constant(.day)
            )
            .frame(width: 280)
            .environment(\.colorScheme, .light)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 320, height: 260)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }

        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        hostingView.layoutSubtreeIfNeeded()
        window.recalculateKeyViewLoop()

        let segmentedControls = nativeSegmentedControls(in: window.contentView)
        let debugSummary = nativeControlDebugSummary(in: window.contentView)
        guard let rangeControl = segmentedControls.first else {
            XCTFail(debugSummary)
            return
        }

        let labels = (0..<rangeControl.segmentCount).compactMap { rangeControl.label(forSegment: $0) }
        XCTAssertEqual(labels, ["Hour", "Day", "Week"])
        XCTAssertTrue(rangeControl.acceptsFirstResponder, debugSummary)
        XCTAssertTrue(window.makeFirstResponder(rangeControl), debugSummary)
    }

    func testAppShellCustomActionRowExposesNativeButtonFocus() async throws {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        XCTAssertTrue(model.setCustomAction(sensorCustomAction(requiresConfirmation: true)))

        let panel = PerchHAApplication.makePanel(model: model)
        defer {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }

        panel.makeKeyAndOrderFront(nil)
        drainPanelRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()

        let buttons = nativeButtons(in: panel.contentView)
        let debugSummary = nativeControlDebugSummary(in: panel.contentView)
        guard let actionButton = buttons.first(where: { String(describing: type(of: $0)).contains("SwiftUIAppKitButton") }) else {
            XCTFail(debugSummary)
            return
        }

        XCTAssertTrue(actionButton.acceptsFirstResponder, debugSummary)
        XCTAssertTrue(panel.makeFirstResponder(actionButton), debugSummary)
        let firstResponder = panel.firstResponder as AnyObject?
        XCTAssertTrue(firstResponder === actionButton || firstResponder === actionButton.currentEditor(), debugSummary)
    }

    func test_t_app_shell_launch_wires_status_item_panel_and_cleanup() {
        let application = PerchHAApplication()
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        let snapshot = application.snapshot
        XCTAssertEqual(snapshot.statusItemTitle, "")
        XCTAssertTrue(snapshot.statusItemHasImage)
        // The fallback may be the app icon (non-template) or the drawn fish (template).
        XCTAssertNotNil(snapshot.statusItemImageIsTemplate)
        XCTAssertTrue(snapshot.statusItemTargetIsApplication)
        XCTAssertTrue(snapshot.statusItemHasAction)
        XCTAssertTrue(snapshot.hasPanel)
        XCTAssertTrue(snapshot.hasPanelModel)
        XCTAssertTrue(snapshot.panelCanBecomeKey)
        XCTAssertTrue(snapshot.panelCanBecomeMain)
        XCTAssertTrue(snapshot.panelIsFloating)
        XCTAssertTrue(snapshot.panelHidesOnDeactivate)
        XCTAssertEqual(snapshot.panelContentWidth, 384)
        XCTAssertEqual(snapshot.panelContentHeight, 468)
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

        XCTAssertEqual(application.snapshot.statusItemTitle, "")
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "PearchHA")
        XCTAssertTrue(application.snapshot.statusItemHasImage)
        // The fallback may be the app icon (non-template) or the drawn fish (template).
        XCTAssertNotNil(application.snapshot.statusItemImageIsTemplate)

        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()

        XCTAssertEqual(application.snapshot.statusItemTitle, "44%")
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Office humidity, 44%")
        // Text items carry the per-entity menu-bar icon by default.
        XCTAssertTrue(application.snapshot.statusItemHasImage)

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
        XCTAssertEqual(application.snapshot.statusItemTitle, "47%")
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Office humidity, 47%")
        XCTAssertTrue(application.snapshot.statusItemHasImage)
    }

    func test_t_app_shell_menu_bar_appearance_mode_suppresses_text_or_image() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity"],
                menuBarEntityIDs: ["sensor.office_humidity"],
                isEntitySelectionExplicit: true,
                menuBarAppearance: .textOnly
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

        // Text-only keeps the value text and drops any image.
        XCTAssertEqual(application.snapshot.statusItemTitle, "44%")
        XCTAssertFalse(application.snapshot.statusItemHasImage)

        // Icon-only: the per-entity menu-bar icon supplies the image, so the
        // title is genuinely dropped and the item stays visible via the glyph.
        XCTAssertEqual(
            application.persist(displayPreferences: application.displayPreferences.with(menuBarAppearance: .iconOnly)),
            .saved
        )
        let iconOnlyItem = application.snapshot.menuBarItems[0]
        XCTAssertTrue(iconOnlyItem.hasImage, "icon-only items draw the per-entity menu-bar icon")
        XCTAssertEqual(application.snapshot.statusItemTitle, "")

        // Returning to icon-and-text restores the value title.
        XCTAssertEqual(
            application.persist(displayPreferences: application.displayPreferences.with(menuBarAppearance: .iconAndText)),
            .saved
        )
        XCTAssertEqual(application.snapshot.statusItemTitle, "44%")
    }

    func test_t_app_shell_persists_and_reloads_display_preferences() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: selectionRooms()) }
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        let preferences = PerchHADisplayPreferences(
            menuBarAppearance: .iconOnly,
            stableMenuBarWidth: true,
            themeMode: .dark,
            accentColor: PerchHAAccentColor(red: 0.1, green: 0.2, blue: 0.3),
            dashboardRowDensity: .compact,
            defaultHistoryRange: .week,
            showsFooterTimestamp: false,
            hiddenModuleIDs: ["room.office"]
        )
        XCTAssertEqual(application.persist(displayPreferences: preferences), .saved)
        XCTAssertEqual(application.displayPreferences, preferences)
        application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        let reloaded = try store.load()
        XCTAssertEqual(reloaded.menuBarAppearance, .iconOnly)
        XCTAssertTrue(reloaded.stableMenuBarWidth)
        XCTAssertEqual(reloaded.themeMode, .dark)
        XCTAssertEqual(reloaded.accentColor, PerchHAAccentColor(red: 0.1, green: 0.2, blue: 0.3))
        // The new dashboard display preferences also round-trip.
        XCTAssertEqual(reloaded.dashboardRowDensity, .compact)
        XCTAssertEqual(reloaded.dashboardDefaultHistoryRange, .week)
        XCTAssertFalse(reloaded.dashboardShowsFooterTimestamp)
        XCTAssertEqual(reloaded.dashboardHiddenModuleIDs, ["room.office"])
    }

    func testPanelModelApplyDisplayPreferencesUpdatesHonoredValue() {
        let model = PerchHAPanelModel()
        XCTAssertEqual(model.displayPreferences, .defaults)

        model.applyDisplayPreferences(.defaults.with(dashboardRowDensity: .compact))

        XCTAssertEqual(model.displayPreferences.dashboardRowDensity, .compact)
    }

    func test_t_entity_icon_visibility_and_custom_symbol_apply_and_persist() async {
        let model = PerchHAPanelModel(connector: { _ in .success(rooms: selectionRooms()) })
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        let id = EntityID("sensor.office_temperature")

        // Defaults: icon shown, automatic symbol.
        var configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
        XCTAssertTrue(configuration.showsEntityIcon)
        XCTAssertNil(configuration.customIconName)

        XCTAssertTrue(model.setShowsEntityIcon(id, showsEntityIcon: false))
        configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
        XCTAssertFalse(configuration.showsEntityIcon)

        XCTAssertTrue(model.setCustomEntityIcon(id, symbolName: "flame"))
        configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
        XCTAssertEqual(configuration.customIconName, "flame")

        // A blank name clears back to the automatic icon.
        XCTAssertTrue(model.setCustomEntityIcon(id, symbolName: "   "))
        configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
        XCTAssertNil(configuration.customIconName)
    }

    func test_t_alert_count_ignores_hidden_modules_and_counts_only_visible_problems() async {
        let rooms = [
            Room(id: "office", name: "Office", entities: [
                DiscoveredEntity(id: "sensor.ok", name: "OK", state: "21.4", unit: "°C", areaID: nil, deviceID: nil),
                DiscoveredEntity(id: "sensor.broken", name: "Broken", state: "unavailable", unit: nil, areaID: nil, deviceID: nil)
            ]),
            Room(id: "attic", name: "Attic", entities: [
                DiscoveredEntity(id: "sensor.dead_1", name: "Dead 1", state: "unavailable", unit: nil, areaID: nil, deviceID: nil),
                DiscoveredEntity(id: "sensor.dead_2", name: "Dead 2", state: "unknown", unit: nil, areaID: nil, deviceID: nil)
            ])
        ]
        let model = PerchHAPanelModel(connector: { _ in .success(rooms: rooms) })
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        // Every module visible: all three problem entities count.
        XCTAssertEqual(model.snapshot.dashboardSummary().warningCount, 3)

        // Hidden modules do not contribute — the summary describes only what
        // the dashboard actually shows.
        XCTAssertEqual(
            model.snapshot.dashboardSummary(hiddenModuleIDs: ["attic"]).warningCount,
            1,
            "the warning count must cover only entities in visible modules"
        )
    }

    func test_t_status_panel_escape_closes_and_command_comma_opens_settings() {
        var openedSettings = 0
        let panel = PerchHAStatusPanel()
        panel.onOpenSettings = {
            openedSettings += 1
        }
        panel.makeKeyAndOrderFront(nil)
        XCTAssertTrue(panel.isVisible)

        panel.cancelOperation(nil)
        XCTAssertFalse(panel.isVisible, "Escape (cancelOperation) closes the panel")

        let commaEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: 43
        )
        XCTAssertNotNil(commaEvent)
        if let commaEvent {
            XCTAssertTrue(panel.performKeyEquivalent(with: commaEvent), "Cmd+, is handled by the panel")
        }
        XCTAssertEqual(openedSettings, 1, "Cmd+, routes to the open-settings path")
    }

    func test_t_menu_bar_presenter_reads_promotions_from_live_snapshot() {
        let presenter = PerchHAMenuBarPresenter()
        let rooms = selectionRooms()
        let snapshot = PerchHAPanelSnapshot(
            connectionState: .connected,
            phase: .connectedData,
            rooms: rooms,
            availableRooms: rooms,
            menuBarDisplayConfiguration: MenuBarDisplayConfiguration(
                promotedEntityIDs: ["sensor.office_humidity", "sensor.office_temperature"]
            )
        )
        // The launch-time configuration promotes nothing; the presenter must use
        // the live snapshot so runtime promotions appear in the menu bar.
        let presentations = presenter.presentations(
            configuration: PerchHAConfiguration(),
            panelSnapshot: snapshot
        )
        XCTAssertEqual(presentations.count, 2)
        XCTAssertEqual(
            presentations.compactMap(\.entityID),
            ["sensor.office_humidity", "sensor.office_temperature"]
        )
    }

    func test_t_app_shell_promotes_multiple_menu_bar_items() async throws {
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

        let items = application.snapshot.menuBarItems
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "44%")
        XCTAssertEqual(items[0].accessibilityLabel, "Office humidity, 44%")
        XCTAssertEqual(items[1].title, "21 °C")
        XCTAssertEqual(items[1].accessibilityLabel, "Office temperature, 21 °C")
        for item in items {
            XCTAssertTrue(item.hasAction)
            XCTAssertTrue(item.targetIsApplication)
        }
        // The legacy single-item fields mirror the first promoted item.
        XCTAssertEqual(application.snapshot.statusItemTitle, "44%")
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Office humidity, 44%")
    }

    func test_t_app_shell_icon_only_suppresses_title_when_glyph_present() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity"],
                menuBarEntityIDs: ["sensor.office_humidity"],
                menuBarItemConfigurations: [
                    MenuBarItemConfiguration(entityID: "sensor.office_humidity", style: .battery)
                ],
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
        XCTAssertEqual(
            application.persist(displayPreferences: application.displayPreferences.with(menuBarAppearance: .iconOnly)),
            .saved
        )

        // A gauge-style item carries an image, so icon-only legitimately drops
        // the title while the item stays visible via its rendered gauge image.
        let item = application.snapshot.menuBarItems[0]
        XCTAssertTrue(item.hasImage)
        XCTAssertEqual(item.title, "")
    }

    func test_t_menu_bar_presenter_show_label_sets_stacked_label() {
        let presenter = PerchHAMenuBarPresenter()
        let rooms = selectionRooms()
        let snapshot = PerchHAPanelSnapshot(
            connectionState: .connected,
            phase: .connectedData,
            rooms: rooms,
            availableRooms: rooms,
            menuBarDisplayConfiguration: MenuBarDisplayConfiguration(
                promotedEntityIDs: ["sensor.office_humidity", "sensor.office_temperature"],
                itemConfigurations: [
                    MenuBarItemConfiguration(entityID: "sensor.office_humidity", showsLabel: true)
                ]
            )
        )
        let presentations = presenter.presentations(
            configuration: PerchHAConfiguration(),
            panelSnapshot: snapshot
        )
        XCTAssertEqual(presentations.count, 2)
        XCTAssertEqual(
            presentations[0].stackedLabel,
            "Office humidity",
            "Show label renders as the stacked (label-above-value) style"
        )
        XCTAssertNil(
            presentations[1].stackedLabel,
            "entities without Show label keep the flat single-line title"
        )
    }

    func test_t_app_shell_show_label_renders_stacked_two_line_title() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity"],
                menuBarEntityIDs: ["sensor.office_humidity"],
                menuBarItemConfigurations: [
                    MenuBarItemConfiguration(entityID: "sensor.office_humidity", showsLabel: true)
                ],
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

        // The stacked style renders the caps label on its own line above the
        // value, so the status-item title carries exactly one line break.
        XCTAssertEqual(application.snapshot.menuBarItems[0].title, "OFFICE HUMIDITY\n44%")
    }

    func test_t_app_shell_promoted_items_stay_visible_under_icon_only_appearance() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity", "switch.kitchen_light"],
                isEntitySelectionExplicit: true,
                menuBarAppearance: .iconOnly
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

        // Promote two text-style entities through the real toggle path. Neither
        // carries a gauge or icon glyph, so a global icon-only appearance would
        // zero out their image *and* their title, producing invisible items.
        XCTAssertTrue(application.setMenuBarEntity("sensor.office_humidity", isVisible: true))
        XCTAssertTrue(application.setMenuBarEntity("switch.kitchen_light", isVisible: true))
        XCTAssertEqual(
            application.persist(displayPreferences: application.displayPreferences.with(menuBarAppearance: .iconOnly)),
            .saved
        )

        let items = application.snapshot.menuBarItems
        XCTAssertEqual(items.count, 2)
        for item in items {
            let hasTitle = !(item.title ?? "").isEmpty
            XCTAssertTrue(
                item.hasImage || hasTitle,
                "promoted menu-bar item must remain visible (image or non-empty title), got title=\(item.title ?? "nil") hasImage=\(item.hasImage)"
            )
        }
    }

    func test_t_app_shell_per_entity_appearance_overrides_global() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity", "sensor.office_temperature"],
                menuBarEntityIDs: ["sensor.office_humidity", "sensor.office_temperature"],
                isEntitySelectionExplicit: true,
                menuBarAppearance: .iconOnly
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

        // Global icon-only would drop every text title. A per-entity text-only
        // choice must win, so humidity keeps its value text while temperature
        // follows the global icon-only default (and stays visible via fallback).
        XCTAssertTrue(application.setMenuBarAppearance("sensor.office_humidity", appearance: .textOnly))
        let items = application.snapshot.menuBarItems
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "44%")
        let hasContent = items[1].hasImage || !(items[1].title ?? "").isEmpty
        XCTAssertTrue(hasContent, "global icon-only item must remain visible")
    }

    func test_t_app_shell_menu_bar_item_count_tracks_promotion_changes() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity", "sensor.office_temperature"],
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
        XCTAssertEqual(application.snapshot.menuBarItems.count, 1)
        XCTAssertEqual(application.snapshot.menuBarItems[0].title, "44%")

        XCTAssertTrue(application.setMenuBarEntity("sensor.office_temperature", isVisible: true))
        XCTAssertEqual(application.snapshot.menuBarItems.count, 2)
        XCTAssertEqual(application.snapshot.menuBarItems[1].title, "21 °C")

        XCTAssertTrue(application.setMenuBarEntity("sensor.office_humidity", isVisible: false))
        XCTAssertEqual(application.snapshot.menuBarItems.count, 1)
        XCTAssertEqual(application.snapshot.menuBarItems[0].title, "21 °C")

        // Demoting the last entity collapses back to the single fallback item.
        XCTAssertTrue(application.setMenuBarEntity("sensor.office_temperature", isVisible: false))
        let fallback = application.snapshot.menuBarItems
        XCTAssertEqual(fallback.count, 1)
        XCTAssertEqual(fallback[0].title, "")
        XCTAssertTrue(fallback[0].hasImage)
        // The fallback may be the app icon (non-template) or the drawn fish (template).
        XCTAssertNotNil(fallback[0].imageIsTemplate)
        XCTAssertTrue(fallback[0].hasAction)
        XCTAssertTrue(fallback[0].targetIsApplication)
    }

    func test_t_app_shell_no_promotion_shows_single_fallback_item() {
        let application = PerchHAApplication()
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        let items = application.snapshot.menuBarItems
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "")
        XCTAssertTrue(items[0].hasImage)
        // The fallback may be the app icon (non-template) or the drawn fish (template).
        XCTAssertNotNil(items[0].imageIsTemplate)
        XCTAssertTrue(items[0].hasAction)
        XCTAssertTrue(items[0].targetIsApplication)
    }

    func test_t_app_shell_per_item_gauge_cache_isolates_redraws() async throws {
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

        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()
        XCTAssertEqual(gaugeRenderer.renderCount, 0)

        // Render two gauge items: one render each.
        XCTAssertTrue(application.setMenuBarDisplayStyle("sensor.office_humidity", style: .battery))
        XCTAssertEqual(gaugeRenderer.renderCount, 1)
        XCTAssertTrue(application.setMenuBarAbsoluteTotal("sensor.office_temperature", total: 50))
        XCTAssertTrue(application.setMenuBarDisplayStyle("sensor.office_temperature", style: .ring))
        XCTAssertEqual(gaugeRenderer.renderCount, 2)
        XCTAssertTrue(application.snapshot.menuBarItems[0].hasImage)
        XCTAssertTrue(application.snapshot.menuBarItems[1].hasImage)

        // A live update to the first entity must not redraw the second item.
        XCTAssertTrue(
            application.applyLiveState(
                EntityState(
                    id: "sensor.office_temperature",
                    name: "Office temperature",
                    state: "21.4",
                    unit: "°C"
                )
            )
        )
        XCTAssertEqual(gaugeRenderer.renderCount, 2)
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

        let _hoisted55 = await recorder.callCount()
        XCTAssertEqual(_hoisted55, 1)
        let _hoisted56 = await recorder.tokens()
        XCTAssertEqual(_hoisted56, ["fake-token"])
        let _hoisted57 = await recorder.ranges()
        XCTAssertEqual(_hoisted57, [.hour])
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
        let _hoisted58 = await client.discoveryTokens()
        XCTAssertEqual(_hoisted58, ["expired-access", "fresh-access"])
        let _mlHoisted1009 = await client.refreshRequests()
        XCTAssertEqual(
            _mlHoisted1009,
            [
                OAuthRefreshRequest(
                    baseURL: try XCTUnwrap(URL(string: "http://homeassistant.local:8123")),
                    refreshToken: "refresh-token",
                    clientID: "https://perchha.dev/app",
                    serverTrustPolicy: HAServerTrustPolicy()
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
        XCTAssertFalse(expectedPolicy.trustsAllHosts)
        let _hoisted59 = await client.discoveryTrustPolicies()
        XCTAssertEqual(_hoisted59, [expectedPolicy, expectedPolicy])
        let _mlHoisted1010 = await client.refreshRequests()
        XCTAssertEqual(
            _mlHoisted1010,
            [
                OAuthRefreshRequest(
                    baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local:8123")),
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
        // The default trusting posture scopes the allowance to the form's own
        // HTTPS hosts — never all hosts.
        let expectedPolicy = HAServerTrustPolicy(
            allowedSelfSignedCertificateHosts: ["primary.local", "fallback.example"]
        )

        application.updateConnectionForm(
            urlString: primaryURL.absoluteString,
            fallbackURLString: fallbackURL.absoluteString,
            usesStoredAuthSession: true
        )
        await application.connect()

        XCTAssertEqual(application.snapshot.connectionState, .connected)
        let _hoisted60 = await client.discoveryURLs()
        XCTAssertEqual(_hoisted60, [primaryURL, fallbackURL, fallbackURL])
        let _hoisted61 = await client.discoveryTokens()
        XCTAssertEqual(_hoisted61, ["expired-access", "expired-access", "fresh-access"])
        let _hoisted62 = await client.discoveryTrustPolicies()
        XCTAssertEqual(_hoisted62, [expectedPolicy, expectedPolicy, expectedPolicy])
        let _mlHoisted1011 = await client.refreshRequests()
        XCTAssertEqual(
            _mlHoisted1011,
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
        let _hoisted63 = await client.discoveryURLs()
        XCTAssertEqual(_hoisted63, [primaryURL, fallbackURL])
        let _hoisted64 = await client.discoveryTokens()
        XCTAssertEqual(_hoisted64, ["long-lived-token", "long-lived-token"])
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
        let _hoisted65 = await client.discoveryTokens()
        XCTAssertEqual(_hoisted65, ["expired-access"])
        let _hoisted66 = await client.refreshRequests().map(\.refreshToken)
        XCTAssertEqual(_hoisted66, ["refresh-token"])
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
        let _hoisted67 = await client.discoveryTokens()
        XCTAssertEqual(_hoisted67, ["expired-access", "fresh-access"])
        let _hoisted68 = await client.refreshRequests().count
        XCTAssertEqual(_hoisted68, 1)
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
                fallbackURLString: "https://fallback.example"
            )
        )

        XCTAssertEqual(result, .success)
        let _mlHoisted1012 = presenter.authorizationURLs().first
        XCTAssertEqual(
            _mlHoisted1012,
            try XCTUnwrap(URL(string: "https://homeassistant.local:8123/auth/authorize?client_id=https%3A%2F%2Fperchha.dev%2Fapp&redirect_uri=perchha%3A%2F%2Fauth&state=state-value"))
        )
        let recordedRequests = await transport.requests()
        let request = try XCTUnwrap(recordedRequests.first)
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
        let _hoisted69 = await transport.requests()
        XCTAssertEqual(_hoisted69, [])
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
        let _hoisted70 = await transport.requests()
        XCTAssertEqual(_hoisted70, [])
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
        let _hoisted71 = await transport.requests()
        XCTAssertEqual(_hoisted71, [])
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
        let _hoisted72 = await recorder.tokens()
        XCTAssertEqual(_hoisted72, [""])
        let _hoisted73 = await recorder.usesStoredAuthSessions()
        XCTAssertEqual(_hoisted73, [true])
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
        let _hoisted74 = await recorder.urlStrings()
        XCTAssertEqual(_hoisted74, ["http://homeassistant.local:8123"])
        let _hoisted75 = await recorder.usesStoredAuthSessions()
        XCTAssertEqual(_hoisted75, [true])
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

    func testPanelCheckForUpdatesPublishesAvailableRelease() async throws {
        let releaseURL = try XCTUnwrap(URL(string: "https://github.com/YunaBraska/pearch_ha/releases/tag/2026.7.71500"))
        let downloadURL = try XCTUnwrap(URL(string: "https://github.com/YunaBraska/pearch_ha/releases/download/2026.7.71500/PerchHA-2026.7.71500.dmg"))
        let model = PerchHAPanelModel(
            releaseUpdateChecker: { currentVersion in
                XCTAssertEqual(currentVersion, "1.0")
                return .updateAvailable(
                    PerchHAReleaseUpdate(
                        currentVersion: "1.0",
                        latestVersion: "2026.7.71500",
                        releaseURL: releaseURL,
                        downloadURL: downloadURL
                    )
                )
            },
            currentApplicationVersionProvider: { "1.0" }
        )

        await model.checkForUpdates()

        XCTAssertEqual(
            model.releaseUpdateState,
            .updateAvailable(
                PerchHAReleaseUpdate(
                    currentVersion: "1.0",
                    latestVersion: "2026.7.71500",
                    releaseURL: releaseURL,
                    downloadURL: downloadURL
                )
            )
        )
    }

    func testGitHubReleaseUpdateCheckerPrefersDMGAssetAndReportsAvailableRelease() async throws {
        let checker = PerchHAGitHubReleaseUpdateChecker { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2026-03-10")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "PerchHA/1.0")
            let payload = """
            {
              "tag_name": "2026.7.71500",
              "html_url": "https://github.com/YunaBraska/pearch_ha/releases/tag/2026.7.71500",
              "assets": [
                {
                  "name": "PerchHA-2026.7.71500.zip",
                  "browser_download_url": "https://github.com/YunaBraska/pearch_ha/releases/download/2026.7.71500/PerchHA-2026.7.71500.zip"
                },
                {
                  "name": "PerchHA-2026.7.71500.dmg",
                  "browser_download_url": "https://github.com/YunaBraska/pearch_ha/releases/download/2026.7.71500/PerchHA-2026.7.71500.dmg"
                }
              ]
            }
            """
            return (
                Data(payload.utf8),
                try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            )
        }

        let result = await checker.checkLatest(currentVersion: "1.0")

        XCTAssertEqual(
            result,
            .updateAvailable(
                PerchHAReleaseUpdate(
                    currentVersion: "1.0",
                    latestVersion: "2026.7.71500",
                    releaseURL: try XCTUnwrap(URL(string: "https://github.com/YunaBraska/pearch_ha/releases/tag/2026.7.71500")),
                    downloadURL: try XCTUnwrap(URL(string: "https://github.com/YunaBraska/pearch_ha/releases/download/2026.7.71500/PerchHA-2026.7.71500.dmg"))
                )
            )
        )
    }

    func testGitHubReleaseUpdateCheckerReturnsUpToDateWhenLatestReleaseIsInstalled() async throws {
        let checker = PerchHAGitHubReleaseUpdateChecker { request in
            let payload = """
            {
              "tag_name": "2026.7.71500",
              "html_url": "https://github.com/YunaBraska/pearch_ha/releases/tag/2026.7.71500",
              "assets": []
            }
            """
            return (
                Data(payload.utf8),
                try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            )
        }

        let result = await checker.checkLatest(currentVersion: "2026.7.71500")

        XCTAssertEqual(
            result,
            .upToDate(
                currentVersion: "2026.7.71500",
                latestVersion: "2026.7.71500",
                releaseURL: try XCTUnwrap(URL(string: "https://github.com/YunaBraska/pearch_ha/releases/tag/2026.7.71500"))
            )
        )
    }

    func testGitHubReleaseUpdateCheckerFallsBackToReleasePageWhenNoAssetMatches() async throws {
        let checker = PerchHAGitHubReleaseUpdateChecker { request in
            let payload = """
            {
              "tag_name": "2026.7.71500",
              "html_url": "https://github.com/YunaBraska/pearch_ha/releases/tag/2026.7.71500",
              "assets": [
                {
                  "name": "checksums.txt",
                  "browser_download_url": "https://github.com/YunaBraska/pearch_ha/releases/download/2026.7.71500/checksums.txt"
                }
              ]
            }
            """
            return (
                Data(payload.utf8),
                try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            )
        }

        let result = await checker.checkLatest(currentVersion: "1.0")

        XCTAssertEqual(
            result,
            .updateAvailable(
                PerchHAReleaseUpdate(
                    currentVersion: "1.0",
                    latestVersion: "2026.7.71500",
                    releaseURL: try XCTUnwrap(URL(string: "https://github.com/YunaBraska/pearch_ha/releases/tag/2026.7.71500")),
                    downloadURL: try XCTUnwrap(URL(string: "https://github.com/YunaBraska/pearch_ha/releases/tag/2026.7.71500"))
                )
            )
        )
    }

    func testGitHubReleaseUpdateCheckerPrefersPerchHAArtifactWhenOtherDMGsExist() async throws {
        let checker = PerchHAGitHubReleaseUpdateChecker { request in
            let payload = """
            {
              "tag_name": "2026.7.71500",
              "html_url": "https://github.com/YunaBraska/pearch_ha/releases/tag/2026.7.71500",
              "assets": [
                {
                  "name": "OtherTool.dmg",
                  "browser_download_url": "https://github.com/YunaBraska/pearch_ha/releases/download/2026.7.71500/OtherTool.dmg"
                },
                {
                  "name": "PerchHA-2026.7.71500.zip",
                  "browser_download_url": "https://github.com/YunaBraska/pearch_ha/releases/download/2026.7.71500/PerchHA-2026.7.71500.zip"
                }
              ]
            }
            """
            return (
                Data(payload.utf8),
                try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            )
        }

        let result = await checker.checkLatest(currentVersion: "1.0")

        XCTAssertEqual(
            result,
            .updateAvailable(
                PerchHAReleaseUpdate(
                    currentVersion: "1.0",
                    latestVersion: "2026.7.71500",
                    releaseURL: try XCTUnwrap(URL(string: "https://github.com/YunaBraska/pearch_ha/releases/tag/2026.7.71500")),
                    downloadURL: try XCTUnwrap(URL(string: "https://github.com/YunaBraska/pearch_ha/releases/download/2026.7.71500/PerchHA-2026.7.71500.zip"))
                )
            )
        )
    }

    func testGitHubReleaseUpdateCheckerAcceptsVersionPrefixAndReportsUpToDate() async throws {
        let checker = PerchHAGitHubReleaseUpdateChecker { request in
            let payload = """
            {
              "tag_name": "v2026.7.71500",
              "html_url": "https://github.com/YunaBraska/pearch_ha/releases/tag/v2026.7.71500",
              "assets": []
            }
            """
            return (
                Data(payload.utf8),
                try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            )
        }

        let result = await checker.checkLatest(currentVersion: "2026.7.71500")

        XCTAssertEqual(
            result,
            .upToDate(
                currentVersion: "2026.7.71500",
                latestVersion: "v2026.7.71500",
                releaseURL: try XCTUnwrap(URL(string: "https://github.com/YunaBraska/pearch_ha/releases/tag/v2026.7.71500"))
            )
        )
    }

    func testGitHubReleaseUpdateCheckerRejectsInvalidLatestReleaseTagExplicitly() async throws {
        let checker = PerchHAGitHubReleaseUpdateChecker { request in
            let payload = """
            {
              "tag_name": "stable",
              "html_url": "https://github.com/YunaBraska/pearch_ha/releases/tag/stable",
              "assets": []
            }
            """
            return (
                Data(payload.utf8),
                try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            )
        }

        let result = await checker.checkLatest(currentVersion: "1.0")

        XCTAssertEqual(result, .failed("GitHub latest release tag is invalid: stable"))
    }

    func testGitHubReleaseUpdateCheckerRejectsInvalidCurrentVersionExplicitly() async throws {
        let checker = PerchHAGitHubReleaseUpdateChecker { _ in
            XCTFail("network request should not run for an invalid current version")
            throw URLError(.badURL)
        }

        let result = await checker.checkLatest(currentVersion: "stable")

        XCTAssertEqual(result, .failed("current version is invalid: stable"))
    }

    func testGitHubReleaseUpdateCheckerReportsHTTPFailureExplicitly() async throws {
        let checker = PerchHAGitHubReleaseUpdateChecker { request in
            return (
                Data("{}".utf8),
                try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 503, httpVersion: nil, headerFields: nil))
            )
        }

        let result = await checker.checkLatest(currentVersion: "1.0")

        XCTAssertEqual(result, .failed("GitHub release check failed with HTTP 503"))
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

        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()
        XCTAssertEqual(gaugeRenderer.renderCount, 0)

        XCTAssertTrue(application.setMenuBarDisplayStyle("sensor.office_humidity", style: .battery))
        XCTAssertEqual(application.snapshot.statusItemTitle, "44%")
        XCTAssertEqual(application.snapshot.statusItemAccessibilityLabel, "Office humidity, 44%, 44 percent, battery")
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

        // Show label renders as the stacked style: caps label above the value.
        XCTAssertTrue(application.setMenuBarShowsLabel("sensor.office_humidity", showsLabel: true))
        XCTAssertEqual(application.snapshot.statusItemTitle, "OFFICE HUMIDITY\n44%")
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
        XCTAssertEqual(application.snapshot.statusItemTitle, "OFFICE HUMIDITY\n\(expectedDecimalValue)")

        XCTAssertTrue(application.setMenuBarDefaultHistoryRange("sensor.office_humidity", defaultHistoryRange: .week))
        XCTAssertEqual(gaugeRenderer.renderCount, 2)
        XCTAssertEqual(application.snapshot.statusItemTitle, "OFFICE HUMIDITY\n\(expectedDecimalValue)")
        XCTAssertEqual(
            application.snapshot.menuBarDisplayConfiguration
                .itemConfiguration(for: "sensor.office_humidity")
                .defaultHistoryRange,
            .week
        )

        let saved = try store.load()
        XCTAssertEqual(saved.menuBarEntityIDs, ["sensor.office_humidity"])
        XCTAssertEqual(saved.menuBarItemConfigurations.count, 1)
        XCTAssertEqual(saved.menuBarItemConfigurations.first?.style, .battery)
        XCTAssertEqual(saved.menuBarItemConfigurations.first?.showsLabel, true)
        XCTAssertEqual(saved.menuBarItemConfigurations.first?.showsUnit, false)
        XCTAssertEqual(saved.menuBarItemConfigurations.first?.maximumFractionDigits, 1)
        XCTAssertEqual(saved.menuBarItemConfigurations.first?.defaultHistoryRange, .week)
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
                thresholds: ValueThresholds(warning: ValueThreshold(value: 40, direction: .aboveOrEqual), critical: nil)
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
                thresholds: ValueThresholds(warning: nil, critical: ValueThreshold(value: 40, direction: .aboveOrEqual))
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
                thresholds: ValueThresholds(warning: nil, critical: ValueThreshold(value: 20, direction: .aboveOrEqual))
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
        // No total yet, so no gauge — the per-entity menu-bar icon fills in.
        XCTAssertTrue(application.snapshot.statusItemHasImage)

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
        XCTAssertTrue(savedConfiguration.thresholds.steps.isEmpty)
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
                            warning: ValueThreshold(value: 20, direction: .aboveOrEqual),
                            critical: nil
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
        XCTAssertEqual(
            savedConfiguration.thresholds.steps,
            [ThresholdStep(value: 20, color: ValueThresholds.warningColor)],
            "the legacy warning setter maps to an orange step"
        )
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

        XCTAssertEqual(application.snapshot.statusItemTitle, "44%")
        XCTAssertFalse(application.setMenuBarDisplayStyle("sensor.office_humidity", style: .battery))
        XCTAssertEqual(application.snapshot.statusItemTitle, "44%")
        XCTAssertEqual(application.snapshot.menuBarItemConfigurations, [])
        XCTAssertTrue(application.snapshot.displayPersistenceFailureDescription?.contains("disk full") == true)
        XCTAssertFalse(application.setMenuBarDefaultHistoryRange("sensor.office_humidity", defaultHistoryRange: .month))
        XCTAssertEqual(application.snapshot.statusItemTitle, "44%")
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

        XCTAssertEqual(application.snapshot.statusItemTitle, "44%")
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
        XCTAssertEqual(application.snapshot.statusItemTitle, "44%")
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

        XCTAssertEqual(application.snapshot.statusItemTitle, "44%")
        XCTAssertFalse(application.moveMenuBarEntity("sensor.office_humidity", direction: .down))
        XCTAssertEqual(application.snapshot.statusItemTitle, "44%")
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
            token: "long-lived-token"
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
        XCTAssertTrue(secondApplication.snapshot.hasTokenInput)
        XCTAssertTrue(
            secondApplication.snapshot.connectionForm.allowsSelfSignedCertificates,
            "the default trusting posture survives a relaunch"
        )
    }

    func test_t_keychain_save_failure_when_remembering_session_surfaces_in_settings() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let secretStore = ScriptableFailureSecretStore()
        secretStore.failsSave = true
        let application = PerchHAApplication(
            configStore: JSONConfigStore(fileURL: url),
            authSessionStore: PerchHAAuthSessionStore(secretStore: secretStore),
            client: RefreshingHAClientRecorder(
                discoveryResults: [.success(oauthDiscoverySnapshot())]
            )
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(urlString: "https://homeassistant.local:8123", token: "long-lived-token")
        await application.connect()

        // The connection works, but the remembered session was lost — the user
        // will have to re-enter the token next launch. That must be visible.
        XCTAssertEqual(application.snapshot.connectionState, .connected)
        let failure = try XCTUnwrap(application.snapshot.shellPersistenceFailureDescription)
        XCTAssertFalse(failure.contains("long-lived-token"), "the banner must never carry the token")
    }

    func testAppShellRemembersEnteredTokenAfterUnreachableFailureWhenNoStoredTokenExists() async throws {
        let url = temporaryConfigURL()
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            _ = try? sessionStore.clear()
        }

        let application = PerchHAApplication(
            configStore: JSONConfigStore(fileURL: url),
            authSessionStore: sessionStore,
            client: RefreshingHAClientRecorder(
                discoveryResults: [.failure(.unreachable(host: "homeassistant.local"))]
            )
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(
            urlString: "https://homeassistant.local:8123",
            token: "long-lived-token"
        )
        await application.connect()

        XCTAssertEqual(application.snapshot.connectionState, .failed(.unreachable(host: "homeassistant.local")))
        XCTAssertEqual(try sessionStore.loadAccessToken(), "long-lived-token")
    }

    func testAppShellDoesNotOverwriteStoredTokenWhenReplacementAttemptFails() async throws {
        let url = temporaryConfigURL()
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            _ = try? sessionStore.clear()
        }
        _ = try sessionStore.saveAccessToken("stored-token")

        let application = PerchHAApplication(
            configStore: JSONConfigStore(fileURL: url),
            authSessionStore: sessionStore,
            client: RefreshingHAClientRecorder(
                discoveryResults: [.failure(.unreachable(host: "homeassistant.local"))]
            )
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        application.updateConnectionForm(
            urlString: "https://homeassistant.local:8123",
            token: "replacement-token"
        )
        await application.connect()

        XCTAssertEqual(application.snapshot.connectionState, .failed(.unreachable(host: "homeassistant.local")))
        XCTAssertEqual(try sessionStore.loadAccessToken(), "stored-token")
    }

    func test_t_keychain_clear_failure_on_sign_out_surfaces_in_settings() async throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let secretStore = ScriptableFailureSecretStore()
        let application = PerchHAApplication(
            configStore: JSONConfigStore(fileURL: url),
            authSessionStore: PerchHAAuthSessionStore(secretStore: secretStore),
            client: RefreshingHAClientRecorder(
                discoveryResults: [.success(oauthDiscoverySnapshot())]
            )
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        application.updateConnectionForm(urlString: "https://homeassistant.local:8123", token: "long-lived-token")
        await application.connect()
        XCTAssertNil(application.snapshot.shellPersistenceFailureDescription)

        // The token is still in the Keychain even though the user signed out —
        // silently pretending otherwise would be a lie about their security.
        secretStore.failsDelete = true
        application.signOut()

        XCTAssertNotNil(application.snapshot.shellPersistenceFailureDescription)
    }

    func testAppShellRemembersSelfSignedCertificateOptInAcrossRelaunch() async throws {
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
        firstApplication.updateConnectionForm(
            urlString: "https://homeassistant.local:8123",
            token: "long-lived-token",
            allowsSelfSignedCertificates: true
        )
        await firstApplication.connect()
        firstApplication.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        let secondApplication = PerchHAApplication(
            configStore: JSONConfigStore(fileURL: url),
            authSessionStore: sessionStore,
            client: RefreshingHAClientRecorder()
        )
        secondApplication.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            secondApplication.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        XCTAssertTrue(secondApplication.snapshot.connectionForm.allowsSelfSignedCertificates)
    }

    func testAppShellAutoConnectsOnLaunchWhenStoredSessionAndProfileExist() async throws {
        let url = temporaryConfigURL()
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            _ = try? sessionStore.clear()
        }

        let seedApplication = PerchHAApplication(
            configStore: JSONConfigStore(fileURL: url),
            authSessionStore: sessionStore,
            client: RefreshingHAClientRecorder(
                discoveryResults: [.success(oauthDiscoverySnapshot())]
            )
        )
        seedApplication.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        seedApplication.updateConnectionForm(
            urlString: "https://homeassistant.local:8123",
            token: "long-lived-token"
        )
        await seedApplication.connect()
        seedApplication.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        let relaunched = PerchHAApplication(
            configStore: JSONConfigStore(fileURL: url),
            authSessionStore: sessionStore,
            client: RefreshingHAClientRecorder(
                discoveryResults: [.success(oauthDiscoverySnapshot())]
            )
        )
        relaunched.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            relaunched.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        let state = await relaunched.awaitAutoConnect()
        XCTAssertEqual(state, .connected)
        XCTAssertEqual(relaunched.snapshot.connectionState, .connected)
        XCTAssertEqual(relaunched.snapshot.connectionForm.token, "")
        XCTAssertTrue(relaunched.snapshot.hasTokenInput)
    }

    func testAppShellAutoConnectRetriesTransientLaunchFailureUntilStoredSessionSucceeds() async throws {
        let url = temporaryConfigURL()
        let keychain = KeychainSecretStore(service: "dev.perchha.ui.tests.\(UUID().uuidString)")
        let sessionStore = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            _ = try? sessionStore.clear()
        }

        let seedApplication = PerchHAApplication(
            configStore: JSONConfigStore(fileURL: url),
            authSessionStore: sessionStore,
            client: RefreshingHAClientRecorder(
                discoveryResults: [.success(oauthDiscoverySnapshot())]
            )
        )
        seedApplication.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        seedApplication.updateConnectionForm(
            urlString: "https://homeassistant.local:8123",
            token: "long-lived-token"
        )
        await seedApplication.connect()
        seedApplication.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        let retryingClient = RefreshingHAClientRecorder(
            discoveryResults: [
                .failure(.unreachable(host: "homeassistant.local")),
                .success(oauthDiscoverySnapshot())
            ]
        )
        let relaunched = PerchHAApplication(
            configStore: JSONConfigStore(fileURL: url),
            authSessionStore: sessionStore,
            client: retryingClient
        )
        relaunched.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            relaunched.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        let state = await relaunched.awaitAutoConnect()
        XCTAssertEqual(state, .connected)
        XCTAssertEqual(relaunched.snapshot.connectionState, .connected)
        let tokens = await retryingClient.discoveryTokens()
        XCTAssertEqual(tokens, ["long-lived-token", "long-lived-token"])
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

    // MARK: - History bulk sync loop

    @MainActor
    private func makeConnectedBulkSyncModel(
        recorder: BulkHistoryRecorder,
        clock: TestPerchClock,
        rooms: [Room],
        bulkSync: PerchHAHistoryBulkSyncConfiguration,
        cacheTTL: PerchDuration = .seconds(60),
        capacity: Int = 64
    ) async -> PerchHAPanelModel {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: rooms) },
            bulkHistoryProvider: { form, entityIDs, range in
                await recorder.provide(form: form, entityIDs: entityIDs, range: range)
            },
            clock: clock,
            historyCacheConfiguration: PerchHAHistoryCacheConfiguration(capacity: capacity, ttl: cacheTTL),
            bulkSyncConfiguration: bulkSync,
            // Isolate bulk sync from the active-panel periodic refresh safety net so
            // its clock sleeper-count assertions stay exact.
            periodicRefreshConfiguration: .disabled
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        return model
    }

    /// Lets the freshly armed bulk-sync loop reach its settle sleep, fires the
    /// settle delay, and waits for the first cycle's batches to land.
    private func runSettledBulkSyncCycle(
        clock: TestPerchClock,
        recorder: BulkHistoryRecorder,
        settleDelay: PerchDuration,
        expectedBatches: Int
    ) async {
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        _ = await clock.advance(by: settleDelay)
        await spinUntil { await recorder.batchCount() >= expectedBatches }
    }

    /// Advances the clock by one interval to drive the next re-armed cycle and
    /// waits for its batches.
    private func advanceBulkSyncCycle(
        clock: TestPerchClock,
        recorder: BulkHistoryRecorder,
        interval: PerchDuration,
        untilBatches: Int
    ) async {
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        _ = await clock.advance(by: interval)
        await spinUntil { await recorder.batchCount() >= untilBatches }
    }

    func test_t_bulk_sync_syncs_all_displayed_entities_in_one_request() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 10),
            // Cold divisor 1 so every entity syncs the first cycle regardless of
            // interest; batch cap above the count so a cycle is a single request.
            bulkSync: PerchHAHistoryBulkSyncConfiguration(settleDelay: settleDelay, batchSize: 40, coldRefreshDivisor: 1)
        )

        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0", "sensor.prefetch_1"])
        await runSettledBulkSyncCycle(clock: clock, recorder: recorder, settleDelay: settleDelay, expectedBatches: 1)

        // One bulk request covered the whole displayed list — not one per entity.
        let batchCount = await recorder.batchCount()
        XCTAssertEqual(batchCount, 1, "the displayed entities sync in a single bulk request, not one-by-one")
        let requested = await recorder.requestedIDs()
        XCTAssertEqual(requested, Set((0..<10).map { EntityID("sensor.prefetch_\($0)") }))
    }

    func test_t_cancelled_bulk_cycle_never_writes_previous_connections_history() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder(defaultValue: 111)
        let settleDelay = PerchDuration.milliseconds(250)
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 1),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(settleDelay: settleDelay, batchSize: 40, coldRefreshDivisor: 1)
        )
        await recorder.holdNextBatches(1)

        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0"])
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        _ = await clock.advance(by: settleDelay)
        await spinUntil { await recorder.heldBatchCount() == 1 }

        // Reconnect to a DIFFERENT instance while the old fetch is in flight.
        // The connection change evicts the cache and cancels the old cycle.
        model.updateConnectionForm(urlString: "http://127.0.0.1:9999", token: "other-token")
        await model.connect()
        XCTAssertNil(model.cachedHistorySeries(for: "sensor.prefetch_0"))

        // The old cycle only now completes its in-flight batch. Its results
        // belong to the previous connection (entity IDs overlap across HA
        // instances) and must not poison the freshly cleared cache.
        await recorder.releaseHeldBatches()
        for _ in 0..<50 {
            await Task.yield()
        }
        XCTAssertNil(
            model.cachedHistorySeries(for: "sensor.prefetch_0"),
            "a cancelled bulk cycle must not write the previous connection's history"
        )
        model.setPanelActive(false)
    }

    func test_t_scroll_pause_rearm_does_not_refetch_recently_synced_entities() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        let interval = PerchDuration.seconds(30)
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 3),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(interval: interval, settleDelay: settleDelay, coldRefreshDivisor: 1)
        )

        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0"])
        await runSettledBulkSyncCycle(clock: clock, recorder: recorder, settleDelay: settleDelay, expectedBatches: 1)
        let afterFirstCycle = await recorder.batchCount()
        XCTAssertEqual(afterFirstCycle, 1)
        // Wait for the cycle's results to land in the cache — re-arming while
        // the apply is still in flight would cancel it and drop the sync marks.
        await spinUntil { model.cachedHistorySeries(for: "sensor.prefetch_0") != nil }

        // A scroll pause re-arms the loop, but every displayed entity was synced
        // moments ago — the settled cycle must fetch nothing instead of
        // re-requesting the whole list on every 250 ms pause.
        model.updateVisibleEntities(["sensor.prefetch_1"])
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        _ = await clock.advance(by: settleDelay)
        for _ in 0..<50 {
            await Task.yield()
        }
        let afterRearm = await recorder.batchCount()
        XCTAssertEqual(afterRearm, 1, "a re-arm within the interval must not refetch just-synced entities")

        // After a full interval the same entities are due again.
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        _ = await clock.advance(by: interval)
        await spinUntil { await recorder.batchCount() >= 2 }
        model.setPanelActive(false)
    }

    func test_t_bulk_history_refreshes_expired_oauth_session_and_retries_once() async throws {
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
            refreshResults: [
                .success(
                    HAOAuthToken(
                        accessToken: "fresh-access",
                        refreshToken: nil,
                        expiresInSeconds: 1800,
                        tokenType: "Bearer"
                    )
                )
            ],
            historyBatchResults: [
                .failure(.authentication),
                .success(["sensor.a": historySeries(entityID: "sensor.a", range: .hour, value: 1.0)])
            ]
        )
        let gateway = PerchHAAuthorizedHomeAssistantGateway(client: client, authSessionStore: sessionStore)
        let form = PerchHAConnectionForm(urlString: "http://homeassistant.local:8123", usesStoredAuthSession: true)

        // OAuth access tokens expire after ~30 minutes. The background sync used
        // to bypass the refresh path entirely, silently returning nothing forever.
        let result = await gateway.bulkHistory(form: form, entityIDs: ["sensor.a"], range: .hour)

        XCTAssertEqual(result["sensor.a"], historySeries(entityID: "sensor.a", range: .hour, value: 1.0))
        let tokens = await client.historyBatchTokens()
        XCTAssertEqual(tokens, ["expired-access", "fresh-access"], "the expired token is refreshed and the batch retried once")
        XCTAssertEqual(try sessionStore.load().accessToken, "fresh-access")
    }

    func test_t_bulk_sync_pauses_while_connection_failed_and_resumes_on_recovery() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        let interval = PerchDuration.seconds(30)
        let outcomes = PeriodicConnectorOutcomes(
            results: [
                .success(rooms: prefetchRooms(count: 2)),
                .failure(.unreachable(host: "ha.local")),
                .success(rooms: prefetchRooms(count: 2))
            ],
            fallback: .success(rooms: prefetchRooms(count: 2))
        )
        let model = PerchHAPanelModel(
            connector: { _ in await outcomes.next() },
            bulkHistoryProvider: { form, entityIDs, range in
                await recorder.provide(form: form, entityIDs: entityIDs, range: range)
            },
            clock: clock,
            bulkSyncConfiguration: PerchHAHistoryBulkSyncConfiguration(interval: interval, settleDelay: settleDelay, coldRefreshDivisor: 1),
            periodicRefreshConfiguration: .disabled
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0"])
        await runSettledBulkSyncCycle(clock: clock, recorder: recorder, settleDelay: settleDelay, expectedBatches: 1)

        // The connection drops: while the state is failed, interval ticks must
        // not hammer the dead server with bulk batches across fallback URLs.
        await model.refresh()
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        _ = await clock.advance(by: interval)
        for _ in 0..<50 {
            await Task.yield()
        }
        let duringOutage = await recorder.batchCount()
        XCTAssertEqual(duringOutage, 1, "bulk sync must pause while the connection is failed")

        // Recovery: a successful refresh restores the connected state, and the
        // next interval tick resumes syncing.
        await model.refresh()
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        _ = await clock.advance(by: interval)
        await spinUntil { await recorder.batchCount() >= 2 }
        model.setPanelActive(false)
    }

    func test_t_bulk_sync_rearms_and_runs_multiple_cycles_over_time() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        let interval = PerchDuration.seconds(30)
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 3),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(interval: interval, settleDelay: settleDelay, coldRefreshDivisor: 1)
        )

        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0"])
        await runSettledBulkSyncCycle(clock: clock, recorder: recorder, settleDelay: settleDelay, expectedBatches: 1)
        let firstCycleBatches = await recorder.batchCount()
        XCTAssertEqual(firstCycleBatches, 1, "first cycle ran on open")

        // The loop must RE-ARM on its own: advancing the clock by the interval (no
        // new visibility change) triggers further cycles.
        await advanceBulkSyncCycle(clock: clock, recorder: recorder, interval: interval, untilBatches: 2)
        await advanceBulkSyncCycle(clock: clock, recorder: recorder, interval: interval, untilBatches: 3)
        let cycles = await recorder.cycleCount()
        XCTAssertGreaterThan(cycles, 1, "the sync re-arms and runs multiple cycles, not just once")
    }

    func test_t_bulk_sync_overrides_cached_series_in_place() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        let interval = PerchDuration.seconds(30)
        await recorder.setValue(10.0, for: "sensor.prefetch_0")
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 1),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(interval: interval, settleDelay: settleDelay, coldRefreshDivisor: 1)
        )

        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0"])
        await runSettledBulkSyncCycle(clock: clock, recorder: recorder, settleDelay: settleDelay, expectedBatches: 1)
        await spinUntil { model.cachedHistorySeries(for: "sensor.prefetch_0")?.samples.first?.numericValue == 10.0 }

        // A later cycle returns a NEW value; the cache entry is overridden in place.
        await recorder.setValue(20.0, for: "sensor.prefetch_0")
        await advanceBulkSyncCycle(clock: clock, recorder: recorder, interval: interval, untilBatches: 2)
        await spinUntil { model.cachedHistorySeries(for: "sensor.prefetch_0")?.samples.first?.numericValue == 20.0 }

        XCTAssertEqual(
            model.cachedHistorySeries(for: "sensor.prefetch_0")?.samples.first?.numericValue,
            20.0,
            "a cycle overrides the cached series in place with the refetched value"
        )
    }

    func test_t_bulk_sync_keeps_prior_series_for_entity_missing_from_result() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        let interval = PerchDuration.seconds(30)
        await recorder.setValue(5.0, for: "sensor.prefetch_0")
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 1),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(interval: interval, settleDelay: settleDelay, coldRefreshDivisor: 1)
        )

        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0"])
        await runSettledBulkSyncCycle(clock: clock, recorder: recorder, settleDelay: settleDelay, expectedBatches: 1)
        await spinUntil { model.cachedHistorySeries(for: "sensor.prefetch_0") != nil }

        // The next cycle returns NO series for _0 (partial response). The prior
        // cached series must survive — a cycle never deletes a valid entry.
        await recorder.omit("sensor.prefetch_0")
        await advanceBulkSyncCycle(clock: clock, recorder: recorder, interval: interval, untilBatches: 2)
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(
            model.cachedHistorySeries(for: "sensor.prefetch_0")?.samples.first?.numericValue,
            5.0,
            "an entity absent from a bulk result keeps its prior cached series (no deletion)"
        )
    }

    func test_t_bulk_sync_syncs_hot_every_cycle_and_cold_less_often() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        let interval = PerchDuration.seconds(30)
        // Cold entities sync only every 3rd cycle; hot (visible) ones every cycle.
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 4),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(interval: interval, settleDelay: settleDelay, coldRefreshDivisor: 3)
        )

        model.setPanelActive(true)
        // _0 is visible (hot); _1.._3 are cold. Cycle 0 includes cold (0 % 3 == 0).
        model.updateVisibleEntities(["sensor.prefetch_0"])
        await runSettledBulkSyncCycle(clock: clock, recorder: recorder, settleDelay: settleDelay, expectedBatches: 1)
        // Cycles 1 and 2 are hot-only.
        await advanceBulkSyncCycle(clock: clock, recorder: recorder, interval: interval, untilBatches: 2)
        await advanceBulkSyncCycle(clock: clock, recorder: recorder, interval: interval, untilBatches: 3)

        let hot = await recorder.requestCountForEntity("sensor.prefetch_0")
        let cold = await recorder.requestCountForEntity("sensor.prefetch_3")
        XCTAssertEqual(hot, 3, "the visible (hot) entity syncs every cycle")
        XCTAssertEqual(cold, 1, "a cold entity syncs only on the divisor-th cycle")
    }

    func test_t_bulk_sync_does_nothing_while_inactive() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 4),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(settleDelay: settleDelay, coldRefreshDivisor: 1)
        )

        // Inactive: reporting visibility must not fetch nor even arm a settle sleep.
        model.updateVisibleEntities(["sensor.prefetch_0", "sensor.prefetch_1"])
        for _ in 0..<10 {
            await Task.yield()
        }
        let inactiveSleepers = await clock.sleepingTaskCount()
        XCTAssertEqual(inactiveSleepers, 0)
        let inactiveBatches = await recorder.batchCount()
        XCTAssertEqual(inactiveBatches, 0)
        XCTAssertNil(model.cachedHistorySeries(for: "sensor.prefetch_0"))
    }

    func test_t_bulk_sync_splits_large_sets_into_capped_batches() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        // 10 displayed entities, batch cap 4 → batches of 4, 4, 2 in one cycle.
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 10),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(
                settleDelay: settleDelay,
                batchSize: 4,
                maxConcurrentBatches: 1,
                coldRefreshDivisor: 1
            )
        )

        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0"])
        await runSettledBulkSyncCycle(clock: clock, recorder: recorder, settleDelay: settleDelay, expectedBatches: 3)
        for _ in 0..<10 {
            await Task.yield()
        }

        let largest = await recorder.largestBatchSize()
        XCTAssertLessThanOrEqual(largest, 4, "no batch exceeds the configured cap")
        let requested = await recorder.requestedIDs()
        XCTAssertEqual(requested, Set((0..<10).map { EntityID("sensor.prefetch_\($0)") }))
    }

    func test_t_bulk_sync_does_not_evict_displayed_entities_beyond_base_capacity() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        // 40 displayed entities with the default cache capacity (256): one cycle's
        // bulk results must all stay cached — no eviction churn flickering previews.
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 40),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(settleDelay: settleDelay, coldRefreshDivisor: 1),
            capacity: 256
        )

        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0"])
        await runSettledBulkSyncCycle(clock: clock, recorder: recorder, settleDelay: settleDelay, expectedBatches: 1)
        await spinUntil { model.cachedHistorySeries(for: "sensor.prefetch_39") != nil }

        XCTAssertNotNil(
            model.cachedHistorySeries(for: "sensor.prefetch_0"),
            "the first displayed entity stays cached after the whole list is synced (no eviction churn)"
        )
        XCTAssertNotNil(
            model.cachedHistorySeries(for: "sensor.prefetch_5"),
            "a mid-list displayed entity stays cached after the whole list is synced"
        )
    }

    func test_t_inline_history_survives_ttl_expiry_for_display() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 2),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(interval: .seconds(120), settleDelay: settleDelay, coldRefreshDivisor: 1),
            cacheTTL: .seconds(60)
        )

        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0"])
        await runSettledBulkSyncCycle(clock: clock, recorder: recorder, settleDelay: settleDelay, expectedBatches: 1)
        await spinUntil { model.cachedHistorySeries(for: "sensor.prefetch_0") != nil }

        // Let _0's cache TTL lapse (advance past it). The already-synced inline
        // sparkline must keep showing its last-known data for display instead of
        // flickering out the moment the entry crosses its TTL.
        _ = await clock.advance(by: .seconds(90))
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertNotNil(
            model.cachedHistorySeries(for: "sensor.prefetch_0"),
            "expired-but-cached history stays visible for display (no flicker)"
        )
    }

    func test_t_gauge_meter_shows_for_available_and_stale_not_for_missing() {
        XCTAssertTrue(PerchHADashboardPreview.meterShows(for: .available))
        // Last-known fraction stays on screen through a background sync / WS gap.
        XCTAssertTrue(PerchHADashboardPreview.meterShows(for: .stale))
        XCTAssertFalse(PerchHADashboardPreview.meterShows(for: .unavailable))
        XCTAssertFalse(PerchHADashboardPreview.meterShows(for: .unknown))
    }

    func test_t_background_periodic_refresh_keeps_session_connected_and_not_stale() async {
        let entered = ConnectionGate()
        let release = ConnectionGate()
        let calls = CallCounter()
        let model = PerchHAPanelModel(
            connector: { _ in
                let n = await calls.next()
                // The initial connect is call 1; the immediate background periodic
                // tick is call 2 — hold it in flight so the test can observe the UI
                // state while a healthy session is syncing.
                if n >= 2 {
                    await entered.open()
                    await release.wait()
                }
                return .success(rooms: selectionRooms())
            },
            historyProvider: { _, _, _ in .unavailable("no history") },
            clock: TestPerchClock()
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        switch model.snapshot.phase {
        case .connectedData, .connectedEmpty:
            break
        default:
            XCTFail("expected a connected session after connect")
        }

        model.setPanelActive(true)
        // Wait until the background sync is genuinely in flight (connector blocked).
        await entered.wait()

        XCTAssertFalse(
            model.snapshot.valuesAreStale,
            "a silent background sync must not mark values stale (which would flicker previews)"
        )
        if case .reconnecting = model.snapshot.phase {
            XCTFail("background sync flipped the UI into a visible reconnecting state")
        }

        await release.open()
        model.setPanelActive(false)
    }

    func test_t_same_connection_ignores_address_row_identity() {
        let a = PerchHAConnectionForm(
            urlString: "http://home:8123",
            addresses: [PerchHAConnectionAddressField(label: "VPN", urlString: "http://vpn:8123")],
            token: "tok"
        )
        let b = PerchHAConnectionForm(
            urlString: "http://home:8123",
            addresses: [PerchHAConnectionAddressField(label: "VPN", urlString: "http://vpn:8123")],
            token: "tok"
        )
        // Plain equality differs on the per-row UUIDs — the hazard that wiped the
        // cache; the connection identity must treat these as the same session.
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.sameConnection(as: b))
        XCTAssertFalse(a.sameConnection(as: nil))
        XCTAssertFalse(a.sameConnection(as: PerchHAConnectionForm(urlString: "http://other:8123", token: "tok")))
        XCTAssertFalse(a.sameConnection(as: PerchHAConnectionForm(
            urlString: "http://home:8123",
            addresses: [PerchHAConnectionAddressField(urlString: "http://vpn:8123")],
            token: "different"
        )))
    }

    func test_t_same_connection_differs_when_self_signed_opt_in_changes() {
        let trusting = PerchHAConnectionForm(urlString: "https://home:8123", token: "tok")
        var strict = trusting
        strict.allowsSelfSignedCertificates = false
        // Changing the certificate trust posture is a real connection change: the
        // session must be rebuilt with the new policy, not silently reused.
        XCTAssertFalse(strict.sameConnection(as: trusting))
        XCTAssertTrue(strict.sameConnection(as: strict))
    }

    func test_t_self_signed_hosts_are_scoped_to_https_addresses_only() {
        let form = PerchHAConnectionForm(
            urlString: "https://HOME.local:8123",
            addresses: [
                PerchHAConnectionAddressField(label: "VPN", urlString: "https://vpn.example/ha"),
                PerchHAConnectionAddressField(label: "LAN", urlString: "http://plain.local:8123"),
                PerchHAConnectionAddressField(label: "Broken", urlString: "not a url")
            ],
            token: "tok",
            allowsSelfSignedCertificates: true
        )
        XCTAssertEqual(form.selfSignedCertificateHosts(), ["home.local", "vpn.example"])

        let httpOnly = PerchHAConnectionForm(urlString: "http://plain.local:8123", token: "tok")
        XCTAssertEqual(httpOnly.selfSignedCertificateHosts(), [])
    }

    func test_t_reapplying_equivalent_form_keeps_history_cache() async {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) },
            historyProvider: { _, id, range in
                .success(HistorySeries(
                    entityID: id,
                    range: range,
                    samples: [HistorySample(
                        timestamp: Date(timeIntervalSince1970: 1_789_999_200),
                        state: "21.4",
                        numericValue: 21.4
                    )]
                ))
            },
            historyDebounce: .milliseconds(0)
        )
        model.updateConnectionForm(
            urlString: "http://127.0.0.1:8123",
            addresses: [PerchHAConnectionAddressField(urlString: "http://10.0.0.2:8123")],
            token: "fake-token"
        )
        await model.connect()
        await model.loadHistory("sensor.office_temperature")
        XCTAssertNotNil(
            model.cachedHistorySeries(for: "sensor.office_temperature"),
            "history is cached after the first load"
        )

        // Re-apply an EQUIVALENT form: same URLs + token, but the address row is
        // rebuilt with a fresh UUID (mirrors restoring the form from the profile).
        model.updateConnectionForm(
            urlString: "http://127.0.0.1:8123",
            addresses: [PerchHAConnectionAddressField(urlString: "http://10.0.0.2:8123")],
            token: "fake-token"
        )
        await model.connect()

        XCTAssertNotNil(
            model.cachedHistorySeries(for: "sensor.office_temperature"),
            "re-applying the same connection must not evict cached history (no off-forever blanking)"
        )
    }

    func test_t_bulk_sync_cancels_in_flight_on_deactivate() async {
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 4),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(settleDelay: settleDelay, coldRefreshDivisor: 1)
        )

        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0"])
        // Arm the settle sleep, then deactivate before it fires: no cycle should run.
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        model.setPanelActive(false)
        _ = await clock.advance(by: settleDelay)
        for _ in 0..<10 {
            await Task.yield()
        }

        let batches = await recorder.batchCount()
        XCTAssertEqual(batches, 0, "deactivating before the settle fires cancels the armed sync")
        XCTAssertNil(model.cachedHistorySeries(for: "sensor.prefetch_0"))
    }

    func test_t_cache_insert_publishes_observable_revision() async {
        // A bulk-sync insert must bump the published history revision and surface in
        // cachedHistorySeries without any unrelated snapshot change, so inline rows
        // can re-render the moment their data lands.
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 2),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(settleDelay: settleDelay, coldRefreshDivisor: 1)
        )

        let revisionBefore = model.historyRevision
        var objectWillChangeFired = false
        let cancellable = model.objectWillChange.sink { objectWillChangeFired = true }
        defer { cancellable.cancel() }

        XCTAssertNil(model.cachedHistorySeries(for: "sensor.prefetch_0"))
        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0"])
        await runSettledBulkSyncCycle(clock: clock, recorder: recorder, settleDelay: settleDelay, expectedBatches: 1)
        await spinUntil { model.cachedHistorySeries(for: "sensor.prefetch_0") != nil }

        XCTAssertGreaterThan(model.historyRevision, revisionBefore)
        XCTAssertTrue(objectWillChangeFired)
        XCTAssertNotNil(model.cachedHistorySeries(for: "sensor.prefetch_0"))
    }

    func test_t_inline_history_available_without_hover() async {
        // Driving only panel-active + visible entities (no startHistoryHover call)
        // populates the inline cache purely from the background bulk sync path.
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let settleDelay = PerchDuration.milliseconds(250)
        let model = await makeConnectedBulkSyncModel(
            recorder: recorder,
            clock: clock,
            rooms: prefetchRooms(count: 3),
            bulkSync: PerchHAHistoryBulkSyncConfiguration(settleDelay: settleDelay, coldRefreshDivisor: 1)
        )

        // No hover popover is open and none is requested.
        XCTAssertNil(model.snapshot.historyPresentationEntityID)
        model.setPanelActive(true)
        model.updateVisibleEntities(["sensor.prefetch_0"])
        await runSettledBulkSyncCycle(clock: clock, recorder: recorder, settleDelay: settleDelay, expectedBatches: 1)
        await spinUntil { model.cachedHistorySeries(for: "sensor.prefetch_1") != nil }

        XCTAssertNotNil(model.cachedHistorySeries(for: "sensor.prefetch_0"))
        XCTAssertNotNil(model.cachedHistorySeries(for: "sensor.prefetch_1"))
        // Still no popover: hover was never involved.
        XCTAssertNil(model.snapshot.historyPresentationEntityID)
    }

    func test_t_inactive_panel_keeps_menu_bar_entities_fresh_without_sync() async {
        // When the panel is closed, no history sync runs, yet a promoted menu-bar
        // entity stays current via the panel-state-independent live push.
        let clock = TestPerchClock()
        let recorder = BulkHistoryRecorder()
        let promoted = EntityID("sensor.prefetch_0")
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: prefetchRooms(count: 4)) },
            bulkHistoryProvider: { form, entityIDs, range in
                await recorder.provide(form: form, entityIDs: entityIDs, range: range)
            },
            clock: clock,
            bulkSyncConfiguration: PerchHAHistoryBulkSyncConfiguration(settleDelay: .milliseconds(250)),
            periodicRefreshConfiguration: .disabled,
            menuBarDisplayConfiguration: MenuBarDisplayConfiguration(promotedEntityIDs: [promoted])
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        // Panel stays closed: report visibility, which must not arm any sync.
        model.updateVisibleEntities([promoted])
        for _ in 0..<10 {
            await Task.yield()
        }
        let closedSleepers = await clock.sleepingTaskCount()
        let closedBatches = await recorder.batchCount()
        XCTAssertEqual(closedSleepers, 0)
        XCTAssertEqual(closedBatches, 0)
        XCTAssertNil(model.cachedHistorySeries(for: promoted))

        // Live push updates the promoted entity while the panel is closed.
        let didUpdate = model.applyLiveState(
            EntityState(id: promoted, name: "Prefetch 0", state: "42.0", unit: "°C")
        )
        XCTAssertTrue(didUpdate)
        let entity = model.snapshot.rooms.flatMap(\.entities).first { $0.id == promoted }
        XCTAssertEqual(entity?.state, "42.0")
        // No history sync was triggered by the closed panel.
        let afterLiveBatches = await recorder.batchCount()
        XCTAssertEqual(afterLiveBatches, 0)
    }

    func test_t_history_range_picker_offers_at_most_one_week() {
        // The dashboard and detail panel cap the offered history at one week.
        XCTAssertEqual(HistoryRange.uiSelectable, [.hour, .day, .week])
        XCTAssertFalse(HistoryRange.uiSelectable.contains(.month))
    }

    func test_t_inline_sparkline_geometry_downsamples_to_budget() {
        // A dense series is downsampled to the inline mini-chart budget, preserving
        // first and last samples, so the tiny preview never plots hundreds of
        // points and the redraw cost stays bounded.
        let base = Date(timeIntervalSince1970: 1_789_000_000)
        let samples = (0..<400).map { index in
            HistorySample(
                timestamp: base.addingTimeInterval(Double(index) * 60),
                state: "\(index)",
                numericValue: Double(index)
            )
        }
        let series = HistorySeries(entityID: "sensor.dense", range: .day, samples: samples)
        let full = PerchHAHistorySparklineGeometry(series: series)
        let capped = PerchHAHistorySparklineGeometry(series: series, maxSamples: 48)
        XCTAssertEqual(full.points.count, 400)
        XCTAssertLessThanOrEqual(capped.points.count, 48)
        XCTAssertGreaterThan(capped.points.count, 1)
        XCTAssertEqual(capped.points.first?.x ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(capped.points.last?.x ?? -1, 1, accuracy: 0.0001)
    }

    func test_t_periodic_refresh_runs_while_active_and_pauses_when_inactive() async {
        let clock = TestPerchClock()
        let interval = PerchDuration.seconds(45)
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: prefetchRooms(count: 1)) },
            clock: clock,
            periodicRefreshConfiguration: PerchHAPeriodicRefreshConfiguration(interval: interval)
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        XCTAssertEqual(model.snapshot.refreshCount, 0)

        // Activating the panel refreshes immediately (safety net on open), then
        // settles into the interval loop on the injected clock. Activation also
        // arms the bulk history sync loop on the same clock, so wait for BOTH
        // sleepers before advancing — advancing after only one is armed can
        // wake just the bulk loop and leave the refresh loop sleeping forever.
        model.setPanelActive(true)
        await spinUntil { model.snapshot.refreshCount == 1 }
        await spinUntil { await clock.sleepingTaskCount() == 2 }
        XCTAssertEqual(model.snapshot.refreshCount, 1)

        // Firing the interval performs one more refresh and re-arms the loop.
        _ = await clock.advance(by: interval)
        await spinUntil { model.snapshot.refreshCount == 2 }
        await spinUntil { await clock.sleepingTaskCount() == 2 }

        // Deactivating pauses the loop: advancing the clock performs no refresh.
        model.setPanelActive(false)
        await spinUntil { await clock.sleepingTaskCount() == 0 }
        _ = await clock.advance(by: interval)
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertEqual(model.snapshot.refreshCount, 2)
    }

    func test_t_model_with_active_background_loops_deallocates_when_released() async {
        let clock = TestPerchClock()
        weak var weakModel: PerchHAPanelModel?
        do {
            let model = PerchHAPanelModel(
                connector: { _ in .success(rooms: prefetchRooms(count: 1)) },
                clock: clock,
                bulkSyncConfiguration: PerchHAHistoryBulkSyncConfiguration(),
                periodicRefreshConfiguration: PerchHAPeriodicRefreshConfiguration()
            )
            model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
            await model.connect()
            model.setPanelActive(true)
            // Let both loops arm and reach their clock sleeps.
            await spinUntil { await clock.sleepingTaskCount() >= 1 }
            weakModel = model
        }
        // The loops re-bind self weakly per iteration, so dropping the last
        // strong reference must deallocate the model (deinit cancels the
        // loops) instead of the loops pinning it alive forever.
        for _ in 0..<100 {
            await Task.yield()
        }
        XCTAssertNil(weakModel, "background loops must not keep the released model alive")
    }

    func test_t_periodic_refresh_arms_after_first_run_connect_while_panel_open() async {
        let clock = TestPerchClock()
        let interval = PerchDuration.seconds(45)
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: prefetchRooms(count: 1)) },
            clock: clock,
            bulkSyncConfiguration: .disabled,
            periodicRefreshConfiguration: PerchHAPeriodicRefreshConfiguration(interval: interval)
        )

        // First-run order: the panel opens before any session exists, so
        // activation alone cannot arm the refresh loop.
        model.setPanelActive(true)
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        // The connect itself delivered fresh data — no immediate re-refresh —
        // but the safety-net loop must now be armed on the clock.
        XCTAssertEqual(model.snapshot.refreshCount, 0)
        await spinUntil { await clock.sleepingTaskCount() == 1 }

        _ = await clock.advance(by: interval)
        await spinUntil { model.snapshot.refreshCount == 1 }

        model.setPanelActive(false)
    }

    func test_t_status_panel_reports_visibility_changes_on_every_dismissal_path() {
        let panel = PerchHAStatusPanel()
        var reported: [Bool] = []
        panel.onVisibilityChange = { reported.append($0) }

        panel.makeKeyAndOrderFront(nil)
        XCTAssertEqual(reported, [true])

        // Escape routes through cancelOperation -> orderOut.
        panel.cancelOperation(nil)
        XCTAssertEqual(reported, [true, false])

        // Repeated hides do not re-report; only genuine changes fire.
        panel.orderOut(nil)
        XCTAssertEqual(reported, [true, false])
    }

    func test_t_panel_dismissal_stops_background_work_without_status_item_toggle() async {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: prefetchRooms(count: 1)) }
        )
        let panel = PerchHAApplication.makePanel(model: model)
        defer {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }

        panel.makeKeyAndOrderFront(nil)
        XCTAssertTrue(model.isPanelActive, "showing the panel activates background sync")

        // Escape (or click-away auto-hide) must deactivate the model even though
        // the status-item toggle never ran — this leaked background loops before.
        panel.cancelOperation(nil)
        XCTAssertFalse(model.isPanelActive, "hiding the panel stops background sync")
    }

    func test_t_periodic_refresh_backs_off_after_failure() async {
        let clock = TestPerchClock()
        let interval = PerchDuration.seconds(45)
        let outcomes = PeriodicConnectorOutcomes(
            // First call (model.connect) succeeds; the immediate tick fails, so the
            // next sleep must be a backed-off interval (2x the base), not the base.
            results: [
                .success(rooms: prefetchRooms(count: 1)),
                .failure(.unreachable(host: "ha.local"))
            ],
            fallback: .success(rooms: prefetchRooms(count: 1))
        )
        let model = PerchHAPanelModel(
            connector: { _ in await outcomes.next() },
            clock: clock,
            periodicRefreshConfiguration: PerchHAPeriodicRefreshConfiguration(
                interval: interval,
                maximumBackoff: .seconds(300)
            )
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        model.setPanelActive(true)
        // The immediate tick fails; the loop arms a backed-off sleep.
        await spinUntil { if case .failed = model.snapshot.connectionState { return true } else { return false } }
        await spinUntil { await clock.sleepingTaskCount() == 1 }

        // The base interval is not yet enough to wake the backed-off sleep.
        _ = await clock.advance(by: interval)
        for _ in 0..<20 {
            await Task.yield()
        }
        await spinUntil { await clock.sleepingTaskCount() == 1 }
        let beforeBackoff = model.snapshot.connectionState
        if case .failed = beforeBackoff {} else {
            XCTFail("expected the backed-off sleep to still be pending after one base interval")
        }

        // Advancing the remainder of the doubled backoff wakes it and recovers.
        _ = await clock.advance(by: interval)
        await spinUntil {
            if case .connected = model.snapshot.connectionState { return true } else { return false }
        }
    }

    /// Spins until `condition` holds. Yields for the fast path, then falls
    /// back to short real sleeps so loaded CI runners still converge; total
    /// budget stays bounded (~2 s) so a genuinely stuck condition fails fast.
    private func spinUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
        for _ in 0..<2_000 where !condition() {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func spinUntil(_ condition: @escaping () async -> Bool) async {
        for _ in 0..<100 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        for _ in 0..<2_000 {
            if await condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
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

    private func setNativeTextFieldValue(_ value: String, for textField: NSTextField, in panel: NSWindow) throws {
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

    @MainActor
    private func nativeSegmentedControls(in root: NSView?) -> [NSSegmentedControl] {
        guard let root else {
            return []
        }
        var result: [NSSegmentedControl] = []
        func collect(_ view: NSView) {
            if let control = view as? NSSegmentedControl, !control.isHiddenOrHasHiddenAncestor {
                result.append(control)
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
        if let segmented = view as? NSSegmentedControl {
            let labels = (0..<segmented.segmentCount).compactMap { segmented.label(forSegment: $0) }.joined(separator: "|")
            return "\(type(of: view))(label:\(segmented.accessibilityLabel() ?? ""),segments:\(labels))"
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

    func test_t_cover_control_mode_defaults_to_both_and_persists_changes() async {
        let sink = MenuBarDisplaySinkRecorder()
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms()) },
            menuBarDisplaySink: { displayConfiguration in
                sink.record(displayConfiguration)
            }
        )

        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        let cover = model.snapshot.rooms.flatMap(\.entities).first { $0.id == "cover.office_blinds" }
        guard let cover else {
            return XCTFail("expected cover entity")
        }
        XCTAssertEqual(model.coverControlMode(for: cover), .both)
        XCTAssertEqual(model.snapshot.coverControlMode(for: cover), .both)

        XCTAssertTrue(model.setCoverControlMode("cover.office_blinds", mode: .slider))
        XCTAssertEqual(model.coverControlMode(for: cover), .slider)
        XCTAssertEqual(
            model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: "cover.office_blinds").coverControlMode,
            .slider
        )
        XCTAssertEqual(
            sink.lastDisplayConfiguration?.itemConfiguration(for: "cover.office_blinds").coverControlMode,
            .slider
        )
    }

    func test_t_panel_formatted_value_applies_display_unit_temperature() async {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.setDisplayUnit("sensor.office_temperature", displayUnit: .fahrenheit))

        let temperature = model.snapshot.rooms.flatMap(\.entities).first { $0.id == "sensor.office_temperature" }
        XCTAssertEqual(
            temperature.map { model.snapshot.formattedValue(for: $0, locale: Locale(identifier: "en_US")) },
            FormattedEntityValue(text: "70.52 °F", status: .available)
        )
    }

    func test_t_panel_formatted_value_applies_display_unit_percent() async {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: selectionRooms()) }
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        XCTAssertTrue(model.setDisplayUnit("sensor.office_humidity", displayUnit: .percent))

        let humidity = model.snapshot.rooms.flatMap(\.entities).first { $0.id == "sensor.office_humidity" }
        XCTAssertEqual(
            humidity.map { model.snapshot.formattedValue(for: $0, locale: Locale(identifier: "en_US")) },
            FormattedEntityValue(text: "44%", status: .available)
        )
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

    // MARK: Dashboard cockpit components

    func testDashboardPaletteResolvesDistinctDesignedLightAndDarkSurfaces() {
        let dark = PerchHATheme.Dashboard.palette(.dark)
        let light = PerchHATheme.Dashboard.palette(.light)
        XCTAssertEqual(dark, PerchHATheme.Dashboard.darkPalette)
        XCTAssertEqual(light, PerchHATheme.Dashboard.lightPalette)
        XCTAssertNotEqual(dark, light, "light and dark are designed, not identical")
        XCTAssertNotEqual(
            dark.surfaceRoot,
            dark.surfacePanel,
            "the dark root surface is deeper than the panel surface"
        )
        XCTAssertNotEqual(
            dark.surfacePanel,
            dark.surfacePanelElevated,
            "the elevated panel is distinct from the standard panel"
        )
    }

    func testDashboardPaletteCompatibilityAliasesTrackTheNewTokens() {
        let palette = PerchHATheme.Dashboard.darkPalette
        XCTAssertEqual(palette.popoverBackground, palette.surfaceRoot)
        XCTAssertEqual(palette.cardBackground, palette.surfacePanel)
        XCTAssertEqual(palette.cardBackgroundElevated, palette.surfacePanelElevated)
        XCTAssertEqual(palette.separator, palette.separatorSubtle)
        XCTAssertEqual(palette.chartTrack, palette.meterTrack)
    }

    func testDashboardPaletteSeverityColorMapsToSemanticTokens() {
        let palette = PerchHATheme.Dashboard.darkPalette
        XCTAssertEqual(palette.severityColor(.normal), palette.accentPrimary)
        XCTAssertEqual(palette.severityColor(.warning), palette.warning)
        XCTAssertEqual(palette.severityColor(.critical), palette.danger)
    }

    func testDashboardPaletteConnectionColorMapsConnectionStates() {
        let palette = PerchHATheme.Dashboard.darkPalette
        XCTAssertEqual(palette.connectionColor(.connected), palette.success)
        XCTAssertEqual(palette.connectionColor(.connecting), palette.warning)
        XCTAssertEqual(palette.connectionColor(.reconnecting(attempt: 1)), palette.warning)
        XCTAssertEqual(palette.connectionColor(.failed(.authentication)), palette.danger)
        XCTAssertEqual(palette.connectionColor(.disconnected), palette.textSecondary)
    }

    func testSummaryStripMetricEquatableDistinguishesValueAndCaption() {
        let base = SummaryStripMetric(caption: "Humidity", value: "44%")
        XCTAssertEqual(base, SummaryStripMetric(caption: "Humidity", value: "44%"))
        XCTAssertNotEqual(base, SummaryStripMetric(caption: "Humidity", value: "45%"))
        XCTAssertNotEqual(base, SummaryStripMetric(caption: "Temp", value: "44%"))
    }

    // MARK: - Dashboard summary selected metrics

    private func connectedDashboardSnapshot() -> PerchHAPanelSnapshot {
        let rooms = selectionRooms()
        return PerchHAPanelSnapshot(
            connectionState: .connected,
            phase: .connectedData,
            rooms: rooms,
            availableRooms: rooms
        )
    }

    func testDashboardSummaryEmptySelectionKeepsAutomaticBehavior() {
        let snapshot = connectedDashboardSnapshot()

        let auto = snapshot.dashboardSummary()
        let explicitEmpty = snapshot.dashboardSummary(selectedMetricIDs: [])

        XCTAssertTrue(auto.selectedMetrics.isEmpty)
        XCTAssertTrue(explicitEmpty.selectedMetrics.isEmpty)
        // The automatic primary metric is still derived (the first numeric value).
        XCTAssertNotNil(auto.primaryMetric)
        XCTAssertEqual(auto.primaryMetric?.entityID, "sensor.office_temperature")
    }

    func testDashboardSummaryUsesSelectedEntitiesInOrder() {
        let snapshot = connectedDashboardSnapshot()

        let summary = snapshot.dashboardSummary(
            selectedMetricIDs: ["sensor.office_humidity", "sensor.office_temperature"]
        )

        XCTAssertEqual(summary.selectedMetrics.map(\.entityID), ["sensor.office_humidity", "sensor.office_temperature"])
        XCTAssertEqual(summary.selectedMetrics.first?.name, "Office humidity")
        XCTAssertTrue(summary.selectedMetrics.allSatisfy(\.isAvailable))
        XCTAssertTrue(summary.selectedMetrics[0].valueText.contains("44"))
    }

    func testDashboardSummaryCapsSelectionAtThree() {
        let snapshot = connectedDashboardSnapshot()

        let summary = snapshot.dashboardSummary(
            selectedMetricIDs: [
                "sensor.office_temperature",
                "sensor.office_humidity",
                "switch.kitchen_light",
                "sensor.does_not_exist"
            ]
        )

        XCTAssertEqual(summary.selectedMetrics.count, 3)
        XCTAssertEqual(
            summary.selectedMetrics.map(\.entityID),
            ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"]
        )
    }

    func testDashboardSummaryShowsMutedPlaceholderForMissingSelectedEntity() {
        let snapshot = connectedDashboardSnapshot()

        let summary = snapshot.dashboardSummary(
            selectedMetricIDs: ["sensor.office_temperature", "sensor.vanished"]
        )

        XCTAssertEqual(summary.selectedMetrics.count, 2)
        let missing = summary.selectedMetrics[1]
        XCTAssertEqual(missing.entityID, "sensor.vanished")
        XCTAssertFalse(missing.isAvailable)
        XCTAssertEqual(missing.valueText, "—")
        // The available metric is untouched.
        XCTAssertTrue(summary.selectedMetrics[0].isAvailable)
    }

    func testPanelModelApplyDisplayPreferencesExposesSummaryMetricSelection() {
        let model = PerchHAPanelModel()
        XCTAssertTrue(model.displayPreferences.summaryMetricEntityIDs.isEmpty)

        model.applyDisplayPreferences(
            .defaults.with(summaryMetricEntityIDs: ["sensor.office_humidity"])
        )

        XCTAssertEqual(model.displayPreferences.summaryMetricEntityIDs, ["sensor.office_humidity"])
    }

    // MARK: - Diagnostics event ring buffer

    func test_t_diagnostics_records_connection_failure_event() async {
        let model = PerchHAPanelModel(
            connector: { _ in .failure(.unreachable(host: "ha.local")) },
            clock: TestPerchClock()
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")

        await model.connect()

        XCTAssertEqual(model.diagnosticEvents.count, 1)
        let event = model.diagnosticEvents.first
        XCTAssertEqual(event?.kind, .connectionFailed)
        XCTAssertEqual(event?.count, 1)
        XCTAssertTrue(event?.message.contains("ha.local") ?? false)
    }

    func test_t_diagnostics_dedupes_repeated_identical_failure_and_bumps_count() async {
        let clock = TestPerchClock()
        let model = PerchHAPanelModel(
            connector: { _ in .failure(.unreachable(host: "ha.local")) },
            clock: clock
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")

        await model.connect()
        let firstSeen = model.diagnosticEvents.first?.firstSeen
        _ = await clock.advance(by: .seconds(30))
        await model.connect()

        XCTAssertEqual(model.diagnosticEvents.count, 1, "identical consecutive failures must dedupe")
        let event = model.diagnosticEvents.first
        XCTAssertEqual(event?.count, 2)
        XCTAssertEqual(event?.firstSeen, firstSeen, "firstSeen is preserved on dedup")
        XCTAssertNotEqual(event?.lastSeen, firstSeen, "lastSeen advances on dedup")
    }

    func test_t_diagnostics_records_recovered_event_when_connection_returns() async {
        let outcomes = PeriodicConnectorOutcomes(
            results: [
                .failure(.unreachable(host: "ha.local")),
                .success(rooms: prefetchRooms(count: 1))
            ],
            fallback: .success(rooms: prefetchRooms(count: 1))
        )
        let model = PerchHAPanelModel(
            connector: { _ in await outcomes.next() },
            clock: TestPerchClock()
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")

        await model.connect()
        XCTAssertEqual(model.diagnosticEvents.first?.kind, .connectionFailed)

        await model.connect()

        XCTAssertEqual(model.diagnosticEvents.first?.kind, .recovered)
        if case .connected = model.snapshot.connectionState {} else {
            XCTFail("expected connected after recovery")
        }
    }

    func test_t_diagnostics_does_not_record_recovery_for_routine_healthy_connect() async {
        let model = PerchHAPanelModel(
            connector: { _ in .success(rooms: prefetchRooms(count: 1)) },
            clock: TestPerchClock()
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")

        await model.connect()

        XCTAssertTrue(model.diagnosticEvents.isEmpty, "a clean first connect records nothing")
    }

    func test_t_diagnostics_ring_buffer_evicts_oldest_beyond_capacity() async {
        let clock = TestPerchClock()
        let host = HostSequence(start: 0)
        let model = PerchHAPanelModel(
            connector: { _ in .failure(.unreachable(host: await host.next())) },
            clock: clock
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")

        // Record more distinct failures than the 50-event cap.
        for _ in 0..<55 {
            _ = await clock.advance(by: .seconds(1))
            await model.connect()
        }

        XCTAssertEqual(model.diagnosticEvents.count, PerchHADiagnosticLog.defaultCapacity)
        // The very first host must have been evicted; the newest must be present.
        XCTAssertFalse(model.diagnosticEvents.contains { $0.message.hasSuffix("host-0") })
        XCTAssertTrue(model.diagnosticEvents.first?.message.hasSuffix("host-54") ?? false)
    }

    func test_t_diagnostics_clear_empties_the_ring_buffer() async {
        let model = PerchHAPanelModel(
            connector: { _ in .failure(.unreachable(host: "ha.local")) },
            clock: TestPerchClock()
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        XCTAssertFalse(model.diagnosticEvents.isEmpty)

        model.clearDiagnostics()

        XCTAssertTrue(model.diagnosticEvents.isEmpty)
    }

    func test_t_diagnostics_retry_backoff_state_reflects_periodic_backoff() async {
        let clock = TestPerchClock()
        let interval = PerchDuration.seconds(45)
        let outcomes = PeriodicConnectorOutcomes(
            results: [
                .success(rooms: prefetchRooms(count: 1)),
                .failure(.unreachable(host: "ha.local"))
            ],
            fallback: .failure(.unreachable(host: "ha.local"))
        )
        let model = PerchHAPanelModel(
            connector: { _ in await outcomes.next() },
            clock: clock,
            periodicRefreshConfiguration: PerchHAPeriodicRefreshConfiguration(interval: interval, maximumBackoff: .seconds(300))
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        XCTAssertEqual(model.retryBackoffState, .connected)

        model.setPanelActive(true)
        await spinUntil {
            if case .backingOff = model.retryBackoffState { return true } else { return false }
        }
        if case let .backingOff(failureStreak, nextRetrySeconds) = model.retryBackoffState {
            XCTAssertEqual(failureStreak, 1)
            XCTAssertGreaterThan(nextRetrySeconds, 0)
        } else {
            XCTFail("expected backing off after a periodic refresh failure")
        }
    }

    func test_t_diagnostics_records_reconnecting_event_when_recovering_via_refresh() async {
        // connect succeeds; the periodic tick fails (degraded); the next tick is a
        // reconnect-while-degraded that must record a `.reconnecting` event.
        let clock = TestPerchClock()
        let interval = PerchDuration.seconds(45)
        let outcomes = PeriodicConnectorOutcomes(
            results: [
                .success(rooms: prefetchRooms(count: 1)),
                .failure(.unreachable(host: "ha.local")),
                .success(rooms: prefetchRooms(count: 1))
            ],
            fallback: .success(rooms: prefetchRooms(count: 1))
        )
        let model = PerchHAPanelModel(
            connector: { _ in await outcomes.next() },
            clock: clock,
            periodicRefreshConfiguration: PerchHAPeriodicRefreshConfiguration(interval: interval, maximumBackoff: .seconds(300))
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()

        model.setPanelActive(true)
        await spinUntil { model.diagnosticEvents.contains { $0.kind == .refreshFailed } }
        await spinUntil { await clock.sleepingTaskCount() == 1 }

        // Wake the backed-off sleep (failure doubled the base interval).
        _ = await clock.advance(by: interval)
        _ = await clock.advance(by: interval)
        await spinUntil { model.diagnosticEvents.contains { $0.kind == .recovered } }

        XCTAssertTrue(model.diagnosticEvents.contains { $0.kind == .reconnecting })
        XCTAssertTrue(model.diagnosticEvents.contains { $0.kind == .recovered })
    }

    func test_t_diagnostics_never_leak_token_into_event_messages() async {
        let secret = "supersecret-token-DO-NOT-LEAK-12345"
        let outcomes = PeriodicConnectorOutcomes(
            results: [
                .failure(.authentication),
                .failure(.protocolError("handshake rejected")),
                .success(rooms: prefetchRooms(count: 1))
            ],
            fallback: .success(rooms: prefetchRooms(count: 1))
        )
        let model = PerchHAPanelModel(
            connector: { _ in await outcomes.next() },
            clock: TestPerchClock()
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: secret)

        await model.connect()
        await model.connect()
        await model.connect()

        XCTAssertFalse(model.diagnosticEvents.isEmpty)
        for event in model.diagnosticEvents {
            XCTAssertFalse(event.message.contains(secret), "token must never appear in a diagnostic message")
        }
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

/// An in-memory secret store whose save/delete calls can be scripted to fail,
/// for exercising the shell's Keychain-failure surfacing.
private final class ScriptableFailureSecretStore: SecretStore, @unchecked Sendable {
    var failsSave = false
    var failsDelete = false
    private var values: [PerchHASecret: String] = [:]

    @discardableResult
    func save(_ value: String, for secret: PerchHASecret) throws -> SecretWriteResult {
        if failsSave {
            throw SecretStoreError.operationFailed(operation: "save", secret: secret, status: -25299)
        }
        let result: SecretWriteResult = values[secret] == nil ? .created : .updated
        values[secret] = value
        return result
    }

    func read(_ secret: PerchHASecret) throws -> String {
        guard let value = values[secret] else {
            throw SecretStoreError.notFound(secret)
        }
        return value
    }

    @discardableResult
    func delete(_ secret: PerchHASecret) throws -> SecretDeleteResult {
        if failsDelete {
            throw SecretStoreError.operationFailed(operation: "delete", secret: secret, status: -25299)
        }
        let result: SecretDeleteResult = values[secret] == nil ? .notFound : .deleted
        values[secret] = nil
        return result
    }
}

/// Scripted live-update stream sessions for exercising the model's reconnect
/// loop: each `run` consumes one session, emits its events, optionally holds
/// the stream open until released, then returns its failure.
private actor LiveStreamSessionScript {
    struct Session {
        let events: [EntityState]
        let failure: ConnectionFailure
        let holdsOpen: Bool
    }

    private var sessions: [Session]
    private var started = 0
    private var recordedFormTokens: [String] = []
    private var holdWaiters: [CheckedContinuation<Void, Never>] = []

    init(sessions: [Session]) {
        self.sessions = sessions
    }

    func run(
        form: PerchHAConnectionForm,
        onEvent: @Sendable (EntityState) async -> Void
    ) async -> ConnectionFailure {
        started += 1
        recordedFormTokens.append(form.trimmedToken)
        guard !sessions.isEmpty else {
            await withCheckedContinuation { holdWaiters.append($0) }
            return .protocolError("script exhausted")
        }
        let session = sessions.removeFirst()
        for event in session.events {
            await onEvent(event)
        }
        if session.holdsOpen {
            await withCheckedContinuation { holdWaiters.append($0) }
        }
        return session.failure
    }

    func startedSessions() -> Int {
        started
    }

    func formTokens() -> [String] {
        recordedFormTokens
    }

    func release() {
        let waiters = holdWaiters
        holdWaiters = []
        waiters.forEach { $0.resume() }
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
    private var historyBatchResults: [HAClientResult<[EntityID: HistorySeries]>]
    private var recordedDiscoveryURLs: [URL] = []
    private var recordedDiscoveryTokens: [String] = []
    private var recordedDiscoveryTrustPolicies: [HAServerTrustPolicy] = []
    private var recordedRefreshRequests: [OAuthRefreshRequest] = []
    private var recordedHistoryBatchTokens: [String] = []

    init(
        discoveryResults: [HAClientResult<DiscoverySnapshot>] = [],
        refreshResults: [HAClientResult<HAOAuthToken>] = [],
        historyBatchResults: [HAClientResult<[EntityID: HistorySeries]>] = []
    ) {
        self.discoveryResults = discoveryResults
        self.refreshResults = refreshResults
        self.historyBatchResults = historyBatchResults
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

    func historyBatch(_ input: HAConnectionInput, entityIDs: [EntityID], range: HistoryRange, end: Date) async -> HAClientResult<[EntityID: HistorySeries]> {
        recordedHistoryBatchTokens.append(input.token)
        guard !historyBatchResults.isEmpty else {
            return .success([:])
        }
        return historyBatchResults.removeFirst()
    }

    func streamEntityStateChanges(
        _ input: HAConnectionInput,
        onEvent: @escaping @Sendable (EntityState) async -> Void
    ) async -> HAClientFailure {
        .transport("live updates are not scripted in this recorder")
    }

    func historyBatchTokens() -> [String] {
        recordedHistoryBatchTokens
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
    private var recordedURLLists: [[String]] = []
    private var recordedTokens: [String] = []
    private var recordedUsesStoredAuthSessions: [Bool] = []

    func record(_ form: PerchHAConnectionForm) {
        recordedCallCount += 1
        recordedURLStrings.append(form.primaryURL()?.absoluteString ?? form.urlString)
        recordedFallbackURLString = form.fallbackURL()?.absoluteString
        recordedURLLists.append(form.urls().map(\.absoluteString))
        recordedTokens.append(form.token)
        recordedUsesStoredAuthSessions.append(form.usesStoredAuthSession)
    }

    func urlLists() -> [[String]] {
        recordedURLLists
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

/// Records every history request and answers with a series matching the
/// requested entity and range, so concurrent prefetch fetches never depend on
/// call ordering. Optionally blocks each call until released, letting tests
/// observe in-flight concurrency.

/// Records bulk-history requests for the background sync loop, returning one
/// series per requested entity. Each request (one batch) is logged so tests can
/// count cycles, assert which entities synced, and verify batching.
private actor BulkHistoryRecorder {
    /// One entry per bulk request, each the entity IDs in that batch.
    private(set) var batches: [[EntityID]] = []
    /// A canned numeric value returned for every series; tests can override per
    /// entity to assert override-in-place semantics.
    private var valueByEntity: [EntityID: Double] = [:]
    private let defaultValue: Double
    /// Entities the provider must omit from its result (simulating a partial
    /// response — the entity stays absent without failing the batch).
    private var omitted: Set<EntityID> = []
    /// How many upcoming batches must block until ``releaseHeldBatches()``,
    /// letting a test change the connection while a bulk fetch is in flight.
    private var holdCount = 0
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []

    init(defaultValue: Double = 1.0) {
        self.defaultValue = defaultValue
    }

    func setValue(_ value: Double, for entityID: EntityID) {
        valueByEntity[entityID] = value
    }

    func omit(_ entityID: EntityID) {
        omitted.insert(entityID)
    }

    func holdNextBatches(_ count: Int) {
        holdCount = count
    }

    func heldBatchCount() -> Int {
        heldWaiters.count
    }

    func releaseHeldBatches() {
        let waiters = heldWaiters
        heldWaiters = []
        waiters.forEach { $0.resume() }
    }

    func provide(
        form: PerchHAConnectionForm,
        entityIDs: [EntityID],
        range: HistoryRange
    ) async -> [EntityID: HistorySeries] {
        batches.append(entityIDs)
        if holdCount > 0 {
            holdCount -= 1
            await withCheckedContinuation { continuation in
                heldWaiters.append(continuation)
            }
        }
        var result: [EntityID: HistorySeries] = [:]
        for id in entityIDs where !omitted.contains(id) {
            let value = valueByEntity[id] ?? defaultValue
            result[id] = HistorySeries(
                entityID: id,
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
        return result
    }

    func cycleCount() -> Int {
        // Each cycle issues at least one batch; with a single range and a batch cap
        // above the displayed count, a cycle == a batch. Tests using a single range
        // treat batch count as cycle count.
        batches.count
    }

    func batchCount() -> Int {
        batches.count
    }

    func requestedIDs() -> Set<EntityID> {
        Set(batches.flatMap { $0 })
    }

    func requestCountForEntity(_ entityID: EntityID) -> Int {
        batches.reduce(0) { $0 + ($1.contains(entityID) ? 1 : 0) }
    }

    func largestBatchSize() -> Int {
        batches.map(\.count).max() ?? 0
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

/// A mutable, thread-safe wall-clock date source for tests that drive the
/// model's injected `wallClock`.
private final class MutableDateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    var now: Date {
        lock.lock()
        defer {
            lock.unlock()
        }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer {
            lock.unlock()
        }
        date = date.addingTimeInterval(interval)
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

func fakeHAConnector(form: PerchHAConnectionForm) async -> PerchHAConnectionAttemptResult {
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

actor CallCounter {
    private var count = 0

    func next() -> Int {
        count += 1
        return count
    }
}

func selectionRooms() -> [Room] {
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

func prefetchRooms(count: Int = 10) -> [Room] {
    let entities = (0..<count).map { index in
        DiscoveredEntity(
            id: EntityID("sensor.prefetch_\(index)"),
            name: "Prefetch \(index)",
            state: "\(Double(index))",
            unit: "°C",
            areaID: nil,
            deviceID: nil
        )
    }
    return [Room(id: "prefetch", name: "Prefetch", entities: entities)]
}

/// A deterministic connector that returns a scripted sequence of results, then a
/// fallback, used to drive the periodic-refresh backoff test.
private actor HostSequence {
    private var current: Int

    init(start: Int) {
        current = start
    }

    func next() -> String {
        defer { current += 1 }
        return "host-\(current)"
    }
}

private actor PeriodicConnectorOutcomes {
    private var results: [PerchHAConnectionAttemptResult]
    private let fallback: PerchHAConnectionAttemptResult

    init(results: [PerchHAConnectionAttemptResult], fallback: PerchHAConnectionAttemptResult) {
        self.results = results
        self.fallback = fallback
    }

    func next() -> PerchHAConnectionAttemptResult {
        guard !results.isEmpty else {
            return fallback
        }
        return results.removeFirst()
    }
}

func controlRooms() -> [Room] {
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

func energyRooms() -> [Room] {
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

private func historySeriesFixture(entityID: EntityID, range: HistoryRange, value: Double) -> HistorySeries {
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
#endif

extension PerchHAUITests {
    @MainActor
    func test_t_pearch_application_icon_resource_loads() throws {
        // The Dock icon for unbundled dev runs comes from this module
        // resource; a rename or packaging change must fail loudly here, not as
        // a silently generic Dock icon.
        let icon = try XCTUnwrap(PerchHAApplication.pearchApplicationIcon())
        XCTAssertGreaterThan(icon.size.width, 0)
        XCTAssertGreaterThan(icon.size.height, 0)
    }
}
