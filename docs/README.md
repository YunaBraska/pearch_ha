# PerchHA docs

This directory is the project contract. Keep it small, linked, and current.

## Document map

| File | Purpose |
|---|---|
| [PRD.md](PRD.md) | Product scope, requirements, and acceptance criteria. |
| [ROADMAP.md](ROADMAP.md) | End-to-end implementation sequence and definition of done. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Stack, modules, data flow, state, and failure boundaries. |
| [HA_API.md](HA_API.md) | Home Assistant API contract and mirror fixture checklist. |
| [TESTING.md](TESTING.md) | Test strategy, FakeHA behavior, coverage gates, and traceability matrix. |
| [UX.md](UX.md) | User-facing surfaces, layout, interactions, and accessibility. |
| [ADRs.md](ADRs.md) | Binding technical decisions and rejected alternatives. |
| [RELEASE.md](RELEASE.md) | Release checklist, evidence manifest, and credentialed packaging commands. |

## Precedence

When documents disagree:

1. `ADRs.md` wins for accepted technical decisions.
2. `PRD.md` wins for product behavior.
3. `HA_API.md` wins for Home Assistant wire behavior.
4. `TESTING.md` wins for verification and traceability.
5. `ARCHITECTURE.md` and `UX.md` describe how the behavior is built.
6. `ROADMAP.md` describes order, not scope.

Fix contradictions by updating the source document and linking from the others. Do not duplicate large tables or decisions.

## Vocabulary

| Term | Meaning |
|---|---|
| Area | Home Assistant's room/grouping concept. |
| Room | User-facing word for an area in PerchHA. |
| Device | Home Assistant device associated with one or more entities. |
| Entity | A Home Assistant state object such as `sensor.office_temperature` or `cover.bedroom_blinds`. |
| Bar item | A macOS menu bar value or gauge owned by PerchHA. |
| Custom action | Saved Home Assistant service call that can be attached to any entity row, including sensors. |
| Mirror | An anonymized fixture set captured from a real Home Assistant instance. |
| FakeHA | Local test server that replays mirrored fixtures over REST and WebSocket. |
| `hamirror` | Tool that captures, anonymizes, verifies, and can serve mirrored HA fixtures. |

## Local inputs

`.env.local` is ignored and may contain real Home Assistant access data:

```sh
url=
url2=
token=
user=
password=
PERCHHA_OAUTH_CLIENT_ID=
PERCHHA_OAUTH_REDIRECT_URI=
```

Bare `host:port` values are accepted and treated as `http://host:port`.

Exported overrides:

```sh
PERCHHA_ENV_FILE=
PERCHHA_HA_URL=
PERCHHA_HA_FALLBACK_URL=
PERCHHA_HA_TOKEN=
PERCHHA_HA_USER=
PERCHHA_HA_PASSWORD=
PERCHHA_OAUTH_CLIENT_ID=
PERCHHA_OAUTH_REDIRECT_URI=
```

Use `token` first because Home Assistant REST and WebSocket APIs ultimately authenticate with bearer access tokens. OAuth/IndieAuth sign-in uses `PERCHHA_OAUTH_CLIENT_ID` and `PERCHHA_OAUTH_REDIRECT_URI` for the native callback flow. Exported values override `.env.local`; exported `PERCHHA_ENV_FILE` can point to another env file. `user` and `password` are only for login-flow work or manual fixture work; they are never sent as Basic auth to the REST or WebSocket APIs.

Run `swift run hamirror doctor --env .env.local` before mirror capture. It reports redacted key presence/status, next-step hints when capture is blocked, and exact suggested commands when capture or OAuth checks are ready. Use `--probe` to perform a live redacted `/api/` probe against the configured primary and fallback Home Assistant URLs with endpoint-specific remediation hints, `--json` for scriptable presence/status output, and `--strict` when a script should fail unless `token` is present for REST and WebSocket capture. Run `swift run hamirror oauth-check --env .env.local` to verify the OAuth client website and redirect declaration before native sign-in; when OAuth config is incomplete, it fails with redacted setup guidance instead of echoing secrets.
`hamirror capture` uses `url` first and retries `url2` when the primary `/api/` capture endpoint fails, so the mirrored fixture path can follow the same fallback host shape the app already supports.
Run `swift run perchha-package-app --write-oauth-site .build/perchha-oauth-site/index.html --oauth-env .env.local` to generate the deployable OAuth client-website HTML artifact from the same OAuth env values, then `swift run perchha-package-app --verify-oauth-site .build/perchha-oauth-site/index.html --oauth-env .env.local` to confirm the checked artifact still matches the configured client website and redirect URI. After publishing that HTML, run `swift run perchha-package-app --verify-published-oauth-site --oauth-env .env.local` to verify the live client website URL now serves the required redirect declaration.
When you produce a release evidence manifest, pass `--oauth-site .build/perchha-oauth-site/index.html` so the retained release bundle records and re-verifies the exact OAuth client-website artifact alongside the app, DMG, and smoke screenshots.
Run `swift run hamirror serve --fixtures Fixtures/public/m2-minimal --token fake-token` to replay mirrored REST plus capability-aware WebSocket behavior locally. Add `--path-prefix /ha` when you need a prefixed test base URL.
Run `swift run perchha-xcode-doctor --json` to see whether the checked-in Xcode project, shared scheme, `xcodebuild` project listing, active developer directory, discovered Xcode developer directories, local `DEVELOPER_DIR` overrides, Xcode license acceptance, `xctest`, and `xcodebuild` are ready for native verification. Add `--strict` when a script or CI step should fail unless the full-Xcode path is actually usable.

Run `swift build -c release` and then `swift run perchha-package-app --executable .build/release/PerchHA --output .build/PerchHA.app --callback-scheme perchha --replace --verify-launch-services --sign-ad-hoc --verify-signature --package-dmg --verify-dmg --verify-dmg-contents --release-manifest .build/perchha-release-manifest.json --bundle-release-evidence .build/perchha-release-evidence --oauth-site .build/perchha-oauth-site/index.html --snapshot-dir .build/perchha-snapshots/current` to verify the generated app bundle records the native callback claim with LaunchServices, signs locally, produces a verified DMG with the expected drag-install layout, and writes portable release evidence. Re-check retained evidence with `swift run perchha-package-app --verify-release-manifest .build/perchha-release-manifest.json`; [RELEASE.md](RELEASE.md) lists the full required screenshot gate. This registers the bundle in the user LaunchServices database; unregister throwaway bundles with `lsregister -u <path-to-app>`. This is not a full GUI callback-delivery test.

## Update policy

- New product behavior: update `PRD.md`, then `TESTING.md`.
- New public API or persistence decision: update `ADRs.md`.
- New Home Assistant endpoint or payload shape: update `HA_API.md`.
- New workflow step: update `ROADMAP.md`.
- New UI state or interaction: update `UX.md`.
- New test scenario: add one row to the traceability matrix in `TESTING.md`.
