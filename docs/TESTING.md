# Testing strategy - PerchHA

## 1. Principle

Tests use real public entrypoints and real wire protocols. Normal CI never depends on a live Home Assistant instance. Live Home Assistant is used only to create or verify mirrored fixtures.

Project target gates:

- `PerchHACore` line coverage: at least 95%.
- `PerchHAClient` line coverage: at least 95%.
- Branch coverage target for core behavior: at least 90%.
- Every requirement row below has one named test.

Coverage thresholds are final readiness gates. Early milestones enforce the runnable slice they introduce, then add coverage enforcement once full-Xcode XCTest execution is available in CI.

## 2. Test layers

| Layer | Scope |
|---|---|
| Unit | Pure logic: formatting, normalization, ordering, thresholds, rate limiting, backoff, cache, clocks. |
| Contract | `PerchHAClient` against FakeHA over REST and WebSocket. |
| E2E | Actual app launched against FakeHA, driven through UI automation. |
| Snapshot | Gauges, panel, and key states in light/dark and supported locales. |
| Performance | Public-entrypoint checks for CPU, memory, launch, panel open, and request volume. |
| Drift | Opt-in real-HA check comparing current wire shapes with fixtures. |

## 2.1 Toolchain expectations

Full local verification uses Xcode, because XCTest and app bundle checks are Xcode-provided on macOS.

Command Line Tools-only environments must still pass:

```sh
swift build
swift test
swift run perchha-smoke
```

In CLT-only mode, `swift test` verifies that test targets compile. XCTest case execution is verified in CI and on machines with full Xcode selected.

## 3. `hamirror`

`hamirror` reads `.env.local`, connects to real Home Assistant, and writes anonymized fixtures.
With `--websocket`, it also records optimized WebSocket command availability without storing private command payloads. Verification rejects stale WebSocket evidence files and unknown evidence fields.

M2 foundation responsibilities:

- Capture `GET /api/` and `GET /api/states`.
- Review and redact fixtures before writing.
- Verify fixture schema, manifest consistency, and sanitizer idempotence.
- Serve a fixture set through FakeHA for local smoke checks.

Later responsibilities:

- Capture REST and WebSocket payloads beyond the M2 foundation.
- Capture service metadata and custom action examples.
- Capture live update behavior.
- Capture unavailable-command behavior.
- Verify existing fixtures against real HA on demand.

Normal implementation uses the easiest API first, then adds optimized paths when mirrors prove support.

## 4. FakeHA

FakeHA is a maintained local test server under `Tests/FakeHA`. The M2 foundation serves `/api/` and `/api/states` from mirrored fixtures and journals requests with secrets redacted.

M2 foundation implements:

- REST endpoints used by PerchHA.
- Request journaling with secrets redacted.
- WebSocket auth handshake behavior as a pure skeleton.

Later FakeHA work implements:

- WebSocket command/result behavior.
- Recorded live update streams.
- Programmable failure modes.

Programmable modes:

- `normal`
- `authInvalid`
- `unreachable`
- `tlsError`
- `restartMidSession`
- `serviceFails`
- `unavailableCommand`
- `rateLimited`
- `slowHistory`
- `malformedHistory`

## 5. Determinism

- Time behavior uses an injected clock.
- Tests advance virtual time instead of sleeping.
- FakeHA emits live updates on test command.
- UI tests wait on observable states.
- Snapshot tests pin appearance, locale, contrast, and reduced-motion settings.

## 6. Performance checks

Required repeatable checks:

- Idle CPU while connected.
- Memory over an AppKit shell lifecycle soak run.
- Cold launch time.
- Panel open time from cached state.
- Request volume during reconnect through FakeHA journal assertions.
- History hover debounce and cache hits.
- Bar item redraw frequency through injected status-item image renderer counts.

## 7. Traceability matrix

| ID | Scenario | Test | Layer |
|---|---|---|---|
| FR-1 | area/device/entity grouping including `Unassigned` | `t_discovery_grouping` | Contract |
| FR-2 | select, reorder, persist across relaunch | `t_select_reorder_persist` | Persistence; E2E pending full Xcode |
| FR-3 | live update through best supported WS path | `t_live_updates_panel_and_bar` | Contract + E2E |
| M3-REST | REST auth smoke and initial state fetch through public client | `t_rest_client_contract` | Contract |
| M3-WS | WebSocket auth and `get_states` through public client | `t_websocket_auth_and_get_states` | Contract |
| M3-SERVICE | WebSocket `call_service` journals exact payload | `t_call_service_journaled` | Contract |
| M3-PREFIX | HA base URLs with path prefixes preserve the prefix | `testRESTSmokePreservesBasePathPrefix` | Contract |
| MIRROR-PREFIX | mirrored HA base URLs with path prefixes preserve the prefix | `testMirrorCapturePreservesBasePathPrefix` | Contract |
| FAKEHA-START | FakeHA servers start on distinct ports under burst creation | `testFakeHAServersStartOnDistinctPortsUnderBurstCreation` | Contract |
| FAKEHA-BUFFER | FakeHA preserves coalesced HTTP/WebSocket tail bytes | `testFakeHAConsumesCoalescedWebSocketBytes` | Contract |
| MIRROR-ATTRIBUTES | mirrored fixtures redact unknown attribute values | `testMirrorCaptureSanitizesPrivateStatePayload` | Contract |
| M4-CONFIG | config writes are atomic and round-trip as versioned JSON | `testConfigStoreWritesAtomicallyEnoughToLeaveOneReadableJSONFile` | Unit |
| M5-SHELL | app launch wires the status item, panel, model, and cleanup path | `test_t_app_shell_launch_wires_status_item_panel_and_cleanup` | App shell |
| M5-CONNECT | first-run panel model connects against FakeHA and exposes values | `test_t_panel_model_connects_against_fakeha` | Contract + UI model |
| M5-PANEL | custom app panel is key-capable and hosts first-run content | `testAppShellPanelCanBecomeKeyForFirstRunTextEntry` | UI |
| M5-FIRST-RUN | first-run connection failures are visible in panel state | `test_t_first_run_connection_failure_states` | UI |
| M5-SECRET | panel public state never exposes access tokens | `testPublicPanelSnapshotNeverExposesAccessToken` | UI model |
| M5-FORM | non-token form edits preserve private token state and token clearing blocks connection | `test_t_non_token_form_edits_preserve_private_token_for_connection`, `testClearingTokenRemovesPrivateTokenBeforeConnect` | UI model |
| M5-CANCEL | cancelled panel actions ignore late connector results | `test_t_cancelling_panel_action_ignores_late_connection_result` | UI model |
| M5-FALLBACK | fallback URL validation fails early and valid fallback URLs reach the connector | `testInvalidFallbackURLFailsBeforeConnectionAttempt`, `test_t_fallback_url_is_forwarded_to_connector` | UI model |
| M5-REFRESH | manual refresh updates panel values | `test_t_manual_refresh_updates_panel_values` | UI |
| M6-SELECTION | searchable selection tree and selected-room ordering projection | `testSelectionProjectorBuildsSearchableCheckboxTree`, `testSelectionProjectorAppliesRoomAndEntityOrderToSelectedRooms` | Unit |
| M6-REORDER-CORE | room/entity reorder logic preserves explicit selection and ignores boundary no-ops | `testSelectionReordererMovesRoomsAndSelectionOrder`, `testSelectionReordererMovesEntitiesWithinRoom`, `testSelectionReordererLeavesBoundaryMovesUntouched`, `testSelectionReordererPlacesRoomsRelativeToDropTarget`, `testSelectionReordererPlacesEntitiesRelativeToDropTargetWithinRoom`, `testSelectionReordererIgnoresEntityDropsAcrossRooms` | Unit |
| M6-PERSIST | selected entity, room order, and entity order survive config round-trip | `test_t_select_reorder_persist` | Persistence |
| M6-PANEL | panel applies persisted selection and exposes searchable checkbox settings | `test_t_panel_applies_selection_config_to_visible_rooms`, `test_t_settings_toggle_updates_selection_and_persists` | UI model |
| M6-REORDER-PANEL | settings reorder operations update visible rows and persist order | `test_t_settings_reorders_rooms_and_entities_and_persists`, `test_t_settings_drag_reorder_places_rooms_and_entities_and_persists`, `testSelectionDropTranslatorUsesTargetRelativePlacement`, `test_t_settings_reorder_boundary_move_does_not_persist` | UI model |
| M6-APP-CONFIG | app shell loads persisted selection configuration | `test_t_app_shell_launch_loads_selection_config` | App shell |
| M6-APP-RELAUNCH | app-shell selection persistence survives relaunch with room/entity order | `test_t_app_shell_reorder_save_survives_relaunch` | App shell |
| M6-CONFIG-FAILURE | config load/save failures are visible, failed loads block overwrite saves, and failed saves reject panel changes | `test_t_app_shell_reports_config_load_failure_and_blocks_save`, `test_t_app_shell_reports_config_save_failure_without_mutating_loaded_config`, `test_t_panel_rejects_reorder_when_app_shell_save_fails`, `test_t_panel_rejects_drop_reorder_when_app_shell_save_fails`, `test_t_panel_rejects_entity_drop_reorder_when_app_shell_save_fails`, `test_t_panel_rejects_entity_move_when_app_shell_save_fails`, `test_t_panel_rejects_selection_toggle_when_app_shell_save_fails` | App shell + UI model |
| M6-STALE | reconnecting rows render stale value state | `test_t_reconnecting_rows_render_as_stale_values` | UI model |
| M6-REFRESH-FAIL | refresh failures keep last-known rows visible as stale | `test_t_refresh_failure_keeps_last_rows_visible_as_stale` | UI model |
| M6-REORDER-STALE | reordering after refresh failure preserves stale rows and stale formatting | `test_t_reordering_after_refresh_failure_keeps_rows_stale` | UI model |
| M6-CANCEL | cancelled reconnects do not report connected success | `test_t_cancelling_reconnect_does_not_mark_state_connected` | UI model |
| M6-VANISHED | vanished selected entities are removed when selection changes | `test_t_vanished_selected_ids_are_removed_when_selection_changes` | UI model |
| M7-GAUGE | percent and absolute menu bar gauges normalize and render deterministically | `test_t_gauge_rendering_humidity_battery`, `testMenuBarRendererRendersAbsoluteRingWithExplicitTotal`, `testMenuBarRendererUsesTotalEntityForAbsoluteGauges`, `testMenuBarRendererClampsPercentageGauge` | Unit + Smoke |
| M7-GAUGE-FALLBACK | non-percent values without totals render as text instead of fake gauges | `testMenuBarRendererFallsBackToTextWhenGaugeIsLocked` | Unit |
| M7-THRESHOLD | warning and critical thresholds produce explicit severity | `testMenuBarRendererAppliesThresholdSeverity` | Unit |
| M7-PROMOTE | promoted menu bar entities preserve configured order and skip missing IDs | `testMenuBarItemProjectorPromotesConfiguredEntitiesInOrder` | Unit + Smoke |
| M7-PROMOTE-REORDER | promoted menu bar item reorder persists, updates the real status item after successful save, and is blocked while settings search is active | `testMenuBarDisplayConfigurationMovesPromotedItems`, `test_t_settings_reorders_promoted_menu_bar_entities_and_persists`, `test_t_settings_search_blocks_promoted_menu_bar_reorder`, `test_t_menu_bar_reorder_settings_apply_live_and_persist`, `test_t_menu_bar_reorder_save_failure_rejects_live_status_item_change` | Unit + UI model + App shell + Smoke |
| M7-STATUS | promoted menu bar entity updates the real status item title and accessibility label from connection/live state | `test_t_app_shell_promoted_menu_bar_item_updates_from_panel_and_live_state` | App shell + Smoke |
| M7-STATUS-IMAGE | bar, battery, and ring styles draw real non-template status-item gauge images with severity colors | `test_t_status_item_gauge_image_renderer_draws_severity_colors`, `test_t_display_settings_apply_live`, `test_t_display_total_threshold_settings_apply_live` | App shell + Smoke |
| M7-LIVE-STALE | live state updates refresh entity payloads without clearing reconnecting or failed-stale status | `test_t_live_update_during_reconnect_preserves_stale_phase`, `test_t_live_update_after_refresh_failure_preserves_failed_stale_phase` | UI model + Smoke |
| M7-DISPLAY-LIVE | display settings persist and update the real status item without relaunch after successful save | `test_t_display_settings_apply_live`, `test_t_display_total_threshold_settings_apply_live`, `test_t_display_total_threshold_settings_reject_invalid_inputs` | App shell + Smoke |
| M7-DISPLAY-FAILURE | failed display setting saves do not mutate the visible status item | `test_t_display_settings_save_failure_rejects_live_status_item_change`, `test_t_display_total_threshold_save_failure_rejects_live_status_item_change` | App shell |
| M7-HISTORY-RANGE | default history range display setting persists, defaults safely for older JSON, and rolls back on failed saves | `testJSONConfigStoreDefaultsMissingHistoryRangeToHour`, `test_t_settings_updates_default_history_range_and_persists`, `test_t_settings_rejects_default_history_range_when_save_fails`, `test_t_display_settings_apply_live`, `test_t_display_settings_save_failure_rejects_live_status_item_change` | Persistence + UI model + App shell + Smoke |
| M8-DISCOVERY-OPTIMIZED | discovery prefers entity registry display-list data, falls back to full registry, and survives unavailable registry commands with states-only discovery | `test_t_discovery_uses_entity_registry_display_list_when_supported`, `test_t_discovery_falls_back_to_full_entity_registry_when_display_list_is_unknown`, `test_t_discovery_falls_back_to_states_when_registry_commands_are_unknown` | Client + FakeHA + Smoke |
| M8-LIVE-OPTIMIZED | live updates prefer compact `subscribe_entities`, merge partial compact changes and removals including cover `current_position`, fall back to documented `subscribe_events`, and expose unavailable commands explicitly | `testStateChangedEventMapsNewState`, `test_t_live_updates_merge_partial_subscribe_entities_change`, `test_t_live_updates_merge_subscribe_entities_attribute_removals`, `test_t_live_updates_clear_current_position_when_subscribe_entities_removes_it`, `test_t_live_updates_ignore_subscribe_entities_entity_removal_until_next_state`, `test_t_live_updates_wait_past_many_subscribe_entities_removals`, `test_t_live_updates_do_not_merge_partial_change_after_entity_removal`, `test_t_live_updates_fall_back_to_subscribe_events_when_subscribe_entities_is_unknown`, `test_t_live_updates_fall_back_to_subscribe_events_when_subscribe_entities_is_legacy_unsupported`, `testFakeHAWebSocketServerRejectsUnknownCommandExplicitly` | Client + FakeHA + Smoke |
| M9-REST-HISTORY | REST history fetches documented period data, accepts minimal response rows, preserves HA base paths, handles empty results, and rejects malformed payloads | `test_t_rest_history_provider_maps_and_sorts_samples`, `testRESTHistoryAcceptsMinimalResponseRowsWithoutEntityID`, `testRESTHistoryPreservesBasePathPrefixAgainstFakeHA`, `testRESTHistoryReturnsEmptySeriesForNoSamples`, `testRESTHistoryRejectsMalformedPayload` | Client + FakeHA + Smoke |
| M9-RECORDER-STATS | Week and Month history prefer `recorder/statistics_during_period`, map millisecond statistic rows, preserve HA path prefixes, treat missing numeric columns as no sample, and fall back to REST on unavailable recorder commands or unreachable WebSocket transport | `test_t_history_week_routes_to_recorder_statistics`, `testHistoryMonthRoutesToRecorderStatisticsWithDailyPeriod`, `testHistoryRecorderStatisticsPreservesBasePathPrefixAgainstFakeHA`, `testHistoryFallsBackToRESTWhenRecorderStatisticsIsUnknown`, `testHistoryRecorderStatisticsFallbackPreservesBasePathPrefixAgainstFakeHA`, `testHistoryFallsBackToRESTWhenRecorderStatisticsIsLegacyUnsupported`, `testHistoryFallsBackToRESTWhenRecorderStatisticsTransportIsUnreachable`, `testHistoryRecorderStatisticsRejectsMalformedPayload`, `testFakeHAWebSocketServerReturnsRecorderStatistics`; smoke covers week/month success, unknown-command prefixed fallback, legacy unsupported fallback, and transport-failure fallback | Client + FakeHA + Smoke |
| M9-HOVER-CACHE | history hover debounces provider calls, caches by entity/range with TTL and capacity, clears on connection changes, closes on hover-out, uses default ranges, exposes skeleton loading, no-data, and unavailable states explicitly, and routes through AppShell | `test_t_history_hover_debounces_before_provider_call`, `test_t_history_cancel_hover_resets_loading_state`, `test_t_history_load_uses_default_history_range_when_nil`, `testHistoryBodyPresentationUsesSkeletonForLoadingState`, `testHistoryLoadingSkeletonUsesChartAndStatisticsPlaceholders`, `testHistoryBodyPresentationMapsLoadedAndUnavailableStates`, `test_t_history_cache_reuses_series_until_ttl_expires`, `testHistoryCacheEvictsLeastRecentlyUsedEntryWhenCapacityIsReached`, `test_t_history_reconnect_clears_cached_series_and_visible_history`, `test_t_history_hover_out_closes_loaded_and_unavailable_popovers`, `testHistoryContentSummaryEmptySeriesIsNoNumericData`, `testHistoryContentSummaryNonNumericOnlySeriesIsNoNumericData`, `test_t_history_unavailable_state_is_explicit`, `test_t_app_shell_load_history_uses_injected_provider`; smoke covers loading skeleton state mapping; full visual snapshot pending Xcode | UI model + App shell + Smoke |
| M9-CHART-GEOMETRY | history statistics and sparklines sort numeric samples chronologically, keep valid numeric history when later rows are non-numeric, map time/value samples into deterministic normalized points, center constant series, and fall back to midline for empty, single, or non-numeric history | `testHistoryContentSummaryKeepsNumericHistoryWhenTrailingSampleIsNonNumeric`, `testHistoryContentSummaryMapsSingleNumericSampleToStatistics`, `testHistoryContentSummaryUsesLatestChronologicalNumericSample`, `testHistorySparklineGeometryMapsTimeAndValueIntoNormalizedPoints`, `testHistorySparklineGeometrySortsSamplesChronologically`, `testHistorySparklineGeometryFallsBackToMidlineWithoutEnoughNumericSamples`, `testHistorySparklineGeometryCentersConstantValuesAndSpreadsEqualTimestamps`; smoke covers mixed numeric history, unsorted input, normal geometry, and constant/equal-time chart geometry | UI model + Smoke; full visual snapshot pending Xcode |
| M10-BUILTIN-TOGGLE | switch, light, and input boolean controls derive one `ActionSpec`, run through the app-shell service-call path, optimistically update visible state, reject unsupported sensors, preserve success after stale refresh/live updates, and roll back on service failure or cancellation | `testBuiltInControlDerivesToggleActionsForSupportedDomains`, `test_t_builtin_controls_toggle_switch_optimistically_and_emit_one_action`, `test_t_action_rollback_restores_previous_state_and_shows_inline_failure`, `testBuiltInControlCancellationRollsBackOptimisticState`, `testBuiltInControlSuccessReassertsTargetStateAfterStaleRefreshDuringInFlightAction`, `testBuiltInControlSuccessReassertsTargetStateAfterStaleLiveUpdateDuringInFlightAction`, `test_t_builtin_controls_reject_sensor_without_service_call`, `testBuiltInControlUsesFakeHAServiceCallJournal`, `testAppShellRunsBuiltInControlThroughInjectedActionRunner`; smoke covers exact FakeHA toggle `call_service` payload and rollback | UI model + App shell + FakeHA + Smoke |
| M10-BUILTIN-COVER | cover controls derive open, close, stop, and set-position `ActionSpec` values, preserve `current_position`, emit one service call per UI action, update optimistically, reject covers without position support, preserve success after stale refresh/live updates, and roll back on failure or cancellation | `testBuiltInCoverControlDerivesActionsAndPosition`, `test_t_builtin_cover_open_close_stop_emit_separate_actions`, `test_t_builtin_cover_position_updates_optimistically_and_emits_position_payload`, `test_t_builtin_cover_position_rollback_restores_previous_state_and_position`, `testBuiltInCoverPositionCancellationRollsBackOptimisticPosition`, `testBuiltInCoverPositionSuccessReassertsTargetAfterStaleRefreshDuringInFlightAction`, `testBuiltInCoverPositionSuccessReassertsTargetAfterStaleLiveUpdateDuringInFlightAction`, `test_t_builtin_cover_position_rejects_cover_without_position`, `testBuiltInCoverPositionUsesFakeHAServiceCallJournal`, `testBuiltInCoverButtonsUseFakeHAServiceCallJournal`, `testAppShellRunsBuiltInCoverControlThroughInjectedActionRunner`, `testAppShellRunsBuiltInCoverButtonControlsThroughInjectedActionRunner`, `testStatesMapsFriendlyNameUnitAndMissingAttributes`, `test_t_live_updates_merge_partial_subscribe_entities_change`, `test_t_live_updates_clear_current_position_when_subscribe_entities_removes_it`; smoke covers exact FakeHA cover `call_service` payloads for position and buttons | UI model + Client + App shell + FakeHA + Smoke; full-Xcode visual/keyboard pending |
| M11-CUSTOM-ACTION | persisted custom actions attach to entity rows, settings can add/edit/delete/reorder core service fields and scalar service-data fields, metadata drives domain/service choices and scalar field defaults, orphaned actions stay visible for deletion, sensor-attached buttons emit exact service payloads, optional confirmation blocks unconfirmed execution, failures show inline errors without mutating sensor values, malformed/duplicate/protected persisted actions fail explicitly, service metadata is fetched through WebSocket `get_services`, and app-shell persistence/run/remove/reorder wiring uses the shared service-call path | `testJSONConfigStoreRoundTripsVersionedConfiguration`, `testJSONConfigStoreDefaultsMissingHistoryRangeToHour`, `testJSONConfigStoreRejectsMalformedCustomActionsOnLoad`, `testJSONConfigStoreRejectsProtectedCustomActionServiceDataOnSave`, `test_t_custom_action_service_metadata_fetches_get_services`, `testFakeHAWebSocketServerReturnsServiceMetadata`, `test_t_sensor_custom_action_attaches_to_sensor_and_emits_exact_payload`, `testCustomActionConfirmationBlocksUnconfirmedRun`, `test_t_custom_action_failure_shows_inline_error_without_changing_sensor_state`, `testCustomActionRejectsIncompleteOrUnknownEntityConfiguration`, `testCustomActionRejectsProtectedServiceDataKeys`, `testCustomActionServiceDataEditorUpdatesScalarsAndRejectsUnsafeKeys`, `testCustomActionOrphanedLoadedActionsRemainVisibleForDeletion`, `testCustomActionServiceMetadataLoadsAfterConnectAndScaffoldsDefaults`, `testCustomActionServiceMetadataFailureDoesNotFailConnection`, `testCustomActionUsesFakeHAServiceCallJournal`, `testAppShellPersistsCustomActionsAndRunsInjectedActionRunner`, `test_t_app_shell_custom_action_save_failure_rejects_live_configuration_change`, `test_t_app_shell_custom_action_remove_failure_rejects_live_configuration_change`, `test_t_app_shell_rejects_invalid_loaded_custom_action_configuration`; smoke covers exact FakeHA custom-action payloads and sensor-state preservation | Persistence + Client + UI model + App shell + FakeHA + Smoke; full-Xcode visual/keyboard pending |
| M12-OAUTH-CLIENT | OAuth/IndieAuth authorization URLs, optional state, authorization-code exchange, refresh-token grant, refresh-token revoke, invalid token payloads, inactive users, invalid request status, and transport redaction use the documented Home Assistant auth API | `testOAuthAuthorizationURLUsesOfficialAuthorizeEndpointAndEncodesNativeRedirect`, `testOAuthAuthorizationURLAllowsOmittedOptionalState`, `testOAuthAuthorizationURLRejectsInvalidInputBeforeOpeningBrowser`, `testOAuthCodeExchangePostsFormAndRequiresRefreshToken`, `testOAuthCodeExchangeRejectsTokenPayloadWithoutRefreshToken`, `testOAuthCodeExchangeRejectsWhitespaceRefreshToken`, `testOAuthCodeExchangeRejectsNonBearerTokenType`, `testOAuthCodeExchangeRejectsEmptyAccessToken`, `testOAuthCodeExchangeRejectsWhitespaceAccessToken`, `testOAuthCodeExchangeRejectsNonPositiveExpiry`, `testOAuthRefreshPostsRefreshGrantAndKeepsStoredRefreshTokenExternal`, `testOAuthRefreshInvalidRequestIsNotAuthenticationAndTransportErrorsAreRedacted`, `testOAuthTokenEndpointInactiveUserMapsToAuthentication`, `testOAuthRevokePostsRevokeActionAndAcceptsEmptyBody` | Client |
| M12-OAUTH-CLIENT-WEBSITE | native OAuth client websites declare the redirect URI in the first 10kB, same-origin redirects skip declaration fetches with normalized default ports, missing or late declarations fail, invalid inputs fail before network, and `hamirror oauth-check` verifies OAuth-only env files without sending HA secrets | `testOAuthClientWebsiteAcceptsDeclaredNativeRedirectInFirstTenKB`, `testOAuthClientWebsiteAcceptsRedirectDeclarationWithAttributesInEitherOrder`, `testOAuthClientWebsiteRejectsMissingNativeRedirectDeclaration`, `testOAuthClientWebsiteRejectsNativeRedirectDeclarationAfterFirstTenKB`, `testOAuthClientWebsiteSkipsNetworkForSameOriginRedirect`, `testOAuthClientWebsiteSkipsNetworkForExplicitDefaultHTTPSPort`, `testOAuthClientWebsiteSkipsNetworkForExplicitDefaultHTTPPort`, `testOAuthClientWebsiteRejectsInvalidInputsBeforeNetwork`, `testOAuthClientWebsiteEnvironmentParsesOAuthOnlyEnvFile`, `testOAuthClientWebsiteEnvironmentRejectsMissingOAuthKeys`; `perchha-smoke` covers success; CI runs `hamirror oauth-check` with a non-network OAuth-only same-origin fixture | Client + CLI + Smoke + CI |
| M12-OAUTH-CONFIG | native sign-in configuration loads client website and redirect URI from exported env or `.env.local`, prefers exported values including blank exported overrides and broken-file overrides, derives the callback scheme, and rejects malformed env-file lines through the real load path when file values participate | `testOAuthApplicationConfigurationLoadsFromExplicitEnvironmentFile`, `testOAuthApplicationConfigurationEnvironmentOverridesEnvironmentFile`, `testOAuthApplicationConfigurationEnvironmentOverridesMalformedEnvironmentFile`, `testOAuthApplicationConfigurationEnvironmentOverridesMissingEnvironmentFile`, `testOAuthApplicationConfigurationBlankEnvironmentValueOverridesEnvironmentFile`, `testOAuthApplicationConfigurationRejectsMalformedEnvironmentFileLine`, `testOAuthApplicationConfigurationFromEnvironmentRejectsMalformedEnvironmentFileLine`; `perchha-smoke` covers env-file loading | App shell + Smoke |
| M12-APP-BUNDLE-CALLBACK | packaged `.app` bundle declares the OAuth callback URL scheme, menu-bar-agent mode, executable layout, refuses accidental overwrites, registers with LaunchServices, records the callback scheme claim with Viewer role, and app-shell URL ingress accepts only configured OAuth redirect bases without retaining authorization code or state values | `testInfoPlistDeclaresCallbackURLSchemeAndMenuBarAgent`, `testAppBundleBuilderCreatesBundleWithExecutableInfoPlistAndPkgInfo`, `testAppBundleBuilderRefusesToOverwriteWithoutReplace`, `testManifestRejectsInvalidCallbackURLScheme`, `testLaunchServicesVerifierRegistersBundleAndClaimsCallbackScheme`, `testLaunchServicesVerifierRejectsBundleWithoutCallbackScheme`, `testLaunchServicesVerifierRejectsBundleWithoutCallbackRole`, `testLaunchServicesVerifierRejectsDumpWhenClaimBindingHasWrongRole`, `testLaunchServicesVerifierRejectsDumpWhenSchemeBindingIsMissing`, `testAppShellApplicationOpenAcceptsConfiguredOAuthCallbackWithoutRetainingSecrets`, `testAppShellExternalOAuthCallbackSurvivesColdLaunchCleanup`, `testAppShellExternalOAuthCallbackRejectsWrongScheme`, `testAppShellExternalOAuthCallbackRejectsMismatchedRedirectBase`, `testAppShellExternalOAuthCallbackRejectsWhenOAuthIsNotConfigured`; `perchha-smoke` and CI package the bundle, register it, inspect `Info.plist`, and verify callback scheme registration; `perchha-smoke` covers redacted app-shell callback ingress | Packaging + App shell + Smoke + CI; real delivered-callback/full-Xcode verification still pending |
| M12-AUTH-SESSION | OAuth access tokens, refresh tokens, and client IDs save, rotate, load, clear, reject empty values, and restore previous session state after second-operation Keychain failures | `testAuthSessionStoreSavesRotatesLoadsAndClearsTokens`, `testAuthSessionRejectsEmptyTokensBeforeWritingToKeychain`, `testAuthSessionSaveRestoresPreviousAccessTokenWhenRefreshWriteFails`, `testAuthSessionSaveRestoresFullSessionWhenClientIDWriteFails`, `testAuthSessionClearRestoresAccessTokenWhenRefreshDeleteFails`, `testAuthSessionClearRestoresFullSessionWhenClientIDDeleteFails` | Persistence |
| M12-AUTH-RECOVERY | app-shell stored OAuth sessions connect without exposing tokens, refresh expired access tokens once, retry with the rotated access token, persist the rotation, avoid retry loops when the retry still authenticates, and clear failed refresh sessions so reconnect is required | `testStoredAuthSessionConnectsWithoutVisibleToken`, `testStoredAuthSessionAuthenticationFailureRequiresReconnect`, `testAppShellRefreshesStoredOAuthSessionAndRetriesConnectionOnce`, `testAppShellClearsStoredOAuthSessionWhenRefreshFails`, `testAppShellDoesNotLoopWhenRetryAfterRefreshStillAuthenticates` | UI model + App shell + Persistence |
| M12-OAUTH-SIGNIN | native sign-in builds the authorization URL, presents the callback flow, validates callback scheme, redirect URI, and state, exchanges code for tokens, stores the first OAuth session, switches the panel to stored-session mode using the authorized form, and rejects bad callbacks without storing secrets | `testOAuthSignInCoordinatorStoresSessionFromCallback`, `testOAuthSignInCoordinatorRejectsMismatchedStateWithoutStoringSession`, `testOAuthSignInCoordinatorRejectsMismatchedCallbackSchemeWithoutStoringSession`, `testOAuthSignInCoordinatorRejectsMismatchedRedirectURIWithoutStoringSession`, `testPanelOAuthSignInSwitchesToStoredSessionAndConnects`, `testPanelOAuthSignInConnectsWithAuthorizedFormWhenFieldsChangeDuringSignIn`, `testPanelOAuthSignInFailureDoesNotStoreSessionFlag` | App shell + UI model + Persistence; full-Xcode callback and real-HA evidence pending |
| FR-4 | value formatting, stale, unavailable | `t_value_rendering_states` | Unit; E2E pending full Xcode |
| FR-5 | history ranges route to supported providers | `test_t_rest_history_provider_maps_and_sorts_samples`, `test_t_history_week_routes_to_recorder_statistics`, `testHistoryMonthRoutesToRecorderStatisticsWithDailyPeriod`, `testHistoryRecorderStatisticsPreservesBasePathPrefixAgainstFakeHA`, `testHistoryFallsBackToRESTWhenRecorderStatisticsIsUnknown`, `testHistoryRecorderStatisticsFallbackPreservesBasePathPrefixAgainstFakeHA`, `testHistoryFallsBackToRESTWhenRecorderStatisticsIsLegacyUnsupported`, `testHistoryFallsBackToRESTWhenRecorderStatisticsTransportIsUnreachable`, `test_t_history_load_uses_default_history_range_when_nil`, `testHistorySparklineGeometryMapsTimeAndValueIntoNormalizedPoints`; `t_history_ranges_and_routing` pending full-popover slice | Contract + E2E |
| FR-6 | percent and absolute gauges render correctly | `t_gauge_rendering` | Unit + Snapshot |
| FR-7 | display settings update live | `t_display_settings_apply_live` | E2E |
| FR-8 | fallback polling interval uses jitter | `t_interval_fallback_polling` | Unit + Contract |
| FR-9 | connection errors are specific | `t_connection_errors` | Contract |
| FR-9-AUTH | OAuth/IndieAuth login primitives normalize to access tokens, verify native client website readiness, keep refresh tokens and client IDs in Keychain storage with rollback on partial session-store failures, refresh/retry expired stored sessions through the app shell, verify macOS callback scheme registration for generated bundles, accept only configured external callback ingress without retaining code/state values, and create first sessions from native callback sign-in | `testOAuthCodeExchangePostsFormAndRequiresRefreshToken`, `testOAuthCodeExchangeRejectsWhitespaceRefreshToken`, `testOAuthCodeExchangeRejectsWhitespaceAccessToken`, `testOAuthClientWebsiteAcceptsDeclaredNativeRedirectInFirstTenKB`, `testOAuthClientWebsiteRejectsMissingNativeRedirectDeclaration`, `testOAuthRefreshPostsRefreshGrantAndKeepsStoredRefreshTokenExternal`, `testAuthSessionStoreSavesRotatesLoadsAndClearsTokens`, `testAuthSessionSaveRestoresPreviousAccessTokenWhenRefreshWriteFails`, `testAuthSessionSaveRestoresFullSessionWhenClientIDWriteFails`, `testAuthSessionClearRestoresAccessTokenWhenRefreshDeleteFails`, `testAuthSessionClearRestoresFullSessionWhenClientIDDeleteFails`, `testAppShellRefreshesStoredOAuthSessionAndRetriesConnectionOnce`, `testAppShellClearsStoredOAuthSessionWhenRefreshFails`, `testAppShellDoesNotLoopWhenRetryAfterRefreshStillAuthenticates`, `testLaunchServicesVerifierRegistersBundleAndClaimsCallbackScheme`, `testLaunchServicesVerifierRejectsBundleWithoutCallbackRole`, `testLaunchServicesVerifierRejectsDumpWhenClaimBindingHasWrongRole`, `testAppShellApplicationOpenAcceptsConfiguredOAuthCallbackWithoutRetainingSecrets`, `testAppShellExternalOAuthCallbackSurvivesColdLaunchCleanup`, `testAppShellExternalOAuthCallbackRejectsWrongScheme`, `testAppShellExternalOAuthCallbackRejectsMismatchedRedirectBase`, `testOAuthSignInCoordinatorStoresSessionFromCallback`, `testOAuthSignInCoordinatorRejectsMismatchedStateWithoutStoringSession`, `testOAuthSignInCoordinatorRejectsMismatchedCallbackSchemeWithoutStoringSession`, `testOAuthSignInCoordinatorRejectsMismatchedRedirectURIWithoutStoringSession`, `testPanelOAuthSignInSwitchesToStoredSessionAndConnects`, `testPanelOAuthSignInConnectsWithAuthorizedFormWhenFieldsChangeDuringSignIn` | Client + Persistence + App shell + Packaging; real delivered callback and real-HA evidence pending |
| FR-10 | built-in controls emit one service call | `test_t_builtin_controls_toggle_switch_optimistically_and_emit_one_action`, `testBuiltInControlUsesFakeHAServiceCallJournal`, `test_t_builtin_cover_open_close_stop_emit_separate_actions`, `test_t_builtin_cover_position_updates_optimistically_and_emits_position_payload`, `testBuiltInCoverPositionUsesFakeHAServiceCallJournal`, `testBuiltInCoverButtonsUseFakeHAServiceCallJournal` | E2E |
| FR-11 | custom action attached to sensor sends exact payload | `test_t_sensor_custom_action_attaches_to_sensor_and_emits_exact_payload`, `testCustomActionUsesFakeHAServiceCallJournal`, `testAppShellPersistsCustomActionsAndRunsInjectedActionRunner`, `testJSONConfigStoreRejectsMalformedCustomActionsOnLoad`, `testJSONConfigStoreRejectsProtectedCustomActionServiceDataOnSave` | UI model + App shell + FakeHA + Smoke; full-Xcode E2E pending |
| FR-12 | service failure rolls back optimistic UI or preserves non-mutated rows with a visible error | `test_t_action_rollback_restores_previous_state_and_shows_inline_failure`, `testBuiltInControlCancellationRollsBackOptimisticState`, `test_t_builtin_cover_position_rollback_restores_previous_state_and_position`, `testBuiltInCoverPositionCancellationRollsBackOptimisticPosition`, `test_t_custom_action_failure_shows_inline_error_without_changing_sensor_state`; custom-action optimistic mutation rollback pending only for later custom-action types that intentionally change visible state | E2E |
| NFR-CPU | idle CPU stays near zero after launch, discovery, and stable status-item rendering | `perchha-smoke` runs `verifyIdleCPUAtRest` with warm-up and process CPU-time budget | Smoke |
| NFR-MEM | memory stays bounded over repeated AppKit launch/connect/status-item update/termination loops backed by FakeHA WebSocket discovery | `perchha-smoke` runs `verifyApplicationLifecycleMemorySoak` with warm-up and resident-memory growth budget | Smoke |
| NFR-OPEN | panel opens from cached state under target through the public AppKit factory and SwiftUI layout/display path | `perchha-smoke` runs `verifyPanelOpenPerformance` with 150 ms median and 300 ms max budgets | Smoke |
| NFR-RATE | rate limiting, jitter, backoff, coalescing | `t_rate_limit_hygiene` | Unit |
| NFR-REQ | reconnect request volume stays bounded to one optimized discovery sequence plus one service-metadata fetch when display-list discovery is available | `test_t_reconnect_request_volume_uses_single_discovery_and_service_metadata_fetch`; `perchha-smoke` panel model FakeHA journal check | UI model + Smoke |
| NFR-REDRAW | status-item gauge images render only when image-relevant fields change; text-only items skip image rendering | `test_t_display_settings_apply_live`; `perchha-smoke` menu-bar render-count checks | App shell + Smoke |
| NFR-SEC | tokens are stored in Keychain and redacted; plaintext custom-action config rejects protected service-data keys | `t_secret_storage_and_redaction`, `testJSONConfigStoreRejectsProtectedCustomActionServiceDataOnSave`, `testCustomActionRejectsProtectedServiceDataKeys` | Unit + Contract |
| NFR-A11Y | keyboard and VoiceOver paths expose stable labels, hints, root state announcements, Reduce Motion policy, Increase Contrast policy, value/control labels, running/failure states, search-blocked reorder hints, and CLT-runnable light/dark/increased-contrast/reduced-motion panel snapshots | `test_t_accessibility_summary_reflects_empty_loading_success_and_error_states`, `test_t_accessibility_preferences_map_reduce_motion_and_increase_contrast`, `test_t_accessibility_view_root_surfaces_state_announcements_and_platform_preferences`, `test_t_accessibility_rows_expose_voiceover_labels_for_values_controls_and_failures`, `test_t_accessibility_keyboard_reorder_hints_follow_search_and_boundaries`; `perchha-smoke` runs `verifyPanelSnapshotRendering`; full-Xcode focus traversal pending | UI model + Smoke + E2E pending |
| NFR-RECOVER | HA restart reconnects and resubscribes after a post-subscription live WebSocket drop | `test_t_reconnect_after_restart_resubscribes_live_state`; `perchha-smoke` restart live subscription check | Client + FakeHA + Smoke |
| MIRROR | fixture capture redacts sensitive fields | `t_mirror_redaction` | Unit + Contract |
| MIRROR-WS | optimized WebSocket mirror evidence captures support without private payloads and fails safely on stale/private evidence or non-responsive sockets | `testMirrorCaptureRecordsOptimizedWebSocketEvidence`, `testMirrorWebSocketEvidenceCaptureTimesOutWhenServerStopsResponding`, `testFixtureWriterWritesWebSocketEvidenceWhenPresent`, `testFixtureWriterRemovesStaleWebSocketEvidenceWhenWritingRestOnlyFixtures`, `testFixtureVerifierAcceptsWebSocketEvidence`, `testFixtureVerifierRejectsWebSocketFileWithoutManifestEvidence`, `testFixtureVerifierRejectsUnknownWebSocketEvidenceFields` | Client + FakeHA + Smoke |
| DRIFT | real-HA contract drift is reported | `t_contract_drift` | Opt-in |

Add one row for every new requirement. Do not duplicate this matrix elsewhere.
