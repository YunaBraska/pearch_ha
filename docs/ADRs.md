# Architecture Decision Records - PearchHA

Format: context, decision, consequences, alternatives.

## ADR-0001 - Native macOS app

Context: PearchHA is an always-running menu bar utility and must be fast, native, and low overhead.

Decision: Build with Swift, SwiftUI, AppKit, and Swift Charts. Do not use Electron, Tauri, Java, or a web runtime.

Consequences: Best native fidelity and lowest expected overhead. macOS only.

Alternatives: Electron and Tauri were rejected because the app is a small ambient utility, not a cross-platform web shell.

## ADR-0002 - `NSStatusItem` plus custom `NSPanel`

Context: PearchHA needs multiple menu bar items, gauges, hover behavior, sliders, charts, and rich keyboard support.

Decision: Use `NSStatusItem` for menu bar items and a custom borderless `NSPanel` hosting SwiftUI for the drop-down.

Consequences: More AppKit glue, but full control over layout and interaction.

Alternatives: `MenuBarExtra` is simpler but too constrained for the full panel and independent bar widgets.

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

## ADR-0009 - Release through signed and notarized direct distribution

Context: PearchHA needs normal macOS trust behavior and may need menu bar freedoms that are awkward in the Mac App Store.

Decision: Ship a Developer ID signed and notarized app. Use a DMG for v1. Add Sparkle only after the core release path is stable.

Consequences: Direct install is viable; automatic updates are deferred until they earn the added dependency and release work.

Alternatives: Mac App Store first was deferred because sandbox and review constraints can slow this kind of utility.

## ADR-0010 - Host-scoped self-signed trust, on by default, never trust-all

Context: The dashboard-overhaul connection form briefly shipped with certificate validation disabled for every host, exposing bearer tokens to interception on any connection. Home-lab Home Assistant deployments, PearchHA's primary audience, very commonly run behind self-issued certificates, so a strict-only default breaks most first-run connections.

Decision: The self-signed allowance is a visible switch in the Settings Connection tab, on by default, persisted with the connection profile, and scoped to exactly the profile's own HTTPS hosts — the client never trusts all hosts, and hosts outside the configured addresses always get full validation. Turning it off gives strict validation everywhere. The OAuth token exchange uses the same derived policy, and profiles stored before the field decode as trusting so existing setups keep working.

Consequences: Self-signed home labs connect out of the box; the blast radius of the default is limited to the user's own configured addresses. Security-conscious users flip one switch for strict validation. Changing the trust posture counts as a connection-identity change, so caches and sessions rebuild with the new policy.

Alternatives: Trust-all was rejected as a silent security regression with unbounded scope. Strict-by-default with opt-in was implemented first but rejected as product policy because it breaks the dominant deployment. Per-certificate pinning was rejected as disproportionate for a v1 menu bar utility.

## ADR-0011 - Live updates as the primary path, polling as the safety net

Context: The product promise is glanceable, live values. The client had `subscribe_entities` support, but nothing drove it: the UI updated through a periodic refresh that paid a full connect-and-auth handshake per tick.

Decision: The panel model owns one long-lived streaming subscription per connected session (`subscribe_entities`, falling back to `subscribe_events`), applying each pushed state immediately — independent of panel visibility so menu bar items stay live. The stream reconnects with exponential backoff and resets once events flow. The periodic refresh remains only as a backstop, and the background history sync pauses while the connection is failed.

Consequences: Values update in real time over one socket instead of ~45-second polls; request volume drops. WebSocket command/auth/ack receives carry a deadline and receives honor task cancellation, so a silent or half-open server can never hang a caller.

Alternatives: Keeping polling as the primary path was rejected as contradicting FR-3 and wasting request volume. Managing the subscription in the app shell was rejected because the model owns the connection lifecycle and session identity.

## ADR-0012 - Home Assistant palette on an iStat-style layout

Context: The dashboard used a bespoke graphite/navy palette and a flat "Name Value" menu-bar title. User direction: look and behave like iStat Menus, with theme colors that read as Home Assistant.

Decision: The dashboard palettes adopt the Home Assistant theme tokens (dark `#111111`/`#1C1C1C`/`#282828`, light `#FAFAFA`/white, HA text grays, semantic trio `#4CAF50`/`#FF9800`/`#F44336`, 12pt card radius) while layout idioms come from iStat Menus/Stats: accent-colored caps section headers, min/max peak labels pinned on the history chart, a per-entity gear shortcut in the history popover, and the "Show label" menu-bar option rendering as a stacked tiny-caps-label-above-value status item instead of widening the bar with a flat title.

Consequences: One glance reads as "Home Assistant in an iStat shell". The stacked title changes the persisted-visible rendering of "Show label" (title now carries a line break); the review baseline was regenerated. Severity colors are shared between the panel, thresholds, and menu-bar gauges.

Alternatives: Cloning iStat 7's ring-heavy dropdown was rejected — its density cost is the most criticized part of iStat 7. A full theme-pack system was rejected as disproportionate; the accent stays user-configurable.
