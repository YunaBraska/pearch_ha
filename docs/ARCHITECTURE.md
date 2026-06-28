# Architecture - PerchHA

## 1. Stack

- Language: Swift 6 mode where practical, Swift 5.9+ compatibility during bootstrap.
- UI: SwiftUI views hosted in AppKit.
- Menu bar: `NSStatusItem` plus custom `NSPanel`.
- Charts: Swift Charts.
- Networking: `URLSession`, `URLSessionWebSocketTask`, and standard Foundation APIs.
- Persistence: Codable JSON for non-secret config; Keychain for secrets.
- Packaging: SwiftPM-first modules with a thin Xcode app target.
- Target: macOS 13+ unless implementation proves a higher minimum is required.

No Electron, Tauri, Java runtime, or third-party HTTP client.

## 2. Modules

```text
PerchHAApp -> PerchHAUI -> PerchHACore <- PerchHAClient -> PerchHASupport
                                 ^                         ^
                                 `---- PerchHAPersistence --'
```

- `PerchHACore`: domain models, app state, formatting, normalization, ordering, thresholds, and pure behavior.
- `PerchHAClient`: Home Assistant REST/WebSocket client, auth, reconnection, decoding, service calls, history, and registry discovery.
- `PerchHASupport`: strict command-line option parsing, rate limiter, jittered scheduler, request coalescer, backoff, clock abstraction, redacted logging.
- `PerchHAPersistence`: JSON config and Keychain-backed secret storage behind protocols.
- `PerchHAUI`: SwiftUI panel, settings, gauges, charts, controls, and accessibility labels.
- `PerchHAApp`: lifecycle, status items, panel positioning, external URL ingress, app commands, and release integration.
- `PerchHAPackaging`: SwiftPM-driven `.app` bundle metadata, executable layout, OAuth callback URL scheme declaration, LaunchServices verification, code-signature creation/verification, native DMG creation/verification, notarization/stapling command orchestration, and release evidence manifests.
- `FakeHA`: local test server that mirrors Home Assistant wire behavior from fixtures.
- `hamirror`: tool that captures and verifies mirrored fixture sets from real Home Assistant.

## 3. State model

`AppStore` is the single source of truth and is isolated to the main actor.

It owns:

- `connection`: disconnected, connecting, connected, reconnecting, or failed.
- `entities`: latest entity states by entity ID.
- `rooms`: resolved area/device/entity grouping.
- `config`: selected entities, display order, bar items, actions, thresholds, interval, and theme.
- `historyCache`: bounded history data keyed by entity and range.

Mutation flow:

```text
Home Assistant event or user action
-> PerchHAClient result
-> AppStore mutation
-> immutable UI snapshot
-> SwiftUI/AppKit render
```

UI does not call Home Assistant directly.

## 4. Home Assistant data flow

### Initial load

```text
connect
-> authenticate
-> fetch config/registry/state
-> resolve rooms
-> render cached snapshot
```

The first implementation path uses documented APIs first: REST `/api/states`, WebSocket `get_states`, `call_service`, and REST history. Mirror support then records less-public but useful WebSocket commands such as `subscribe_entities`, registry display lists, and recorder statistics where the user's HA supports them.

### Live updates

```text
WebSocket subscription
-> decode state delta
-> AppStore.apply(delta)
-> panel and bar item update
```

Preferred live mechanisms:

1. `subscribe_entities` if supported by the mirrored HA version.
2. `subscribe_events` for `state_changed`.
3. Jittered REST polling only while WebSocket live updates are unavailable.

### History

```text
hover
-> debounce
-> cache lookup
-> history provider
-> chart snapshot
```

Hour and Day use documented REST history first. Week and Month use recorder statistics when supported. Unsupported history paths fail with an explicit "history unavailable" state, not an empty chart.

### Actions

```text
button/toggle/slider
-> ActionSpec
-> WebSocket call_service
-> result
-> keep optimistic state or roll back
```

All built-in controls and custom actions use one service-call path.

Persisted custom actions wrap `ActionSpec` with a stable action ID, attached entity ID, button title, and confirmation flag. Only `ActionSpec` crosses the Home Assistant transport boundary.

## 5. Concurrency

- `AppStore` mutation is main-actor only.
- Network work runs in async tasks and returns typed results.
- Long-running WebSocket reads are owned tasks with explicit cancellation.
- Time-sensitive behavior uses an injected clock.
- Tests do not rely on fixed sleeps.
- No shared mutable state outside actors or well-scoped synchronization.

## 6. Failure boundaries

Typed error categories:

- Authentication failed.
- Host unreachable.
- TLS rejected.
- WebSocket protocol error.
- Unsupported HA command.
- Service call failed.
- History unavailable.
- Fixture drift.

Every category maps to a user-facing message and at least one test.

## 7. Performance design

- No busy loops.
- No timers while WebSocket is healthy and the panel is closed.
- Bar item images are cached and redrawn only when style, gauge value, or severity changes.
- App shell launch and termination release panel, model, status item, and image cache resources under a repeated lifecycle soak.
- History cache is bounded and TTL-based.
- Identical in-flight requests are coalesced.
- REST bursts are rate limited.
- Reconnects use capped exponential backoff with jitter.

## 8. Persistence

Config path:

```text
~/Library/Application Support/PerchHA/config.json
```

Secrets:

- Access tokens.
- Refresh tokens.
- Protected custom-action service-data fields backed by opaque references in JSON and resolved from Keychain at execution time.

Secrets live in Keychain and never in JSON config, fixtures, logs, or `.env.local` snapshots. The M11 custom-action slice stores protected service-data as opaque references in JSON, resolves them before `call_service`, and fails explicitly if a referenced secret is missing.

Connection trust exceptions are transient connection-form state in the current local slice. The optional self-signed certificate allowance is off by default, scoped to the current HTTPS Home Assistant hosts, and forwarded to REST, WebSocket, and OAuth token requests.
