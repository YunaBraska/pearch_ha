# PerchHA

Native macOS menu bar app for Home Assistant.

PerchHA surfaces rooms, sensors, controls, history, and custom actions from Home Assistant in a fast SwiftUI/AppKit menu bar app. The target experience is calm and dense: glanceable menu bar values, an iStat-style drop-down panel, history on hover, and direct actions for the devices that matter.

## Current state

This repository has local implementation work through the native sign-in plumbing slice of `M12 - OAuth/IndieAuth sign-in`, pending production OAuth client identity, real-HA callback evidence, and full-Xcode/native UI verification.

Implemented locally:

- Git repository.
- SwiftPM package.
- Core module skeleton.
- AppKit/SwiftUI executable entrypoint.
- `hamirror` command with env parsing, token capture, fixture writing, privacy sanitization, and fixture verification.
- `hamirror capture --websocket` records optimized WebSocket command evidence without storing private WebSocket payloads.
- Framework-free smoke verifier.
- CI workflow.
- Deterministic clock, rate limiting, jitter, backoff, request coalescing, and redaction primitives.
- FakeHA REST replay foundation for `/api/` and `/api/states`.
- Public sanitized M2 fixture set under `Fixtures/public/m2-minimal`.
- M3 REST client slice for `/api/` and `/api/states` against FakeHA.
- M3 WebSocket auth and `get_states` slice against FakeHA.
- M3 WebSocket `subscribe_events` and `call_service` contract against FakeHA.
- M4 discovery models and room resolution.
- M4 WebSocket registry discovery against FakeHA.
- M4 atomic JSON config store.
- M4 Keychain-backed secret store.
- M5 custom AppKit panel hosted with SwiftUI.
- M5 menu bar app launch wiring for status item, panel, model, and cleanup.
- M5 first-run connection form and panel state model.
- M5 fallback URL validation and forwarding.
- M5 app shell panel factory smoke verification.
- M5 manual refresh path.
- M6 selection projection, ordering persistence, native move controls, target-relative drag/drop reorder translation, minimal searchable settings, app-shell config loading, config failure reporting, failed-save rejection, and value-state formatting.
- M7 menu bar value/gauge rendering model, percent and absolute normalization, threshold severity, accessible rendered labels, promotion projection, persisted promotion IDs, promoted `NSStatusItem` value/image updates from connection/live state, cached AppKit gauge images with severity colors, persisted live display settings for style, label, unit, decimals, manual totals, total-entity sources, warning/critical thresholds, default history range, plus live persisted reorder controls for promoted menu bar items.
- M8 optimized entity registry display-list discovery with fallback to full registry or states-only discovery when commands are unavailable, plus `subscribe_entities` live updates with documented `subscribe_events` fallback.
- M9 history provider for documented `/api/history/period/<start>` responses and recorder statistics Week/Month routing, plus panel hover debounce, bounded history cache, and a compact history popover with loading, loaded, and unavailable states.
- M10 built-in switch/light/input boolean toggles and cover controls through the shared `call_service` action path, with optimistic visible state, rollback, and inline failure state.
- M11 persisted custom actions attached to entity rows, including settings-side add/edit/delete/reorder for core service fields and scalar service-data fields, metadata-driven domain/service pickers and field defaults from Home Assistant `get_services`, sensor-attached buttons, optional confirmation, exact service payload preservation, malformed-config rejection, protected service-data key rejection for plaintext config, orphaned-action deletion, FakeHA journal verification, and inline failure state without mutating sensor values.
- M12 native OAuth client primitives, Keychain session storage, stored-session refresh/retry, app bundle callback URL registration verification, OAuth env loading, and redacted external callback ingress.
- M13 accessibility presentation contracts for connection/content states, keyboard hints, row values, controls, failures, Reduce Motion policy, Increase Contrast policy, and CLT-runnable panel snapshot rendering for light/dark/contrast/motion variants.
- M14 cached panel-open performance smoke measurement, idle CPU budget, AppKit lifecycle memory soak, bounded reconnect request-volume evidence, status-item gauge redraw throttling, and live WebSocket restart recovery at the public AppKit/SwiftUI and FakeHA journal boundaries.

Blocked before `M0` can be called complete:

- Full-Xcode verification of the thin app wrapper path.
- `xcodebuild` verification once Xcode is installed and selected.

Current roadmap items:

- `M11 - Custom actions`: active local slice; full-Xcode action-row visual/keyboard verification remains, plus object/array service-data editing only if service metadata proves a concrete need.
- `M13 - Accessibility and polish`: active local slice; full-Xcode focus traversal and native control verification remain.
- `M12 - OAuth and app bundle`: active local slice; production OAuth client website deployment, real callback evidence, and full-Xcode/native callback verification remain.
- `M14 - Performance and resilience`: local Command Line Tools slice complete; keep smoke gates active while full-Xcode work continues on other milestones.
- `M9 - History`: active local slice; full-Xcode history popover and chart verification remain.
- `M10 - Built-in controls`: active local slice; full-Xcode control-row visual and keyboard verification remain.
- `M8 - Optimized Home Assistant paths`: active local slice; real-HA mirror evidence for optimized WebSocket commands remains.
- `M7 - Menu bar items and gauges`: full-Xcode status-item/settings verification remains.
- `M6 - Selection, ordering, and formatting`: full-Xcode drag/UI verification remains.
- `M5 - App shell and first run`: local slice pending full-Xcode verification.

## Start here

1. Read [docs/README.md](docs/README.md) for document scope, vocabulary, and precedence.
2. Read [docs/ROADMAP.md](docs/ROADMAP.md) for the start-to-finish build plan.
3. Read [docs/PRD.md](docs/PRD.md) for requirements.
4. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before creating code.
5. Read [docs/TESTING.md](docs/TESTING.md) before adding behavior.

## Local Home Assistant config

Local real-HA access belongs in `.env.local`. It is ignored by Git.

Supported keys:

```sh
url=http://homeassistant.local:8123
url2=https://example.ui.nabu.casa
token=<long-lived-access-token>
user=<home-assistant-user>
password=<home-assistant-password>
PERCHHA_OAUTH_CLIENT_ID=<application-website-url>
PERCHHA_OAUTH_REDIRECT_URI=<native-callback-uri>
```

Bare `host:port` values are accepted and treated as `http://host:port`.

API calls use bearer access tokens. Long-lived tokens work now. OAuth/IndieAuth token exchange, native sign-in presentation, callback exchange, refresh, revoke, and stored-session recovery are implemented locally. A real OAuth client website and redirect URI must be configured with `PERCHHA_OAUTH_CLIENT_ID` and `PERCHHA_OAUTH_REDIRECT_URI`; exported process values override `.env.local`, and exported `PERCHHA_ENV_FILE` can point to another env file. Username/password keys are reserved for login-flow work and are never sent as REST or WebSocket credentials.

## Local verification

```sh
swift build
swift test
swift run perchha-smoke
swift run perchha-package-app --executable .build/debug/PerchHA --output .build/PerchHA.app --callback-scheme perchha --replace --verify-launch-services
swift run hamirror --help
swift run hamirror verify --fixtures Fixtures/public/m2-minimal
swift run hamirror oauth-check --env .env.local
swift run hamirror capture --env .env.local --output Fixtures/private/m8-real --websocket --write
```

Full XCTest execution and `xcodebuild` verification require a full Xcode installation, not only Command Line Tools.
`perchha-package-app --verify-launch-services` registers the generated app bundle in the user LaunchServices database. Remove throwaway bundles with `lsregister -u <path-to-app>`.

## Planned repo layout

```text
PerchHA/
|- Package.swift
|- PerchHA.xcodeproj        # thin app wrapper, verified with full Xcode
|- Sources/
|  |- PerchHAApp/
|  |- PerchHAUI/
|  |- PerchHACore/
|  |- PerchHAClient/
|  |- PerchHAPersistence/
|  `- PerchHASupport/
|- Tools/
|  |- hamirror/
|  `- perchha-smoke/
|- Tests/
|  |- FakeHA/
|  |- PerchHACoreTests/
|  |- PerchHAClientTests/
|  |- PerchHAPersistenceTests/
|  |- PerchHASupportTests/
|  |- PerchHAUITests/
|  `- PerchHAE2ETests/
|- Fixtures/
`- docs/
```

## Verification target

No live Home Assistant dependency in normal tests. Real HA is used only by `hamirror` to create anonymized fixtures and by opt-in contract drift checks.
