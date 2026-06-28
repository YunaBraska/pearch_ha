# Roadmap - PerchHA

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

Done:

- `swift build` runs.
- `swift test` runs.
- `swift run perchha-smoke` runs.
- CI runs on pull requests.
- Full-Xcode app wrapper build is verified with `xcodebuild`.
- Docs match created paths.

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
- FakeHA WebSocket service-call journal entries with exact redacted command payloads.

Done:

- `t_connection_errors` passes.
- `t_websocket_auth_and_get_states` passes.
- `t_live_updates_panel_and_bar` passes at contract level.
- `t_call_service_journaled` passes.
- Service calls are journaled.

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
- `hamirror verify` rejects stale WebSocket evidence files and unknown WebSocket evidence fields.
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
- Command Line Tools smoke covers optimized display-list discovery, states-only fallback, optimized live updates, partial compact diff merging, compact removals, and live-update fallback.
- Command Line Tools smoke covers `hamirror` optimized WebSocket evidence capture and timeout behavior against FakeHA.

Remaining before M8 is complete:

- Run `hamirror capture --env .env.local --output Fixtures/private/m8-real --websocket --write` against the real Home Assistant instance and verify the ignored fixture set.

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
- Full-Xcode snapshot or visual verification for chart rendering and unavailable-history UI.

Done:

- `test_t_rest_history_provider_maps_and_sorts_samples` passes for the REST-provider slice.
- `testRESTHistoryAcceptsMinimalResponseRowsWithoutEntityID`, `testRESTHistoryPreservesBasePathPrefixAgainstFakeHA`, `testRESTHistoryReturnsEmptySeriesForNoSamples`, and `testRESTHistoryRejectsMalformedPayload` cover minimal responses, routing, empty results, and malformed payloads.
- `test_t_history_hover_debounces_before_provider_call`, `test_t_history_cancel_hover_resets_loading_state`, `test_t_history_load_uses_default_history_range_when_nil`, `testHistoryBodyPresentationUsesSkeletonForLoadingState`, `testHistoryLoadingSkeletonUsesChartAndStatisticsPlaceholders`, and `testHistoryBodyPresentationMapsLoadedAndUnavailableStates` cover hover debounce, cancellation, default range routing, skeleton loading, skeleton placeholder layout, and body presentation state mapping.
- `test_t_history_cache_reuses_series_until_ttl_expires` and `testHistoryCacheEvictsLeastRecentlyUsedEntryWhenCapacityIsReached` cover cache reuse, TTL expiry, and bounded eviction.
- `test_t_history_reconnect_clears_cached_series_and_visible_history`, `test_t_history_hover_out_closes_loaded_and_unavailable_popovers`, `testHistoryContentSummaryEmptySeriesIsNoNumericData`, `testHistoryContentSummaryNonNumericOnlySeriesIsNoNumericData`, and `testHistoryContentSummaryKeepsNumericHistoryWhenTrailingSampleIsNonNumeric` cover cache scoping, popover dismissal, no-data summaries, and mixed numeric/non-numeric summaries.
- `test_t_history_unavailable_state_is_explicit` covers disconnected and provider-unavailable history states.
- `test_t_app_shell_load_history_uses_injected_provider` covers app-shell history provider wiring.
- `test_t_history_week_routes_to_recorder_statistics`, `testHistoryMonthRoutesToRecorderStatisticsWithDailyPeriod`, `testHistoryRecorderStatisticsPreservesBasePathPrefixAgainstFakeHA`, `testHistoryFallsBackToRESTWhenRecorderStatisticsIsUnknown`, `testHistoryRecorderStatisticsFallbackPreservesBasePathPrefixAgainstFakeHA`, `testHistoryFallsBackToRESTWhenRecorderStatisticsIsLegacyUnsupported`, `testHistoryFallsBackToRESTWhenRecorderStatisticsTransportIsUnreachable`, and `testHistoryRecorderStatisticsRejectsMalformedPayload` cover recorder-statistics routing, path-prefix handling, fallback, null-column handling, transport failure, and malformed payloads.
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
- Settings exposes per-entity custom action controls for add, edit, delete, and reorder of title, domain, service, target entity, scalar `serviceData`, and confirmation.
- Settings uses fetched Home Assistant service metadata for domain/service pickers and scalar field defaults while preserving manual fallback fields when metadata is unavailable.
- Settings exposes unmatched persisted actions so stale entity attachments can be deleted instead of hidden.
- Sensor-attached action buttons run through the same injected action runner as built-in controls.
- Optional confirmation blocks execution until the caller confirms.
- Exact domain, service, target entity, and `serviceData` payloads are preserved through the FakeHA `call_service` journal.
- Failed custom actions show an inline entity-scoped error and do not mutate sensor values.
- Malformed persisted custom actions fail explicitly on load or save, including blank required fields and duplicate action IDs.
- Custom action `serviceData` stored in plaintext JSON rejects protected key names such as token, password, pin, code, and secret, including nested keys.
- `HomeAssistantClient.services` fetches Home Assistant WebSocket `get_services` metadata and FakeHA replays service metadata fixtures.
- App shell persists custom actions and exposes run/set/remove entrypoints.

Remaining before M11 is complete:

- Native object and array service-data editing, if needed after service metadata proves a concrete use case.
- Keychain-backed protected custom-action fields if secret-bearing service payloads are supported later.
- Full-Xcode visual and keyboard verification for custom action rows and confirmation.
- Native UI automation/snapshot coverage once the full app wrapper is available.

Done:

- `test_t_sensor_custom_action_attaches_to_sensor_and_emits_exact_payload` covers sensor attachment, exact action emission, and non-mutating sensor state.
- `testCustomActionConfirmationBlocksUnconfirmedRun` covers confirmation gating.
- `test_t_custom_action_failure_shows_inline_error_without_changing_sensor_state` covers failure visibility and sensor-state preservation.
- `testCustomActionRejectsIncompleteOrUnknownEntityConfiguration` covers invalid and unknown-entity configuration rejection.
- `testCustomActionRejectsProtectedServiceDataKeys` covers UI-model rejection for secret-bearing plaintext service data.
- `testCustomActionServiceDataEditorUpdatesScalarsAndRejectsUnsafeKeys` covers scalar service-data add, edit, rename, delete, duplicate-key rejection, invalid scalar-value rejection, and protected-key rejection.
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
- `PerchHAPackaging` builds a SwiftPM-driven `.app` bundle with `CFBundleURLTypes` for the OAuth callback scheme, `LSUIElement=true`, and CI/smoke coverage for generated metadata.
- `PerchHALaunchServicesVerifier` registers the generated bundle and verifies macOS records its OAuth callback scheme claim with `Viewer` role.
- `HomeAssistantClient.verifyOAuthClientWebsite` and `hamirror oauth-check` verify the production OAuth client website rule for native redirects without sending HA tokens or credentials.
- `PerchHAApplication` handles delivered external URLs, accepts only the configured OAuth callback redirect base, and stores only redacted ingress metadata so authorization codes and states are not retained.

Remaining:

- Production OAuth client website deployment using the configured redirect URI.
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
- `perchha-smoke` renders real `PerchHAPanelView` snapshots through `NSHostingView` for light, dark, increased-contrast, reduced-motion, empty, success, and error variants, then verifies stable dimensions, nonblank pixels, and distinct appearance/state hashes.

Remaining:

- Full-Xcode focus traversal and native control verification.
- Stored visual baselines for release review, if they earn the maintenance cost beyond the smoke hash gate.

Completion criteria:

- `t_accessibility` passes in CI and full-Xcode focus traversal passes.
- Snapshot suite passes for light, dark, increased-contrast, and reduced-motion variants.

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
- Sparkle update support only if it earns its complexity before release.

Done:

- Signed and notarized build artifact is produced.
- No telemetry is present by default.

## Ongoing rules

- One requirement change means one traceability update.
- New Home Assistant wire behavior means one mirror fixture update.
- New persistence, auth, or public module decision means one ADR update.
- No committed `.env.local`, tokens, credentials, or private fixture data.
