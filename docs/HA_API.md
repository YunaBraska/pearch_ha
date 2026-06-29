# Home Assistant API contract - PearchHA

This document defines the Home Assistant surface PerchHA depends on and the fixture set FakeHA must mirror.

Authoritative references:

- [Home Assistant REST API](https://developers.home-assistant.io/docs/api/rest/)
- [Home Assistant WebSocket API](https://developers.home-assistant.io/docs/api/websocket/)
- [Home Assistant Authentication API](https://developers.home-assistant.io/docs/auth_api/)
- [Statistics WebSocket API change note](https://developers.home-assistant.io/blog/2023/04/30/statistics_impossible_values/)

## 1. Authentication

REST calls use:

```text
Authorization: Bearer <access-token>
```

WebSocket auth uses:

```json
{ "type": "auth", "access_token": "<access-token>" }
```

Supported input methods:

1. Long-lived access token. This is the first implementation path.
2. OAuth/IndieAuth login. This produces access and refresh tokens and normalizes to the same bearer-token API path.

Username/password is not a REST or WebSocket authentication mode. If credentials are present in `.env.local`, they are used only for the login flow or manual fixture work.

OAuth/IndieAuth uses the documented Authentication API:

| Step | Method and path | Fields |
|---|---|---|
| Authorize | `GET /auth/authorize` | `client_id`, `redirect_uri`, optional `state` |
| Exchange code | `POST /auth/token` | `grant_type=authorization_code`, `code`, `client_id` |
| Refresh access token | `POST /auth/token` | `grant_type=refresh_token`, `refresh_token`, `client_id` |
| Revoke refresh token | `POST /auth/token` | `token=<refresh-token>`, `action=revoke` |

Access-token responses must include `access_token`, `expires_in`, and `token_type=Bearer`. Code exchange must also include `refresh_token`; refresh responses may omit it. PerchHA stores the OAuth `client_id` with the refresh token because Home Assistant requires the same client ID for refresh. A `401` or WebSocket `auth_invalid` from an authenticated app-shell request triggers one access-token refresh and one retry. A failed refresh clears stored secrets and returns the user to reconnect.

Native sign-in reads the application client website and callback URI from `PERCHHA_OAUTH_CLIENT_ID` and `PERCHHA_OAUTH_REDIRECT_URI`. Exported process values win; otherwise the app reads those keys from `.env.local`, or from the exported `PERCHHA_ENV_FILE` path. The packaged `.app` must declare the callback scheme in `CFBundleURLTypes` with `CFBundleTypeRole=Viewer`; `perchha-package-app --verify-launch-services` writes that metadata, registers the generated bundle, and verifies macOS records the callback scheme claim for that bundle. The app shell accepts delivered callback URLs only when their scheme and redirect base match the configured redirect URI, and records only a redacted ingress event. The client website must publish the redirect URI according to the Home Assistant native-app registration rules before this can pass real-HA sign-in verification.

For native callback schemes such as `perchha://auth`, the application website must include a redirect declaration in the first 10kB of HTML:

```html
<link rel="redirect_uri" href="perchha://auth">
```

Run `swift run hamirror oauth-check --env .env.local` before real browser sign-in. The check reads only `PERCHHA_OAUTH_CLIENT_ID` and `PERCHHA_OAUTH_REDIRECT_URI`, verifies the public client website declaration, reports redacted setup guidance when OAuth config is incomplete, and does not send the Home Assistant token, user, or password.
Run `swift run perchha-package-app --write-oauth-site .build/perchha-oauth-site/index.html --oauth-env .env.local` to generate the static HTML artifact that should be published at the configured client website, then `swift run perchha-package-app --verify-oauth-site .build/perchha-oauth-site/index.html --oauth-env .env.local` to confirm the artifact still matches the configured website URL and redirect declaration before deployment. After publishing, run `swift run perchha-package-app --verify-published-oauth-site --oauth-env .env.local` to fetch the live client website URL and verify the deployed HTML declaration without sending Home Assistant secrets.
For releasable builds, include `--oauth-site .build/perchha-oauth-site/index.html` when writing the release manifest so the retained release evidence can re-verify the exact OAuth declaration page that was meant to be deployed.

## 2. Required documented API surface

### REST

| Method and path | Purpose |
|---|---|
| `GET /api/` | Reachability and auth smoke check. |
| `GET /api/states` | Initial full state and fallback polling. |
| `GET /api/states/<entity_id>` | Single entity verification. |
| `GET /api/history/period/<start>` | Hour/Day history. |
| `POST /api/services/<domain>/<service>` | Fallback service call path. |

### WebSocket

| Type | Purpose |
|---|---|
| `auth` | Authenticate WebSocket session. |
| `get_states` | Initial state snapshot. |
| `subscribe_events` with `event_type: state_changed` | Documented live-state fallback. |
| `call_service` | Primary control and custom action path. |
| `get_services` | Discover service metadata for custom actions. |

## 3. Supported extended API surface

These commands are useful and should be mirrored when available, but PerchHA must detect support and keep explicit fallbacks.

| Type | Purpose | Fallback |
|---|---|---|
| `subscribe_entities` | Compact live entity diff stream. | `subscribe_events` + initial `get_states`. |
| `config/entity_registry/list_for_display` | Lightweight entity display metadata. | Full state plus registry commands where available. |
| `config/area_registry/list` | Room discovery. | Entity/device area data, then `Unassigned`. |
| `config/device_registry/list` | Entity -> device -> area resolution. | Entity area or `Unassigned`. |
| `config/entity_registry/list` | Full entity registry. | `list_for_display` or states. |
| `recorder/statistics_during_period` | Week/Month history. | REST history for available retention period. |

The Home Assistant project has documented that recorder statistics WebSocket APIs may change. Treat missing columns as null and fixture drift as a contract warning, not a crash.

## 4. Entity state shape

PerchHA consumes state objects with at least:

```json
{
  "entity_id": "sensor.office_temperature",
  "state": "21.4",
  "attributes": {
    "friendly_name": "Office temperature",
    "unit_of_measurement": "°C",
    "device_class": "temperature",
    "state_class": "measurement"
  },
  "last_changed": "2026-06-27T09:00:00+00:00",
  "last_updated": "2026-06-27T09:00:00+00:00"
}
```

State values are strings. Numeric parsing uses Home Assistant's API format; display formatting uses the user's locale.

The first M3 client slice maps REST state objects into `EntityState` by reading `entity_id`, `state`, `attributes.friendly_name`, and `attributes.unit_of_measurement`. Missing friendly names fall back to the entity ID.

The WebSocket M3 slice authenticates at `/api/websocket`, validates `auth_required` -> `auth_ok`, sends `get_states` with an integer `id`, requires the matching result `id`, and maps command errors separately from transport failures.

The live-update path tries `subscribe_entities` first. Full compact states in `event.a` and partial state changes in `event.c[entity_id]["+"]` map to `EntityState`; partial changes merge with the current stream snapshot. Attribute removals in `event.c[entity_id]["-"].a` clear removed display fields, and top-level entity removals in `event.r` remove entries from that snapshot before later partial changes are considered. Removal-only frames are skipped until the next state-producing frame. If Home Assistant reports `unknown_command` or legacy `unsupported_command`, PerchHA falls back to documented `subscribe_events` with `event_type: state_changed` and maps `event.data.new_state` into `EntityState`.

The service-call slice sends WebSocket `call_service` with `domain`, `service`, optional `target.entity_id`, and arbitrary JSON `service_data`. FakeHA journals the exact redacted command payload for control and custom-action assertions.

The discovery slice sends WebSocket registry commands for areas, devices, and entities, then pairs those registry records with `get_states`. Room resolution happens in core code so registry transport and grouping rules stay separately testable.

The first history slice sends `GET /api/history/period/<start>` with `filter_entity_id`, `end_time`, `minimal_response=true`, and `no_attributes=true`. Minimal history rows may omit `entity_id`; the request-level filter is the entity boundary, and rows that still carry a different `entity_id` are discarded. Returned samples are sorted by timestamp and mapped to a string state plus a numeric value when the state parses as `Double`. Empty history is a successful empty series. Missing timestamps or malformed payloads fail as explicit invalid-payload client errors.

The recorder-statistics slice sends WebSocket `recorder/statistics_during_period` for Week and Month ranges. Requests use ISO date strings for `start_time` and `end_time`, a single `statistic_ids` entry, `types: ["mean", "state"]`, hourly buckets for Week, and daily buckets for Month. Responses are keyed by statistic ID. Row `start` values are Unix epoch milliseconds; `mean` is preferred over `state` when both are present. Missing or null numeric columns are treated as no sample, not as malformed payloads. If Home Assistant reports `unknown_command` or legacy `unsupported_command`, or if the recorder-statistics WebSocket endpoint is unreachable or TLS-rejected, PerchHA falls back to REST history for the same range. Malformed statistic rows still fail as explicit invalid-payload client errors.

## 5. Domains

V1 reads and displays any entity with a usable state.

Built-in controls:

- `cover.*`
- `switch.*`
- `light.*`
- `input_boolean.*`

Custom actions can be attached to any entity, including `sensor.*` and `binary_sensor.*`.

## 6. Service calls

Primary WebSocket shape:

```json
{
  "id": 7,
  "type": "call_service",
  "domain": "switch",
  "service": "turn_on",
  "target": { "entity_id": "switch.office_lamp" },
  "service_data": {}
}
```

Persisted custom actions wrap the service call with PerchHA row metadata:

```json
{
  "id": "boost-air",
  "entityID": "sensor.office_temperature",
  "title": "Boost air",
  "requiresConfirmation": false,
  "action": {
    "domain": "script",
    "service": "turn_on",
    "targetEntityID": "script.air_cleaner_boost",
    "serviceData": {
      "mode": "boost",
      "duration": 15
    }
  }
}
```

`requiresConfirmation`, `title`, and attached row metadata are local UI/config fields. The WebSocket transport sends only the nested action as Home Assistant `call_service` fields.

Protected custom-action values are stored in JSON as opaque protected-string references. The actual secret scalar strings live in Keychain, are resolved immediately before `call_service`, and fail explicitly if the referenced secret is missing. Documentation, logs, fixtures, and snapshots must not imply plaintext secret storage.

FakeHA must journal every received service call so tests can assert exact payloads.

The custom-action metadata slice sends WebSocket `get_services` and maps the returned domain -> service -> field metadata into typed service metadata. PerchHA preserves field examples and selectors as generic JSON values because Home Assistant selectors vary by integration.

## 7. Cover semantics

Supported services:

- `cover.open_cover`
- `cover.close_cover`
- `cover.stop_cover`
- `cover.set_cover_position`

Position payload:

```json
{ "position": 0 }
```

`current_position` drives the visible slider when present.

## 8. Mirrored fixtures

`hamirror` captures from `.env.local`, anonymizes, and writes fixtures under `Fixtures/`. `hamirror doctor --env .env.local` reports redacted key presence/status plus next-step hints, emits machine-readable readiness plus redacted guidance with `--json`, surfaces exact suggested commands when capture or OAuth checks are ready, and fails before capture in `--strict` mode when the bearer token is missing. `hamirror doctor --probe` adds a live redacted `/api/` check for primary and fallback URLs plus endpoint-specific remediation hints for transport and authorization failures. Exported `PERCHHA_ENV_FILE`, `PERCHHA_HA_URL`, `PERCHHA_HA_FALLBACK_URL`, `PERCHHA_HA_TOKEN`, `PERCHHA_HA_USER`, `PERCHHA_HA_PASSWORD`, `PERCHHA_OAUTH_CLIENT_ID`, and `PERCHHA_OAUTH_REDIRECT_URI` override the file-based values for capture and OAuth checks. The M2 foundation captures `/api/` and `/api/states`; M8 adds optional `--websocket` evidence for optimized commands. The WebSocket evidence records command availability and error codes without storing private WebSocket result payloads. `hamirror serve` replays the mirrored REST payloads and the captured command-availability surface locally; when display-list payloads were intentionally omitted for privacy, FakeHA synthesizes minimal registry rows from mirrored `states.json` so optimized discovery can still be exercised. Deterministic FakeHA tests can also record compact event top-level keys. Verification rejects stale `websocket.json` files and unknown WebSocket evidence fields, and WebSocket capture fails explicitly when HA does not answer before the receive timeout. Later milestones add services and history fixtures.

The M2 sanitizer structurally rewrites captured JSON before writing. It redacts tokens and credentials, aliases entity IDs, redacts friendly names and free-text attributes, zeros location coordinates, and normalizes timestamps.

Required fixture groups:

- Auth success and failure.
- REST API ping.
- Full state snapshot.
- WebSocket `get_states`.
- Live update stream through `subscribe_entities` if supported.
- Live update stream through `subscribe_events`.
- Area, device, and entity registry data where supported.
- REST history for at least one numeric entity.
- Recorder statistics for at least one numeric entity where supported.
- Successful and failed service calls.
- Cover state and cover service calls.
- At least one custom action attached to a sensor.
- HA restart / WebSocket reconnect sequence.
- TLS failure and unreachable host modes.

Fixtures must not contain tokens, credentials, GPS coordinates, real names, or private free text unless explicitly approved during review.

## 9. Error modes

PerchHA handles:

- REST `401`.
- WebSocket `auth_invalid`.
- DNS failure.
- Connection refused.
- TLS rejection.
- WebSocket close during session.
- Unsupported WebSocket command.
- Service result failure.
- Empty or malformed history payload.

Each mode has a visible message and a traceability row in `TESTING.md`.
