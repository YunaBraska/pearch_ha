# PearchHA

A native macOS menu bar app for Home Assistant.

[![CI](https://github.com/YunaBraska/pearch_ha/actions/workflows/ci.yml/badge.svg)](https://github.com/YunaBraska/pearch_ha/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](https://developer.apple.com/macos/)

| Drop-down panel | First run | Settings |
| --- | --- | --- |
| ![Rooms, sensors and controls in the drop-down panel](docs/images/panel.png) | ![First-run connection screen](docs/images/first-run.png) | ![Settings window](docs/images/settings.png) |

## What it does

- Menu bar values and gauges.
- Room-based panel with cached history detail.
- Native controls for switches, covers, and custom actions.
- Browser sign-in or token auth, restored from Keychain.
- FakeHA-backed tests and release packaging from the same repo.

## Requirements

- macOS 13 or newer.
- A reachable Home Assistant instance.

## Run it

With Xcode:

```sh
open PerchHA.xcodeproj
```

From the command line:

```sh
swift build -c release --product PerchHA
swift run perchha-package-app \
  --executable .build/release/PerchHA \
  --output .build/PerchHA.app \
  --callback-scheme perchha \
  --replace \
  --sign-ad-hoc
open .build/PerchHA.app
```

## Verify it

```sh
swift test
sh scripts/check.sh
```

## Docs

- [docs/README.md](docs/README.md)
- [docs/ROADMAP.md](docs/ROADMAP.md)
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/HA_API.md](docs/HA_API.md)
- [docs/TESTING.md](docs/TESTING.md)
- [docs/ADRs.md](docs/ADRs.md)

## Repo layout

```text
PerchHA/
|- Package.swift
|- PerchHA.xcodeproj
|- Sources/
|- Tests/
|- Fixtures/
`- docs/
```
