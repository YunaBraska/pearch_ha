# Verification

Run the shared local and CI contract with full Xcode selected:

```sh
sh scripts/check.sh
```

The script checks Xcode readiness, builds with warnings as errors, executes XCTest,
exports coverage across all test bundles, runs native smoke checks, and audits the
repository for private data, generated output, and telemetry dependencies.
Native checks open windows and can change focus. Run the full suite in an isolated
desktop session or CI, not while someone is working on the machine. Compilation
alone (`swift build -Xswiftc -warnings-as-errors`) does not interact with the desktop.

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
| Cold app launch, real status-item clicks, focus, dismissal and shortcuts | [XCUITest](../Xcode/PearchHAE2ETests) on [hosted macOS CI](../.github/workflows/ui-tests.yml) |
| Local OS readings, source isolation, sampling lifecycle, translations | [Local reader](../Tests/PearchHAUITests/PearchHALocalSensorReaderTests.swift), [integration](../Tests/PearchHAUITests/PearchHALocalSensorIntegrationTests.swift) |
| Universal app, signing, DMG, OAuth site, release evidence | [Packaging](../Tests/PearchHAPackagingTests) |
| Clocks, jitter, backoff, redaction | [Support](../Tests/PearchHASupportTests) |
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

Smoke exercises native popovers and controls, focus, connection and failure states,
light/dark and accessibility appearances, packaging, and the app-shell lifecycle.
It also measures cold launch, cached panel opening, idle CPU, memory across repeated
lifecycles, request volume, history debounce/cache behavior, and status-item redraws.
Timing tests use injected clocks. Async tests wait for observable progress.

The separate `Native UI` workflow runs `scripts/test-ui.sh` on GitHub-hosted macOS
desktops. The script and XCUITest both reject local and self-hosted execution.
The test launches the production app in the background and clicks its observed
status-item location through Finder's coordinate space. It must not activate
PearchHA before the first click, which would hide the cold-start focus regression.
One click must open the panel, and the next must close it. Input originates from
the already-active app, even when a native popover has keyboard focus without
activating PearchHA. Escape and Cmd+, verify keyboard delivery through their visible
effects. Finder dismissal and reopening use the same public interface.
The session repeats after process termination. No Home Assistant credentials or
real devices are involved. Each run retains its logs, screenshots and `.xcresult`
for seven days. These tests do not publish or install a release.
The macOS 26 job also retains smoke screenshots and the native 100–200% text-size
checks for visual review. All captures use fixtures, without personal HA data.

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
`scripts/package-app-store.sh VERSION BUILD_NUMBER`. The existing App Store
workflow supplies `APP_STORE_BUNDLE_ID`, `APP_STORE_TEAM_ID`,
`MACOS_APP_STORE_APPLICATION_IDENTITY` and `MACOS_APP_STORE_PROFILE_PATH`.
The script builds both architectures without Sparkle and signs the sandboxed
bundle under `dist/app-store`. Export `PEARCHHA_OAUTH_CLIENT_ID` and
`PEARCHHA_OAUTH_REDIRECT_URI` to embed the public sign-in configuration through
the package tool. Verify the deployed client
website with `pearchha-package-app --verify-published-oauth-site` first. The
packaged app must retain both public values and its matching callback scheme
without a shell environment. Do not use this lane for the direct ZIP/DMG release.

A local UI review can package the Store executable with the existing local test
identity and existing data profile. That does not verify sandbox migration or
Store Keychain access. Test those with the actual distribution identity before
submission. Do not disable library validation to make the direct-channel
Sparkle framework work with a local test certificate.
