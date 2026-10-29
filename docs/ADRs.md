# Architecture Decision Records - PearchHA

Format: context, decision, consequences, alternatives.

## ADR-0001 - Native macOS app

Context: PearchHA is an always-running menu bar utility and must be fast, native, and low overhead.

Decision: Build with Swift, SwiftUI, AppKit, and Swift Charts. Do not use Electron, Tauri, Java, or a web runtime.

Consequences: Best native fidelity and lowest expected overhead. macOS only.

Alternatives: Electron and Tauri were rejected because the app is a small ambient utility, not a cross-platform web shell.

## ADR-0002 - `NSStatusItem` plus native `NSPopover`

Context: PearchHA needs multiple menu bar items, gauges, sliders, charts, and keyboard support. The former nonactivating `NSPanel` could be hidden by app deactivation before the status-item action arrived. Its visibility flag then caused a close click to reopen the panel.

Decision: Use `NSStatusItem` for menu bar items and a transient `NSPopover` hosting the same SwiftUI content. AppKit owns anchoring and presentation. Explicit toggles and app deactivation close the popover, including nested control popovers. Delegate callbacks own the model's visible state. Escape returns from history before closing the root, and Cmd+, opens Settings.

Consequences: The native frame includes an anchor arrow. Content stays attached across ordinary closes to preserve scroll and expansion state. Settings and shutdown release it. Manual positioning, occlusion inference and the inactivity timer are removed.

Alternatives: `MenuBarExtra` is too constrained for independent bar widgets. Timing thresholds and extra mouse monitors would make the former panel's event ordering more fragile.

## ADR-0003 - Token-normalized Home Assistant auth

Context: Home Assistant REST and WebSocket APIs authenticate with bearer access tokens. User/password login is part of OAuth/IndieAuth, not a direct REST or WebSocket auth method.

Decision: Implement long-lived token flow first, then OAuth/IndieAuth on the official `/auth/authorize` and `/auth/token` endpoints. Normalize both paths to access tokens for API calls and store access tokens, refresh tokens, and OAuth client IDs in Keychain.

Consequences: REST and WebSocket clients keep one bearer-token contract. The app shell owns native sign-in, stored-session refresh and retry, clears secrets when refresh fails, and keeps the panel model free of secret storage concerns.

Alternatives: Sending username/password directly to REST or WebSocket APIs was rejected because it is not the API contract.

## ADR-0004 - Documented APIs first, optimized HA paths second

Context: Home Assistant's documented REST and WebSocket APIs cover the stable basics. Some useful commands, such as `subscribe_entities` and recorder statistics, are less stable or version-sensitive.

Decision: Implement documented APIs first. Add optimized paths behind support detection and mirror fixtures.

Consequences: The app works on more HA versions while still gaining performance where available.

Alternatives: Hard-depending on every optimized command was rejected because it would make fixture drift a release blocker.

## ADR-0005 - Mirror real HA into FakeHA

Context: Tests need real wire behavior without depending on a live Home Assistant instance in CI.

Decision: `hamirror` captures anonymized fixtures from real HA. FakeHA replays those fixtures over REST and WebSocket and journals requests.

Consequences: Tests remain deterministic and realistic. The mirror tool is a maintained part of the project.

Alternatives: Internal mocks were rejected because they would skip transport, parsing, and payload compatibility.

## ADR-0006 - One service-call path

Context: Built-in controls and custom actions all become Home Assistant service calls.

Decision: Model Home Assistant service calls as `ActionSpec` and execute them through one `call_service` path. Built-in UI controls produce `ActionSpec`; custom actions persist row metadata around `ActionSpec`. Protected custom-action service-data values are stored in JSON as opaque references, resolved from Keychain before `call_service`, and fail explicitly if the referenced secret is missing.

Consequences: Covers, switches, lights, scripts, shell commands, and sensor-attached buttons share one tested transport path. Custom actions with secret-bearing payloads keep JSON opaque, resolve secrets at execution time, and fail explicitly instead of pretending the secret was safely "just config."

Alternatives: Per-domain transport handlers were rejected as duplicated and harder to test.

## ADR-0007 - JSON config and Keychain secrets

Context: Display config should be inspectable and migratable. Secrets must not live in plain text.

Decision: Store non-secret config as versioned Codable JSON in Application Support. Store tokens and credential-derived secrets in Keychain.

Consequences: Config is testable and human-readable; secrets are isolated.

Alternatives: UserDefaults for all data was rejected because it is poor secret storage.

## ADR-0008 - Rate limiting and deterministic time

Context: Home Assistant often runs on small hardware. Tests must verify timing behavior without flakiness.

Decision: Use token-bucket rate limiting, jitter, capped backoff, request coalescing, debounce, and injected clocks.

Consequences: Request load is predictable and timing behavior is testable.

Alternatives: Fixed polling and wall-clock sleeps were rejected.

## ADR-0009 - Maintain separate direct and Mac App Store channels

Context: Direct downloads need Developer ID signing, notarization, and Sparkle. The Mac App Store requires a sandboxed bundle and must use Apple's update channel.

Decision: Keep the direct ZIP and DMG release unchanged. A manual Store-package workflow builds a separate sandboxed package with bundle identifier `berlin.yuna.pearchha`, without Sparkle or a GitHub update control. It is packaged and signed for validation only. Store upload follows successful sandbox testing and App Review preparation.

Both channels embed only the public OAuth client website and redirect URI in the signed bundle. Finder launches must not depend on a working-directory env file. Explicit environment overrides remain available for development. The public redirect declaration is deployed and verified separately from the app.

Consequences: One source tree supports both channels without presenting an external updater in the Store build. The Store channel needs a matching provisioning profile and real-device validation before submission. Configuration transfer is explicit through Import Settings. The original file is never moved or modified. A validated import replaces the destination atomically and quits the app, blocking pending saves until the next launch. Keychain secrets are not exported or copied. Automatic container migration was rejected because the macOS 27.0.1 runtime probe removed the source file.

Alternatives: Reusing the direct app bundle for the Store was rejected because it would retain Sparkle and two competing update channels. Replacing direct distribution with Mac App Store only was rejected because sandbox and review constraints would remove existing direct-install capabilities.

## ADR-0010 - Host-scoped self-signed trust, on by default, never trust-all

Context: The dashboard-overhaul connection form briefly shipped with certificate validation disabled for every host, exposing bearer tokens to interception on any connection. Home-lab Home Assistant deployments, PearchHA's primary audience, very commonly run behind self-issued certificates, so a strict-only default breaks most first-run connections.

Decision: The self-signed allowance is a visible switch in the Settings Connection tab, on by default, persisted with the connection profile, and scoped to the profile's own HTTPS hosts. The app never enables the client policy's explicit `trustsAllHosts` option. Hosts outside the configured addresses get full validation. Turning it off gives strict validation everywhere. The OAuth token exchange uses the same derived policy, and profiles stored before the field decode as trusting so existing setups keep working.

Consequences: Self-signed home labs connect out of the box. The blast radius of the default is limited to the user's own configured addresses. Security-conscious users flip one switch for strict validation. Changing the trust posture counts as a connection-identity change, so caches and sessions rebuild with the new policy.

Alternatives: Trust-all was rejected as a silent security regression with unbounded scope. Strict-by-default with opt-in was implemented first but rejected as product policy because it breaks the dominant deployment. Per-certificate pinning was rejected as disproportionate for a v1 menu bar utility.

## ADR-0011 - Optional live updates and demand-driven history

Context: A menu bar utility must keep background work bounded. A permanent live
subscription and eager history loading add processing even when no panel is visible.

Decision: Live Updates is off by default. When enabled, one subscription runs while
the panel is open, using `subscribe_entities` with `subscribe_events` fallback and
reconnect backoff. Timed state refresh keeps selected panel and promoted menu bar
values current while closed. Selected daily history previews warm after connection
and refresh in bounded REST batches at the data interval. Other ranges load on demand
and refresh only for the open detail.

Consequences: Closing the panel stops live updates and detail refresh. Daily previews
stay current, and cached graphs remain visible during refresh or failure. Short
WebSocket requests for discovery, controls, and statistics remain available
independently of the Live Updates preference.

Alternatives: An always-on subscription and eager loading of every history range
were replaced after resource measurements. Refresh lifecycle stays in the panel model.

## ADR-0012 - Shared Cyan surfaces and compact telemetry layout

Context: The compact telemetry layout works, but separate gray treatments made the panel, Settings and entity details feel unrelated. The current design direction is consistent Cyan with all controls and customization retained.

Decision: One adaptive palette owns the panel, Settings, inspector and control/history details. Pale Cyan and cool graphite surfaces use opaque fills, readable secondary text and the saved user accent. Semantic threshold and connection colors remain distinct. Fixed preview, value and control slots preserve alignment while history or requested-value feedback changes. Settings keeps its icon-and-label sidebar and a single connection summary. Screenshots render the production views at their real sizes. Chart min/max labels, the entity settings shortcut and the stacked menu-bar label/value option remain available.

Entity management uses a room rail, a lazy entity list with search/type/scope filters, and an independent detail pane. Narrow windows show the same inspector in place of the list. History opens inside the panel, retains the room view beneath it, and offers recorded samples to keyboard and assistive-technology users. No data, control capabilities, or refresh ownership change.

The inspector and control editor reuse the existing card surface, spacing and typography instead of maintaining separate detail styling. Panel ordering uses the same persisted room/entity order as Settings. Entity names/icons and room headings are drag handles, with menu and accessibility alternatives. Drops only reorder within the existing hierarchy and never send device commands. Invalid or cancelled drops leave the order unchanged. A native drag source owns session completion on macOS 13 and clears transient state for every outcome. Both app manifests declare the private drag data type. Room reorder actions belong to the header rather than being inherited by each entity.

Accent foregrounds resolve against the actual light/dark content and selection surfaces, targeting at least 4.5:1 contrast and 7:1 with Increase Contrast. Saved accents and custom threshold colors remain unchanged. The shared resolver replaces the blanket contrast filter. Cyan stays the default hue; an extreme custom fill can limit the maximum achievable contrast.

Reading text has a 10-point minimum. One persisted text-size preference scales real fonts from 100% to 200%, because macOS does not apply SwiftUI Dynamic Type sizing. Larger text reflows telemetry and inspector controls. The panel grows within its screen and retains scrolling. Native fields and history selectors use the same preference. The fixed-height system menu bar caps text at 18 points and combines label and value on one line at larger sizes.

Consequences: Shared surface tokens prevent visual drift between navigation and details. Opaque content removes the redundant material overlay and respects reduced transparency without a second rendering path. Severity colors remain shared between the panel, thresholds and menu-bar gauges. The stacked menu-bar title uses a line break at 100% when "Show label" is enabled. Existing configurations retain 100% text size, and partial configuration updates preserve this preference.

Alternatives: Cloning iStat 7's ring-heavy dropdown was rejected — its density cost is the most criticized part of iStat 7. A full theme-pack system was rejected as disproportionate; the accent stays user-configurable.

## ADR-0013 - Read-only local Mac source

Context: Menu-bar values should also describe the current Mac without requiring
a Home Assistant connection or private hardware APIs.

Decision: Reuse selection, formatting, gauges, thresholds and menu-bar presentation.
Stable `local-mac:` entity IDs identify their source and cannot collide with HA's
`domain.object_id` identifiers. Labels and raw state codes remain separate, with
English and German resources. The app shell reads documented Mach, IOPowerSources
and ProcessInfo APIs. The panel model owns the cancellable sampling loop and
rejects results from superseded requests. Native notification subscriptions belong
to the shell and are released with it.

Consequences: Local values work offline and survive HA reconnects and sign-out.
They are opt-in, read-only, excluded from HA requests, and never recorded to disk.
CPU requires two samples. Memory is active, wired and compressed pages as a share
of physical RAM, not memory pressure. Battery readings require an internal battery.
Thermal load is a state, not a temperature. Both packaging channels embed the same
localization bundle. App Store signing and review remain separate release gates.

Alternatives: Fake HA entities, a separate selection store, persistent local history,
private SMC access, fan control and a general plugin framework are unnecessary for
this scope.
