# PRD - PearchHA

Status: Draft v1

## 1. Goal

PerchHA is a native macOS menu bar app for Home Assistant. It provides a fast, glanceable view of rooms, sensors, history, and controls without requiring a browser tab or full Home Assistant dashboard.

The app should feel like a focused utility: always available, low overhead, readable at a glance, and safe to leave running all day.

## 2. Product scope

V1 is not a minimal prototype. V1 includes the full path from connection to release:

- Home Assistant connection and authentication.
- Room/entity discovery.
- Entity selection, display ordering, and persistence.
- Live value updates.
- Menu bar values and gauges.
- Hover history charts.
- Device controls.
- Custom service actions attached to any entity row, including sensors.
- Mirrored FakeHA test infrastructure.
- Accessibility, performance, and release packaging.

Non-goals for v1: Home Assistant automation editing, full dashboard editing, mobile apps, multi-server dashboards, energy dashboard parity, and years-long history exploration.

## 3. Personas

- Glancer: wants key values visible in the menu bar.
- Operator: opens the panel to toggle switches, move covers, or run a saved action.
- Maintainer: extends behavior while preserving tests, fixtures, and performance limits.

## 4. Functional requirements

### FR-1 Discovery and grouping

PerchHA discovers areas, devices, and entities from Home Assistant. It displays areas as rooms. Entity grouping resolves in this order:

1. Entity area.
2. Device area.
3. `Unassigned`.

Acceptance: with FakeHA serving at least 3 rooms and 12 entities, the app groups entities correctly, including `Unassigned`.

### FR-2 Selection and ordering

Settings shows a searchable room -> entity tree. Each entity has a checkbox. Checked entities appear in the panel. Rooms and entities are reorderable; order persists across relaunch.

Acceptance: checking 5 entities, reordering them, and relaunching yields exactly those 5 entities in the chosen order.

### FR-3 Live values

Live state uses WebSocket first. The easiest implementation path is:

1. Authenticate over `/api/websocket`.
2. Fetch initial state with documented `get_states`.
3. Subscribe to `state_changed` events or `subscribe_entities`, depending on availability.
4. Prefer `subscribe_entities` when the mirrored HA instance supports it because it is smaller and better for large installations.

Acceptance: FakeHA pushes a state change and the panel plus any bound bar item update without manual refresh.

### FR-4 Value rendering

Each value shows friendly name, formatted value, unit, and freshness. Unavailable or stale values render explicitly.

Acceptance: unavailable values do not render as blank or as fresh stale data.

### FR-5 History

Hovering a value opens a history popover with Hour, Day, Week, and Month ranges. Hour/Day use documented REST history first. Week/Month use recorder statistics where supported, with graceful fallback to available history.

Acceptance: switching ranges hits the expected FakeHA endpoint and renders min, average, and max where data supports it.

### FR-6 Menu bar items and gauges

Any selected value can be promoted to the menu bar. Supported display styles:

- Text.
- Bar.
- Battery.
- Ring.

Percentage entities offer all gauge styles. Absolute values can use an explicit total value or total entity to unlock gauges.

Acceptance: humidity renders as a battery gauge; an absolute sensor with a total renders as a ring.

### FR-7 Display configuration

Each displayed item supports label visibility, unit visibility, decimals, thresholds, default history range, and menu bar visibility.

Acceptance: changing display settings updates the panel and menu bar without relaunch.

### FR-8 Refresh behavior

A global update interval controls fallback polling and visible-item history prefetch. WebSocket push remains the primary live mechanism. Manual refresh is always available.

Acceptance: with WebSocket disabled, fallback polling uses the configured interval with jitter.

### FR-9 Connection

Connection settings support:

- Local URL.
- Optional remote/fallback URL.
- Long-lived access token.
- OAuth/IndieAuth login that produces access/refresh tokens.
- Optional per-host self-signed certificate allowance, off by default.

REST and WebSocket calls always use bearer access tokens. Username/password is not a REST or WebSocket auth mode.

Acceptance: bad token, unreachable host, and TLS failure produce specific user-facing errors.

### FR-10 Controls

Built-in controls:

- Covers: open, close, stop, and set position.
- Switches, lights, and input booleans: on/off.

Acceptance: each UI action emits exactly one expected service call in the FakeHA journal.

### FR-11 Custom actions

A custom action is a saved row action that wraps a Home Assistant service call:

```json
{
  "id": "boost-air",
  "entityID": "sensor.office_temperature",
  "title": "Boost air",
  "requiresConfirmation": false,
  "action": {
    "domain": "script",
    "service": "turn_on",
    "targetEntityID": "script.example",
    "serviceData": {}
  }
}
```

Custom actions can attach to any entity row, including sensors. Sensor-attached actions render as buttons and never imply that the sensor itself is writable.

Custom action configuration stores opaque protected-string references in JSON when a field needs secrecy. The actual secret scalar strings live in Keychain, are resolved before service execution, and fail explicitly if the referenced secret is missing.

Acceptance: a saved custom action sends the configured `action` payload exactly as stored.

### FR-12 Optimistic UI

Controls and custom actions may render optimistically. If Home Assistant reports failure, PerchHA rolls back visible state and shows a quiet inline error.

Acceptance: FakeHA service failure causes rollback and a visible error.

## 5. Non-functional requirements

- Idle CPU should be near zero while connected.
- Steady-state memory target is under 80 MB.
- Cold panel open target is under 150 ms to first paint from cached state.
- REST calls use rate limiting, jitter, backoff, coalescing, and hover debounce.
- Secrets are stored in Keychain only, never logged, and never implied to live in plaintext JSON.
- No telemetry by default.
- Dark and light mode are first-class.
- Full keyboard operation and useful VoiceOver labels are required.
- Network loss, HA restart, and expired tokens fail visibly and recover where possible.

## 6. Quality requirements

- Every requirement maps to a test in `TESTING.md`.
- Normal tests run against FakeHA, not a live Home Assistant instance.
- `PerchHACore` keeps at least 95% line coverage. `PerchHAClient` is held at its current measured baseline (91.56% on the full-Xcode check run) to prevent regression; raising it to the 95% goal is a tracked follow-up.
- Branch coverage target is at least 90% for core behavior.
- Real-HA drift checks are opt-in.
- Performance checks exist for core runtime paths.
