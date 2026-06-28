# PerchHA

Native macOS menu bar app for Home Assistant.

[![CI](https://github.com/YunaBraska/pearch_ha/actions/workflows/ci.yml/badge.svg)](https://github.com/YunaBraska/pearch_ha/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](https://developer.apple.com/macos/)

**Home** | [Docs](docs/README.md) | [Roadmap](docs/ROADMAP.md) | [Testing](docs/TESTING.md) | [Release](docs/RELEASE.md) | [Contributing](CONTRIBUTING.md)

PerchHA surfaces rooms, sensors, controls, history, and custom actions from Home Assistant in a fast SwiftUI/AppKit menu bar app. The target experience is calm and dense: glanceable menu bar values, an iStat-style drop-down panel, history on hover, and direct actions for the devices that matter.

## Current state

This repository has local implementation work across `M1` through `M15`, with `M14 - Performance and resilience` complete for the local Command Line Tools slice. Remaining blockers are production OAuth identity, real-HA callback and optimized-command evidence, Developer ID credentials/notarized release evidence, and full-Xcode/native UI verification.

Implemented locally:

- Git repository.
- SwiftPM package.
- Core module skeleton.
- AppKit/SwiftUI executable entrypoint.
- Thin Xcode app wrapper metadata with menu-bar mode, OAuth callback scheme, shared scheme, and local Swift package library product wiring.
- `hamirror` command with env parsing, token capture, fixture writing, privacy sanitization, and fixture verification.
- Shared strict CLI option parsing across repo tools so malformed commands fail explicitly instead of treating the next flag as data.
- `hamirror doctor` reports real-HA mirror readiness from redacted key presence/status plus next-step hints and suggested follow-up commands, supports scriptable JSON output, and fails strict preflight when capture is blocked.
- `perchha-xcode-doctor` reports full-Xcode native verification readiness from project/scheme presence, `xcodebuild` project listing, active developer directory, `xctest`, and `xcodebuild` availability, supports scriptable JSON output, and fails strict preflight when native verification is blocked.
- `hamirror capture --websocket` records optimized WebSocket command evidence without storing private WebSocket payloads.
- `hamirror capture --write` immediately re-verifies the written fixture set, and private fixture outputs under `Fixtures/private/` also prove they are still ignored by Git.
- `hamirror serve` replays mirrored REST and capability-aware WebSocket behavior locally, with minimal registry bodies synthesized from mirrored states when private WebSocket payloads were intentionally not captured.
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
- M5/FR-9 self-signed certificate opt-in scoped to current HTTPS Home Assistant hosts.
- M5 app shell panel factory smoke verification.
- M5 manual refresh path.
- M6 selection projection, ordering persistence, native move controls, target-relative drag/drop reorder translation, minimal searchable settings, app-shell config loading, config failure reporting, failed-save rejection, and value-state formatting.
- M7 menu bar value/gauge rendering model, percent and absolute normalization, threshold severity, accessible rendered labels, promotion projection, persisted promotion IDs, promoted `NSStatusItem` value/image updates from connection/live state, cached AppKit gauge images with severity colors, persisted live display settings for style, label, unit, decimals, manual totals, total-entity sources, warning/critical thresholds, default history range, plus live persisted reorder controls for promoted menu bar items.
- M8 optimized entity registry display-list discovery with fallback to full registry or states-only discovery when commands are unavailable, plus `subscribe_entities` live updates with documented `subscribe_events` fallback.
- M9 history provider for documented `/api/history/period/<start>` responses and recorder statistics Week/Month routing, plus panel hover debounce, bounded history cache, and a compact history popover with loading, loaded, and unavailable states.
- M10 built-in switch/light/input boolean toggles and cover controls through the shared `call_service` action path, with optimistic visible state, rollback, and inline failure state.
- M10 native built-in control panel-factory evidence for the switch class, marked cover-position slider class, and cover buttons.
- M11 persisted custom actions attached to entity rows, including settings-side add/edit/delete/reorder for core service fields and scalar/object/list service-data fields, metadata-driven domain/service pickers and field defaults from Home Assistant `get_services`, sensor-attached buttons, optional confirmation, exact nested service payload preservation, real settings-editor text-field mutation coverage plus CLT popup-presence/model-mutation coverage for metadata-driven service/type changes, malformed-config rejection, protected service-data values stored as opaque Keychain-backed references in JSON, orphaned-action deletion, FakeHA journal verification, and inline failure state without mutating sensor values.
- M12 native OAuth client primitives, Keychain session storage, stored-session refresh/retry, app bundle callback URL registration verification, OAuth env loading, deployable OAuth client-website artifact generation/verification, published-site verification, and redacted external callback ingress.
- M13 accessibility presentation contracts for connection/content states, keyboard hints, row values, controls, failures, Reduce Motion policy, Increase Contrast policy, native first-run focus verification plus a custom-action editor text-field focus path and metadata popup verification, CLT-runnable panel snapshot rendering for light/dark/contrast/motion variants, and a checked-in release-review baseline manifest for screenshot drift review.
- M14 cached panel-open performance smoke measurement, idle CPU budget, AppKit lifecycle memory soak, bounded reconnect request-volume evidence, status-item gauge redraw throttling, and live WebSocket restart recovery at the public AppKit/SwiftUI and FakeHA journal boundaries.
- Full-Xcode CI coverage gate for `PerchHACore` and `PerchHAClient` through LLVM coverage JSON.
- M15 native app signing and signature verification, Developer ID/notary preflight, `notarytool`/stapler command support, release evidence manifests and verification, and DMG packaging through `hdiutil`, with app staging, mounted content verification, Applications shortcut, overwrite refusal, smoke coverage, and CI traceability.
- Manual GitHub Actions release workflow for branch-test local evidence and credentialed main-branch release packaging.
- `perchha-package-app --release-preflight` reports redacted readiness, next-step hints, and suggested credentialed-release commands in both human and JSON output.
- Repository safety audit for local env files, private fixtures, build output, credential artifacts, and default telemetry SDKs/endpoints.

Blocked before `M0` can be called complete:

- Full-Xcode build verification of `PerchHA.xcodeproj` once Xcode is installed and selected.

Current roadmap items:

- `M11 - Custom actions`: active local slice; scalar/object/list service-data editing is locally integrated, and full-Xcode action-row visual/keyboard verification remains.
- `M13 - Accessibility and polish`: active local slice; checked-in smoke review baselines, native first-run focus checks, and a custom-action editor text-field focus path are integrated, and full-Xcode execution of those focus checks remains.
- `M12 - OAuth and app bundle`: active local slice; deployable OAuth client-website generation is locally integrated, and published hosting, real callback evidence, and full-Xcode/native callback verification remain.
- `M15 - Release packaging`: active local slice; ad-hoc signing, signature verification, Developer ID/notary preflight, notary command support, release checklist, evidence manifest, updater deferral, and DMG packaging are locally integrated; Developer ID credentialed signing and notarized release evidence remain.
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

Exported overrides for `hamirror` and OAuth-capable app-shell paths:

```sh
PERCHHA_ENV_FILE=/absolute/path/to/another.env
PERCHHA_HA_URL=http://homeassistant.local:8123
PERCHHA_HA_FALLBACK_URL=https://example.ui.nabu.casa
PERCHHA_HA_TOKEN=<long-lived-access-token>
PERCHHA_HA_USER=<home-assistant-user>
PERCHHA_HA_PASSWORD=<home-assistant-password>
PERCHHA_OAUTH_CLIENT_ID=<application-website-url>
PERCHHA_OAUTH_REDIRECT_URI=<native-callback-uri>
```

API calls use bearer access tokens. Long-lived tokens work now. OAuth/IndieAuth token exchange, native sign-in presentation, callback exchange, refresh, revoke, and stored-session recovery are implemented locally. Exported process values override `.env.local`, and exported `PERCHHA_ENV_FILE` can point to another env file. Username/password keys are reserved for login-flow work and are never sent as REST or WebSocket credentials.

## Local verification

Command Line Tools can build the package and run smoke gates:

```sh
swift build -Xswiftc -warnings-as-errors
swift test -Xswiftc -warnings-as-errors
swift run perchha-repo-audit
swift build -c release
PERCHHA_SMOKE_SNAPSHOT_DIR=.build/perchha-snapshots swift run perchha-smoke
PERCHHA_SMOKE_SNAPSHOT_DIR=.build/perchha-snapshots swift run perchha-smoke --repeat 5
swift run perchha-package-app --executable .build/release/PerchHA --output .build/PerchHA.app --callback-scheme perchha --replace --verify-launch-services --sign-ad-hoc --verify-signature --package-dmg --verify-dmg --verify-dmg-contents --release-manifest .build/perchha-release-manifest.json --bundle-release-evidence .build/perchha-release-evidence --oauth-site .build/perchha-oauth-site/index.html --snapshot-dir .build/perchha-snapshots/current
swift run perchha-package-app --verify-release-manifest .build/perchha-release-manifest.json
swift run perchha-package-app --write-oauth-site .build/perchha-oauth-site/index.html --oauth-env .env.local
swift run perchha-package-app --verify-oauth-site .build/perchha-oauth-site/index.html --oauth-env .env.local
swift run perchha-package-app --verify-published-oauth-site --oauth-env .env.local
swift run hamirror --help
swift run hamirror verify --fixtures Fixtures/public/m2-minimal
swift run hamirror doctor --env .env.local
swift run hamirror doctor --env .env.local --json
swift run hamirror doctor --env .env.local --probe
swift run hamirror doctor --env .env.local --strict
swift run hamirror oauth-check --env .env.local   # reports redacted guidance when OAuth vars are missing
swift run hamirror capture --env .env.local --output Fixtures/private/m8-real --websocket --write
swift run hamirror serve --fixtures Fixtures/public/m2-minimal --token fake-token
swift run perchha-xcode-doctor --json
```

Full XCTest execution, coverage, and `xcodebuild` verification require a full Xcode installation, not only Command Line Tools:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
swift run perchha-xcode-doctor --json --strict
xcrun --find xctest
swift test --disable-swift-testing --enable-xctest list
swift test --disable-swift-testing --enable-xctest -Xswiftc -warnings-as-errors --enable-code-coverage
coverage_path="$(swift test --disable-swift-testing --enable-xctest --enable-code-coverage --show-codecov-path | tail -n 1)"
swift run perchha-coverage-check --coverage-json "$coverage_path" --line-target PerchHACore=95 --line-target PerchHAClient=95 --branch-target PerchHACore=90
xcodebuild -project PerchHA.xcodeproj -scheme PerchHA -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

`perchha-package-app --verify-launch-services` registers the generated app bundle in the user LaunchServices database. Remove throwaway bundles with `lsregister -u <path-to-app>`.
When `PERCHHA_SMOKE_SNAPSHOT_DIR` is set, smoke screenshots are written under `.build/perchha-snapshots/current/`.
Use `swift run perchha-smoke --repeat <count>` when you want the public smoke entrypoint to stress-run the full suite as fresh process invocations for drift or flake hunting.
Release evidence manifests store relative artifact paths when possible, so the manifest stays verifiable after relocation as long as the app, DMG, and `perchha-snapshots/current/` tree keep the same layout beside it.
Smoke also compares rendered panel screenshot signatures and the contact-sheet signature against `docs/release-review-baseline.json`; when an intentional UI change is approved, refresh that baseline with `swift run perchha-smoke --update-review-baseline`.

## Repo layout

```text
PerchHA/
|- Package.swift
|- PerchHA.xcodeproj        # thin app wrapper; full build requires Xcode
|- Xcode/
|  `- PerchHA/
|- Sources/
|  |- PerchHAApp/
|  |- PerchHAUI/
|  |- PerchHACore/
|  |- PerchHAClient/
|  |- PerchHAPersistence/
|  |- PerchHAPackaging/
|  |- PerchHASupport/
|  |- PerchHACoverageCheck/
|  `- PerchHARepoAudit/
|- Tools/
|  |- hamirror/
|  |- perchha-smoke/
|  |- perchha-package-app/
|  |- perchha-coverage-check/
|  |- perchha-xcode-doctor/
|  `- perchha-repo-audit/
|- Tests/
|  |- FakeHA/
|  |- PerchHACoreTests/
|  |- PerchHAClientTests/
|  |- PerchHAPersistenceTests/
|  |- PerchHAPackagingTests/
|  |- PerchHASupportTests/
|  |- PerchHAUITests/
|  |- PerchHACoverageCheckTests/
|  `- PerchHARepoAuditTests/
|- Fixtures/
`- docs/
```

## Verification target

No live Home Assistant dependency in normal tests. Real HA is used only by `hamirror` to create anonymized fixtures and by opt-in contract drift checks.
