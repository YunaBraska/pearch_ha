# Verification

Run the shared local and CI contract with full Xcode selected:

```sh
sh scripts/check.sh
```

The script checks Xcode readiness, builds with warnings as errors, executes XCTest,
exports coverage across all test bundles, runs native smoke checks, and audits the
repository for private data, generated output, and telemetry dependencies.

Command Line Tools-only builds may compile tests without executing them. A run
ending at `Build complete!` is not test evidence. SwiftPM may export coverage for
only its last test bundle, so the script uses the merged LLVM profile explicitly.

## Gates

- `PearchHACore` line coverage: at least 95%.
- `PearchHAClient` line coverage: at least 90%. The target remains 95%.
- Core branch coverage: at least 90% when branch sites are exported. The current
  Swift exporter reports zero sites. Passing that policy is not measured branch coverage.
- Missing coverage targets or metrics fail explicitly.

Tests are the scenario inventory. Keep behavior assertions alongside the owning
component instead of maintaining a second list of test names here:

| Boundary | Tests |
| --- | --- |
| Formatting, selection, thresholds, actions, cache | [Core](../Tests/PearchHACoreTests), [UI](../Tests/PearchHAUITests) |
| REST, WebSocket, auth, fallback, history, controls | [Client](../Tests/PearchHAClientTests), [FakeHA](../Tests/FakeHATests) |
| Config migration, atomic writes, Keychain, protected action values | [Persistence](../Tests/PearchHAPersistenceTests) |
| Native panel/settings, focus, action cancellation, refresh lifecycle | [UI and AppShell](../Tests/PearchHAUITests) |
| Universal app, signing, DMG, OAuth site, release evidence | [Packaging](../Tests/PearchHAPackagingTests) |
| Clocks, rate limits, backoff, coalescing, redaction | [Support](../Tests/PearchHASupportTests) |
| Coverage and repository policy | [Coverage](../Tests/PearchHACoverageCheckTests), [Audit](../Tests/PearchHARepoAuditTests) |

## Protocol fixtures

[FakeHA](../Tests/FakeHA/FakeHA.swift) serves real loopback HTTP and WebSocket
boundaries, including TLS, discovery, history, services, live events, and injected
failures. `start()` waits for an OS-assigned port before `baseURL` is used. Tests
assert the redacted request journal rather than mocking client internals.

`hamirror` captures sanitized REST states and optional WebSocket command-support
evidence. Capture, replay, and verification use the same [API contract](HA_API.md).
Follow the [fixture privacy rules](../Fixtures/README.md). Normal CI never needs a
live Home Assistant instance. Real-instance fixture and performance checks are opt-in.

```sh
swift run hamirror verify --fixtures Fixtures/public/m2-minimal
```

## Native and performance checks

```sh
PEARCHHA_SMOKE_SNAPSHOT_DIR=.build/pearchha-snapshots swift run pearchha-smoke
swift run pearchha-smoke --repeat 5
```

Smoke exercises native panels and controls, focus, connection and failure states,
light/dark and accessibility appearances, packaging, and the app-shell lifecycle.
It also measures cold launch, cached panel opening, idle CPU, memory across repeated
lifecycles, request volume, history debounce/cache behavior, and status-item redraws.
Timing tests use injected clocks. Async tests wait for observable progress.

Snapshots and a contact sheet are written under `.build/pearchha-snapshots/current`.
Panel and history captures use the production 384×468 view. Settings captures
include the sidebar and inspector at the production 1120×720 window size.
The comparison baseline is [release-review-baseline.json](release-review-baseline.json).
A different macOS version can skip the pixel comparison. Render success then needs
separate visual review. Use `--update-review-baseline` only for an intentional,
reviewed appearance change.

Real-app measurements must distinguish a closed menu, an open panel/history view,
and Settings. Record duration, entity count, refresh intervals, Live Updates mode,
CPU, and memory. A model-only measurement does not establish GUI performance or
long-session stability. Remaining evidence gaps belong in [ROADMAP.md](ROADMAP.md).

## Release evidence

The [packaging script](../scripts/package.sh) builds both architectures, signs the
app, notarizes and staples the ZIP app and DMG, verifies the DMG and mounted contents, and emits a manifest plus portable
screenshots/evidence. Reverify a retained bundle with:

```sh
swift run pearchha-package-app --verify-release-manifest dist/pearchha-release-evidence/pearchha-release-manifest.json
```

Local test signing does not prove Developer ID trust or notarization. The release
workflow requires production credentials for those checks. CLI `--help` is the
canonical option reference.

For the Mac App Store channel, run
`scripts/package-app-store.sh VERSION`. This uses the `AppStore` Xcode
configuration, applies sandbox, network-client and user-selected read-only file
entitlements, and exports an
App Store archive. It requires an installed Apple distribution certificate and
provisioning profile, plus exported `PEARCHHA_OAUTH_CLIENT_ID` and
`PEARCHHA_OAUTH_REDIRECT_URI` public configuration. Verify the deployed client
website with `pearchha-package-app --verify-published-oauth-site` first. The
packaged app must retain both public values and its matching callback scheme
without a shell environment. Do not use this lane for the direct ZIP/DMG release.

A local UI review can package the Store executable with the existing local test
identity and existing data profile. That does not verify sandbox migration or
Store Keychain access. Test those with the actual distribution identity before
submission. Do not disable library validation to make the direct-channel
Sparkle framework work with a local test certificate.
