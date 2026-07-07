# Roadmap - PearchHA

Milestones are vertical slices. Each milestone ends with runnable code, tests, docs updated, and no secret leakage.

## M0 - Repository and project skeleton

Deliver:

- Git repository initialized.
- `.gitignore` protects `.env.local`, build output, and local artifacts.
- SwiftPM package skeleton.
- AppKit/SwiftUI executable entrypoint.
- Thin Xcode app wrapper verified with full Xcode.
- Empty module targets:
  - `PerchHAApp`
  - `PerchHAUI`
  - `PerchHACore`
  - `PerchHAClient`
  - `PerchHAPersistence`
  - `PerchHASupport`
- Initial CI workflow for build and unit tests.
- Framework-free smoke verifier for Command Line Tools environments.

Implemented locally:

- `swift build` runs.
- `swift test` compiles test targets in Command Line Tools environments.
- `swift run perchha-smoke` runs.
- CI runs on pull requests.
- `perchha-xcode-doctor` reports checked-in project/scheme, `xcodebuild` project listing, discovered Xcode developer directories, local `DEVELOPER_DIR` overrides, Xcode license acceptance, and full-Xcode readiness from the active developer directory, `xctest`, and `xcodebuild`, with scriptable JSON output and strict preflight mode.
- Full-Xcode CI selects Xcode, runs `perchha-xcode-doctor --json --strict`, lists XCTest cases with `swift test --disable-swift-testing --enable-xctest list`, and runs XCTest coverage gates.
- `PerchHA.xcodeproj` declares a thin app target that uses the local Swift package library product, menu-bar `Info.plist`, OAuth callback scheme, and shared `PerchHA` scheme.
- CI lints Xcode project, scheme, and `Info.plist` metadata.
- `PerchHARepoAudit` and `perchha-repo-audit` fail on tracked or unignored local env files, private fixture captures, build output, credential-bearing artifact paths, and default telemetry SDK imports/dependencies/endpoints, with public-command XCTest and smoke coverage.
- Docs match created paths.

Remaining before M0 is complete:

- Full-Xcode app wrapper build is verified with `xcodebuild`.

## M1 - Support primitives and test clocks

Deliver:

- Clock protocol with real and test clocks.
- Rate limiter.
- Jittered scheduler.
- Backoff.
- Request coalescer.
- Redacted logging.

Done:

- `t_rate_limit_hygiene` passes.
- Time-based tests use virtual time.
- Command Line Tools environments pass `swift run perchha-smoke`.
- Full-Xcode environments execute the XCTest method `test_t_rate_limit_hygiene`.

## M2 - Mirror and FakeHA foundation

Deliver:

- `hamirror` reads `.env.local`.
- Token-based capture path.
- Fixture redaction and review.
- FakeHA REST server skeleton.
- FakeHA WebSocket auth skeleton.
- Request journal with redaction.

Done:

- `t_mirror_redaction` passes.
- FakeHA serves `/api/` and `/api/states`.
- A mirrored fixture set can be served locally.
- `hamirror verify` parses fixture files, checks manifest consistency, and rejects unsanitized bodies.

## M3 - Home Assistant client contract

Deliver:

- REST auth smoke check.
- WebSocket auth.
- `get_states`.
- `subscribe_events` state-change path.
- `call_service`.
- Typed errors.

Implemented in the first M3 slice:

- REST auth smoke check through `HomeAssistantClient.checkRESTConnection`.
- `GET /api/states` through `HomeAssistantClient.states`.
- WebSocket auth through `HomeAssistantClient.checkWebSocketConnection`.
- WebSocket `get_states` through `HomeAssistantClient.webSocketStates`.
- WebSocket `subscribe_events` through `HomeAssistantClient.nextStateChangedEvent`.
- WebSocket `call_service` through `HomeAssistantClient.callService`.
- Typed REST errors mapped to `ConnectionFailure`.
- Typed WebSocket protocol and command errors mapped to `ConnectionFailure`.
- Optional self-signed certificate allowance is off by default, scoped to the current HTTPS primary/fallback hosts, and forwarded through REST, WebSocket, OAuth exchange, and OAuth refresh requests.
- FakeHA WebSocket service-call journal entries with exact redacted command payloads.

Done:

- `t_connection_errors` passes.
- `t_websocket_auth_and_get_states` passes.
- `t_live_updates_panel_and_bar` passes at contract level.
- `t_call_service_journaled` passes.
- Service calls are journaled.

Remaining production evidence:

- Real Home Assistant evidence for the optional certificate allowance when a self-signed deployment is available.

## M4 - Discovery and persistence

Deliver:

- Entity, device, area, and room models.
- Room resolution.
- Config store with atomic JSON writes.
- Secret store backed by Keychain.
- Token redaction tests.

Implemented in the first M4 slice:

- Area, device, entity registry, discovery snapshot, room, and room-resolver domain models.
- Room resolution order: entity area, device area, then `Unassigned`.
- WebSocket registry discovery through `config/area_registry/list`, `config/device_registry/list`, `config/entity_registry/list`, and `get_states`.
- FakeHA registry responses for discovery contract tests.
- FakeHA path-prefix support, buffered request/frame reads, and burst-start smoke coverage.
- Versioned Codable JSON config persisted with atomic writes.
- Keychain-backed access token and refresh token storage.
- Secret-store failures that avoid echoing secret values.
- Fixture sanitizer allowlists safe attributes and redacts unknown attribute values.

Done:

- `t_discovery_grouping` passes.
- Atomic config write and round-trip tests pass.
- `t_secret_storage_and_redaction` passes.

## M5 - App shell and first run

Deliver:

- Menu bar item.
- Custom panel.
- Connection screen.
- Connection state footer/header.
- Manual refresh.

Implemented in the first M5 slice:

- Menu bar status item opens a custom AppKit `NSPanel` hosted with SwiftUI.
- Custom panel can become key and hosts the first-run form.
- First-run connection form accepts Home Assistant URL, optional fallback URL, and long-lived access token.
- First-run connection form exposes an explicit self-signed certificate opt-in for the current HTTPS Home Assistant hosts.
- Panel model connects through the real Home Assistant discovery client and room resolver.
- Header and footer expose connection state, update status, disabled settings placeholder, quit, and manual refresh.
- Panel displays discovered room/entity values from FakeHA.
- First-run validation and authentication failures are represented as explicit panel states.
- Invalid fallback URLs fail before connection attempts; valid fallback URLs are passed to the connector.
- Panel public state exposes token presence without publishing token values.
- Non-token first-run form edits preserve private token state; explicit token clearing removes it.
- Panel-started connection and refresh work is cancellable during retry or app teardown.

Done:

- App launch wires the status item, custom panel, panel model, and cleanup path.
- App shell factory creates a key-capable custom panel with stable first-run sizing.
- Command Line Tools smoke verification covers the app shell panel factory.
- Panel model connects against FakeHA.
- Values appear in the panel model.
- First-run connection failure states are tested.
- Fallback URL validation and forwarding are tested.
- First-run form sequencing and token clearing behavior are tested.
- Public-state token privacy and cancelled action behavior are tested.

## M6 - Selection, ordering, and formatting

Deliver:

- Searchable room -> entity tree.
- Checkboxes.
- Drag reorder.
- Persistence across relaunch.
- Locale-correct value formatting.
- Explicit stale and unavailable states.

Implemented in the current M6 local slices:

- Pure selection projection for searchable room/entity trees.
- Checkbox state projection from persisted selected entity IDs.
- Selected-room projection that applies room and entity ordering.
- Config bridge from persisted JSON configuration to selection projection.
- App shell loads persisted selection configuration on launch.
- App shell reports config load/save failures and refuses to overwrite a config that failed to load.
- Panel model applies selected entities and persisted ordering to visible rooms.
- Panel model rejects selection/order changes when persistence fails and keeps the failure visible.
- Minimal settings surface exposes searchable room/entity checkboxes.
- Core reorder logic moves rooms and entities while preserving explicit selection membership.
- Panel model exposes native move operations that update visible rows and persist order immediately.
- Settings surface exposes native macOS move controls for rooms and entities.
- Settings rows expose target-relative drag/drop translation for rooms and same-room entities.
- Disabled move controls expose the disabled reason to assistive technology.
- Locale-aware value formatting for numeric entity states.
- Explicit formatted states for unavailable, unknown, and stale values.
- Refresh failures after a successful load keep last-known values visible as stale.
- Reordering after a refresh failure keeps last-known values visible as stale.
- Selection changes drop entities no longer present in discovery.

Verified locally:

- `t_select_reorder_persist` passes at the persistence/projection layer.
- `t_value_rendering_states` passes.
- Core reorderer tests cover room moves, entity moves, and boundary no-ops.
- Core and UI-model tests cover target-relative room placement, same-room entity placement, cross-room entity rejection, room/entity reorder persistence, boundary no-ops, and stale-row reorder behavior.
- App-shell and UI-model tests cover reorder save/relaunch, config load failure, config save failure, load-failure save blocking, and failed-save rejection for room moves, entity moves, and checkbox changes in the panel path.
- Command Line Tools smoke covers selection projection and value formatting.
- Command Line Tools smoke covers panel selection application, settings search, selection persistence sink, target-relative reorder persistence sink, and app-shell config loading.
- Command Line Tools smoke covers app-shell config failure reporting, failed-save panel rejection for room moves, entity moves, and checkbox changes, and reorder relaunch persistence.
- Command Line Tools smoke covers refresh-failure stale rendering and vanished selected ID cleanup.

Remaining before M6 is complete:

- Full-Xcode AppKit/SwiftUI drag interaction execution, including pointer-location placement behavior if added beyond target-relative drops.

## M7 - Menu bar items and gauges

Deliver:

- Text, bar, battery, and ring renderers.
- Percent normalization.
- Absolute value totals.
- Threshold colors.
- Promote and reorder menu bar items.

Implemented in the first M7 local slice:

- Pure menu bar item renderer for text, bar, battery, and ring styles.
- Percent gauges clamp numeric percentage states to `0...100`.
- Absolute gauges support explicit totals and total-entity references.
- Threshold evaluation produces normal, warning, or critical severity.
- Accessible rendered labels include entity name, value, gauge percent, severity, and style.
- Menu bar promotion projector preserves configured order and skips missing entities.
- App shell renders the first persisted promoted entity into the real `NSStatusItem` title and accessibility label.
- App shell updates the promoted status item from panel connection results and live state changes without manual refresh.
- App shell draws cached AppKit status-item gauge images for bar, battery, and ring styles while keeping the textual value as the status title.
- Status-item gauge images use severity colors for normal, warning, and critical states.
- Display settings for menu bar visibility, style, label visibility, unit visibility, and decimals persist to JSON.
- Display settings for manual gauge totals, total-entity gauge sources, warning thresholds, and critical thresholds persist to JSON.
- Display settings for default history range persist to JSON and leave the current status-item rendering stable.
- Display setting changes update the real `NSStatusItem` title and accessibility label immediately after a successful save.
- Failed display-setting saves are rejected without mutating the visible status item.
- Settings expose native move controls for promoted menu bar items.
- Promoted menu bar item reorder persists to JSON and updates the real `NSStatusItem` immediately after a successful save.

Verified locally:

- `t_gauge_rendering` coverage exists through `test_t_gauge_rendering_humidity_battery`.
- Core tests cover explicit-total rings, total-entity bars, percent clamping, non-gauge fallback text, threshold severity, and promotion order.
- App-shell tests cover persisted promotion loading and status-item update from live state.
- UI-model tests cover live updates during reconnect and failed-stale phases without clearing stale status.
- App-shell tests cover real status-item gauge image presence, stable image dimensions, non-template color preservation, and value-title behavior.
- Renderer tests inspect generated `NSImage` pixels for warning and critical severity colors.
- `t_display_settings_apply_live` covers style, label visibility, unit visibility, JSON persistence, and live status-item updates.
- `t_display_total_threshold_settings_apply_live` covers manual totals, total-entity sources, warning/critical thresholds, JSON persistence, and live status-item updates.
- `t_display_total_threshold_settings_reject_invalid_inputs` covers invalid total values, incompatible total entities, percent-source totals, and invalid thresholds without mutating persisted display settings.
- `t_display_total_threshold_save_failure_rejects_live_status_item_change` covers failed-save rejection for total and threshold display settings.
- `t_settings_updates_default_history_range_and_persists` covers default history range persistence at the settings model boundary.
- `t_settings_rejects_default_history_range_when_save_fails` covers failed-save rejection for default history range changes.
- `t_menu_bar_reorder_settings_apply_live_and_persist` covers promoted menu bar item reorder, JSON persistence, and live status-item updates.
- `t_settings_search_blocks_promoted_menu_bar_reorder` covers active-search reorder blocking so hidden promoted items are not reordered from a filtered settings view.
- `t_menu_bar_reorder_save_failure_rejects_live_status_item_change` covers failed-save rejection for promoted menu bar item reorder.
- Command Line Tools smoke covers battery, ring, normalization, accessibility label, promotion projection, promoted status-item live updates, status-item gauge image creation, promoted menu bar item reorder, filtered-search reorder blocking, and display settings live apply for style, labels, decimals, default history range, manual totals, total-entity sources, invalid totals, and thresholds.

Remaining before M7 is complete:

- Full-Xcode execution of the status-item rendering path.

Done:

- `t_gauge_rendering` passes.
- `t_display_settings_apply_live` passes for display changes.

## M8 - Optimized Home Assistant paths

Deliver:

- Detect and use `subscribe_entities` when supported.
- Detect and use registry display/list commands where supported.
- Fallback to documented paths.
- Unsupported-command tests.

Implemented in the first M8 local slice:

- Entity registry discovery tries `config/entity_registry/list_for_display` before the full entity registry list.
- Entity registry discovery falls back to `config/entity_registry/list` when the display-list command is unavailable.
- Discovery treats unavailable area, device, and entity registry commands as empty registry data and still returns states.
- Non-unavailable WebSocket command failures remain explicit failures.
- FakeHA can simulate optimized registry support and command-specific unavailable responses using current `unknown_command` and legacy `unsupported_command`.
- `hamirror capture --websocket` records optimized WebSocket command evidence without storing private command payloads.
- `hamirror capture --write` re-verifies the written fixture set immediately, and private fixture outputs under `Fixtures/private/` also prove they stay ignored by Git.
- `hamirror doctor` reports mirror-capture readiness from redacted key presence/status plus next-step hints and suggested follow-up commands, treats user/password as non-capture credentials, supports scriptable JSON presence/status output plus redacted guidance, and supports strict preflight for scripts.
- `hamirror verify` rejects stale WebSocket evidence files and unknown WebSocket evidence fields.
- `hamirror serve` starts mirrored REST and WebSocket loopback servers together, respects captured optimized-command availability, and synthesizes minimal display/entity registry rows from mirrored states when private WebSocket payloads were intentionally omitted.
- WebSocket mirror capture fails explicitly when HA stops responding during the evidence handshake.
- Live updates try `subscribe_entities` before the documented `subscribe_events` path.
- Live updates merge full `subscribe_entities` additions and partial compact change diffs.
- Live updates apply compact attribute removals, update the stream snapshot for top-level entity removals, and wait until the next usable state frame.
- Live updates fall back to `subscribe_events` when `subscribe_entities` is unavailable.
- FakeHA supports compact `subscribe_entities` additions, changes, removals, and journals both optimized and fallback live subscription paths.

Verified locally:

- `t_discovery_uses_entity_registry_display_list_when_supported` covers the optimized display-list path and verifies the full registry list is skipped.
- `t_discovery_falls_back_to_full_entity_registry_when_display_list_is_unknown` covers fallback from display-list to full registry.
- `t_discovery_falls_back_to_states_when_registry_commands_are_unknown` covers states-only discovery when registry commands are unavailable.
- `testStateChangedEventMapsNewState` covers the optimized `subscribe_entities` live-update path.
- `t_live_updates_merge_partial_subscribe_entities_change` covers partial compact diff merging.
- `t_live_updates_merge_subscribe_entities_attribute_removals` covers compact attribute removal merging.
- `t_live_updates_ignore_subscribe_entities_entity_removal_until_next_state` covers removal-only frames followed by a usable state frame.
- `t_live_updates_wait_past_many_subscribe_entities_removals` covers long removal-only runs before a usable state frame.
- `t_live_updates_do_not_merge_partial_change_after_entity_removal` covers removal followed by a partial diff for the same entity.
- `t_live_updates_fall_back_to_subscribe_events_when_subscribe_entities_is_unknown` covers current `unknown_command` fallback to documented `subscribe_events`.
- `t_live_updates_fall_back_to_subscribe_events_when_subscribe_entities_is_legacy_unsupported` covers legacy `unsupported_command` fallback.
- `testFakeHAWebSocketServerRejectsUnknownCommandExplicitly` covers explicit unknown-command behavior.
- `testMirrorEnvironmentReadinessReportsMissingTokenWithoutCredentialValues`, `testMirrorEnvironmentReadinessReportsCaptureAndOAuthReadiness`, `testMirrorEnvironmentReadinessReportsIncompleteOAuthConfiguration`, `testMirrorEnvironmentReadinessReportsOAuthReadyWhileCaptureBlocked`, `testMirrorEnvironmentSuggestedCommandsShellQuoteEnvPath`, `testMirrorEnvironmentReadinessNextStepsShellQuoteEnvPathCommands`, and `testMirrorEnvironmentReadinessDiagnosticIsScriptableAndRedacted` cover secret-redacted mirror env preflight, mixed readiness states, and shell-safe follow-up guidance.
- `testFakeHALoadsMirrorFixturesAndSynthesizesDisplayRegistryResults` and `testFakeHAMirroredWebSocketModePreservesPerCommandAvailabilityCodes` cover synthesized mirrored registry replay and command-specific unavailable-code preservation.
- Command Line Tools smoke covers optimized display-list discovery, states-only fallback, optimized live updates, partial compact diff merging, compact removals, and live-update fallback.
- Command Line Tools smoke covers `hamirror` optimized WebSocket evidence capture and timeout behavior against FakeHA.
- Command Line Tools smoke launches `hamirror serve`, verifies prefixed mirrored `/api/states` replay, completes the WebSocket auth-required handshake, and exercises synthesized display-list results from mirrored states.

Remaining before M8 is complete:

- Run `hamirror capture --env .env.local --output Fixtures/private/m8-real --websocket --write` against the real Home Assistant instance. The write path now self-verifies the fixture set and ignored private output status; retain that command evidence.

Done:

- Live updates still work with and without `subscribe_entities`.
- Discovery still works with partial registry support.

## M9 - History

Deliver:

- REST history provider.
- Recorder statistics provider where supported.
- Hover debounce.
- History cache.
- History popover.
- Unsupported history state.

Implemented in the first M9 local slice:

- REST history provider uses documented `GET /api/history/period/<start>` with entity filtering, end time, minimal responses, and attributes omitted.
- Minimal history rows without repeated `entity_id` decode correctly.
- History samples are filtered to the requested entity, sorted by timestamp, and carry both raw string state and parsed numeric value when available.
- Empty history returns an explicit empty series.
- Malformed history payloads fail as typed client payload errors instead of becoming empty charts.
- FakeHA serves REST history fixtures and preserves path-prefix routing.
- Command Line Tools smoke covers REST history mapping and FakeHA request routing.
- Panel model history requests use injected-clock debounce before calling the provider.
- History results are cached by entity and range with bounded capacity and TTL expiry.
- The compact history popover exposes range selection, loading, loaded, and unavailable states.
- History popover presentation is separate from loaded history content, so hover-out closes loaded and unavailable popovers.
- Successful connection identity changes clear cached history and visible history state.
- History loading maps to a skeleton presentation instead of a spinner.
- The loading skeleton has a fixed chart-plus-statistics placeholder layout contract for pre-snapshot regression coverage.
- `PerchHAHistoryPopoverContent` is shared between the real popover and smoke rendering, so `perchha-smoke` exports `history-loaded-light.png` with the segmented range control, sparkline, and statistics using the same layout code.
- Empty or non-numeric history renders an explicit no-data state.
- App shell wires the panel history provider to the real Home Assistant history client.
- Command Line Tools smoke covers panel history debounce, cache hit behavior, and disconnected unavailable state.
- Week and month history route through WebSocket `recorder/statistics_during_period` where supported.
- Week statistics use hourly buckets; month statistics use daily buckets.
- Recorder statistics rows map Home Assistant millisecond timestamps to history samples and treat missing numeric columns as null.
- Unsupported or unreachable recorder statistics paths fall back to REST history for the available retention period.
- FakeHA serves recorder statistics fixtures and can replay REST history from the same local server for fallback checks.
- History sparkline geometry is deterministic and testable outside the private SwiftUI shape.
- History statistics and sparklines use the chronologically latest numeric sample, even when later raw history rows are `unknown` or `unavailable`.
- Constant-value and low-data history charts render as centered midlines instead of misleading bottom-edge charts.

Remaining before M9 is complete:

- Full-Xcode verification of the SwiftUI hover popover.
- Full-Xcode native popover and focus verification for chart rendering and unavailable-history UI.

Done:

- `test_t_rest_history_provider_maps_and_sorts_samples` passes for the REST-provider slice.
- `testRESTHistoryAcceptsMinimalResponseRowsWithoutEntityID`, `testRESTHistoryPreservesBasePathPrefixAgainstFakeHA`, `testRESTHistoryReturnsEmptySeriesForNoSamples`, and `testRESTHistoryRejectsMalformedPayload` cover minimal responses, routing, empty results, and malformed payloads.
- `test_t_history_hover_debounces_before_provider_call`, `test_t_history_cancel_hover_resets_loading_state`, `test_t_history_load_uses_default_history_range_when_nil`, `testHistoryBodyPresentationUsesSkeletonForLoadingState`, `testHistoryLoadingSkeletonUsesChartAndStatisticsPlaceholders`, and `testHistoryBodyPresentationMapsLoadedAndUnavailableStates` cover hover debounce, cancellation, default range routing, skeleton loading, skeleton placeholder layout, and body presentation state mapping.
- `test_t_history_cache_reuses_series_until_ttl_expires` and `testHistoryCacheEvictsLeastRecentlyUsedEntryWhenCapacityIsReached` cover cache reuse, TTL expiry, and bounded eviction.
- `test_t_history_reconnect_clears_cached_series_and_visible_history`, `test_t_history_hover_out_closes_loaded_and_unavailable_popovers`, `testHistoryContentSummaryEmptySeriesIsNoNumericData`, `testHistoryContentSummaryNonNumericOnlySeriesIsNoNumericData`, and `testHistoryContentSummaryKeepsNumericHistoryWhenTrailingSampleIsNonNumeric` cover cache scoping, popover dismissal, no-data summaries, and mixed numeric/non-numeric summaries.
- `test_t_history_unavailable_state_is_explicit` covers disconnected and provider-unavailable history states.
- `test_t_app_shell_load_history_uses_injected_provider` covers app-shell history provider wiring.
- `test_t_history_week_routes_to_recorder_statistics`, `testHistoryMonthRoutesToRecorderStatisticsWithDailyPeriod`, `testHistoryRecorderStatisticsPreservesBasePathPrefixAgainstFakeHA`, `testHistoryFallsBackToRESTWhenRecorderStatisticsIsUnknown`, `testHistoryRecorderStatisticsFallbackPreservesBasePathPrefixAgainstFakeHA`, `testHistoryFallsBackToRESTWhenRecorderStatisticsIsLegacyUnsupported`, `testHistoryFallsBackToRESTWhenRecorderStatisticsTransportIsUnreachable`, `testHistoryFallsBackToRESTWhenRecorderStatisticsCommandTransportBreaks`, and `testHistoryRecorderStatisticsRejectsMalformedPayload` cover recorder-statistics routing, path-prefix handling, fallback, null-column handling, unreachable/generic transport failure, and malformed payloads.
- `testHistoryContentSummaryUsesLatestChronologicalNumericSample`, `testHistorySparklineGeometryMapsTimeAndValueIntoNormalizedPoints`, `testHistorySparklineGeometrySortsSamplesChronologically`, `testHistorySparklineGeometryFallsBackToMidlineWithoutEnoughNumericSamples`, and `testHistorySparklineGeometryCentersConstantValuesAndSpreadsEqualTimestamps` cover deterministic chart geometry and mixed numeric/non-numeric history; Command Line Tools smoke covers the same core chart mapping path.
- `t_interval_fallback_polling` passes.

## M10 - Built-in controls

Deliver:

- Switch/light/input boolean toggle.
- Cover buttons.
- Cover position slider.
- Optimistic UI and rollback.

Implemented in the M10 local slices:

- Shared `ActionSpec`/`ActionValue` data models represent Home Assistant service calls for built-in controls and custom actions.
- Switch, light, and input boolean rows derive on/off toggle actions from entity domain and state.
- Panel toggles send one service call through the injected action runner and the app shell production runner uses `HomeAssistantClient.callService`.
- Successful toggles keep the optimistic visible state.
- Failed toggles roll the visible state back and expose an inline entity-scoped failure message.
- Cancelled in-flight toggles roll back their optimistic state.
- Successful in-flight toggles reassert their target state after stale refreshes or live updates arrive before the service result.
- Home Assistant `current_position` is preserved for cover entities through REST state decoding, compact WebSocket live updates, room resolution, and panel snapshots.
- Cover rows derive open, close, stop, and set-position actions through the same shared action runner.
- Cover position changes update optimistically, roll back on service failure, reject covers without a reported position, and clamp payloads to Home Assistant's 0-100 range.
- FakeHA smoke verifies panel toggle and cover position controls emit exact WebSocket `call_service` payloads.
- Command Line Tools smoke exports `built-in-controls-light.png` from the real panel with toggle failure feedback plus cover buttons and position slider visible.
- Command Line Tools smoke and the Xcode-testable UI suite verify the real built-in controls panel exposes the native switch class, marked cover-position slider class, and native cover buttons through the panel factory seam.

Remaining before M10 is complete:

- Full-Xcode visual and keyboard verification for control rows.

Done:

- `testBuiltInControlDerivesToggleActionsForSupportedDomains` covers switch, light, input boolean, unsupported sensor, and unknown-state derivation.
- `testBuiltInCoverControlDerivesActionsAndPosition` covers cover action derivation, position parsing, and clamped set-position payloads.
- `test_t_builtin_controls_toggle_switch_optimistically_and_emit_one_action` covers optimistic state, one action, and single-flight behavior.
- `test_t_action_rollback_restores_previous_state_and_shows_inline_failure` covers rollback and inline failure state.
- `testBuiltInControlCancellationRollsBackOptimisticState` covers optimistic rollback on cancellation.
- `testBuiltInControlSuccessReassertsTargetStateAfterStaleRefreshDuringInFlightAction` and `testBuiltInControlSuccessReassertsTargetStateAfterStaleLiveUpdateDuringInFlightAction` cover stale refresh/live update races while a toggle is running.
- `test_t_builtin_controls_reject_sensor_without_service_call` covers unsupported entity rejection.
- `test_t_builtin_cover_open_close_stop_emit_separate_actions`, `test_t_builtin_cover_position_updates_optimistically_and_emits_position_payload`, `test_t_builtin_cover_position_rollback_restores_previous_state_and_position`, `testBuiltInCoverPositionCancellationRollsBackOptimisticPosition`, `testBuiltInCoverPositionSuccessReassertsTargetAfterStaleRefreshDuringInFlightAction`, `testBuiltInCoverPositionSuccessReassertsTargetAfterStaleLiveUpdateDuringInFlightAction`, and `test_t_builtin_cover_position_rejects_cover_without_position` cover cover button actions, slider payloads, rollback, cancellation, stale refresh/live update races, and unsupported position handling.
- `testBuiltInControlUsesFakeHAServiceCallJournal` covers panel-to-FakeHA `call_service` journaling.
- `testBuiltInCoverPositionUsesFakeHAServiceCallJournal` and `testBuiltInCoverButtonsUseFakeHAServiceCallJournal` cover panel-to-FakeHA cover set-position and button journaling.
- `testAppShellRunsBuiltInControlThroughInjectedActionRunner`, `testAppShellRunsBuiltInCoverControlThroughInjectedActionRunner`, and `testAppShellRunsBuiltInCoverButtonControlsThroughInjectedActionRunner` cover app-shell action runner wiring.
- `testStatesMapsFriendlyNameUnitAndMissingAttributes`, `test_t_live_updates_merge_partial_subscribe_entities_change`, and `test_t_live_updates_clear_current_position_when_subscribe_entities_removes_it` cover `current_position` decoding, compact live update merge, and explicit removal.
- Command Line Tools smoke covers successful panel toggle, cover position, cover button service-call journaling, plus rollback on service failure.

## M11 - Custom actions

Deliver:

- Custom action editor.
- Attach actions to any entity row.
- Sensor-attached action buttons.
- Optional confirmation.
- Exact service payload preservation.

Implemented in the first M11 local slice:

- `EntityCustomAction` persists a stable ID, attached entity, button title, confirmation flag, and shared `ActionSpec`.
- Custom actions can be attached to any discovered entity row, including sensors.
- Settings exposes per-entity custom action controls for add, edit, delete, and reorder of title, domain, service, target entity, scalar/object/list `serviceData`, and confirmation.
- Settings uses fetched Home Assistant service metadata for domain/service pickers and scalar field defaults while preserving manual fallback fields when metadata is unavailable.
- Settings exposes unmatched persisted actions so stale entity attachments can be deleted instead of hidden.
- Sensor-attached action buttons run through the same injected action runner as built-in controls.
- Optional confirmation blocks execution until the caller confirms.
- Exact domain, service, target entity, and `serviceData` payloads are preserved through the FakeHA `call_service` journal.
- Native object and array service-data editing preserves nested JSON payloads through persistence, app-shell forwarding, and FakeHA service-call journaling.
- Protected service-data values round-trip as opaque JSON references, resolve from Keychain before execution, and fail explicitly when the referenced secret is missing.
- Command Line Tools smoke verifies the real settings editor commits native title, target-entity, and nested service-data text-field edits back into `CustomActionConfiguration`.
- Failed custom actions show an inline entity-scoped error and do not mutate sensor values.
- Malformed persisted custom actions fail explicitly on load or save, including blank required fields and duplicate action IDs.
- Custom action `serviceData` no longer stores secret scalar values in plaintext JSON; protected values persist as opaque references and are resolved only at execution time.
- `HomeAssistantClient.services` fetches Home Assistant WebSocket `get_services` metadata and FakeHA replays service metadata fixtures.
- App shell persists custom actions and exposes run/set/remove entrypoints.
- The in-app custom-action editor UI was removed by user decision; custom actions remain a persisted, tested engine (rows still render configured buttons) without a creation UI.

Remaining before M11 is complete:

- Full-Xcode visual and keyboard verification for custom action rows and confirmation.
- Native UI automation coverage once the full app wrapper is available.

Done:

- `test_t_sensor_custom_action_attaches_to_sensor_and_emits_exact_payload` covers sensor attachment, exact action emission, and non-mutating sensor state.
- `testCustomActionConfirmationBlocksUnconfirmedRun` covers confirmation gating.
- `test_t_custom_action_failure_shows_inline_error_without_changing_sensor_state` covers failure visibility and sensor-state preservation.
- `testCustomActionRejectsIncompleteOrUnknownEntityConfiguration` covers invalid and unknown-entity configuration rejection.
- `testCustomActionRejectsProtectedServiceDataKeys` covers UI-model rejection for secret-bearing plaintext service data.
- `testCustomActionServiceDataEditorUpdatesScalarsAndRejectsUnsafeKeys` covers scalar service-data add, edit, rename, delete, duplicate-key rejection, invalid scalar-value rejection, and protected-key rejection.
- `testActionValueRoundTripsNestedJSONShapes`, `testCustomActionServiceDataEditorUpdatesObjectsAndArrays`, and persistence malformed-config cases cover object/list service-data editing, nested JSON round-trip, array-path protected-key rejection, invalid nested paths, nested reordering, and nested removal.
- `testCustomActionOrphanedLoadedActionsRemainVisibleForDeletion` covers stale custom-action attachment visibility and deletion.
- `testCustomActionServiceMetadataLoadsAfterConnectAndScaffoldsDefaults` and `testCustomActionServiceMetadataFailureDoesNotFailConnection` cover metadata loading, metadata failure behavior, and metadata-driven service-data defaults.
- `testCustomActionUsesFakeHAServiceCallJournal` covers panel-to-FakeHA service-call journaling.
- `testAppShellPersistsCustomActionsAndRunsInjectedActionRunner` covers app-shell persistence, run wiring, update, remove, reorder wiring, and service-data persistence wiring.
- `test_t_app_shell_custom_action_save_failure_rejects_live_configuration_change` and `test_t_app_shell_custom_action_remove_failure_rejects_live_configuration_change` cover failed-save rejection for set and remove.
- `test_t_app_shell_rejects_invalid_loaded_custom_action_configuration` covers app-shell rejection of invalid configurations returned by any config store.
- `test_t_custom_action_service_metadata_fetches_get_services` and `testFakeHAWebSocketServerReturnsServiceMetadata` cover service metadata transport and FakeHA replay.
- `testJSONConfigStoreRoundTripsVersionedConfiguration`, `testJSONConfigStoreDefaultsMissingHistoryRangeToHour`, `testJSONConfigStoreRejectsMalformedCustomActionsOnLoad`, and `testJSONConfigStoreRejectsProtectedCustomActionServiceDataOnSave` cover persisted custom actions, old-config defaults, invalid loaded actions, duplicates, and protected service-data key rejection.
- Command Line Tools smoke covers exact FakeHA custom-action payloads attached to a sensor row.

## M12 - OAuth/IndieAuth sign-in

Deliver:

- Native sign-in flow.
- Access and refresh token storage.
- Token refresh.
- Expired-token recovery.

Integrated:

- `HomeAssistantClient.authorizationURL(for:)` builds the documented `/auth/authorize` URL with `client_id`, `redirect_uri`, and optional `state`.
- `HomeAssistantClient.exchangeAuthorizationCode`, `refreshAccessToken`, and `revokeRefreshToken` call `/auth/token` with form-encoded OAuth/IndieAuth requests.
- `PerchHAAuthSessionStore` saves, loads, rotates, clears, and compensates second-operation failures for access tokens, refresh tokens, and OAuth `client_id` through the Keychain secret store.
- `PerchHAAuthorizedHomeAssistantGateway` loads stored OAuth sessions, retries one authenticated app-shell request after access-token refresh, persists rotated access tokens, and clears expired sessions after refresh failure.
- `PerchHAPanelModel` can connect with a stored auth session without exposing tokens and clears the stored-session flag after authentication failure so the user must reconnect.
- `PerchHAOAuthSignInCoordinator` builds the authorization URL, presents native `ASWebAuthenticationSession`, validates callback state and redirect URI, exchanges the code, saves the first Keychain session, and switches the panel into stored-session connection mode with the form that was authorized.
- `PerchHAOAuthApplicationConfiguration` loads the OAuth client website and redirect URI from exported environment values or `.env.local`, with exported values taking precedence and smoke coverage for the env-file path.
- `PerchHAOAuthClientWebsiteBuilder`, `PerchHAOAuthClientWebsiteVerifier`, and `perchha-package-app --write-oauth-site/--verify-oauth-site` generate and verify the static HTML artifact that must be published at the configured OAuth client website URL.
- `perchha-package-app --verify-published-oauth-site` fetches the configured client website URL and verifies the live deployed HTML declaration against the configured redirect URI without sending Home Assistant secrets.
- `PerchHAReleaseEvidenceWriter`, `PerchHAReleaseEvidenceVerifier`, and `perchha-package-app --oauth-site` can retain the generated OAuth client-website artifact in the release evidence manifest so the release bundle can re-verify the exact declaration page beside the app and DMG artifacts.
- `PerchHAPackaging` builds a SwiftPM-driven `.app` bundle with `CFBundleURLTypes` for the OAuth callback scheme, `LSUIElement=true`, and CI/smoke coverage for generated metadata.
- `PerchHALaunchServicesVerifier` registers the generated bundle and verifies macOS records its OAuth callback scheme claim with `Viewer` role.
- `HomeAssistantClient.verifyOAuthClientWebsite` and `hamirror oauth-check` verify the production OAuth client website rule for native redirects without sending HA tokens or credentials.
- `PerchHAApplication` handles delivered external URLs, accepts only the configured OAuth callback redirect base, and stores only redacted ingress metadata so authorization codes and states are not retained.
- `perchha-smoke` exports `signing-in-light.png` by driving the panel through the public native OAuth sign-in path with an in-flight runner, proving the sign-in loading row without contacting real Home Assistant.

Remaining:

- Production hosting of the generated OAuth client website at the configured client website URL.
- Real-HA callback evidence with the configured client identity.
- Real delivered-callback evidence and native UI verification with the generated app bundle or full Xcode.

Completion criteria:

- Token and login paths both normalize to bearer API calls.
- Expired refresh tokens clear secrets and ask for reconnect.

## M13 - Accessibility and polish

Deliver:

- Keyboard navigation.
- VoiceOver labels.
- Reduce Motion.
- Increase Contrast.
- Empty, loading, success, and error states.
- Light/dark snapshot coverage.

Integrated:

- `PerchHAPanelAccessibilityPresentation` exposes testable connection summaries, content state labels, keyboard hints, Reduce Motion policy, and Increase Contrast policy.
- `PerchHAPanelView` surfaces the root accessibility label, value, hint, Reduce Motion policy, and Increase Contrast policy through one tested presentation boundary.
- Entity-row accessibility presentation covers value labels, toggle controls, cover buttons, cover position values, custom actions, running states, and inline failures.
- Keyboard reorder hints for settings and menu-bar promotion share one tested source and explain boundary/search-blocked states.
- Command Line Tools smoke verifies the real first-run AppKit panel exposes native URL/token controls, accepts first-responder assignment for the URL field, and advances through a non-degenerate native key-view path.
- Command Line Tools smoke and the Xcode-testable UI suite both verify the real settings custom-action editor exposes native title/target/service-data text fields, metadata-backed popup selections, and an ordered key-view path from the action title into the rest of the editor.
- `perchha-smoke` renders real `PerchHAPanelView` snapshots through `NSHostingView` for light, dark, increased-contrast, reduced-motion, first-run, connecting/loading, OAuth signing-in, settings selection, settings custom-action editor, built-in controls, reconnecting stale values, empty, success, error, and increased-contrast history variants, then verifies stable dimensions, nonblank pixels, distinct appearance/state hashes, loading accessibility state, public OAuth sign-in state, explicit selection state, menu-bar promotion, and stale-value formatting.
- `perchha-smoke` also exports `review-contact-sheet.png`, a deterministic contact sheet of the real panel screenshots for fast release UI/UX review.
- `perchha-smoke` compares the real panel screenshot signatures and `review-contact-sheet.png` signature against the checked-in `docs/release-review-baseline.json` manifest, and can refresh that manifest intentionally with `--update-review-baseline`.
- `perchha-smoke --repeat <count>` reruns the full public smoke entrypoint as fresh invocations for repeatable flake and snapshot-drift diagnosis while keeping the last-run screenshots as retained evidence.

Remaining:

- Full-Xcode execution of the native focus traversal checks on a machine with Xcode selected.

Completion criteria:

- `t_accessibility` passes in CI and the native focus traversal checks run under a full-Xcode test execution path.
- Snapshot suite passes for light, dark, increased-contrast, and reduced-motion variants, and the stored release-review baseline stays in sync with intentional UI changes.

## M14 - Performance and resilience

Deliver:

- Idle CPU check.
- Memory soak.
- Panel open measurement.
- Reconnect request-volume checks.
- Bar item redraw throttling.

Integrated:

- `perchha-smoke` measures cached panel open from the public AppKit factory through SwiftUI layout/display, with a warm-up, nine samples, a 150 ms median budget, and a 300 ms max budget.
- `perchha-smoke` runs an app-shell lifecycle memory soak through AppKit launch/connect/status-item update/termination loops backed by FakeHA WebSocket discovery, with resident-memory growth bounded after warm-up.
- `perchha-smoke` and `test_t_reconnect_request_volume_uses_single_discovery_and_service_metadata_fetch` bound manual reconnect request volume to one optimized discovery sequence plus one service-metadata fetch, with FakeHA journal evidence and no full entity-registry fallback when display-list discovery is available.
- `perchha-smoke` and `test_t_display_settings_apply_live` prove status-item gauge images are rendered only when image-relevant fields change, and text-only menu-bar items skip image rendering entirely.
- `perchha-smoke` and `test_t_reconnect_after_restart_resubscribes_live_state` prove live WebSocket restart recovery re-authenticates and resubscribes once after a post-subscription socket drop.
- `perchha-smoke` measures process CPU time while the connected AppKit app shell is idle after launch, discovery, and stable status-item rendering.
- `perchha-coverage-check` enforces the documented LLVM coverage JSON gates for `PerchHACore`, `PerchHAClient`, and core branch coverage in full-Xcode CI, including explicit failure when requested branch coverage is unavailable; `perchha-smoke` exercises that guard in Command Line Tools environments.

Remaining:

- None for the local Command Line Tools runner.

Completion criteria:

- `perchha-smoke` passes with idle CPU, memory soak, panel-open, bounded request-volume, redraw-throttling, and restart-recovery checks.

## M15 - Release packaging

Deliver:

- Developer ID signing.
- Notarized app.
- DMG packaging.
- Release checklist.
- Sparkle update support is deferred until after the direct release path is stable.

Integrated:

- `PerchHADMGBuilder` stages the `.app` bundle with an `/Applications` shortcut and creates a compressed read-only DMG through `hdiutil`.
- `PerchHADMGVerifier`, `PerchHADMGContentVerifier`, `perchha-package-app --package-dmg --verify-dmg --verify-dmg-contents`, smoke, and CI verify the generated DMG bytes and mounted drag-install layout with native macOS tooling and retain the local DMG artifact.
- `PerchHACodeSigner` and `PerchHACodeSignatureVerifier` provide explicit `codesign` command orchestration for ad-hoc smoke signing and Developer ID release signing, including hardened runtime, timestamp, and entitlements support.
- `PerchHANotarySubmitter` and `perchha-package-app --notary-profile` provide `xcrun notarytool submit --wait` and `xcrun stapler staple` orchestration for credentialed release machines.
- `perchha-package-app` rejects notary submission options that are missing the DMG packaging step, required notary profile, or Developer ID signing identity, while preserving standalone `--release-preflight`.
- `PerchHAReleasePreflightChecker` and `perchha-package-app --release-preflight` verify that the selected Developer ID identity is installed and the `notarytool` Keychain profile is usable before a credentialed release build starts, with redacted JSON output for release scripts.
- `PerchHAReleasePreflightChecker` and `perchha-package-app --release-preflight` also emit redacted next-step hints and suggested commands so blocked credentialed releases fail with actionable guidance instead of only a terse status.
- CI builds `.build/release/PerchHA` and packages that release executable for local release evidence instead of the debug executable.
- `perchha-smoke` verifies generated app bundles can be ad-hoc signed locally before DMG creation, exports fresh panel PNGs under `PERCHHA_SMOKE_SNAPSHOT_DIR/current` for completion evidence, and CI retains those screenshots.
- `PerchHAReleaseEvidenceWriter`, `perchha-package-app --release-manifest`, and `docs/RELEASE.md` record release checklist evidence, app metadata, DMG hashes, screenshot hashes, signing status, and notarization status.
- `PerchHAReleaseEvidenceVerifier` and `perchha-package-app --verify-release-manifest` re-read retained release evidence and fail when app metadata, recorded app signature validity, recorded stapled DMG validation, DMG hashes, screenshot hashes, or canonical required smoke screenshot names drift from the current artifacts.
- Release evidence manifests store artifact paths relative to the manifest when possible, and CI retains a single portable evidence bundle whose manifest still replay-verifies after download as long as the internal layout is preserved.
- `.github/workflows/release.yml` now cuts a GitHub release automatically on pushes to `main`, and still provides a branch-safe manual `dry_run` path that builds, packages, verifies, and uploads the retained release-evidence bundle without publishing.
- The About view exposes the signed app version directly from bundle metadata and can check GitHub's latest public release, surfacing a native "Check for updates" / "Download <version>" action without adding an updater dependency.
- Local release evidence includes the smoke-generated screenshot contact sheet, so UI review coverage is retained and hash-verified with the individual screenshots.
- Local release evidence also records the smoke-exported `review-baseline-expected.json`, a retained copy of the checked-in baseline that smoke compared against, and hash-verifies it during manifest replay.
- `PerchHARepoAudit` enforces the no-telemetry-by-default release criterion by rejecting common telemetry SDK imports, package identifiers, and collection endpoints from tracked or unignored Swift/build/config files.
- Sparkle is deferred by ADR-0009 until the direct Developer ID release path is stable, so no updater dependency is required for v1.

Remaining:

- Credentialed Developer ID signing evidence.
- Notarized and stapled build artifact evidence.

Completion criteria:

- Signed and notarized build artifact is produced.
- DMG artifact is produced and verified.
- Release evidence manifest is produced and retained.
- No telemetry is present by default.

## Ongoing rules

- One requirement change means one traceability update.
- New Home Assistant wire behavior means one mirror fixture update.
- New persistence, auth, or public module decision means one ADR update.
- No committed `.env.local`, tokens, credentials, or private fixture data.
- CI runs `perchha-repo-audit` and exercises local env, private fixture, build output, credential artifact, and default telemetry failure cases; `perchha-smoke` also runs the same public-command audit guard for Command Line Tools evidence.
- Smoke screenshots are used for UI/UX review before completion reporting; a roadmap item that reaches completion needs a current app screenshot artifact from smoke snapshots, and the completion report must embed that screenshot before reporting it as 100%.
