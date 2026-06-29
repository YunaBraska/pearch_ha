# PerchHA

A native macOS menu bar app for Home Assistant. Keep an eye on your home from the menu bar — glanceable values and gauges, a quiet drop-down panel of rooms and sensors, history on hover, and one-tap controls.

[![CI](https://github.com/YunaBraska/pearch_ha/actions/workflows/ci.yml/badge.svg)](https://github.com/YunaBraska/pearch_ha/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](https://developer.apple.com/macos/)

| Drop-down panel | First run | Settings |
| --- | --- | --- |
| ![Rooms, sensors and controls in the drop-down panel](docs/images/panel.png) | ![First-run connection screen](docs/images/first-run.png) | ![Settings window](docs/images/settings.png) |

## What it does

- **Menu bar values and gauges.** Promote any value to the menu bar as text, a bar, a battery, or a ring.
- **A calm drop-down panel.** Rooms group your sensors and devices; values line up in a stable column and never jump around.
- **History on hover.** Hover a value for an hour/day/week/month chart with min, average, and max.
- **Direct controls.** Toggle lights, switches, and input booleans; open, close, stop, and position covers — with instant, optimistic feedback.
- **Custom actions.** Attach a saved Home Assistant service call to any row, with optional confirmation.
- **Sign in or use a token.** Sign in through Home Assistant in your browser, or paste a long-lived access token. Credentials are stored in the macOS Keychain and restored automatically on the next launch.
- **Native and respectful.** Dark and light mode, full keyboard control, VoiceOver labels, Reduce Motion and Increase Contrast support, near-zero idle CPU, and no telemetry.

## Requirements

- macOS 13 or newer.
- A reachable Home Assistant instance and either a sign-in or a long-lived access token.

## Run it

Signed, notarized downloads are still on the way. For now, build and run from source.

With a full Xcode install:

```sh
open PerchHA.xcodeproj   # then Run the "PerchHA" scheme
```

Or build a runnable `.app` from the command line:

```sh
swift build -c release --product PerchHA
swift run perchha-package-app \
  --executable .build/release/PerchHA \
  --output .build/PerchHA.app \
  --callback-scheme perchha --replace --sign-ad-hoc
open .build/PerchHA.app
```

The PerchHA icon appears in the menu bar. Click it, enter your Home Assistant address, then **Sign in** or paste an **access token** (create one in Home Assistant under your profile → Security → Long-lived access tokens). Open **Settings** to choose which rooms and values to show.

## Learn more

- [docs/README.md](docs/README.md) — documentation map.
- [docs/ROADMAP.md](docs/ROADMAP.md) — detailed milestone status and build plan.
- [docs/PRD.md](docs/PRD.md) — product requirements.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how the code fits together.
- [docs/TESTING.md](docs/TESTING.md) — testing approach and coverage gates.
- [Contributing](CONTRIBUTING.md) — development setup and conventions.

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
swift run perchha-coverage-check --coverage-json "$coverage_path" --line-target PerchHACore=95 --line-target PerchHAClient=86 --branch-target PerchHACore=90
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
