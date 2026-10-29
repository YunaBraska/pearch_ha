# Home Assistant API contract - PearchHA

This document defines the Home Assistant surface PearchHA depends on and the fixture set FakeHA must mirror.

Authoritative references:

- [Home Assistant REST API](https://developers.home-assistant.io/docs/api/rest/)
- [Home Assistant WebSocket API](https://developers.home-assistant.io/docs/api/websocket/)
- [Home Assistant Authentication API](https://developers.home-assistant.io/docs/auth_api/)
- [Statistics WebSocket API change note](https://developers.home-assistant.io/blog/2023/04/30/statistics_impossible_values/)

## Authentication

REST uses `Authorization: Bearer <access-token>`. WebSocket authenticates with
`{"type":"auth","access_token":"<access-token>"}` and requires `auth_ok`.
Long-lived tokens and OAuth sessions share this bearer-token contract.
Username/password credentials are not sent to REST or WebSocket API calls.

| OAuth step | Endpoint | Fields |
| --- | --- | --- |
| Authorize | `GET /auth/authorize` | `client_id`, `redirect_uri`, `state` |
| Exchange | `POST /auth/token` | `grant_type=authorization_code`, `code`, `client_id` |
| Refresh | `POST /auth/token` | `grant_type=refresh_token`, `refresh_token`, `client_id` |

Token responses require `access_token`, `expires_in`, and `token_type=Bearer`.
Code exchange also requires `refresh_token`. Keychain stores the session and client
ID. Authentication failure triggers one refresh and one retry. Failed refresh
clears the stored session and requires reconnecting.

Installed apps read the public application client website and callback URI from
`PEARCHHA_OAUTH_CLIENT_ID` and `PEARCHHA_OAUTH_REDIRECT_URI` in `Info.plist`, so
Finder launches do not require a shell environment. Explicit process values or
`PEARCHHA_ENV_FILE` retain the development override. Only unbundled development
runs fall back to a relative `.env.local` file.

For direct bundles, export both public values during packaging or pass
`pearchha-package-app --oauth-env <local-env-file>`. Only those two fields are
embedded. Tokens and other env-file contents are never bundled. The Store
packaging script uses the same package tool and embeds both values when exported.
Unconfigured local builds can continue to use token sign-in.

The packaged `.app` must declare the callback scheme in `CFBundleURLTypes` with
`CFBundleTypeRole=Viewer`. Packaging and runtime reject a bundled redirect whose
scheme is not declared. `pearchha-package-app --verify-launch-services` registers
the generated bundle and verifies macOS records the scheme claim. The app shell
accepts delivered callback URLs only when their scheme and redirect base match
the configured redirect URI, and records only a redacted ingress event. The
client website must publish the redirect URI according to the Home Assistant
native-app registration rules before real-HA sign-in verification.

For native callback schemes such as `pearchha://auth`, the application website must include a redirect declaration in the first 10kB of HTML:

```html
<link rel="redirect_uri" href="pearchha://auth">
```

Run `swift run hamirror oauth-check --env <local-env-file>` before real browser sign-in. The check reads only `PEARCHHA_OAUTH_CLIENT_ID` and `PEARCHHA_OAUTH_REDIRECT_URI`, verifies the public client website declaration, reports redacted setup guidance when OAuth config is incomplete, and does not send the Home Assistant token, user, or password.
Run `swift run pearchha-package-app --write-oauth-site .build/pearchha-oauth-site/index.html --oauth-env <local-env-file>` to generate the static HTML artifact that should be published at the configured client website, then `swift run pearchha-package-app --verify-oauth-site .build/pearchha-oauth-site/index.html --oauth-env <local-env-file>` to confirm the artifact still matches the configured website URL and redirect declaration before deployment. After publishing, run `swift run pearchha-package-app --verify-published-oauth-site --oauth-env <local-env-file>` to fetch the live client website URL and verify the deployed HTML declaration without sending Home Assistant secrets.
For releasable builds, include `--oauth-site .build/pearchha-oauth-site/index.html` when writing the release manifest so the retained release evidence can re-verify the exact OAuth declaration page that was meant to be deployed.

## Transport and state

Disabling Live Updates disables the persistent subscription. Discovery, service
metadata, controls, and recorder statistics still use short WebSocket sessions.
There is no REST service-call fallback in the current client.

| Request | Purpose and fallback |
| --- | --- |
| REST `GET /api/` | Reachability/auth check |
| REST `GET /api/states` | Full state API |
| WebSocket `get_states` | Discovery snapshot and event-stream baseline |
| `config/area_registry/list`, `config/device_registry/list` | Room/device metadata. Unsupported registries contribute no records. |
| `config/entity_registry/list_for_display` | Entity metadata, falling back to `config/entity_registry/list` |
| `subscribe_entities` | Compact live stream, falling back to `subscribe_events` with `state_changed` |
| `get_services` | Domain/service/field metadata for custom actions |
| `call_service` | Built-in controls and custom actions |
| REST `GET /api/history/period/<start>` | Hour/day history and recorder fallback |
| `recorder/statistics_during_period` | Week/month statistics |

State objects require `entity_id` and a string `state`. Display fields come from
`attributes.friendly_name`, `unit_of_measurement`, and `current_position`. Missing
names fall back to the entity ID. Only attributes used by controls are retained.
Numeric parsing follows the API format. Display formatting uses the user's locale.

Compact additions in `event.a` replace state. Changes in `event.c[id]["+"]` merge
with it. Attribute removals in `event.c[id]["-"].a` clear only named attributes,
and `event.r` removes entities from the stream snapshot. Removal-only frames are
skipped until a state-producing frame arrives. Full `state_changed` events replace
capabilities, preventing obsolete options from surviving a full update.

WebSocket replies must match the command ID. Unsupported commands, auth rejection,
transport/TLS failures, service failures, and invalid payloads remain distinct.
`unknown_command` and `unsupported_command` activate documented fallbacks. Ordered
address fallback retries transport failures, not authentication or malformed data.

## History

REST requests set `filter_entity_id`, `end_time`, `minimal_response=true`, and
`no_attributes=true`. Minimal rows may omit the entity ID. Explicit mismatched IDs
are discarded. Samples are sorted by timestamp. Empty history is a successful
empty series. Missing timestamps or malformed payloads fail explicitly.

Week/month requests use `recorder/statistics_during_period` with `types: ["mean",
"state"]`, hourly buckets for week and daily buckets for month. Results are keyed
by statistic ID. Timestamps use Unix epoch milliseconds. `mean` takes precedence
over `state`. Missing/null numeric columns contribute no sample. Unsupported
commands or unreachable/TLS-rejected statistics sessions fall back to REST for
the same range, subject to HA retention. Malformed statistics still fail.

Preview and detail refresh scheduling is defined in [ARCHITECTURE.md](ARCHITECTURE.md).
Climate history records the operating mode. Temperature attributes are excluded
by `no_attributes=true` and need a separate sensor for a numeric temperature graph.

## Domains

V1 reads and displays any entity with a usable state.

Built-in controls are shown for selected entities in the panel. A single setting is
edited directly in its row: choices use a dropdown, numbers use a borderless editable
value and an optional stepper, booleans use a switch, and actions use a named button.
Position, brightness, fan speed and volume use a slider with a quiet value. Clicking
that value reveals precise numeric entry. Sliders have no additional stepper and
commit on release. Requested values, including choices and switches, remain visible
with a small clock and tooltip until Home Assistant next reports that value, even
if it differs from the request. Service acceptance alone does not clear this status.
An off light displays zero brightness, including when HA clears its brightness attribute.
The status space stays reserved so pending feedback does not move the controls.
Failures clear rejected requests. No extra polling is started.
Multiple settings open an editor from the value marked with a slider icon. Existing on/off
switches and cover controls remain inline. Tooltips list the domain and available
settings, options and numeric bounds. All controls use Home Assistant's current
feature flags, options and numeric bounds:

| Domain | Native controls |
| --- | --- |
| `switch`, `input_boolean` | On/off toggle |
| `cover` | Open, stop, close, position |
| `climate` | HVAC mode, target temperature or range, humidity, fan, preset, swing, power |
| `number`, `select` | Bounded value with step validation, advertised options |
| `light` | Toggle, brightness, color temperature, RGB color, effect |
| `fan` | Power, speed, preset, oscillation, direction |
| `scene`, `button` | Activate, press with confirmation |
| `automation` | Enable, disable, run actions with conditions respected |
| `media_player` | Power, playback/track controls, volume/mute, source, sound mode, shuffle, repeat |
| `update` | Install, skip, clear skipped version with confirmation |
| `notify` | Send an explicitly entered message |

Unsupported features and empty option lists are omitted. Unavailable entities cannot
be controlled. Stateless scenes, buttons and notification entities can still operate
when their state is `unknown`. Numeric fields and steppers share a 600 ms trailing
debounce in both the panel and popup. Return applies immediately and cancels the
pending timer. Escape discards an unsent edit. Invalid and unchanged values are not
sent. Live readings do not replace a focused or pending numeric draft. Color edits use Set.
Buttons, update actions, and automation disable/manual execution require confirmation.
Disabling an automation leaves already running actions alone.

History opens by clicking its preview. Read-only values have no editing symbol.

Capabilities survive REST discovery, WebSocket snapshots, compact updates and attribute
removals. Commands are revalidated against the latest capabilities before dispatch.
Capability-derived commands refresh reported state after success. Failed refreshes
leave a stale-state warning. Existing toggles and covers retain optimistic state
updates with rollback on service failure or cancellation.

`sensor` and `binary_sensor` are read-only domains. Custom actions can be attached to any
entity, including those domains. Advanced media browsing, seeking and arbitrary media
URLs, vendor-specific actions, and domains not listed above still use custom actions.

## Service calls

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

Custom actions persist an `EntityCustomAction` around the same `ActionSpec`.
Their title, attached row, and confirmation flag are local UI/config fields. Only
the nested action becomes the service payload. Protected scalar strings are opaque
references in JSON and resolve from Keychain before execution. Missing references
fail explicitly. FakeHA journals redacted payloads for exact command assertions.

The custom-action metadata slice sends WebSocket `get_services` and maps the returned domain -> service -> field metadata into typed service metadata. PearchHA preserves field examples and selectors as generic JSON values because Home Assistant selectors vary by integration.

Cover actions use `open_cover`, `close_cover`, `stop_cover`, and
`set_cover_position` with an integer `position` from 0 to 100. A reported `current_position`
enables the position slider. The buttons/slider/both preference remains supported.
Open, Stop, and Close cancel pending numeric edits before dispatch so a delayed
position cannot restart movement. Numeric editing follows the shared control rules
above.

## Mirrored fixtures

`hamirror` captures `/api/` and `/api/states` from ignored local configuration,
sanitizes them, and writes reviewable fixtures. `--websocket` also records optimized
command availability and error codes without retaining private result payloads.
Services, history, live events, and failure scenarios are supplied by FakeHA tests.

```sh
swift run hamirror doctor --env <local-env-file> --json --strict
swift run hamirror doctor --env <local-env-file> --probe
swift run hamirror verify --fixtures Fixtures/public/m2-minimal
```

Exported `PEARCHHA_ENV_FILE`, HA URL/fallback/token/user/password, and OAuth
client/redirect variables override file values. `doctor` reports presence and
redacted remediation, never credentials. `--probe` checks configured endpoints.
Use CLI `--help` for capture and replay options.

The sanitizer aliases entity IDs, redacts credentials, names and free text, zeros
location coordinates, and normalizes timestamps. Follow the [privacy rules](../Fixtures/README.md).
Verification rejects stale or unknown WebSocket evidence. Capture has a receive
deadline and honors cancellation. Replay synthesizes minimal registry rows from
sanitized states when private registry payloads were omitted.

The [verification contract](TESTING.md) owns test commands and evidence limits.
