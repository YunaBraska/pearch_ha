# Architecture Decision Records - PerchHA

Format: context, decision, consequences, alternatives.

## ADR-0001 - Native macOS app

Context: PerchHA is an always-running menu bar utility and must be fast, native, and low overhead.

Decision: Build with Swift, SwiftUI, AppKit, and Swift Charts. Do not use Electron, Tauri, Java, or a web runtime.

Consequences: Best native fidelity and lowest expected overhead. macOS only.

Alternatives: Electron and Tauri were rejected because the app is a small ambient utility, not a cross-platform web shell.

## ADR-0002 - `NSStatusItem` plus custom `NSPanel`

Context: PerchHA needs multiple menu bar items, gauges, hover behavior, sliders, charts, and rich keyboard support.

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

Context: PerchHA needs normal macOS trust behavior and may need menu bar freedoms that are awkward in the Mac App Store.

Decision: Ship a Developer ID signed and notarized app. Use a DMG for v1. Add Sparkle only after the core release path is stable.

Consequences: Direct install is viable; automatic updates are deferred until they earn the added dependency and release work.

Alternatives: Mac App Store first was deferred because sandbox and review constraints can slow this kind of utility.
